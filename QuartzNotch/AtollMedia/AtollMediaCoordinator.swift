import AppKit
import Combine
import Foundation

enum AtollMediaSource: String, CaseIterable {
    case nowPlaying
    case musicOnly

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .musicOnly: "Music Only"
        }
    }
}

final class AtollMediaCoordinator {
    var onChange: ((NotchMediaState) -> Void)?

    private(set) var state = NotchMediaState()
    private(set) var source: AtollMediaSource
    private var controller: (any MediaControllerProtocol)?
    private var subscription: AnyCancellable?
    private var started = false
    private var artworkStore = ArtworkStore()

    init() {
        source = Self.source(from: AtollMediaPreferences.selectedSource)
    }

    func start() {
        guard !started else { return }
        started = true
        select(source)
    }

    func stop() {
        subscription = nil
        controller = nil
        started = false
        artworkStore.removeAll()
        publish(NotchMediaState())
    }

    func select(_ source: AtollMediaSource) {
        self.source = source
        AtollMediaPreferences.selectedSource = source.rawValue
        subscription = nil
        controller = makeController(for: source)
        artworkStore.removeAll()
        publish(NotchMediaState())

        guard let controller else { return }
        subscription = controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playbackState in
                guard let self else { return }
                self.publish(self.presentationState(from: playbackState))
            }

        Task { await controller.updatePlaybackInfo() }
    }

    func refresh() {
        guard let controller else { return }
        Task { await controller.updatePlaybackInfo() }
    }

    func togglePlay() {
        guard let controller else { return }
        Task { await controller.togglePlay() }
    }

    func play() {
        guard let controller else { return }
        Task { await controller.play() }
    }

    func pause() {
        guard let controller else { return }
        Task { await controller.pause() }
    }

    func nextTrack() {
        guard let controller else { return }
        Task { await controller.nextTrack() }
    }

    func previousTrack() {
        guard let controller else { return }
        Task { await controller.previousTrack() }
    }

    func seek(to seconds: TimeInterval) {
        guard let controller else { return }
        Task { await controller.seek(to: seconds) }
    }

    func toggleShuffle() {
        guard let controller else { return }
        Task { await controller.toggleShuffle() }
    }

    func toggleRepeat() {
        guard let controller else { return }
        Task { await controller.toggleRepeat() }
    }

    private func makeController(for source: AtollMediaSource) -> (any MediaControllerProtocol)? {
        switch source {
        case .nowPlaying: NowPlayingController()
        case .musicOnly: MusicOnlyController()
        }
    }

    private static func source(from storedValue: String) -> AtollMediaSource {
        AtollMediaSource(rawValue: storedValue)
            ?? (storedValue == AtollMediaSource.nowPlaying.rawValue ? .nowPlaying : .musicOnly)
    }

    private func publish(_ state: NotchMediaState) {
        guard self.state != state else { return }
        self.state = state
        onChange?(state)
    }

    private func presentationState(from playbackState: PlaybackState) -> NotchMediaState {
        let title = playbackState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = playbackState.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let unavailableTitles: Set<String> = ["", "unknown", "not playing", "i'm handsome"]
        let unavailableArtists: Set<String> = ["", "unknown", "me"]
        let isAvailable = playbackState.isPlaying
            || !unavailableTitles.contains(title.lowercased())
            || !unavailableArtists.contains(artist.lowercased())

        return NotchMediaState(
            isAvailable: isAvailable,
            isPlaying: playbackState.isPlaying,
            title: isAvailable ? title : "Aucun media",
            artist: isAvailable ? artist : "",
            album: isAvailable ? playbackState.album : "",
            bundleIdentifier: isAvailable ? playbackState.bundleIdentifier : "",
            elapsed: playbackState.currentTime,
            duration: playbackState.duration,
            playbackRate: playbackState.playbackRate,
            isShuffled: playbackState.isShuffled,
            repeatMode: playbackState.repeatMode,
            updatedAt: playbackState.lastUpdated,
            artwork: artworkStore.image(for: playbackState)
        )
    }
}

private enum MusicApplication: CaseIterable, Hashable {
    case appleMusic
    case spotify
    case youtubeMusic
    case amazonMusic
    case cider

    var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: SpotifyController.bundleIdentifier
        case .youtubeMusic: YouTubeMusicConfiguration.default.bundleIdentifier
        case .amazonMusic: AmazonMusicController.bundleIdentifier
        case .cider: CiderController.bundleIdentifier
        }
    }

    func makeController() -> (any MediaControllerProtocol)? {
        switch self {
        case .appleMusic: AppleMusicController()
        case .spotify: SpotifyController()
        case .youtubeMusic: YouTubeMusicController()
        case .amazonMusic: AmazonMusicController()
        case .cider: CiderController()
        }
    }
}

