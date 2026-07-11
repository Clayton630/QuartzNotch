
import Combine
import Defaults
import SwiftUI

class QuartzViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: QuartzAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var manualOpenUntil: Date = .distantPast
    @Published var isNotchTransitioning: Bool = false
    private var notchTransitionTask: Task<Void, Never>?
    private var isMarketingPreviewModel: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    @Published private(set) var effectiveClosedNotchHeight: CGFloat = getEffectiveClosedNotchHeight()
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var suppressCameraLayoutInOpenContent: Bool = false
    @Published var isRequestingAuthorization: Bool = false
    
    deinit {
        destroy()
    }

    func destroy() {
        notchTransitionTask?.cancel()
        notchTransitionTask = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize
        refreshClosedNotchMetrics()

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()
        setupLayoutObserver()
    }

    func configureForMarketingPreview(screenUUID: String? = NSScreen.main?.displayUUID) {
        isMarketingPreviewModel = true
        self.screenUUID = screenUUID
        hideOnClosed = false
        refreshClosedNotchMetrics()
        closedNotchSize = getClosedNotchSize(screenUUID: self.screenUUID)

        if notchState == .closed {
            notchSize = closedNotchSize
        }
    }
    
    private func setupDetectorObserver() {
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                guard let self else { return }
                if self.isMarketingPreviewModel {
                    if self.hideOnClosed {
                        self.hideOnClosed = false
                    }
                    self.refreshClosedNotchMetrics()
                    return
                }
                withAnimation(.smooth) {
                    self.hideOnClosed = shouldHide
                    self.refreshClosedNotchMetrics()
                }
            }
            .store(in: &cancellables)
    }

    private func setupLayoutObserver() {
        let layoutTrigger = Publishers.MergeMany(
            Defaults.publisher(.debugLargeScreenLayoutPreviewMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.cinemaMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableNotchLyrics).map { _ in () }.eraseToAnyPublisher(),
            OpenNotchPlayerAccessoryState.shared.$isVolumeSliderExpanded.map { _ in () }.eraseToAnyPublisher()
        )

        layoutTrigger
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let updatedClosedSize = getClosedNotchSize(screenUUID: self.screenUUID)
                let targetSize = (self.notchState == .open)
                    ? getOpenNotchSize(screenUUID: self.screenUUID)
                    : updatedClosedSize
                self.closedNotchSize = updatedClosedSize
                self.refreshClosedNotchMetrics()

                if self.notchState == .open,
                   Defaults[.showCalendar],
                   !self.isNotchTransitioning {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self.notchSize = targetSize
                    }
                } else if self.notchState == .open {
                    withAnimation(NotchMotion.notchLayout) {
                        self.notchSize = targetSize
                    }
                } else {
                    self.notchSize = targetSize
                }
            }
            .store(in: &cancellables)
    }

    private func refreshClosedNotchMetrics() {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        let updatedHeight: CGFloat = noNotchAndFullscreen ? 0 : getEffectiveClosedNotchHeight(screenUUID: screenUUID)
        if effectiveClosedNotchHeight != updatedHeight {
            effectiveClosedNotchHeight = updatedHeight
        }
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        webcamManager.refreshVideoAuthorizationStatus()

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
                appIcon.size = NSSize(width: 64, height: 64)
                alert.icon = appIcon
                alert.messageText = AppLocalizer.localized("Camera Access Required")
                alert.informativeText = AppLocalizer.localized("Please allow camera access in System Settings.")
                alert.addButton(withTitle: AppLocalizer.localized("Open Settings"))
                alert.addButton(withTitle: AppLocalizer.localized("Cancel"))

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        dragDetectorTargeting = false
        generalDropTargeting = false
        dropZoneTargeting = false
        dropEvent = false
        markNotchTransitioning(for: .milliseconds(430))

        self.notchSize = getOpenNotchSize(screenUUID: self.screenUUID)
        self.notchState = .open

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(460))
            guard self?.notchState == .open else { return }
            MusicManager.shared.forceUpdate()
        }
    }

    func close() {
        if SharingStateManager.shared.preventNotchClose {
            return
        }

        OpenNotchPlayerAccessoryState.shared.isVolumeSliderExpanded = false

        if isCameraExpanded {
            toggleCameraPreview()
        }

        dragDetectorTargeting = false
        generalDropTargeting = false
        dropZoneTargeting = false
        markNotchTransitioning(for: .milliseconds(390))

        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false
        self.manualOpenUntil = .distantPast

        if !coordinator.openLastTabByDefault {
            coordinator.currentView = coordinator.preferredDefaultView(respectShelfPreference: true)
        }
    }

  /// Close the notch for screen lock/unlock transitions.
  /// Unlike `close()`, this keeps the current tab selection intact (no automatic view switching),
  /// because a lock event should not change the user's navigation state.
    func closeForLockTransition() {
        if SharingStateManager.shared.preventNotchClose {
            return
        }

        if isCameraExpanded {
            toggleCameraPreview()
        }

        dragDetectorTargeting = false
        generalDropTargeting = false
        dropZoneTargeting = false
        markNotchTransitioning(for: .milliseconds(390))

        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false
        self.manualOpenUntil = .distantPast
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }

    private func markNotchTransitioning(for duration: Duration) {
        notchTransitionTask?.cancel()
        isNotchTransitioning = true
        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isNotchTransitioning = false
            notchTransitionTask = nil
        }
    }

}
