import AppKit
import AVFoundation
import Combine
import Defaults
import SwiftUI

private func makeDefaultAlbumArtImage() -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedWhite: 0.28, alpha: 1.0).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    image.unlockFocus()
    return image
}

let defaultImage: NSImage = makeDefaultAlbumArtImage()

private enum MusicDisplayPlaceholder {
    static var title: String { String(localized: "Not Playing") }
    static let rawTitle = "Not Playing"
    static let artist = ""
    static let album = "Unknown Album"
}


enum AlbumArtFlipDirection {
    case next
    case previous
}


class MusicManager: ObservableObject {
  // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    private var activeController: (any MediaControllerProtocol)?

  // MARK: - Routing (new 2-mode UX)
    private enum InternalSource: CaseIterable {
        case nowPlaying
        case appleMusic
        case spotify
        case youtubeMusic
    }

    private var activeSource: InternalSource? = nil
    private var stateBySource: [InternalSource: PlaybackState] = [:]
    private var sourceSubscriptions: [InternalSource: AnyCancellable] = [:]
    private var pendingPlaybackCommand: PendingPlaybackCommand?

    private var nowPlayingController: NowPlayingController? = nil
    private var appleMusicController: AppleMusicController? = nil
    private var spotifyController: SpotifyController? = nil
    private var youTubeMusicController: YouTubeMusicController? = nil

    @Published var songTitle: String = MusicDisplayPlaceholder.title
    @Published var artistName: String = MusicDisplayPlaceholder.artist
    @Published var albumArt: NSImage = defaultImage

    @Published var albumArtFlipEventID: UUID = UUID()
    @Published var albumArtFlipDirection: AlbumArtFlipDirection = .next
    @Published var albumArtFlipImage: NSImage = defaultImage
    @Published var previousButtonAnimationID: UUID = UUID()
    @Published var nextButtonAnimationID: UUID = UUID()
    @Published var isPlaying = false
    @Published var album: String = MusicDisplayPlaceholder.album
    @Published var isPlayerIdle: Bool = true
    @Published var animations: QuartzAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var spectrogramTopColor: NSColor = .white
    @Published var spectrogramBottomColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published private(set) var lyricsSnapshot: LyricsSnapshot = .empty
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false
    @Published var isArtworkTintReady: Bool = false
    @Published var playbackPreviewPosition: TimeInterval? = nil
    @Published private(set) var lyricsTrackKey: String = ""

    private struct PendingPlaybackCommand {
        let targetIsPlaying: Bool
        let source: InternalSource?
        let trackIdentity: String?
        let expiresAt: Date
    }

    private struct ArtworkSignature: Equatable {
        let byteCount: Int
        let head: UInt64
        let tail: UInt64

        init?(_ data: Data?) {
            guard let data else { return nil }
            if data.count < 256 { return nil }

            self.byteCount = data.count
            self.head = ArtworkSignature.fnv1a64(data.prefix(256))
            self.tail = ArtworkSignature.fnv1a64(data.suffix(256))
        }

        private static func fnv1a64(_ bytes: Data) -> UInt64 {
            var hash: UInt64 = 14695981039346656037
            for b in bytes {
                hash ^= UInt64(b)
                hash &*= 1099511628211
            }
            return hash
        }
    }

    private var artworkData: Data? = nil
    private var artworkSignature: ArtworkSignature? = nil

    private var lastArtworkTitle: String = MusicDisplayPlaceholder.title
    private var lastArtworkArtist: String = MusicDisplayPlaceholder.artist
    private var lastArtworkAlbum: String = MusicDisplayPlaceholder.album
    private var lastArtworkBundleIdentifier: String? = nil

    private var pendingAlbumArtFlipDirection: AlbumArtFlipDirection? = nil
    private var trackNavigationHistory: [String] = []
    private var trackNavigationIndex: Int = -1

