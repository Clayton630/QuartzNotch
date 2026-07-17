import AppKit
import Combine
import Defaults
import SwiftUI

private func makeDefaultAlbumArtImage() -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedWhite: 0.28, alpha: 1).setFill()
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

final class MusicManager: ObservableObject {
    static let shared = MusicManager()

    @Published var songTitle = MusicDisplayPlaceholder.title
    @Published var artistName = MusicDisplayPlaceholder.artist
    @Published var albumArt = defaultImage
    @Published var albumArtFlipEventID = UUID()
    @Published var albumArtFlipDirection: AlbumArtFlipDirection = .next
    @Published var albumArtFlipImage = defaultImage
    @Published var isPlaying = false
    @Published var album = MusicDisplayPlaceholder.album
    @Published var isPlayerIdle = true
    @Published var avgColor: NSColor = .white
    @Published var spectrogramTopColor: NSColor = .white
    @Published var spectrogramBottomColor: NSColor = .white
    @Published var bundleIdentifier: String?
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate = Date()
    @Published var playbackRate: Double = 1
    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported = false
    @Published var usingAppIconForArtwork = false
    @Published var currentLyrics = ""
    @Published var isFetchingLyrics = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published private(set) var lyricsSnapshot: LyricsSnapshot = .empty
    @Published var isFavoriteTrack = false
    @Published var isArtworkTintReady = false
    @Published var playbackPreviewPosition: TimeInterval?
    @Published private(set) var lyricsTrackKey = ""

    let coordinator = QuartzViewCoordinator.shared

    private let mediaCoordinator: AtollMediaCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    private var lyricsFetchTask: Task<Void, Never>?
    private var favoriteTask: Task<Void, Never>?
    private var activeLyricsRequestID = UUID()
    private var activeLyricsKey = ""
    private var currentTrackKey = ""
    private var currentTrackDirection: AlbumArtFlipDirection = .next
    private var pendingAlbumArtFlipDirection: AlbumArtFlipDirection?
    private var lastEngineArtwork: NSImage?
    private var lastForceUpdateAt = Date.distantPast

    var isUsingIdleMetadata: Bool {
        let normalizedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty
            || normalizedTitle == MusicDisplayPlaceholder.title
            || normalizedTitle == MusicDisplayPlaceholder.rawTitle
    }

    var hasResolvableBundleIcon: Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    private init() {
        AtollMediaPreferences.selectedSource = Self.mediaSource(for: Defaults[.playbackScope]).rawValue
        mediaCoordinator = AtollMediaCoordinator()
        mediaCoordinator.onChange = { [weak self] state in
            guard let self else { return }
            if Thread.isMainThread {
                self.apply(state)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.apply(state)
                }
            }
        }

        NotificationCenter.default.publisher(for: .playbackScopeChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.mediaCoordinator.select(Self.mediaSource(for: Defaults[.playbackScope]))
            }
            .store(in: &cancellables)