private final class MusicOnlyController: MediaControllerProtocol {
    @Published private var playbackState = PlaybackState(bundleIdentifier: "")

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        controllers.values.contains { $0.isWorking }
    }

    private var controllers: [MusicApplication: any MediaControllerProtocol] = [:]
    private var states: [MusicApplication: PlaybackState] = [:]
    private var subscriptions: [MusicApplication: AnyCancellable] = [:]
    private var activeApplication: MusicApplication?
    private var applicationSubscriptions = Set<AnyCancellable>()

    init() {
        observeApplicationLifecycle()
        synchronizeControllers()
    }

    deinit {
        applicationSubscriptions.removeAll()
        subscriptions.removeAll()
        controllers.removeAll()
    }

    func play() async {
        await activeController?.play()
    }

    func pause() async {
        await activeController?.pause()
    }

    func togglePlay() async {
        await activeController?.togglePlay()
    }

    func nextTrack() async {
        await activeController?.nextTrack()
    }

    func previousTrack() async {
        await activeController?.previousTrack()
    }

    func seek(to time: Double) async {
        await activeController?.seek(to: time)
    }

    func toggleShuffle() async {
        await activeController?.toggleShuffle()
    }

    func toggleRepeat() async {
        await activeController?.toggleRepeat()
    }

    func isActive() -> Bool {
        !controllers.isEmpty
    }

    func updatePlaybackInfo() async {
        synchronizeControllers()
        await activeController?.updatePlaybackInfo()
    }

    private var activeController: (any MediaControllerProtocol)? {
        guard let activeApplication else { return nil }
        return controllers[activeApplication]
    }

    private func observeApplicationLifecycle() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                self?.handleApplicationChange(notification)
            }
            .store(in: &applicationSubscriptions)

        notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                self?.handleApplicationChange(notification)
            }
            .store(in: &applicationSubscriptions)
    }

    private func handleApplicationChange(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              MusicApplication.allCases.contains(where: { $0.bundleIdentifier == application.bundleIdentifier })
        else { return }

        synchronizeControllers()
    }

    private func synchronizeControllers() {
        let runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        for application in MusicApplication.allCases where runningBundleIdentifiers.contains(application.bundleIdentifier) {
            startControllerIfNeeded(for: application)
        }

        for application in controllers.keys where !runningBundleIdentifiers.contains(application.bundleIdentifier) {
            subscriptions.removeValue(forKey: application)
            controllers.removeValue(forKey: application)
            states.removeValue(forKey: application)
        }

        selectBestApplication()
    }

    private func startControllerIfNeeded(for application: MusicApplication) {
        guard controllers[application] == nil,
              let controller = application.makeController()
        else { return }

        controllers[application] = controller
        subscriptions[application] = controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.receive(state, from: application)
            }

        Task { await controller.updatePlaybackInfo() }
    }

    private func receive(_ state: PlaybackState, from application: MusicApplication) {
        states[application] = state
        selectBestApplication()
    }

    private func selectBestApplication() {
        let candidates = states.filter { Self.isAvailable($0.value) }
        let selected = candidates.max { lhs, rhs in
            Self.priority(for: lhs.value, application: lhs.key, current: activeApplication)
                < Self.priority(for: rhs.value, application: rhs.key, current: activeApplication)
        }

        guard let selected else {
            activeApplication = nil
            playbackState = PlaybackState(bundleIdentifier: "")
            return
        }

        activeApplication = selected.key
        playbackState = selected.value
    }

    private static func isAvailable(_ state: PlaybackState) -> Bool {
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = state.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.isPlaying || (!["", "unknown", "not playing", "i'm handsome"].contains(title)
            && !["", "unknown", "me"].contains(artist))
    }

    private static func priority(
        for state: PlaybackState,
        application: MusicApplication,
        current: MusicApplication?
    ) -> (Int, Int, Date) {
        (state.isPlaying ? 1 : 0, application == current ? 1 : 0, state.lastUpdated)
    }
}

private struct TrackIdentity: Hashable {
    let bundleIdentifier: String
    let title: String
    let artist: String
    let album: String

    init?(_ playbackState: PlaybackState) {
        let title = Self.normalize(playbackState.title)
        let artist = Self.normalize(playbackState.artist)
        let album = Self.normalize(playbackState.album)
        let unavailableTitles: Set<String> = ["", "unknown", "not playing", "i'm handsome"]
        let unavailableArtists: Set<String> = ["", "unknown", "me"]

        guard !unavailableTitles.contains(title), !unavailableArtists.contains(artist) else {
            return nil
        }

        self.bundleIdentifier = Self.normalize(playbackState.bundleIdentifier)
        self.title = title
        self.artist = artist
        self.album = album
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ArtworkSignature: Equatable {
    let byteCount: Int
    let prefix: UInt64
    let suffix: UInt64

    init(_ data: Data) {
        byteCount = data.count
        prefix = Self.hash(data.prefix(96))
        suffix = Self.hash(data.suffix(96))
    }

    private static func hash(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(1_469_598_103_934_665_603) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private struct ArtworkStore {
    private struct Entry {
        let signature: ArtworkSignature
        let image: NSImage
    }

    private static let capacity = 24
    private var entries: [TrackIdentity: Entry] = [:]
    private var recency: [TrackIdentity] = []

    mutating func image(for playbackState: PlaybackState) -> NSImage? {
        guard let identity = TrackIdentity(playbackState) else { return nil }

        guard let artworkData = playbackState.artwork else {
            return cachedImage(for: identity)
        }

        let signature = ArtworkSignature(artworkData)
        if let entry = entries[identity], entry.signature == signature {
            touch(identity)
            return entry.image
        }

        guard let image = NSImage(data: artworkData) else {
            return cachedImage(for: identity)
        }

        entries[identity] = Entry(signature: signature, image: image)
        touch(identity)
        trimToCapacity()
        return image
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
        recency.removeAll(keepingCapacity: false)
    }

    private mutating func cachedImage(for identity: TrackIdentity) -> NSImage? {
        guard let entry = entries[identity] else { return nil }
        touch(identity)
        return entry.image
    }

    private mutating func touch(_ identity: TrackIdentity) {
        recency.removeAll { $0 == identity }
        recency.append(identity)
    }

    private mutating func trimToCapacity() {
        while recency.count > Self.capacity {
            entries.removeValue(forKey: recency.removeFirst())
        }
    }
}