    private var artworkDecodeRequestID: UUID = UUID()
    private var lyricsFetchTask: Task<Void, Never>?
    private var activeLyricsRequestID = UUID()
    private var activeLyricsKey: String = ""
    private var lastForceUpdateAt: Date = .distantPast
    private var forceUpdateTask: Task<Void, Never>?

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    var isUsingIdleMetadata: Bool {
        songTitle == MusicDisplayPlaceholder.title && artistName == MusicDisplayPlaceholder.artist
    }

    var hasResolvableBundleIcon: Bool {
        guard let bundleID = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

  // MARK: - Initialization
    init() {
        migratePlaybackScopeIfNeeded()

        NotificationCenter.default.publisher(for: Notification.Name.playbackScopeChanged)
            .sink { [weak self] _ in
                self?.reselectActiveSource(reason: "scope-changed")
            }
            .store(in: &cancellables)

        Publishers.Merge(
            Defaults.publisher(.enableLyrics).map(\.newValue),
            Defaults.publisher(.enableNotchLyrics).map(\.newValue)
        )
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard enabled else { return }
                Task { @MainActor [weak self] in
                    self?.refreshLyricsForCurrentTrack()
                }
            }
            .store(in: &cancellables)

        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            self.setupControllersIfNeeded()
            self.reselectActiveSource(reason: "startup")
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        debounceIdleTask = nil
        cancellables.removeAll()
        controllerCancellables.removeAll()
        sourceSubscriptions.removeAll()
        stateBySource.removeAll()
        flipWorkItem?.cancel()
        flipWorkItem = nil
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
        forceUpdateTask?.cancel()
        forceUpdateTask = nil

        activeController = nil
        activeSource = nil
        nowPlayingController = nil
        appleMusicController = nil
        spotifyController = nil
        youTubeMusicController = nil
    }

  // MARK: - Setup Methods (routing)
    private func setupControllersIfNeeded() {
        if nowPlayingController == nil {
            nowPlayingController = NowPlayingController()
        }
        if appleMusicController == nil { appleMusicController = AppleMusicController() }
        if spotifyController == nil { spotifyController = SpotifyController() }
        
        if youTubeMusicController == nil {
            if NSWorkspace.shared.runningApplications.contains(where: {
                $0.bundleIdentifier == "com.github.th-ch.youtube-music"
            }) {
                youTubeMusicController = YouTubeMusicController()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.attachYouTubeMusicIfNeeded()
                }
            }
        }

