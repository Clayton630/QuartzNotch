import AppKit
import Combine
import Foundation

struct NotchMediaState: Equatable {
    var isAvailable = false
    var isPlaying = false
    var title = "Aucun media"
    var artist = ""
    var album = ""
    var bundleIdentifier = ""
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Double = 1
    var isShuffled = false
    var repeatMode: RepeatMode = .off
    var updatedAt = Date.distantPast
    var artwork: NSImage?

    static func == (lhs: NotchMediaState, rhs: NotchMediaState) -> Bool {
        lhs.isAvailable == rhs.isAvailable
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && abs(lhs.elapsed - rhs.elapsed) < 0.05
            && lhs.duration == rhs.duration
            && lhs.playbackRate == rhs.playbackRate
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && lhs.artwork === rhs.artwork
    }
}

final class NotchMediaViewModel: ObservableObject {
    @Published private(set) var state = NotchMediaState()

    func update(_ state: NotchMediaState) {
        guard self.state != state else { return }
        self.state = state
    }
}
