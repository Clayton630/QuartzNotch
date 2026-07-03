
import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case bluetooth
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class QuartzViewCoordinator: ObservableObject {

 // MARK: - Shared motion presets (notch/live-activities)
    private let expandingInAnimation: Animation = NotchMotion.liveActivityIn
    private let batteryExpandingInAnimation: Animation = NotchMotion.liveActivityBatteryIn
    private let expandingOutAnimation: Animation = NotchMotion.liveActivityOut

    static let shared = QuartzViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var hudEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = preferredDefaultView()
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    private init() {
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("[OK] Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("[WARN] Could not find display named '\(legacyName)', falling back to main screen")
            }
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            }
        }

        hudReplacementCancellable = Defaults.publisher(.hudReplacement, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()

            if Defaults[.hudReplacement] && !authorized {
                Defaults[.hudReplacement] = false
            }

            if authorized {
                await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            } else if Defaults[.hudReplacement] {
                Defaults[.hudReplacement] = false
            }
        }
    }

    func preferredDefaultView(respectShelfPreference: Bool = false) -> NotchViews {
        if respectShelfPreference,
           Defaults[.pageShelfEnabled] || Defaults[.allowShelfRevealWhenPageHidden],
           !ShelfStateViewModel.shared.isEmpty,
           Defaults[.openShelfByDefault] {
            return .shelf
        }

        return enabledNotchViewsInConfiguredOrder().first ?? .home
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            return
        }
    }

    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        animationOverride: Animation? = nil
    ) {
        sneakPeekDuration = duration
        if type != .music {
            if !Defaults[.hudReplacement] {
                return
            }
        }
        Task { @MainActor in
            let animation = animationOverride ?? (status ? expandingInAnimation : expandingOutAnimation)
            withAnimation(animation) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(expandingOutAnimation) {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        Task { @MainActor in
            let animation: Animation
            if status {
                switch type {
                case .battery:
                    animation = batteryExpandingInAnimation
                case .bluetooth:
                    animation = NotchMotion.liveActivityBluetoothIn
                default:
                    animation = expandingInAnimation
                }
            } else {
                animation = expandingOutAnimation
            }
            withAnimation(animation) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    private func scheduleExpandingViewAutoHide() {
        guard expandingView.show else { return }
        expandingViewTask?.cancel()

        let duration: TimeInterval
        switch expandingView.type {
        case .download:
            duration = 2
        case .bluetooth:
            duration = 5
        case .battery:
            duration = 3.4
        default:
            duration = 3
        }
        let currentType = expandingView.type
        expandingViewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            self.toggleExpandingView(status: false, type: currentType)
        }
    }

 /// Cancel the auto-hide timer for the currently shown expanding view.
 /// Useful when the user is actively interacting (e.g. hovering a popup).
    func pauseExpandingViewAutoHide() {
        expandingViewTask?.cancel()
    }

 /// Resume the auto-hide timer for the currently shown expanding view.
    func resumeExpandingViewAutoHide() {
        scheduleExpandingViewAutoHide()
    }

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                scheduleExpandingViewAutoHide()
            } else {
                expandingViewTask?.cancel()
            }
        }
    }
    
    func showEmpty() {
        currentView = preferredDefaultView()
    }
}