        Publishers.Merge(
            Defaults.publisher(.enableLyrics).map(\.newValue),
            Defaults.publisher(.enableNotchLyrics).map(\.newValue)
        )
        .sink { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.refreshLyricsForCurrentTrack()
            } else {
                self.lyricsFetchTask?.cancel()
                self.clearLyricsState()
            }
        }
        .store(in: &cancellables)

        mediaCoordinator.start()
    }

    public func destroy() {
        debounceIdleTask?.cancel()
        lyricsFetchTask?.cancel()
        favoriteTask?.cancel()
        cancellables.removeAll()
        mediaCoordinator.onChange = nil
        mediaCoordinator.stop()
    }

    private static func mediaSource(for scope: PlaybackScope) -> AtollMediaSource {
        scope == .musicOnly ? .musicOnly : .nowPlaying
    }

    private func apply(_ state: NotchMediaState) {
        let available = state.isAvailable
        let nextTitle = available && !state.title.isEmpty ? state.title : MusicDisplayPlaceholder.title
        let nextArtist = available ? state.artist : MusicDisplayPlaceholder.artist
        let nextAlbum = available && !state.album.isEmpty ? state.album : MusicDisplayPlaceholder.album
        let nextBundleIdentifier = available && !state.bundleIdentifier.isEmpty ? state.bundleIdentifier : nil
        let nextTrackKey = available
            ? trackIdentity(
                title: nextTitle,
                artist: nextArtist,
                album: nextAlbum,
                bundleIdentifier: nextBundleIdentifier
            )
            : ""
        let trackChanged = nextTrackKey != currentTrackKey

        if trackChanged {
            currentTrackKey = nextTrackKey
            currentTrackDirection = pendingAlbumArtFlipDirection ?? .next
            pendingAlbumArtFlipDirection = nil
        }

        songTitle = nextTitle
        artistName = nextArtist
        album = nextAlbum
        bundleIdentifier = nextBundleIdentifier
        isPlaying = available && state.isPlaying
        songDuration = max(0, state.duration)
        elapsedTime = min(max(0, state.elapsed), songDuration > 0 ? songDuration : max(0, state.elapsed))
        timestampDate = state.updatedAt == .distantPast ? Date() : state.updatedAt
        playbackRate = state.playbackRate
        isShuffled = state.isShuffled
        repeatMode = state.repeatMode
        volumeControlSupported = Self.supportsVolume(bundleIdentifier: nextBundleIdentifier)

        updateArtwork(from: state, trackChanged: trackChanged)
        updateIdleState(isPlaying: isPlaying)

        if trackChanged {
            fetchLyricsIfAvailable(
                bundleIdentifier: nextBundleIdentifier,
                title: nextTitle,
                artist: nextArtist,
                album: nextAlbum,
                duration: songDuration
            )
            refreshFavoriteState()
            updateSneakPeek()
        }
    }

    private func updateArtwork(from state: NotchMediaState, trackChanged: Bool) {
        if let artwork = state.artwork {
            let artworkChanged = artwork !== lastEngineArtwork
            lastEngineArtwork = artwork
            usingAppIconForArtwork = false
            if trackChanged || artworkChanged {
                presentArtwork(artwork)
            }
            return
        }

        guard trackChanged else { return }
        lastEngineArtwork = nil

        if let bundleIdentifier,
           let icon = AppIconAsNSImage(for: bundleIdentifier) {
            usingAppIconForArtwork = true
            presentArtwork(icon)
        } else {
            usingAppIconForArtwork = false
            presentArtwork(defaultImage)
        }
    }

    private func presentArtwork(_ artwork: NSImage) {
        albumArtFlipDirection = currentTrackDirection
        albumArtFlipImage = artwork
        albumArtFlipEventID = UUID()
        albumArt = artwork
        isArtworkTintReady = false

        if Defaults[.coloredSpectrogram] {
            calculateAverageColor()
            calculateSpectrogramGradientColors()
        } else {
            isArtworkTintReady = true
        }
    }

    private func updateIdleState(isPlaying: Bool) {
        debounceIdleTask?.cancel()
        if isPlaying {
            isPlayerIdle = false
            return
        }

        debounceIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isPlaying else { return }
                withAnimation { self.isPlayerIdle = true }
            }
        }
    }

    private func trackIdentity(
        title: String,
        artist: String,
        album: String,
        bundleIdentifier: String?
    ) -> String {
        [bundleIdentifier ?? "", title, artist, album]
            .map {
                $0.folding(options: .diacriticInsensitive, locale: .current)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .joined(separator: "|")
    }

    private func lyricsIdentity(bundleIdentifier: String?, title: String, artist: String, album: String) -> String {
        trackIdentity(title: title, artist: artist, album: album, bundleIdentifier: bundleIdentifier)
    }

    private func clearLyricsState(for key: String = "") {
        let nextSnapshot = key.isEmpty
            ? LyricsSnapshot.empty
            : LyricsSnapshot(
                trackKey: key,
                state: .unavailable,
                plainLyrics: "",
                syncedLines: [],
                source: nil,
                fetchedAt: Date()
            )

        lyricsTrackKey = key
        isFetchingLyrics = false
        currentLyrics = ""
        syncedLyrics = []
        if lyricsSnapshot != nextSnapshot { lyricsSnapshot = nextSnapshot }
    }

    private func fetchLyricsIfAvailable(
        bundleIdentifier: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) {
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
            clearLyricsState()
            return
        }

        guard key != activeLyricsKey else { return }
        lyricsFetchTask?.cancel()
        activeLyricsKey = key
        activeLyricsRequestID = UUID()
        let requestID = activeLyricsRequestID

        lyricsFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
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

            let fallback = await self.fetchAppleMusicPlainLyricsIfAvailable(bundleIdentifier: bundleIdentifier)
            let snapshot = await LyricsService.shared.fetchSnapshot(for: request, plainFallback: fallback)
            guard requestID == self.activeLyricsRequestID,
                  key == self.activeLyricsKey,
                  !Task.isCancelled else { return }
            self.applyLyricsSnapshot(snapshot)
        }
    }

    func refreshLyricsForCurrentTrack() {
        let request = LyricsTrackRequest(
            bundleIdentifier: bundleIdentifier,
            title: songTitle,
            artist: artistName,
            album: album,
            duration: songDuration
        )
        let key = request.cacheKey.isEmpty
            ? lyricsIdentity(
                bundleIdentifier: bundleIdentifier,
                title: songTitle,
                artist: artistName,
                album: album
            )
            : request.cacheKey

        if lyricsSnapshot.trackKey == key,
           lyricsSnapshot.hasAnyLyrics || lyricsSnapshot.state == .instrumental {
            return
        }

        activeLyricsKey = ""
        activeLyricsRequestID = UUID()
        fetchLyricsIfAvailable(
            bundleIdentifier: bundleIdentifier,
            title: songTitle,
            artist: artistName,
            album: album,
            duration: songDuration
        )
    }

    @MainActor
    private func applyLyricsSnapshot(_ snapshot: LyricsSnapshot) {
        if lyricsSnapshot != snapshot { lyricsSnapshot = snapshot }
        if lyricsTrackKey != snapshot.trackKey { lyricsTrackKey = snapshot.trackKey }
        isFetchingLyrics = snapshot.state == .loading
        currentLyrics = snapshot.plainLyrics
        let nextSyncedLyrics = snapshot.syncedLines.map { (time: $0.startTime, text: $0.text) }
        if syncedLyrics.count != nextSyncedLyrics.count
            || !zip(syncedLyrics, nextSyncedLyrics).allSatisfy({ lhs, rhs in
                lhs.time == rhs.time && lhs.text == rhs.text
            }) {
            syncedLyrics = nextSyncedLyrics
        }
    }

    private func fetchAppleMusicPlainLyricsIfAvailable(bundleIdentifier: String?) async -> String? {
        guard bundleIdentifier == "com.apple.Music",
              !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return nil
        }

        let script = """
        tell application "Music"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        set currentLyrics to lyrics of current track
                        if currentLyrics is missing value then
                            return ""
                        else
                            return currentLyrics
                        end if
                    on error
                        return ""
                    end try
                end if
            end if
            return ""
        end tell
        """

        guard let result = try? await AppleScriptHelper.execute(script),
              let lyrics = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lyrics.isEmpty else {
            return nil
        }
        return lyrics
    }

    func lyricIndex(at elapsed: Double) -> Int {
        let lines = lyricsSnapshot.syncedLines
        guard !lines.isEmpty else { return -1 }
        var low = 0
        var high = lines.count - 1
        var result = 0

        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].startTime <= elapsed {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }

    func lyricLine(at elapsed: Double) -> String {
        guard lyricsSnapshot.hasSyncedLyrics else { return currentLyrics }
        let index = lyricIndex(at: elapsed)
        guard lyricsSnapshot.syncedLines.indices.contains(index) else { return "" }
        return lyricsSnapshot.syncedLines[index].text
    }

    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }
        let estimate = elapsedTime + date.timeIntervalSince(timestampDate) * playbackRate
        return min(max(0, estimate), songDuration)
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
        let artwork = albumArt
        artwork.averageColor { [weak self] color in
            DispatchQueue.main.async {
                guard let self, self.albumArt === artwork else { return }
                withAnimation(.smooth) {
                    self.avgColor = color ?? .white
                    self.isArtworkTintReady = true
                }
            }
        }
    }

    func calculateSpectrogramGradientColors() {
        let artwork = albumArt
        artwork.verticalGradientColors { [weak self] top, bottom in
            DispatchQueue.main.async {
                guard let self, self.albumArt === artwork else { return }
                withAnimation(.smooth) {
                    self.spectrogramTopColor = top ?? self.avgColor
                    self.spectrogramBottomColor = bottom ?? self.avgColor
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.toggleSneakPeek(status: true, type: .music)
            }
        }
    }

    func playPause() {
        togglePlay()
    }

    func play() {
        mediaCoordinator.play()
    }

    func pause() {
        mediaCoordinator.pause()
    }

    func togglePlay() {
        mediaCoordinator.togglePlay()
    }

    func toggleShuffle() {
        mediaCoordinator.toggleShuffle()
    }

    func toggleRepeat() {
        mediaCoordinator.toggleRepeat()
    }

    func nextTrack() {
        pendingAlbumArtFlipDirection = .next
        triggerNextButtonAnimation()
        mediaCoordinator.nextTrack()
    }

    func previousTrack() {
        pendingAlbumArtFlipDirection = .previous
        triggerPreviousButtonAnimation()
        mediaCoordinator.previousTrack()
    }

    func triggerNextButtonAnimation() {
        NotificationCenter.default.post(name: .musicNextButtonAnimationTriggered, object: nil)
    }

    func triggerPreviousButtonAnimation() {
        NotificationCenter.default.post(name: .musicPreviousButtonAnimationTriggered, object: nil)
    }

    func seek(to position: TimeInterval) {
        let clamped = min(max(0, position), songDuration > 0 ? songDuration : position)
        elapsedTime = clamped
        timestampDate = Date()
        mediaCoordinator.seek(to: clamped)
    }

    func skip(seconds: TimeInterval) {
        seek(to: min(max(0, estimatedPlaybackPosition() + seconds), songDuration))
    }

    func setVolume(to level: Double) {
        let clamped = min(max(0, level), 1)
        volume = clamped
        guard let application = Self.scriptableApplication(for: bundleIdentifier) else { return }
        let value = Int((clamped * 100).rounded())
        Task {
            try? await AppleScriptHelper.executeVoid("""
            tell application "\(application)"
                if it is running then set sound volume to \(value)
            end tell
            """)
        }
    }

    func syncVolumeFromActiveApp() async {
        guard let application = Self.scriptableApplication(for: bundleIdentifier),
              let result = try? await AppleScriptHelper.execute("""
              tell application "\(application)"
                  if it is running then
                      get sound volume
                  else
                      return 50
                  end if
              end tell
              """) else { return }

        let currentVolume = Double(result.int32Value) / 100
        await MainActor.run {
            if abs(currentVolume - self.volume) > 0.01 {
                self.volume = currentVolume
            }
        }
    }

    private static func scriptableApplication(for bundleIdentifier: String?) -> String? {
        switch bundleIdentifier {
        case "com.apple.Music": "Music"
        case "com.spotify.client": "Spotify"
        default: nil
        }
    }

    private static func supportsVolume(bundleIdentifier: String?) -> Bool {
        scriptableApplication(for: bundleIdentifier) != nil
    }

    func toggleFavoriteTrack() {
        guard bundleIdentifier == "com.apple.Music" else { return }
        favoriteTask?.cancel()
        favoriteTask = Task { [weak self] in
            guard let self,
                  let result = try? await AppleScriptHelper.execute("""
                  tell application "Music"
                      if it is running then
                          try
                              set favorited of current track to (not favorited of current track)
                              return favorited of current track
                          on error
                              return false
                          end try
                      end if
                      return false
                  end tell
                  """) else { return }
            await MainActor.run { self.isFavoriteTrack = result.booleanValue }
        }
    }

    private func refreshFavoriteState() {
        favoriteTask?.cancel()
        guard bundleIdentifier == "com.apple.Music" else {
            isFavoriteTrack = false
            return
        }

        favoriteTask = Task { [weak self] in
            guard let self,
                  let result = try? await AppleScriptHelper.execute("""
                  tell application "Music"
                      if it is running then
                          try
                              return favorited of current track
                          on error
                              return false
                          end try
                      end if
                      return false
                  end tell
                  """) else { return }
            await MainActor.run { self.isFavoriteTrack = result.booleanValue }
        }
    }

    func openMusicApp() {
        guard let bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    func forceUpdate() {
        let now = Date()
        guard now.timeIntervalSince(lastForceUpdateAt) > 0.2 else { return }
        lastForceUpdateAt = now
        mediaCoordinator.refresh()
    }
}
