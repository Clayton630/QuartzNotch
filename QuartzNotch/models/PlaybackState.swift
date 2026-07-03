
import Foundation

enum RepeatMode: Int, Codable {
    case off = 1
    case one = 2
    case all = 3
}

struct PlaybackState {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = "I'm Handsome"
    var artist: String = "Me"
    var album: String = "Self Love"
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false
}

extension PlaybackState: Equatable {
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && abs(lhs.currentTime - rhs.currentTime) < 0.05
            && lhs.duration == rhs.duration
            && lhs.playbackRate == rhs.playbackRate
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && PlaybackState.hasSameArtwork(lhs.artwork, rhs.artwork)
            && abs(lhs.volume - rhs.volume) < 0.005
            && lhs.isFavorite == rhs.isFavorite
    }

    private static func hasSameArtwork(_ lhs: Data?, _ rhs: Data?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            guard left.count == right.count else { return false }
            if left.count < 512 { return left == right }
            return left.prefix(256) == right.prefix(256)
                && left.suffix(256) == right.suffix(256)
        default:
            return false
        }
    }
}