        attach(controller: nowPlayingController, source: .nowPlaying)
        attach(controller: appleMusicController, source: .appleMusic)
        attach(controller: spotifyController, source: .spotify)
        if youTubeMusicController != nil {
            attachYouTubeMusicIfNeeded()
        }
    }
    
    private func attachYouTubeMusicIfNeeded() {
        if sourceSubscriptions[.youtubeMusic] == nil {
            attach(controller: youTubeMusicController, source: .youtubeMusic)
        }
    }

    private func attach(controller: (any MediaControllerProtocol)?, source: InternalSource) {
        guard let controller = controller else { return }
        if sourceSubscriptions[source] != nil { return }

        let sub = controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleIncomingPlaybackState(state, from: source)
            }
        sourceSubscriptions[source] = sub
    }

    @MainActor
    private func handleIncomingPlaybackState(_ state: PlaybackState, from source: InternalSource) {
        stateBySource[source] = state

        reselectActiveSource(reason: "state-updated")
    }

    private func reselectActiveSource(reason: String) {
        setupControllersIfNeeded()

        let scope = Defaults[.playbackScope]
        let desired: InternalSource?

        switch scope {
        case .systemWide:
            if nowPlayingController != nil, let np = stateBySource[.nowPlaying], np.lastUpdated != .distantPast {
                desired = nativeMusicSource(matching: np) ?? .nowPlaying
            } else {
                desired = pickMostRecentMusicSource()
            }
        case .musicOnly:
            desired = pickMostRecentMusicSource()
        }

        if desired != activeSource {
            activeSource = desired
            setActiveControllerForCurrentSource()
        }

        applyActiveStateIfAvailable()
    }

    private func nativeMusicSource(matching nowPlaying: PlaybackState) -> InternalSource? {
        if nowPlaying.bundleIdentifier == "com.apple.Music",
           let appleMusic = stateBySource[.appleMusic],
           playbackState(appleMusic, matches: nowPlaying) {
            return .appleMusic
        }

        if nowPlaying.bundleIdentifier == "com.spotify.client",
           let spotify = stateBySource[.spotify],
           playbackState(spotify, matches: nowPlaying) {
            return .spotify
        }

        if isYouTubeMusicAppBundleIdentifier(nowPlaying.bundleIdentifier),
           let youtubeMusic = stateBySource[.youtubeMusic],
           playbackState(youtubeMusic, matches: nowPlaying) {
            return .youtubeMusic
        }

        return nil
    }

    private func isYouTubeMusicAppBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return false
        }

        let normalizedBundleID = bundleIdentifier.lowercased()
        if normalizedBundleID == YouTubeMusicConfiguration.default.bundleIdentifier.lowercased() {
            return true
        }
        if normalizedBundleID.contains("ytmusic") || normalizedBundleID.contains("yt-music") {
            return true
        }
        if normalizedBundleID.contains("youtube") && normalizedBundleID.contains("music") {
            return true
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let appName = ((try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? appURL.deletingPathExtension().lastPathComponent)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            if appName.contains("youtube") && appName.contains("music") {
                return true
            }
        }

        return false
    }

    private func musicOnlyNowPlayingFallbackCandidate(_ state: PlaybackState) -> (InternalSource, PlaybackState)? {
        guard state.lastUpdated != .distantPast else { return nil }

        if state.bundleIdentifier == "com.apple.Music",
           let appleMusic = stateBySource[.appleMusic],
           playbackState(appleMusic, matches: state) {
            return nil
        }

        if state.bundleIdentifier == "com.spotify.client",
           let spotify = stateBySource[.spotify],
           playbackState(spotify, matches: state) {
            return nil
        }

        if isYouTubeMusicAppBundleIdentifier(state.bundleIdentifier),
           let youtubeMusic = stateBySource[.youtubeMusic],
           playbackState(youtubeMusic, matches: state) {
            return nil
        }

        guard state.bundleIdentifier == "com.apple.Music"
            || state.bundleIdentifier == "com.spotify.client"
            || isYouTubeMusicAppBundleIdentifier(state.bundleIdentifier) else {
            return nil
        }

        return (.nowPlaying, state)
    }

    private func playbackState(_ lhs: PlaybackState, matches rhs: PlaybackState) -> Bool {
        let leftTitle = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rightTitle = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let leftArtist = lhs.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rightArtist = rhs.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if leftTitle.isEmpty || rightTitle.isEmpty {
            return lhs.lastUpdated != .distantPast
        }

        return leftTitle == rightTitle && (leftArtist.isEmpty || rightArtist.isEmpty || leftArtist == rightArtist)
    }

    private func pickMostRecentMusicSource() -> InternalSource? {
        var candidates: [(InternalSource, PlaybackState)] = [
            (.appleMusic, stateBySource[.appleMusic]),
            (.spotify, stateBySource[.spotify]),
            (.youtubeMusic, stateBySource[.youtubeMusic])
        ].compactMap { src, st in
            guard let st else { return nil }
            guard st.lastUpdated != .distantPast else { return nil }
            return (src, st)
        }

        if let nowPlaying = stateBySource[.nowPlaying],
           let fallback = musicOnlyNowPlayingFallbackCandidate(nowPlaying) {
            candidates.append(fallback)
        }

        let playing = candidates.filter { $0.1.isPlaying }
        if let best = playing.max(by: { $0.1.lastUpdated < $1.1.lastUpdated }) {
            return best.0
        }
        return candidates.max(by: { $0.1.lastUpdated < $1.1.lastUpdated })?.0
    }

    private func setActiveControllerForCurrentSource() {
        controllerCancellables.removeAll()

        switch activeSource {
        case .nowPlaying:
            activeController = nowPlayingController
        case .appleMusic:
            activeController = appleMusicController
        case .spotify:
            activeController = spotifyController
        case .youtubeMusic:
            activeController = youTubeMusicController
        case .none:
            activeController = nil
        }

        canFavoriteTrack = activeController?.supportsFavorite ?? false
        volumeControlSupported = activeController?.supportsVolumeControl ?? true
    }

    @MainActor
    private func applyActiveStateIfAvailable() {
        guard let source = activeSource, let raw = stateBySource[source] else { return }

        var effective = raw
        effective.artwork = sanitizeArtworkData(effective.artwork)

        if effective.artwork == nil, source != .nowPlaying,
           let np = stateBySource[.nowPlaying], np.bundleIdentifier == effective.bundleIdentifier {
            let npArtwork = sanitizeArtworkData(np.artwork)
            if npArtwork != nil {
                effective.artwork = npArtwork
            }
        }

        applyPendingPlaybackCommandIfNeeded(to: &effective)

        updateFromPlaybackState(effective)
    }

    @MainActor
    private func applyPendingPlaybackCommandIfNeeded(to state: inout PlaybackState) {
        guard let pending = pendingPlaybackCommand else { return }

        if Date() > pending.expiresAt {
            pendingPlaybackCommand = nil
            return
        }

        let stateIdentity = trackIdentity(
            title: state.title,
            artist: state.artist,
            album: state.album,
            bundleIdentifier: state.bundleIdentifier
        )
        let sameTrack = pending.trackIdentity == nil
            || stateIdentity == nil
            || pending.trackIdentity == stateIdentity
        guard sameTrack else {
            pendingPlaybackCommand = nil
            return
        }

        state.isPlaying = pending.targetIsPlaying
        if !pending.targetIsPlaying {
            state.playbackRate = 0
        } else if state.playbackRate <= 0 {
            state.playbackRate = 1
        }
        state.lastUpdated = Date()
    }

    private func sanitizeArtworkData(_ data: Data?) -> Data? {
        guard let data else { return nil }
        if data.count < 256 { return nil }
        return data
    }

    private func migratePlaybackScopeIfNeeded() {
        if Defaults[.didMigratePlaybackScopeV1] { return }

        let hasScope = UserDefaults.standard.object(forKey: "playbackScope") != nil
        if !hasScope {
            let hasLegacy = UserDefaults.standard.object(forKey: "mediaController") != nil
            if hasLegacy {
                let legacy = Defaults[.mediaController]
                switch legacy {
                case .nowPlaying:
                    Defaults[.playbackScope] = .systemWide
                case .appleMusic, .spotify, .youtubeMusic:
                    Defaults[.playbackScope] = .musicOnly
                }
            }
        }

        Defaults[.didMigratePlaybackScopeV1] = true
    }

  // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        let normalizedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = state.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = normalizedTitle.isEmpty ? MusicDisplayPlaceholder.title : state.title
        let displayArtist = normalizedArtist.isEmpty ? MusicDisplayPlaceholder.artist : state.artist
        let previousIsPlaying = self.isPlaying
        let playbackEstimateBeforeStateMutation = self.estimatedPlaybackPosition(at: Date())
        let pauseShouldFreezeAtCurrentEstimate = previousIsPlaying && !state.isPlaying

        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            if pauseShouldFreezeAtCurrentEstimate {
                self.elapsedTime = playbackEstimateBeforeStateMutation
                self.timestampDate = Date()
                self.playbackRate = 0
            }
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }


        }

        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        let newSig = ArtworkSignature(state.artwork)
        let artworkChanged = (newSig != nil) && (newSig != self.artworkSignature)
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged
        let newTrackIdentity = trackIdentity(
            title: displayTitle,
            artist: displayArtist,
            album: state.album,
            bundleIdentifier: state.bundleIdentifier
        )
        let currentTrackIdentity = currentHistoryIdentity
        let trackIdentityChanged = newTrackIdentity != nil && newTrackIdentity != currentTrackIdentity

        if let newTrackIdentity, trackIdentityChanged {
            let resolvedDirection = pendingAlbumArtFlipDirection ?? inferredDirection(for: newTrackIdentity)

            if pendingAlbumArtFlipDirection == nil {
                switch resolvedDirection {
                case .next:
                    triggerNextButtonAnimation()
                case .previous:
                    triggerPreviousButtonAnimation()
                }
                pendingAlbumArtFlipDirection = resolvedDirection
            }

            syncTrackNavigationHistory(with: newTrackIdentity, preferredDirection: resolvedDirection)
        }

        if hasContentChange {
            let willUseFreshArtwork = artworkChanged || bundleChanged
            if willUseFreshArtwork {
                self.isArtworkTintReady = false
            }
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                if bundleChanged {
                    if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                        self.usingAppIconForArtwork = true
                        self.updateAlbumArt(newAlbumArt: appIconImage)
                    } else {
                        self.usingAppIconForArtwork = false
                        self.updateAlbumArt(newAlbumArt: defaultImage)
                    }
                } else if self.albumArt == defaultImage,
                          let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier)
                {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork
            self.artworkSignature = newSig

            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier

            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            self.fetchLyricsIfAvailable(
                bundleIdentifier: state.bundleIdentifier,
                title: displayTitle,
                artist: displayArtist,
                album: state.album,
                duration: state.duration
            )
        }

        let sameDisplayedTrack =
            displayTitle == self.songTitle
            && displayArtist == self.artistName
            && state.album == self.album
            && state.bundleIdentifier == self.bundleIdentifier

        let candidateCurrentTime = pauseShouldFreezeAtCurrentEstimate
            ? max(state.currentTime, playbackEstimateBeforeStateMutation)
            : state.currentTime

        let shouldIgnoreStalePlaybackTime =
            sameDisplayedTrack
            && previousIsPlaying
            && state.isPlaying
            && candidateCurrentTime < playbackEstimateBeforeStateMutation - 0.75
            && abs(candidateCurrentTime - self.elapsedTime) < 1.0

        let effectiveCurrentTime = shouldIgnoreStalePlaybackTime
            ? playbackEstimateBeforeStateMutation
            : candidateCurrentTime
        let effectiveTimestampDate = (pauseShouldFreezeAtCurrentEstimate || shouldIgnoreStalePlaybackTime) ? Date() : state.lastUpdated

        let timeChanged = abs(effectiveCurrentTime - self.elapsedTime) > 0.05
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = abs(state.volume - self.volume) > 0.005
        
        if displayTitle != self.songTitle {
            self.songTitle = displayTitle
        }

        if displayArtist != self.artistName {
            self.artistName = displayArtist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = effectiveCurrentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        if timeChanged
            || playbackRateChanged
            || abs(effectiveTimestampDate.timeIntervalSince(self.timestampDate)) > 0.25 {
            self.timestampDate = effectiveTimestampDate
        }
    }

    private var currentHistoryIdentity: String? {
        guard trackNavigationIndex >= 0, trackNavigationIndex < trackNavigationHistory.count else {
            return nil
        }
        return trackNavigationHistory[trackNavigationIndex]
    }

    private func trackIdentity(title: String, artist: String, album: String, bundleIdentifier: String?) -> String? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTitle.isEmpty
            || normalizedTitle == MusicDisplayPlaceholder.title
            || normalizedTitle == MusicDisplayPlaceholder.rawTitle {
            return nil
        }

        func normalize(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
        }

        return [
            normalize(bundleIdentifier ?? ""),
            normalize(title),
            normalize(artist),
            normalize(album)
        ].joined(separator: "|")
    }

    private func inferredDirection(for newTrackIdentity: String) -> AlbumArtFlipDirection {
        if trackNavigationIndex > 0,
           trackNavigationHistory[trackNavigationIndex - 1] == newTrackIdentity {
            return .previous
        }

        if trackNavigationIndex >= 0,
           trackNavigationIndex + 1 < trackNavigationHistory.count,
           trackNavigationHistory[trackNavigationIndex + 1] == newTrackIdentity {
            return .next
        }

        return .next
    }

    private func syncTrackNavigationHistory(with newTrackIdentity: String, preferredDirection: AlbumArtFlipDirection) {
        if trackNavigationHistory.isEmpty {
            trackNavigationHistory = [newTrackIdentity]
            trackNavigationIndex = 0
            return
        }

        if currentHistoryIdentity == newTrackIdentity {
            return
        }

        switch preferredDirection {
        case .previous:
            if trackNavigationIndex > 0,
               trackNavigationHistory[trackNavigationIndex - 1] == newTrackIdentity {
                trackNavigationIndex -= 1
                return
            }
            if let existingIndex = trackNavigationHistory.lastIndex(of: newTrackIdentity) {
                trackNavigationIndex = existingIndex
                return
            }
        case .next:
            if trackNavigationIndex >= 0,
               trackNavigationIndex + 1 < trackNavigationHistory.count,
               trackNavigationHistory[trackNavigationIndex + 1] == newTrackIdentity {
                trackNavigationIndex += 1
                return
            }
        }

        if trackNavigationIndex + 1 < trackNavigationHistory.count {
            trackNavigationHistory.removeSubrange((trackNavigationIndex + 1)..<trackNavigationHistory.count)
        }

        trackNavigationHistory.append(newTrackIdentity)
        trackNavigationIndex = trackNavigationHistory.count - 1
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set favorited of current track to (not favorited of current track)
                    return favorited of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

  /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

  // MARK: - Lyrics
    private func lyricsIdentity(bundleIdentifier: String?, title: String, artist: String, album: String) -> String {
        [bundleIdentifier ?? "", title, artist, album]
            .map {
                $0
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .joined(separator: "|")
    }

    @MainActor
    private func clearLyricsState(for key: String = "") {
        let nextSnapshot = key.isEmpty
            ? LyricsSnapshot.empty
            : LyricsSnapshot(trackKey: key, state: .unavailable, plainLyrics: "", syncedLines: [], source: nil, fetchedAt: Date())

        lyricsTrackKey = key
        if isFetchingLyrics { isFetchingLyrics = false }
        if !currentLyrics.isEmpty { currentLyrics = "" }
        if !syncedLyrics.isEmpty { syncedLyrics = [] }
        if lyricsSnapshot != nextSnapshot { lyricsSnapshot = nextSnapshot }
    }

    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String, album: String, duration: TimeInterval) {
        let request = LyricsTrackRequest(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        let key = request.cacheKey.isEmpty
            ? lyricsIdentity(bundleIdentifier: bundleIdentifier, title: title, artist: artist, album: album)
            : request.cacheKey

        guard (Defaults[.enableLyrics] || Defaults[.enableNotchLyrics]),
              !title.isEmpty,
              title != MusicDisplayPlaceholder.title else {
            lyricsFetchTask?.cancel()
            activeLyricsKey = ""
            activeLyricsRequestID = UUID()
            Task { @MainActor in
                self.clearLyricsState()
            }
            return
        }

        guard key != activeLyricsKey else { return }

        lyricsFetchTask?.cancel()
        activeLyricsKey = key
        activeLyricsRequestID = UUID()
        let requestID = activeLyricsRequestID

        lyricsFetchTask = Task { @MainActor in
            self.lyricsTrackKey = key
            self.isFetchingLyrics = true
            self.currentLyrics = ""
            self.syncedLyrics = []
            self.lyricsSnapshot = LyricsSnapshot(
                trackKey: key,
                state: .loading,
                plainLyrics: "",
                syncedLines: [],
                source: nil,
                fetchedAt: nil
            )

            let appleMusicFallback = await self.fetchAppleMusicPlainLyricsIfAvailable(bundleIdentifier: bundleIdentifier)
            let snapshot = await LyricsService.shared.fetchSnapshot(for: request, plainFallback: appleMusicFallback)
            guard requestID == self.activeLyricsRequestID, key == self.activeLyricsKey, !Task.isCancelled else { return }
            self.applyLyricsSnapshot(snapshot)
        }
    }

    @MainActor
    func refreshLyricsForCurrentTrack() {
        let title = songTitle
        let artist = artistName
        let album = album
        let duration = songDuration
        let bundleIdentifier = bundleIdentifier
        let request = LyricsTrackRequest(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        let key = request.cacheKey.isEmpty
            ? lyricsIdentity(bundleIdentifier: bundleIdentifier, title: title, artist: artist, album: album)
            : request.cacheKey

        if lyricsSnapshot.trackKey == key,
           lyricsSnapshot.hasAnyLyrics || lyricsSnapshot.state == .instrumental {
            return
        }

        activeLyricsKey = ""
        activeLyricsRequestID = UUID()
        fetchLyricsIfAvailable(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
    }

    @MainActor
    private func applyLyricsSnapshot(_ snapshot: LyricsSnapshot) {
        if lyricsSnapshot != snapshot { lyricsSnapshot = snapshot }
        if lyricsTrackKey != snapshot.trackKey { lyricsTrackKey = snapshot.trackKey }
        let fetching = snapshot.state == .loading
        if isFetchingLyrics != fetching { isFetchingLyrics = fetching }
        if currentLyrics != snapshot.plainLyrics { currentLyrics = snapshot.plainLyrics }
        let nextSyncedLyrics = snapshot.syncedLines.map { (time: $0.startTime, text: $0.text) }
        if syncedLyrics.count != nextSyncedLyrics.count
            || !zip(syncedLyrics, nextSyncedLyrics).allSatisfy({ lhs, rhs in
                lhs.time == rhs.time && lhs.text == rhs.text
            }) {
            syncedLyrics = nextSyncedLyrics
        }
    }

    private func fetchAppleMusicPlainLyricsIfAvailable(bundleIdentifier: String?) async -> String? {
        guard let bundleIdentifier, bundleIdentifier.contains("com.apple.Music") else { return nil }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return nil }

        let script = """
        tell application \"Music\"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        set l to lyrics of current track
                        if l is missing value then
                            return \"\"
                        else
                            return l
                        end if
                    on error
                        return \"\"
                    end try
                else
                    return \"\"
                end if
            else
                return \"\"
            end if
        end tell
        """

        guard let result = try? await AppleScriptHelper.execute(script),
              let lyrics = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lyrics.isEmpty else {
            return nil
        }
        return lyrics
    }

  // MARK: - Synced lyrics helpers
    func lyricIndex(at elapsed: Double) -> Int {
        let lines = lyricsSnapshot.syncedLines
        guard !lines.isEmpty else { return -1 }
        var low = 0
        var high = lines.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startTime <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return idx
    }

    func lyricLine(at elapsed: Double) -> String {
        guard lyricsSnapshot.hasSyncedLyrics else {
            return currentLyrics
        }
        let idx = lyricIndex(at: elapsed)
        guard lyricsSnapshot.syncedLines.indices.contains(idx) else {
            return ""
        }
        return lyricsSnapshot.syncedLines[idx].text
    }

    private func triggerFlipAnimation() {
        flipWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        let requestID = UUID()
        self.artworkDecodeRequestID = requestID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.artworkDecodeRequestID == requestID else { return }
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()

        let direction = pendingAlbumArtFlipDirection ?? .next
        pendingAlbumArtFlipDirection = nil
        self.albumArtFlipDirection = direction
        self.albumArtFlipImage = newAlbumArt
        self.albumArtFlipEventID = UUID()

        self.albumArt = newAlbumArt
        if Defaults[.coloredSpectrogram] {
            self.calculateAverageColor()
            self.calculateSpectrogramGradientColors()
        } else {
            self.isArtworkTintReady = true
        }
    }

  // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    @MainActor
    func previewPlaybackPosition(_ position: TimeInterval?) {
        guard let position else {
            playbackPreviewPosition = nil
            return
        }
        playbackPreviewPosition = min(max(0, position), songDuration > 0 ? songDuration : position)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                    self?.isArtworkTintReady = true
                }
            }
        }
    }
    

    func calculateSpectrogramGradientColors() {
        albumArt.verticalGradientColors { [weak self] top, bottom in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.spectrogramTopColor = top ?? self?.avgColor ?? .white
                    self?.spectrogramBottomColor = bottom ?? self?.avgColor ?? .white
                }
            }
        }
    }


    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            coordinator.toggleSneakPeek(status: true, type: .music)
        }
    }

  // MARK: - Public Methods for controlling playback
    @MainActor
    private func applyOptimisticPlaybackState(isPlaying targetIsPlaying: Bool) {
        let currentEstimate = estimatedPlaybackPosition(at: Date())
        pendingPlaybackCommand = PendingPlaybackCommand(
            targetIsPlaying: targetIsPlaying,
            source: activeSource,
            trackIdentity: trackIdentity(
                title: songTitle,
                artist: artistName,
                album: album,
                bundleIdentifier: bundleIdentifier
            ),
            expiresAt: Date().addingTimeInterval(1.2)
        )
        self.isPlaying = targetIsPlaying
        self.elapsedTime = currentEstimate
        self.timestampDate = Date()
        self.playbackRate = targetIsPlaying ? max(playbackRate, 1) : 0
        self.updateIdleState(state: targetIsPlaying)
    }

    func playPause() {
        let targetIsPlaying = !isPlaying
        Task { @MainActor in
            self.applyOptimisticPlaybackState(isPlaying: targetIsPlaying)
        }
        Task {
            await activeController?.togglePlay()
            try? await Task.sleep(for: .milliseconds(90))
            await activeController?.updatePlaybackInfo()
        }
    }

    func play() {
        Task { @MainActor in
            self.applyOptimisticPlaybackState(isPlaying: true)
        }
        Task {
            await activeController?.play()
            try? await Task.sleep(for: .milliseconds(90))
            await activeController?.updatePlaybackInfo()
        }
    }

    func pause() {
        Task { @MainActor in
            self.applyOptimisticPlaybackState(isPlaying: false)
        }
        Task {
            await activeController?.pause()
            try? await Task.sleep(for: .milliseconds(90))
            await activeController?.updatePlaybackInfo()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        let targetIsPlaying = !isPlaying
        Task { @MainActor in
            self.applyOptimisticPlaybackState(isPlaying: targetIsPlaying)
        }
        Task {
            await activeController?.togglePlay()
            try? await Task.sleep(for: .milliseconds(90))
            await activeController?.updatePlaybackInfo()
        }
    }

    func nextTrack() {
        pendingAlbumArtFlipDirection = .next
        triggerNextButtonAnimation()
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        pendingAlbumArtFlipDirection = .previous
        triggerPreviousButtonAnimation()
        Task {
            await activeController?.previousTrack()
        }
    }

    func triggerNextButtonAnimation() {
        nextButtonAnimationID = UUID()
        NotificationCenter.default.post(name: .musicNextButtonAnimationTriggered, object: nil)
    }

    func triggerPreviousButtonAnimation() {
        previousButtonAnimationID = UUID()
        NotificationCenter.default.post(name: .musicPreviousButtonAnimationTriggered, object: nil)
    }

    func seek(to position: TimeInterval) {
        let clampedPosition = min(max(0, position), songDuration > 0 ? songDuration : position)
        self.elapsedTime = clampedPosition
        self.timestampDate = Date()

        Task {
            await activeController?.seek(to: clampedPosition)
            try? await Task.sleep(for: .milliseconds(120))
            await activeController?.updatePlaybackInfo()
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, estimatedPlaybackPosition() + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        let now = Date()
        guard now.timeIntervalSince(lastForceUpdateAt) > 0.35 else { return }
        lastForceUpdateAt = now
        forceUpdateTask?.cancel()
        forceUpdateTask = Task { [weak self] in
            guard let self = self else { return }
            self.setupControllersIfNeeded()

            if let np = self.nowPlayingController {
                await np.updatePlaybackInfo()
            }

            if let am = self.appleMusicController, am.isActive() { await am.updatePlaybackInfo() }
            if let sp = self.spotifyController, sp.isActive() { await sp.updatePlaybackInfo() }
            if let yt = self.youTubeMusicController, yt.isActive() {
                await yt.pollPlaybackState()
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
