
import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews: String, CaseIterable, Hashable, Codable, Defaults.Serializable, Identifiable {
    case home
    case shelf
    case third

    public var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .home:
            return "Media controls"
        case .shelf:
            return "Shelf + Share"
        case .third:
            return "Timers + Clipboard"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .home:
            return "Player, artwork and playback controls"
        case .shelf:
            return "Shelf items, quick share and drops"
        case .third:
            return "Quick timers and clipboard"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .home:
            return "play.rectangle.fill"
        case .shelf:
            return "shippingbox.fill"
        case .third:
            return "timer"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .home:
            return "Home"
        case .shelf:
            return "Shelf"
        case .third:
            return "Third"
        }
    }

    var isEnabled: Bool {
        visibilityMode == .alwaysShow
    }

    var visibilityMode: NotchPageVisibilityMode {
        switch self {
        case .home:
            return Defaults[.pageHomeEnabled] ? .alwaysShow : .disabled
        case .shelf:
            if Defaults[.pageShelfEnabled] {
                return .alwaysShow
            }
            return Defaults[.allowShelfRevealWhenPageHidden] ? .showConditionally : .disabled
        case .third:
            return Defaults[.pageThirdEnabled] ? .alwaysShow : .disabled
        }
    }

    var supportedVisibilityModes: [NotchPageVisibilityMode] {
        switch self {
        case .shelf:
            return [.alwaysShow, .showConditionally, .disabled]
        case .home, .third:
            return [.alwaysShow, .disabled]
        }
    }

    static func normalizedOrder(from storedValues: [String]) -> [NotchViews] {
        var seen = Set<NotchViews>()
        var ordered = storedValues.compactMap(NotchViews.init(rawValue:)).filter { seen.insert($0).inserted }

        for view in NotchViews.allCases where seen.insert(view).inserted {
            ordered.append(view)
        }

        return ordered
    }
}

public enum NotchPageVisibilityMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case alwaysShow = "Always show"
    case showConditionally = "Show conditionally"
    case disabled = "Disabled"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .alwaysShow: return "Always show"
        case .showConditionally: return "Smart reveal"
        case .disabled: return "Disabled"
        }
    }
}

func configuredNotchViewOrder() -> [NotchViews] {
    NotchViews.normalizedOrder(from: Defaults[.pageOrder])
}

func enabledNotchViewsInConfiguredOrder() -> [NotchViews] {
    let enabled = configuredNotchViewOrder().filter(\.isEnabled)
    return enabled.isEmpty ? [.home] : enabled
}

@MainActor func presentableNotchViewsInConfiguredOrder(currentView: NotchViews) -> [NotchViews] {
    let presentable = configuredNotchViewOrder().filter { view in
        switch view.visibilityMode {
        case .alwaysShow:
            return true
        case .showConditionally:
            let shelfHasItems = !ShelfStateViewModel.shared.items.isEmpty
            return Defaults[.boringShelf] && (currentView == .shelf || (shelfHasItems && Defaults[.openShelfByDefault]))
        case .disabled:
            return false
        }
    }

    return presentable.isEmpty ? [.home] : presentable
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}

enum AppIconChoice: String, CaseIterable, Identifiable, Defaults.Serializable {
    case classic = "Quartz Notch"
    case quartzNew = "Quartz New Icon"

    var id: String { rawValue }
}

enum CameraPreviewClickAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case none = "Disabled"
    case closePreview = "Close preview"
    case capturePhoto = "Capture photo"

    var id: String { rawValue }
}
