import Foundation

enum AtollMediaPreferences {
    private static let defaults = UserDefaults.standard

    static var selectedSource: String {
        get { defaults.string(forKey: "atollMedia.selectedSource") ?? AtollMediaSource.nowPlaying.rawValue }
        set { defaults.set(newValue, forKey: "atollMedia.selectedSource") }
    }

    static var spotifySPDCCookie: String {
        get { defaults.string(forKey: "atollMedia.spotifySPDCCookie") ?? "" }
        set { defaults.set(newValue, forKey: "atollMedia.spotifySPDCCookie") }
    }

    static var spotifyAuthAccessToken: String {
        get { defaults.string(forKey: "atollMedia.spotifyAuthAccessToken") ?? "" }
        set { defaults.set(newValue, forKey: "atollMedia.spotifyAuthAccessToken") }
    }

    static var spotifyAuthAccessTokenExpiration: Double {
        get { defaults.double(forKey: "atollMedia.spotifyAuthAccessTokenExpiration") }
        set { defaults.set(newValue, forKey: "atollMedia.spotifyAuthAccessTokenExpiration") }
    }

    static var spotifyAuthLastValidatedAt: Double {
        get { defaults.double(forKey: "atollMedia.spotifyAuthLastValidatedAt") }
        set { defaults.set(newValue, forKey: "atollMedia.spotifyAuthLastValidatedAt") }
    }

    static var didClearLegacyURLCacheV1: Bool {
        get { defaults.bool(forKey: "atollMedia.didClearLegacyURLCacheV1") }
        set { defaults.set(newValue, forKey: "atollMedia.didClearLegacyURLCacheV1") }
    }
}
