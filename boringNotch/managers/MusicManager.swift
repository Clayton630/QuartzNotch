import AppKit
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
    static let title = "Not Playing"
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
    @Published var animations: BoringAnimations = .init()
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
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false
    @Published var isArtworkTintReady: Bool = false

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
                desired = .nowPlaying
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

    private func pickMostRecentMusicSource() -> InternalSource? {
        let candidates: [(InternalSource, PlaybackState)] = [
            (.appleMusic, stateBySource[.appleMusic]),
            (.spotify, stateBySource[.spotify]),
            (.youtubeMusic, stateBySource[.youtubeMusic])
        ].compactMap { src, st in
            guard let st else { return nil }
            guard st.lastUpdated != .distantPast else { return nil }
            return (src, st)
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

        updateFromPlaybackState(effective)
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

        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
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

            if artworkChanged || state.artwork == nil {
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
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
            self.elapsedTime = state.currentTime
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
        
        self.timestampDate = state.lastUpdated
    }

    private var currentHistoryIdentity: String? {
        guard trackNavigationIndex >= 0, trackNavigationIndex < trackNavigationHistory.count else {
            return nil
        }
        return trackNavigationHistory[trackNavigationIndex]
    }

    private func trackIdentity(title: String, artist: String, album: String, bundleIdentifier: String?) -> String? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTitle.isEmpty || normalizedTitle == MusicDisplayPlaceholder.title {
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
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            DispatchQueue.main.async {
                self.isFetchingLyrics = false
                self.currentLyrics = ""
            }
            return
        }

        if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: title, artist: artist)
                    return
                }

                self.isFetchingLyrics = true
                self.currentLyrics = ""
                do {
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
                    if let result = try await AppleScriptHelper.execute(script), let lyricsString = result.stringValue, !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.currentLyrics = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.isFetchingLyrics = false
                        self.syncedLyrics = []
                        return
                    }
                } catch {
                }
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        } else {
            Task { @MainActor in
                self.isFetchingLyrics = true
                self.currentLyrics = ""
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        }
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String) async {
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            return
        }

        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.currentLyrics = ""
                self.isFetchingLyrics = false
                return
            }
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first {
                let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolved = plain.isEmpty ? synced : plain
                self.currentLyrics = resolved
                self.isFetchingLyrics = false
                if !synced.isEmpty {
                    self.syncedLyrics = self.parseLRC(synced)
                } else {
                    self.syncedLyrics = []
                }
            } else {
                self.currentLyrics = ""
                self.isFetchingLyrics = false
                self.syncedLyrics = []
            }
        } catch {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            self.syncedLyrics = []
        }
    }

  // MARK: - Synced lyrics helpers
    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        lrc.split(separator: "\n").forEach { lineSub in
            let line = String(lineSub)
            let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsLine = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let csRange = match.range(at: 3)
                let centiStr = csRange.location != NSNotFound ? nsLine.substring(with: csRange) : "0"
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let centis = Double(centiStr) ?? 0
                let time = minutes * 60 + seconds + centis / 100.0
                let textStart = match.range.location + match.range.length
                let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append((time, text))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return syncedLyrics[idx].text
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
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
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
        Task {
            await activeController?.togglePlay()
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
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
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
        Task { [weak self] in
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
