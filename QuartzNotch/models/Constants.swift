
import Foundation
import SwiftUI
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

enum ScreenRecordingVisibilityMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case disabled = "Disabled"
    case fullyHidden = "Fully hidden"
    case onlyWhenClosed = "Only when closed"
    case onlyWhenNotInUse = "Only when not in use"

    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system = "system"
    case ar = "ar"
    case cs = "cs"
    case de = "de"
    case en = "en"
    case enGB = "en-GB"
    case es = "es"
    case fr = "fr"
    case hu = "hu"
    case it = "it"
    case ko = "ko"
    case pl = "pl"
    case ptBR = "pt-BR"
    case ru = "ru"
    case tr = "tr"
    case uk = "uk"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var appleLanguagesValue: [String]? {
        self == .system ? nil : [rawValue]
    }

    var displayName: String {
        switch self {
        case .system: return "System language"
        case .ar: return "العربية"
        case .cs: return "Čeština"
        case .de: return "Deutsch"
        case .en: return "English"
        case .enGB: return "English (UK)"
        case .es: return "Español"
        case .fr: return "Français"
        case .hu: return "Magyar"
        case .it: return "Italiano"
        case .ko: return "한국어"
        case .pl: return "Polski"
        case .ptBR: return "Português (Brasil)"
        case .ru: return "Русский"
        case .tr: return "Türkçe"
        case .uk: return "Українська"
        case .zhHans: return "简体中文"
        }
    }
}

enum AppLanguageManager {
    static func apply(_ language: AppLanguage) {
        if let appleLanguagesValue = language.appleLanguagesValue {
            UserDefaults.standard.set(appleLanguagesValue, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

enum AppLocalizer {
    static func localized(_ key: String, table: String? = nil) -> String {
        let language = Defaults[.appLanguage]
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
        }

        return bundle.localizedString(forKey: key, value: key, table: table)
    }
}

extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
    static let playbackScopeChanged = Notification.Name("playbackScopeChanged")
    static let musicPreviousButtonAnimationTriggered = Notification.Name("musicPreviousButtonAnimationTriggered")
    static let musicNextButtonAnimationTriggered = Notification.Name("musicNextButtonAnimationTriggered")
    static let hoverButtonAnimationNoop = Notification.Name("hoverButtonAnimationNoop")

  /// Request the notch window to temporarily become key to allow inline text entry.
    static let notchTextInputBegan = Notification.Name("notchTextInputBegan")
  /// Release key status after inline text entry ends.
    static let notchTextInputEnded = Notification.Name("notchTextInputEnded")
}

enum PlaybackScope: String, CaseIterable, Identifiable, Defaults.Serializable {
    case systemWide = "System Wide"
    case musicOnly = "Music Only"

    var id: String { self.rawValue }
}

enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

enum LargeScreenLayoutPreviewMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic = "Automatic"
    case macBookAir15 = "MacBook Air 15-inch"
    case macBookPro16 = "MacBook Pro 16-inch"

    var id: String { rawValue }

    var simulatedClosedNotchHeight: CGFloat? {
        switch self {
        case .automatic:
            return nil
        case .macBookAir15:
            return 35
        case .macBookPro16:
            return 37
        }
    }

    var simulatedOpenHeaderCenterWidth: CGFloat? {
        switch self {
        case .automatic:
            return nil
        case .macBookAir15:
            return 202
        case .macBookPro16:
            return 214
        }
    }
}

extension Defaults.Keys {
  // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: false)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    
  // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.2)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let cameraPreviewClickAction = Key<CameraPreviewClickAction>("cameraPreviewClickAction", default: .capturePhoto)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: true)
    static let enableLockScreenMediaWidget = Key<Bool>("enableLockScreenMediaWidget", default: true)
    static let lockScreenMusicPanelWidth = Key<Double>("lockScreenMusicPanelWidth", default: 420)
    static let lockScreenMusicVerticalOffset = Key<Double>("lockScreenMusicVerticalOffset", default: 0)
    static let hideFromScreenRecordingLegacy = Key<Bool>("hideFromScreenRecording", default: false)
    static let hideFromScreenRecordingMode = Key<ScreenRecordingVisibilityMode>(
        "hideFromScreenRecordingMode",
        default: .onlyWhenNotInUse
    )
    
  // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    static let showMirror = Key<Bool>("showMirror", default: true)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)
    static let hideMusicSourceAppIcon = Key<Bool>("hideMusicSourceAppIcon", default: false)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: false)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
  // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
  // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let liveAudioWaveform = Key<Bool>("liveAudioWaveform", default: false)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let enableNotchLyrics = Key<Bool>("enableNotchLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
  // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: false)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: false)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: false)

  // MARK: Toolbar
    static let toolbarEnabled = Key<Bool>("toolbarEnabled", default: true)
    
  // MARK: Live Activities
    static let liveActivityShelfContent = Key<Bool>("liveActivityShelfContent", default: true)
    static let liveActivityLockScreen = Key<Bool>("liveActivityLockScreen", default: true)
    static let enableLockScreenTimerWidget = Key<Bool>("enableLockScreenTimerWidget", default: true)
    static let bluetoothLiveActivityEnabled = Key<Bool>("bluetoothLiveActivityEnabled", default: true)
    static let focusLiveActivityEnabled = Key<Bool>("focusLiveActivityEnabled", default: true)
  /// Closed-notch timer indicator (Quick Timers page)
    static let liveActivityTimerEnabled = Key<Bool>("liveActivityTimerEnabled", default: true)
  /// Quick timer alert tone selection.
    static let quickTimerAlertToneID = Key<String>("quickTimerAlertToneID", default: "systemDefault")
  /// Mirrors Clock.app system timer into the timer live activity.
    static let mirrorSystemClockTimer = Key<Bool>("mirrorSystemClockTimer", default: true)

  // MARK: Pages
    static let pageHomeEnabled = Key<Bool>("pageHomeEnabled", default: true)
    static let pageShelfEnabled = Key<Bool>("pageShelfEnabled", default: true)
    static let pageThirdEnabled = Key<Bool>("pageThirdEnabled", default: true)
    static let pageOrder = Key<[String]>(
        "pageOrder",
        default: NotchViews.allCases.map(\.rawValue)
    )
    static let pageUseLiquidGlassBackground = Key<Bool>("pageUseLiquidGlassBackground", default: false)
    static let forceLiquidGlassCompatibilityFallback = Key<Bool>("forceLiquidGlassCompatibilityFallback", default: false)

  // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
  // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
  // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let allowShelfRevealWhenPageHidden = Key<Bool>("allowShelfRevealWhenPageHidden", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
  // MARK: Calendar
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let showCalendarToggle = Key<Bool>("showCalendarToggle", default: true)
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
  // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
  // MARK: Media Controller (legacy - kept only for migration)
    static let mediaController = Key<MediaControllerType>("mediaController", default: .nowPlaying)

  // MARK: Playback scope (new 2-mode setting)
    static let playbackScope = Key<PlaybackScope>("playbackScope", default: .systemWide)
    
  // MARK: Advanced Settings
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    static let cinemaMode = Key<Bool>("cinemaMode", default: false)
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    static let appIconChoice = Key<AppIconChoice>("appIconChoice", default: .classic)
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let debugLargeScreenLayoutPreviewMode = Key<LargeScreenLayoutPreviewMode>(
        "debugLargeScreenLayoutPreviewMode",
        default: .automatic
    )
    
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
    static let didMigratePlaybackScopeV1 = Key<Bool>("didMigratePlaybackScope_v1", default: false)
}
