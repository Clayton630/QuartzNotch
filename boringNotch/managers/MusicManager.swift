//
// MusicManager.swift
// boringNotch
//
// Created by Harsh Vardhan Goswami on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!


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

  // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

  // Active controller
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

  // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage

  // Album art flip animation (UI-driven)
    @Published var albumArtFlipEventID: UUID = UUID()
    @Published var albumArtFlipDirection: AlbumArtFlipDirection = .next
    @Published var albumArtFlipImage: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
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

  // Store a lightweight signature instead of comparing full artwork Data blobs frequently.
    private struct ArtworkSignature: Equatable {
        let byteCount: Int
        let head: UInt64
        let tail: UInt64

        init?(_ data: Data?) {
            guard let data else { return nil }
      // Reject obviously invalid payloads early.
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

  // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    private var pendingAlbumArtFlipDirection: AlbumArtFlipDirection? = nil

  // Prevent slow artwork decodes from applying out-of-order when skipping tracks quickly.
    private var artworkDecodeRequestID: UUID = UUID()

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

  // MARK: - Initialization
    init() {
        migratePlaybackScopeIfNeeded()

    // Listen for changes to the 2-mode preference
        NotificationCenter.default.publisher(for: Notification.Name.playbackScopeChanged)
            .sink { [weak self] _ in
                self?.reselectActiveSource(reason: "scope-changed")
            }
            .store(in: &cancellables)

    // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
      // Initialize the active controller after deprecation check
            self.setupControllersIfNeeded()
            self.reselectActiveSource(reason: "startup")
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

    // Release active controller
        activeController = nil
    }

  // MARK: - Setup Methods (routing)
    private func setupControllersIfNeeded() {
        if nowPlayingController == nil {
            nowPlayingController = NowPlayingController()
        }
        if appleMusicController == nil { appleMusicController = AppleMusicController() }
        if spotifyController == nil { spotifyController = SpotifyController() }
        
    // YouTube Music controller is initialized lazily and safely
    // to avoid deprecation test failures at startup
        if youTubeMusicController == nil {
      // Only initialize if YouTube Music is actually running
            if NSWorkspace.shared.runningApplications.contains(where: { 
                $0.bundleIdentifier == "com.github.th-ch.youtube-music" 
            }) {
                youTubeMusicController = YouTubeMusicController()
        // Attach after a short delay to ensure initialization completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.attachYouTubeMusicIfNeeded()
                }
            }
        }

    // Subscribe once to each controller. We keep all states updated and route UI/controls.
        attach(controller: nowPlayingController, source: .nowPlaying)
        attach(controller: appleMusicController, source: .appleMusic)
        attach(controller: spotifyController, source: .spotify)
    // YouTube Music is attached separately after initialization
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

    // Recompute routing on any relevant change.
        reselectActiveSource(reason: "state-updated")
    }

    private func reselectActiveSource(reason: String) {
    // Ensure controllers exist
        setupControllersIfNeeded()

        let scope = Defaults[.playbackScope]
        let desired: InternalSource?

        switch scope {
        case .systemWide:
      // Prefer Now Playing for system-wide. If it can't be created or has no signal, fallback to music-only selection.
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
      // Ignore uninitialized states
            guard st.lastUpdated != .distantPast else { return nil }
            return (src, st)
        }

        let playing = candidates.filter { $0.1.isPlaying }
        if let best = playing.max(by: { $0.1.lastUpdated < $1.1.lastUpdated }) {
            return best.0
        }
    // If none is playing, keep the most recently updated music app (paused is fine)
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
    // Sanitize invalid artwork data cheaply (avoid decoding images on the main thread).
        effective.artwork = sanitizeArtworkData(effective.artwork)

    // Artwork fallback: if selected controller has no usable artwork, try Now Playing for the same bundle.
        if effective.artwork == nil, source != .nowPlaying,
           let np = stateBySource[.nowPlaying], np.bundleIdentifier == effective.bundleIdentifier {
            let npArtwork = sanitizeArtworkData(np.artwork)
            if npArtwork != nil {
                effective.artwork = npArtwork
            }
        }

    // Drive the existing UI update pipeline.
        updateFromPlaybackState(effective)
    }

    private func sanitizeArtworkData(_ data: Data?) -> Data? {
        guard let data else { return nil }
    // Very small payloads are almost always "" / null / placeholders from AppleScript.
        if data.count < 256 { return nil }
        return data
    }

    private func migratePlaybackScopeIfNeeded() {
    // One-time migration: old 4-option selector -> new 2-mode selector
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
    // Check for playback state changes (playing/paused)
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

    // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

    // Check for artwork changes (cheap signature compare; avoids full Data equality on large blobs).
        let newSig = ArtworkSignature(state.artwork)
        let artworkChanged = (newSig != nil) && (newSig != self.artworkSignature)
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

    // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
        // Don't immediately downgrade to the app icon: keep the last known good artwork.
        // Only use the app icon if we don't have anything meaningful yet.
                if self.albumArt == defaultImage, let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork
            self.artworkSignature = newSig

            if artworkChanged || state.artwork == nil {
        // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

      // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

      // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
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
      // Update volume control support from active controller
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

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
    // Toggle based on current state
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
                    set loved of current track to (not loved of current track)
                    return loved of current track
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

    // Prefer native Apple Music lyrics when available
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
          // fall through to web lookup
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

    // LRCLIB simple search (no auth): https://lrclib.net/api/search?track_name=...&artist_name=...
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
        // Prefer plain lyrics (syncedLyrics may also be present)
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
      // Match [mm:ss.xx] or [m:ss]
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
    // Binary search for last line with time <= elapsed
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
    // Cancel any existing animation
        flipWorkItem?.cancel()

    // Create a new animation
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
    // Mark the latest decode request and ignore late completions.
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

    // Publish a flip event for UI consumers (Dynamic Island-like).
        let direction = pendingAlbumArtFlipDirection ?? .next
        pendingAlbumArtFlipDirection = nil
        self.albumArtFlipDirection = direction
        self.albumArtFlipImage = newAlbumArt
        self.albumArtFlipEventID = UUID()

    // Update the canonical artwork reference (for non-flip consumers).
        self.albumArt = newAlbumArt
        if Defaults[.coloredSpectrogram] {
            self.calculateAverageColor()
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
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
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
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        pendingAlbumArtFlipDirection = .previous
        Task {
            await activeController?.previousTrack()
        }
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
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
    // Request immediate updates from controllers relevant to the 2-mode router.
        Task { [weak self] in
            guard let self = self else { return }
            self.setupControllersIfNeeded()

      // Always keep Now Playing fresh (used for System Wide + artwork fallback)
            if let np = self.nowPlayingController {
                await np.updatePlaybackInfo()
            }

      // Keep music apps fresh (used for Music Only selection)
            if let am = self.appleMusicController, am.isActive() { await am.updatePlaybackInfo() }
            if let sp = self.spotifyController, sp.isActive() { await sp.updatePlaybackInfo() }
            if let yt = self.youTubeMusicController, yt.isActive() {
                await yt.pollPlaybackState()
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
    // Check if bundle identifier is valid and if the app is actually running
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
      // For unsupported apps, don't sync volume
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
