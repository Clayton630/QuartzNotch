import Combine
import CoreGraphics
import CoreImage
import Defaults
import QuartzCore
import SkyLightWindow
import SwiftUI

private final class LockScreenPrivateBackdropView: NSVisualEffectView {
    private final class WindowConfigurator {
        private var shouldAutoFlattenLayerTree = true
        private var canHostLayersInWindowServer = true
        private var backgroundColor: NSColor = .clear

        func apply(to window: NSWindow) {
            shouldAutoFlattenLayerTree = window.value(forKey: "shouldAutoFlattenLayerTree") as? Bool ?? true
            canHostLayersInWindowServer = window.value(forKey: "canHostLayersInWindowServer") as? Bool ?? true
            backgroundColor = window.backgroundColor

            window.setValue(false, forKey: "shouldAutoFlattenLayerTree")
            window.setValue(false, forKey: "canHostLayersInWindowServer")
            window.setValue(true, forKey: "canHostLayersInWindowServer")
            window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
            window.displayIfNeeded()
        }

        func unapply(from window: NSWindow) {
            window.setValue(shouldAutoFlattenLayerTree, forKey: "shouldAutoFlattenLayerTree")
            window.setValue(false, forKey: "canHostLayersInWindowServer")
            window.setValue(canHostLayersInWindowServer, forKey: "canHostLayersInWindowServer")
            window.backgroundColor = backgroundColor
        }
    }

    let hostingView: NSHostingView<LockScreenMusicPanel>
    private let blurRadius: CGFloat
    private let saturationFactor: CGFloat
    private let cornerRadiusValue: CGFloat
    private let configurator = WindowConfigurator()
    private let backdrop: CALayer
    private let backdropContainer = CALayer()
    private let tintLayer = CALayer()
    private let cardMaskLayer = CAShapeLayer()
    private let backdropGroupName = UUID().uuidString

    init(
        rootView: LockScreenMusicPanel,
        blurRadius: CGFloat,
        saturationFactor: CGFloat,
        cornerRadius: CGFloat
    ) {
        hostingView = NSHostingView(rootView: rootView)
        self.blurRadius = blurRadius
        self.saturationFactor = saturationFactor
        self.cornerRadiusValue = cornerRadius
        self.backdrop = Self.makeBackdropLayer()
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropContainer.frame = bounds
        backdrop.frame = bounds
        tintLayer.frame = bounds
        CATransaction.commit()
    }

    override var blendingMode: NSVisualEffectView.BlendingMode {
        get { window?.contentView == self ? .behindWindow : .withinWindow }
        set { }
    }

    override var material: NSVisualEffectView.Material {
        get { .appearanceBased }
        set { }
    }

    override var state: NSVisualEffectView.State {
        get { .active }
        set { }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        backdropContainer.contentsScale = scale
        backdrop.contentsScale = scale
        tintLayer.contentsScale = scale
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if window.contentView == self {
            configurator.apply(to: window)
            backdrop.setValue(true, forKey: "windowServerAware")
        } else {
            backdrop.setValue(false, forKey: "windowServerAware")
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window, window.contentView == self {
            configurator.unapply(from: window)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = cornerRadiusValue
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        backdropContainer.cornerRadius = cornerRadiusValue
        backdropContainer.masksToBounds = true
    }

    @objc private func _shouldAutoFlattenLayerTree() -> Bool {
        false
    }

    func updateCardMask(
        showsMediaCard: Bool,
        mediaCardHeight: CGFloat,
        timerCount: Int,
        panelSize: CGSize,
        renderBleed: CGFloat = 0,
        animated: Bool = false,
        duration: CFTimeInterval = 0.34,
        useFullPanelMask: Bool = false
    ) {
        let spacing = LockScreenMusicPanel.stackSpacing
        let timerHeight = LockScreenMusicPanel.timerCardHeight
        let path = CGMutablePath()

        if useFullPanelMask {
            path.addRoundedRect(
                in: CGRect(origin: .zero, size: panelSize),
                cornerWidth: cornerRadiusValue, cornerHeight: cornerRadiusValue
            )
        } else {
            let inset = max(0, renderBleed)
            var y = inset
            if showsMediaCard {
                path.addRoundedRect(
                    in: CGRect(
                        x: inset,
                        y: y,
                        width: max(0, panelSize.width - (inset * 2)),
                        height: mediaCardHeight
                    ),
                    cornerWidth: cornerRadiusValue, cornerHeight: cornerRadiusValue
                )
                y += mediaCardHeight + spacing
            }
            for _ in 0..<timerCount {
                path.addRoundedRect(
                    in: CGRect(
                        x: inset,
                        y: y,
                        width: max(0, panelSize.width - (inset * 2)),
                        height: timerHeight
                    ),
                    cornerWidth: cornerRadiusValue, cornerHeight: cornerRadiusValue
                )
                y += timerHeight + spacing
            }
        }

        let previousPath = cardMaskLayer.presentation()?.path ?? cardMaskLayer.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardMaskLayer.frame = CGRect(origin: .zero, size: panelSize)
        cardMaskLayer.path = path
        backdropContainer.mask = cardMaskLayer
        CATransaction.commit()

        if animated, let previousPath {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = previousPath
            animation.toValue = path
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.88, 0.24, 1.0)
            animation.fillMode = .removed
            cardMaskLayer.add(animation, forKey: "lockscreen-card-mask-path")
        }
    }

    func update(rootView: LockScreenMusicPanel, size: CGSize) {
        frame = NSRect(origin: .zero, size: size)
        hostingView.frame = bounds
        hostingView.rootView = rootView
        if let window, window.contentView == self {
            backdrop.setValue(true, forKey: "windowServerAware")
        }
    }

    func resize(to size: CGSize) {
        frame = NSRect(origin: .zero, size: size)
        hostingView.frame = bounds
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let window, window.contentView == self {
            backdrop.setValue(true, forKey: "windowServerAware")
        }
    }

    func captureSnapshot(in rect: CGRect) -> NSImage? {
        let captureRect = rect.integral.intersection(bounds)
        guard captureRect.width > 1, captureRect.height > 1 else { return nil }
        guard let representation = bitmapImageRepForCachingDisplay(in: captureRect) else { return nil }
        cacheDisplay(in: captureRect, to: representation)
        let image = NSImage(size: captureRect.size)
        image.addRepresentation(representation)
        return image
    }

    private func commonInit() {
        wantsLayer = true
        layerUsesCoreImageFilters = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadiusValue
        layer?.backgroundColor = NSColor.clear.cgColor

        super.state = .active
        super.blendingMode = .withinWindow
        super.material = .appearanceBased
        setValue(true, forKey: "clear")

        backdrop.name = "lockscreen-backdrop"
        backdrop.backgroundColor = NSColor.clear.cgColor
        backdrop.allowsGroupOpacity = true
        backdrop.setValue(true, forKey: "allowsGroupBlending")
        backdrop.setValue(false, forKey: "allowsEdgeAntialiasing")
        backdrop.setValue(false, forKey: "allowsInPlaceFiltering")
        backdrop.setValue(true, forKey: "disablesOccludedBackdropBlurs")
        backdrop.setValue(true, forKey: "ignoresOffscreenGroups")
        backdrop.setValue(0.25, forKey: "scale")
        backdrop.setValue(0.2, forKey: "bleedAmount")
        backdrop.setValue(backdropGroupName, forKey: "groupName")

        if let blur = Self.makeFilter(type: "gaussianBlur") {
            blur.setValue(true, forKey: "inputNormalizeEdges")
            blur.setValue(blurRadius, forKey: "inputRadius")
            if let saturate = Self.makeFilter(type: "colorSaturate") {
                saturate.setValue(saturationFactor, forKey: "inputAmount")
                backdrop.filters = [blur, saturate]
            } else {
                backdrop.filters = [blur]
            }
        }

        tintLayer.backgroundColor = NSColor.clear.cgColor
        backdropContainer.opacity = 1.0
        backdropContainer.cornerRadius = cornerRadiusValue
        backdropContainer.masksToBounds = true
        backdropContainer.setValue(true, forKey: "allowsGroupBlending")
        backdropContainer.setValue(false, forKey: "allowsEdgeAntialiasing")
        backdropContainer.sublayers = [backdrop, tintLayer]
        layer?.addSublayer(backdropContainer)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layerUsesCoreImageFilters = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private static func makeFilter(type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        let unmanaged = filterClass.perform(selector, with: type)
        return unmanaged?.takeUnretainedValue() as? NSObject
    }

    private static func makeBackdropLayer() -> CALayer {
        guard let backdropType = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            return CALayer()
        }
        return backdropType.init()
    }
}

@MainActor
final class LockScreenPanelManager {
    private struct DesktopImageState {
        let url: URL
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    static let shared = LockScreenPanelManager()

    private var panelWindow: NSWindow?
    private var panelHosting: NSHostingView<LockScreenMusicPanel>?
    private var panelBackdropView: LockScreenPrivateBackdropView?
    private var expandedArtworkBackdropWindow: NSWindow?
    private var expandedArtworkWindow: NSWindow?
    private var loginOverlayWindow: NSWindow?
    private var expandedArtworkSourceOffset: CGSize = .zero
    private var expandedArtworkSourceScale: CGFloat = 0.42
    private var hasDelegated = false
    private var hasDelegatedExpandedArtworkBackdrop = false
    private var hasDelegatedExpandedArtwork = false
    private var hasDelegatedLoginOverlay = false
    private var collapsedFrame: NSRect?
    private(set) var latestFrame: NSRect?
    private let panelAnimator = LockScreenPanelAnimator()
    private var hideTask: Task<Void, Never>?
    private var expandedArtworkRestoreTask: Task<Void, Never>?
    private var expandedArtworkRestoreOnShowTask: Task<Void, Never>?
    private var panelLayoutAnimationTask: Task<Void, Never>?
    private var expandedArtworkRestoreSequence: UInt64 = 0
    private var shouldRestoreExpandedArtworkOnNextShow = false
    private var suppressAlbumArtExpansionSideEffects = false
    private var backdropRefreshTimer: Timer?
    private let backdropCaptureQueue = DispatchQueue(label: "quartznotch.lockscreen.backdrop", qos: .userInteractive)
    private let backdropCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var backdropCaptureInFlight = false
    private var pendingBackdropCapture: (panelFrame: NSRect, windowNumber: Int?)?
    private var backdropCaptureRequestID: UInt64 = 0
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var originalDesktopImages: [String: DesktopImageState] = [:]
    private var generatedDesktopImageURLs: [String: URL] = [:]
    private var expandedArtworkWallpaperScreenUUID: String?

    private init() {
        LockScreenBackdropSharedStore.shared.prepare()
        registerScreenChangeObservers()
        observeDefaultChanges()
    }

    func canToggleExpandedArtwork() -> Bool {
        panelAnimator.showsMediaCard
            && !panelAnimator.isAlbumArtTransitioning
    }

    private func shouldRememberExpandedArtworkState() -> Bool {
        panelAnimator.isAlbumArtExpanded
            || panelAnimator.isAlbumArtTransitioning
            || expandedArtworkWindow?.isVisible == true
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange()
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange()
            }
        }

        workspaceObservers = [wakeObserver]
    }

    deinit {
        backdropRefreshTimer?.invalidate()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    private var activeQuickTimersForLockScreen: [QuickTimer] {
        guard Defaults[.enableLockScreenTimerWidget] else { return [] }

        var timers = QuickTimerManager.shared.timers
            .filter { $0.remainingSeconds > 0 || $0.didFinish }

        if let mirrored = QuickTimerManager.shared.mirroredSystemQuickTimer {
            timers.append(mirrored)
        }

        return timers
    }

    private func makePanelBackdropView(rootView: LockScreenMusicPanel, size: CGSize) -> LockScreenPrivateBackdropView {
        let view = LockScreenPrivateBackdropView(
            rootView: rootView,
            blurRadius: 16,
            saturationFactor: 1.0,
            cornerRadius: LockScreenMusicPanel.panelCornerRadius
        )
        view.frame = NSRect(origin: .zero, size: size)
        view.autoresizingMask = [.width, .height]
        return view
    }

    private func refreshPanelBackdropMask(
        panelSize overridePanelSize: CGSize? = nil,
        mediaCardHeight overrideMediaCardHeight: CGFloat? = nil,
        animated: Bool = false,
        duration: CFTimeInterval = 0.34
    ) {
        guard usesCompatibilityFallbackStyling,
              panelAnimator.usesWindowBackdropFallback,
              let panelBackdropView,
              let panelSize = overridePanelSize ?? latestFrame?.size ?? panelWindow?.contentView?.frame.size
        else { return }

        let mediaCardHeight = overrideMediaCardHeight ?? LockScreenMusicPanel.mediaCardSize(
            progress: panelAnimator.albumArtPanelMorphProgress
        ).height
        let visibleTimerCount = activeQuickTimersForLockScreen
            .filter { !panelAnimator.releasedBackdropTimerIDs.contains($0.id) }
            .count

        panelBackdropView.updateCardMask(
            showsMediaCard: panelAnimator.showsMediaCard,
            mediaCardHeight: mediaCardHeight,
            timerCount: visibleTimerCount,
            panelSize: panelSize,
            renderBleed: LockScreenMusicPanel.renderBleed(showsMediaCard: panelAnimator.showsMediaCard),
            animated: animated,
            duration: duration
        )
    }

    private func animatedMediaCardHeight(for panelHeight: CGFloat, visibleTimerCount: Int) -> CGFloat {
        guard panelAnimator.showsMediaCard else { return 0 }
        let renderBleed = LockScreenMusicPanel.renderBleed(showsMediaCard: true)
        let contentHeight = max(0, panelHeight - (renderBleed * 2))
        let timerStackHeight =
            (CGFloat(visibleTimerCount) * LockScreenMusicPanel.timerCardHeight)
            + (CGFloat(max(0, visibleTimerCount)) * LockScreenMusicPanel.stackSpacing)
        return max(0, contentHeight - timerStackHeight)
    }

    private func mediaCardHeight(forLyricsExpansionProgress progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        let morphProgress = min(max(panelAnimator.albumArtPanelMorphProgress, 0), 1)
        return LockScreenMusicPanel.baseCollapsedSize.height
            + (LockScreenMusicPanel.lyricsHeight * clampedProgress)
            + (LockScreenMusicPanel.volumeHeight * panelAnimator.volumeExpansionProgress)
            - (LockScreenMusicPanel.expandedHeightReduction * morphProgress)
    }

    private func refreshPanelLayout(animated: Bool = false) {
        guard let window = panelWindow else { return }
        guard window.isVisible || panelAnimator.isPresented else { return }
        guard let screen = currentScreen() else { return }

        let targetFrame = panelFrame(
            for: screen.frame,
            showsMediaCard: panelAnimator.showsMediaCard,
            timerCount: activeQuickTimersForLockScreen.count,
            volumeExpansionProgress: panelAnimator.volumeExpansionProgress
        )
        collapsedFrame = targetFrame

        panelLayoutAnimationTask?.cancel()
        panelAnimator.defersLyricsRenderingDuringResize = false
        if animated, window.frame != targetFrame {
            animateLyricsExpansion(enabled: Defaults[.enableLyrics], targetFrame: targetFrame)
            return
        }

        latestFrame = targetFrame
        window.setFrame(targetFrame, display: true)
        resizePanelContent(to: targetFrame.size)
        refreshBackdropSnapshot(panelFrame: targetFrame, excluding: panelWindow)
        refreshPanelBackdropMask()

        if panelAnimator.isAlbumArtExpanded {
            showExpandedArtworkBackdrop()
            showExpandedArtworkOverlay()
        }
    }

    private func resizePanelContent(to size: CGSize) {
        if let panelBackdropView {
            panelBackdropView.resize(to: size)
            panelHosting = panelBackdropView.hostingView
        } else if let panelHosting {
            panelHosting.frame = NSRect(origin: .zero, size: size)
        }

        if let content = panelWindow?.contentView {
            content.frame = NSRect(origin: .zero, size: size)
            content.wantsLayer = true
            content.layer?.masksToBounds = true
            content.layer?.cornerRadius = LockScreenMusicPanel.panelCornerRadius
            content.layer?.backgroundColor = NSColor.clear.cgColor
            content.needsLayout = true
            content.layoutSubtreeIfNeeded()
        }
    }

    private func animateLyricsExpansion(enabled: Bool, targetFrame: NSRect) {
        guard let window = panelWindow else { return }

        panelAnimator.defersLyricsRenderingDuringResize = false
        panelLayoutAnimationTask?.cancel()
        panelLayoutAnimationTask = nil

        if enabled {
            panelAnimator.lyricsExpansionProgress = 0
            latestFrame = targetFrame
            window.setFrame(targetFrame, display: true)
            resizePanelContent(to: targetFrame.size)
            refreshBackdropSnapshot(panelFrame: targetFrame, excluding: panelWindow)
            refreshPanelBackdropMask(
                panelSize: targetFrame.size,
                mediaCardHeight: mediaCardHeight(forLyricsExpansionProgress: 0)
            )

            withAnimation(.spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.08)) {
                panelAnimator.lyricsExpansionProgress = 1
            }
            refreshPanelBackdropMask(
                panelSize: targetFrame.size,
                mediaCardHeight: mediaCardHeight(forLyricsExpansionProgress: 1),
                animated: true,
                duration: 0.36
            )
        } else {
            let startFrame = window.frame
            latestFrame = startFrame
            resizePanelContent(to: startFrame.size)

            withAnimation(.spring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.06)) {
                panelAnimator.lyricsExpansionProgress = 0
            }
            refreshPanelBackdropMask(
                panelSize: startFrame.size,
                mediaCardHeight: mediaCardHeight(forLyricsExpansionProgress: 0),
                animated: true,
                duration: 0.32
            )

            panelLayoutAnimationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(430))
                guard let self, !Task.isCancelled else { return }
                self.latestFrame = targetFrame
                self.panelWindow?.setFrame(targetFrame, display: true)
                self.resizePanelContent(to: targetFrame.size)
                self.refreshBackdropSnapshot(panelFrame: targetFrame, excluding: self.panelWindow)
                self.refreshPanelBackdropMask(
                    panelSize: targetFrame.size,
                    mediaCardHeight: self.mediaCardHeight(forLyricsExpansionProgress: 0)
                )
                self.panelLayoutAnimationTask = nil
            }
        }
    }

    private func animatePanelLayout(from startFrame: NSRect, to targetFrame: NSRect) {
        latestFrame = startFrame
        let isExpandingForLyrics = targetFrame.height > startFrame.height
        panelAnimator.defersLyricsRenderingDuringResize = isExpandingForLyrics
        panelLayoutAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.panelLayoutAnimationTask = nil
            }

            let duration: TimeInterval = 0.34
            let frameInterval: TimeInterval = 1.0 / 60.0
            let startDate = CACurrentMediaTime()

            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startDate
                let rawProgress = min(max(elapsed / duration, 0), 1)
                let t = CGFloat(rawProgress)
                let progress = t * t * (3 - (2 * t))
                let frame = Self.interpolateFrame(from: startFrame, to: targetFrame, progress: progress)

                self.latestFrame = frame
                self.panelWindow?.setFrame(frame, display: true)
                self.resizePanelContent(to: frame.size)
                let visibleTimerCount = self.activeQuickTimersForLockScreen
                    .filter { !self.panelAnimator.releasedBackdropTimerIDs.contains($0.id) }
                    .count
                self.refreshPanelBackdropMask(
                    panelSize: frame.size,
                    mediaCardHeight: self.animatedMediaCardHeight(
                        for: frame.height,
                        visibleTimerCount: visibleTimerCount
                    )
                )

                guard rawProgress < 1 else { break }
                try? await Task.sleep(for: .seconds(frameInterval))
            }

            guard !Task.isCancelled else {
                self.panelAnimator.defersLyricsRenderingDuringResize = false
                return
            }
            self.latestFrame = targetFrame
            self.panelWindow?.setFrame(targetFrame, display: true)
            self.resizePanelContent(to: targetFrame.size)
            self.refreshBackdropSnapshot(panelFrame: targetFrame, excluding: self.panelWindow)
            self.refreshPanelBackdropMask()
            self.panelAnimator.defersLyricsRenderingDuringResize = false

            if self.panelAnimator.isAlbumArtExpanded {
                self.showExpandedArtworkBackdrop()
                self.showExpandedArtworkOverlay()
            }
        }
    }

    private func animateVolumeExpansion(expanded: Bool) {
        guard let window = panelWindow,
              window.isVisible || panelAnimator.isPresented,
              let screen = currentScreen()
        else {
            panelAnimator.volumeExpansionProgress = expanded ? 1 : 0
            refreshPanelLayout()
            return
        }

        let startFrame = window.frame
        let targetFrame = panelFrame(
            for: screen.frame,
            showsMediaCard: panelAnimator.showsMediaCard,
            timerCount: activeQuickTimersForLockScreen.count,
            volumeExpansionProgress: expanded ? 1 : 0
        )

        panelLayoutAnimationTask?.cancel()
        panelLayoutAnimationTask = nil

        if expanded {
            panelAnimator.volumeExpansionProgress = 0
            latestFrame = targetFrame
            window.setFrame(targetFrame, display: true)
            resizePanelContent(to: targetFrame.size)
            refreshBackdropSnapshot(panelFrame: targetFrame, excluding: panelWindow)
            refreshPanelBackdropMask(
                panelSize: targetFrame.size,
                mediaCardHeight: mediaCardHeight(forLyricsExpansionProgress: panelAnimator.lyricsExpansionProgress)
            )

            withAnimation(.spring(response: 0.32, dampingFraction: 0.92, blendDuration: 0.06)) {
                panelAnimator.volumeExpansionProgress = 1
            }
            refreshPanelBackdropMask(
                panelSize: targetFrame.size,
                mediaCardHeight: mediaCardHeight(forLyricsExpansionProgress: panelAnimator.lyricsExpansionProgress),
                animated: true,
                duration: 0.32
            )
        } else {
            latestFrame = startFrame
            resizePanelContent(to: startFrame.size)

            withAnimation(.spring(response: 0.28, dampingFraction: 0.94, blendDuration: 0.05)) {
                panelAnimator.volumeExpansionProgress = 0
            }
            refreshPanelBackdropMask(
                panelSize: startFrame.size,
                mediaCardHeight: mediaCardHeight(forLyricsExpansionProgress: panelAnimator.lyricsExpansionProgress),
                animated: true,
                duration: 0.28
            )

            panelLayoutAnimationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(320))
                guard let self, !Task.isCancelled else { return }
                self.latestFrame = targetFrame
                self.panelWindow?.setFrame(targetFrame, display: true)
                self.resizePanelContent(to: targetFrame.size)
                self.refreshBackdropSnapshot(panelFrame: targetFrame, excluding: self.panelWindow)
                self.refreshPanelBackdropMask()
                self.panelLayoutAnimationTask = nil
            }
        }
    }

    private static func panelLayoutAnimationProgress(_ progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    private static func interpolateFrame(from start: NSRect, to end: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: start.minX + ((end.minX - start.minX) * progress),
            y: start.minY + ((end.minY - start.minY) * progress),
            width: start.width + ((end.width - start.width) * progress),
            height: start.height + ((end.height - start.height) * progress)
        )
    }

    func showPanel(showMediaCard: Bool) {
        let timerCount = activeQuickTimersForLockScreen.count
        guard showMediaCard || timerCount > 0 else {
            hidePanel()
            return
        }
        guard showMediaCard || Defaults[.enableLockScreenMediaWidget] || timerCount > 0 else {
            hidePanel()
            return
        }

        LockScreenBackdropSharedStore.shared.exportCurrentMediaState()

        if panelAnimator.showsMediaCard != showMediaCard && !showMediaCard {
            if panelAnimator.isAlbumArtExpanded {
                hideExpandedArtworkBackdrop()
                hideExpandedArtworkOverlay(animated: false)
            }
            panelAnimator.isAlbumArtExpanded = false
            panelAnimator.albumArtPanelMorphProgress = 0
        }
        panelAnimator.showsMediaCard = showMediaCard

        LockScreenDisplayContextProvider.shared.refresh(reason: "show-panel")
        guard let screen = currentScreen() else { return }

        let targetFrame = panelFrame(
            for: screen.frame,
            showsMediaCard: showMediaCard,
            timerCount: timerCount
        )
        collapsedFrame = targetFrame
        refreshBackdropSnapshot(panelFrame: targetFrame, excluding: panelWindow)
        panelAnimator.albumArtPanelMorphProgress = panelAnimator.isAlbumArtExpanded ? 1 : 0

        let window: NSWindow
        let isExistingVisibleWindow = panelWindow?.isVisible == true
        if let existingWindow = panelWindow {
            window = existingWindow
        } else {
            let newWindow = QuartzNotchWindow(
                contentRect: targetFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false
            newWindow.ignoresMouseEvents = false

            panelWindow = newWindow
            window = newWindow
            hasDelegated = false
        }

        window.setFrame(targetFrame, display: true)
        latestFrame = targetFrame
        panelAnimator.usesWindowBackdropFallback = usesCompatibilityFallbackStyling
        panelAnimator.lyricsExpansionProgress = Defaults[.enableLyrics] ? 1 : 0

        hideTask?.cancel()
        let panelRootView = LockScreenMusicPanel(animator: panelAnimator)
        if usesCompatibilityFallbackStyling {
            if let panelBackdropView {
                panelBackdropView.update(rootView: panelRootView, size: targetFrame.size)
                panelHosting = panelBackdropView.hostingView
                if window.contentView !== panelBackdropView {
                    window.contentView = panelBackdropView
                }
            } else {
                let backdropView = makePanelBackdropView(rootView: panelRootView, size: targetFrame.size)
                window.contentView = backdropView
                panelBackdropView = backdropView
                panelHosting = backdropView.hostingView
            }
            let mediaCardHeight = LockScreenMusicPanel.mediaCardSize(
                progress: panelAnimator.albumArtPanelMorphProgress
            ).height
            panelBackdropView?.updateCardMask(
                showsMediaCard: showMediaCard,
                mediaCardHeight: mediaCardHeight,
                timerCount: timerCount,
                panelSize: targetFrame.size,
                renderBleed: LockScreenMusicPanel.renderBleed(showsMediaCard: showMediaCard)
            )
        } else {
            panelBackdropView = nil
            if let panelHosting {
                panelHosting.rootView = panelRootView
                panelHosting.frame = NSRect(origin: .zero, size: targetFrame.size)
                if window.contentView !== panelHosting {
                    window.contentView = panelHosting
                }
            } else {
                let hosting = NSHostingView(rootView: panelRootView)
                hosting.frame = NSRect(origin: .zero, size: targetFrame.size)
                hosting.autoresizingMask = [.width, .height]
                window.contentView = hosting
                panelHosting = hosting
            }
        }
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.masksToBounds = true
            content.layer?.cornerRadius = LockScreenMusicPanel.panelCornerRadius
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        window.orderFrontRegardless()
        startBackdropRefreshIfNeeded()

        if !isExistingVisibleWindow {
            panelAnimator.isPresented = false
            DispatchQueue.main.async { [weak self] in
                self?.panelAnimator.isPresented = true
                self?.attemptRestoreExpandedArtworkOnNextShow()
            }
        }

        attemptRestoreExpandedArtworkOnNextShow()
    }

    func hidePanel(
        rememberExpandedStateForNextShow: Bool = false,
        preserveExpandedStateForNextShow: Bool = false
    ) {
        expandedArtworkRestoreOnShowTask?.cancel()
        expandedArtworkRestoreOnShowTask = nil
        if rememberExpandedStateForNextShow && shouldRememberExpandedArtworkState() {
            shouldRestoreExpandedArtworkOnNextShow = true
        } else if !rememberExpandedStateForNextShow && !preserveExpandedStateForNextShow {
            shouldRestoreExpandedArtworkOnNextShow = false
        }
        panelAnimator.isPresented = false
        panelAnimator.isAlbumArtExpanded = false
        panelAnimator.albumArtPanelMorphProgress = 0
        expandedArtworkRestoreSequence &+= 1
        panelLayoutAnimationTask?.cancel()
        panelLayoutAnimationTask = nil
        panelAnimator.defersLyricsRenderingDuringResize = false
        expandedArtworkRestoreTask?.cancel()
        expandedArtworkRestoreTask = nil
        hideTask?.cancel()
        stopBackdropRefresh()

        guard let window = panelWindow else {
            latestFrame = nil
            return
        }

        hideTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(360))
            guard let self else { return }
            await MainActor.run {
                window?.orderOut(nil)
                window?.contentView = nil
                self.panelHosting = nil
                self.panelBackdropView = nil
                if let expandedArtworkBackdropWindow = self.expandedArtworkBackdropWindow {
                    expandedArtworkBackdropWindow.orderOut(nil)
                    expandedArtworkBackdropWindow.contentView = nil
                    if self.hasDelegatedExpandedArtworkBackdrop {
                        LockScreenBackdropSkyLightOperator.shared.undelegateWindow(expandedArtworkBackdropWindow)
                        self.hasDelegatedExpandedArtworkBackdrop = false
                    }
                    self.expandedArtworkBackdropWindow = nil
                }
                self.hideLoginOverlay()
                self.expandedArtworkWindow?.orderOut(nil)
                self.expandedArtworkWindow?.contentView = nil
                self.latestFrame = nil
                self.panelAnimator.fallbackBackdropSnapshot = nil
                self.panelAnimator.usesWindowBackdropFallback = false
            }
        }
    }

    func hidePanelForUnlock(rememberExpandedStateForNextShow: Bool = false) {
        expandedArtworkRestoreOnShowTask?.cancel()
        expandedArtworkRestoreOnShowTask = nil
        if rememberExpandedStateForNextShow && shouldRememberExpandedArtworkState() {
            shouldRestoreExpandedArtworkOnNextShow = true
        }

        hideTask?.cancel()
        expandedArtworkRestoreSequence &+= 1
        panelLayoutAnimationTask?.cancel()
        panelLayoutAnimationTask = nil
        panelAnimator.defersLyricsRenderingDuringResize = false
        expandedArtworkRestoreTask?.cancel()
        expandedArtworkRestoreTask = nil
        stopBackdropRefresh()

        suppressAlbumArtExpansionSideEffects = true
        panelAnimator.isPresented = false
        panelAnimator.isAlbumArtExpanded = false
        panelAnimator.isAlbumArtTransitioning = false
        panelAnimator.albumArtPanelMorphProgress = 0
        suppressAlbumArtExpansionSideEffects = false

        panelWindow?.orderOut(nil)
        panelWindow?.contentView = nil
        panelHosting = nil
        panelBackdropView = nil

        if let expandedArtworkBackdropWindow {
            expandedArtworkBackdropWindow.orderOut(nil)
            expandedArtworkBackdropWindow.contentView = nil
            if hasDelegatedExpandedArtworkBackdrop {
                LockScreenBackdropSkyLightOperator.shared.undelegateWindow(expandedArtworkBackdropWindow)
                hasDelegatedExpandedArtworkBackdrop = false
            }
            self.expandedArtworkBackdropWindow = nil
        }
        hideLoginOverlay()
        expandedArtworkWindow?.orderOut(nil)
        expandedArtworkWindow?.contentView = nil

        latestFrame = nil
        panelAnimator.fallbackBackdropSnapshot = nil
        panelAnimator.usesWindowBackdropFallback = false
    }

    private func handleScreenGeometryChange() {
        refreshPanelLayout()
    }

    private func observeDefaultChanges() {
        Defaults.publisher(.lockScreenMusicPanelWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanelLayout()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableLyrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanelLayout(animated: true)
            }
            .store(in: &cancellables)

        OpenNotchPlayerAccessoryState.shared.$isLockScreenVolumeSliderExpanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                self.animateVolumeExpansion(expanded: expanded)
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenMusicVerticalOffset)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanelLayout()
            }
            .store(in: &cancellables)

        MusicManager.shared.$albumArtFlipEventID
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                LockScreenBackdropSharedStore.shared.exportCurrentMediaState()
                self.attemptRestoreExpandedArtworkOnNextShow()
                guard self.panelAnimator.isAlbumArtExpanded else { return }
                self.showExpandedArtworkBackdrop()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            MusicManager.shared.$songTitle.removeDuplicates(),
            MusicManager.shared.$artistName.removeDuplicates(),
            MusicManager.shared.$album.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            LockScreenBackdropSharedStore.shared.exportCurrentMediaState()
            self?.attemptRestoreExpandedArtworkOnNextShow()
        }
        .store(in: &cancellables)

        MusicManager.shared.$bundleIdentifier
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                LockScreenBackdropSharedStore.shared.exportCurrentMediaState()
                self?.attemptRestoreExpandedArtworkOnNextShow()
            }
            .store(in: &cancellables)

        panelAnimator.$isAlbumArtExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] isExpanded in
                guard let self else { return }
                guard !self.suppressAlbumArtExpansionSideEffects else { return }
                self.animatePanelLayout(forExpandedState: isExpanded)
                if isExpanded {
                    self.showExpandedArtworkBackdrop()
                    self.showExpandedArtworkOverlay()
                } else {
                    self.hideExpandedArtworkBackdrop()
                    self.hideExpandedArtworkOverlay(animated: true)
                }
            }
            .store(in: &cancellables)

        panelAnimator.$timerExitingCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanelBackdropMask()
            }
            .store(in: &cancellables)

        panelAnimator.$releasedBackdropTimerIDs
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanelBackdropMask()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            QuickTimerManager.shared.$timers.map { timers in
                timers.map { "\($0.id.uuidString)-\($0.didFinish)-\($0.remainingSeconds)" }
            },
            QuickTimerManager.shared.$mirroredSystemQuickTimer.map { timer in
                guard let timer else { return "nil" }
                return "\(timer.id.uuidString)-\(timer.didFinish)-\(timer.remainingSeconds)"
            }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.refreshPanelBackdropMask()
        }
        .store(in: &cancellables)
    }

    private func attemptRestoreExpandedArtworkOnNextShow() {
        guard shouldRestoreExpandedArtworkOnNextShow,
              LockScreenState.shared.isLocked,
              panelWindow?.isVisible == true,
              panelAnimator.isPresented,
              !panelAnimator.isAlbumArtExpanded,
              !panelAnimator.isAlbumArtTransitioning,
              !MusicManager.shared.isUsingIdleMetadata else {
            return
        }

        expandedArtworkRestoreOnShowTask?.cancel()
        expandedArtworkRestoreOnShowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self,
                  LockScreenState.shared.isLocked,
                  self.panelWindow?.isVisible == true,
                  self.panelAnimator.isPresented,
                  !self.panelAnimator.isAlbumArtExpanded,
                  !self.panelAnimator.isAlbumArtTransitioning,
                  !MusicManager.shared.isUsingIdleMetadata else {
                return
            }
            self.shouldRestoreExpandedArtworkOnNextShow = false
            self.panelAnimator.isAlbumArtExpanded = true
        }
    }

    private func panelFrame(
        for screenFrame: NSRect,
        showsMediaCard: Bool,
        timerCount: Int,
        volumeExpansionProgress overrideVolumeExpansionProgress: CGFloat? = nil
    ) -> NSRect {
        var size = LockScreenMusicPanel.size(
            showsMediaCard: showsMediaCard,
            timerCount: timerCount,
            mediaProgress: 0,
            availableWidth: screenFrame.width - 80
        )
        if showsMediaCard {
            let volumeProgress = overrideVolumeExpansionProgress ?? panelAnimator.volumeExpansionProgress
            size.height += LockScreenMusicPanel.volumeHeight * min(max(volumeProgress, 0), 1)
        }
        let insetX: CGFloat = 40
        let insetBottom: CGFloat = 40
        let renderBleed = LockScreenMusicPanel.renderBleed(showsMediaCard: showsMediaCard)
        let originX = screenFrame.minX + insetX - renderBleed
        let baseOriginY = screenFrame.minY + insetBottom
        let userOffset = CGFloat(Defaults[.lockScreenMusicVerticalOffset])
        let clampedOffset = min(max(userOffset, -160), 160)
        let originY = baseOriginY + clampedOffset - renderBleed
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private func animatePanelLayout(forExpandedState isExpanded: Bool) {
        guard let window = panelWindow,
              window.isVisible || panelAnimator.isPresented,
              let screen = currentScreen() else {
            panelAnimator.albumArtPanelMorphProgress = isExpanded ? 1 : 0
            return
        }

        let targetProgress: CGFloat = isExpanded ? 1 : 0
        panelAnimator.albumArtPanelMorphProgress = targetProgress
        let targetFrame = panelFrame(
            for: screen.frame,
            showsMediaCard: panelAnimator.showsMediaCard,
            timerCount: activeQuickTimersForLockScreen.count
        )
        collapsedFrame = targetFrame
        latestFrame = targetFrame
        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
            panelHosting?.frame = NSRect(origin: .zero, size: targetFrame.size)
        }
        refreshBackdropSnapshot(panelFrame: targetFrame, excluding: panelWindow)
    }

    func captureTimerCardSnapshot(panelSize: CGSize, cardRect: CGRect) -> NSImage? {
        guard panelAnimator.usesWindowBackdropFallback else {
            return nil
        }

        if let panelWindow {
            let fullWindowRect = CGRect(origin: .zero, size: panelSize)
            if let cgImage = CGWindowListCreateImage(
                fullWindowRect,
                .optionIncludingWindow,
                CGWindowID(panelWindow.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                let scaleX = CGFloat(cgImage.width) / max(panelSize.width, 1)
                let scaleY = CGFloat(cgImage.height) / max(panelSize.height, 1)
                let cropRect = CGRect(
                    x: cardRect.minX * scaleX,
                    y: max(0, panelSize.height - cardRect.maxY) * scaleY,
                    width: cardRect.width * scaleX,
                    height: cardRect.height * scaleY
                ).integral

                if let cropped = cgImage.cropping(to: cropRect) {
                    return NSImage(cgImage: cropped, size: cardRect.size)
                }
            }
        }

        guard let backdropView = panelBackdropView else { return nil }
        let snapshotRect = CGRect(
            x: cardRect.minX,
            y: max(0, panelSize.height - cardRect.maxY),
            width: cardRect.width,
            height: cardRect.height
        )
        return backdropView.captureSnapshot(in: snapshotRect)
    }

    private func currentScreen() -> NSScreen? {
        LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main
    }

    private func showExpandedArtworkOverlay() {
        guard panelWindow?.isVisible == true,
              let screen = currentScreen() else {
            panelAnimator.isAlbumArtExpanded = false
            return
        }

        let artSize = min(max(260, screen.frame.height * 0.30), 420)
        let shadowBleed: CGFloat = 170
        let overlaySize = NSSize(width: artSize + shadowBleed * 2, height: artSize + shadowBleed * 2)
        let overlayFrame = NSRect(
            x: screen.frame.midX - overlaySize.width / 2,
            y: screen.frame.midY - overlaySize.height / 2,
            width: overlaySize.width,
            height: overlaySize.height
        )
        let transitionParameters = expandedArtworkTransitionParameters(
            screen: screen,
            overlayFrame: overlayFrame,
            artSize: artSize
        )
        expandedArtworkSourceOffset = transitionParameters.offset
        expandedArtworkSourceScale = transitionParameters.scale

        let window: NSWindow
        if let existingWindow = expandedArtworkWindow {
            window = existingWindow
        } else {
            let newWindow = QuartzNotchWindow(
                contentRect: overlayFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false
            newWindow.ignoresMouseEvents = false

            expandedArtworkWindow = newWindow
            window = newWindow
        }

        window.setFrame(overlayFrame, display: true)

        if window.isVisible {
            window.orderFrontRegardless()
            return
        }

        let hosting = NSHostingView(
            rootView: AnyView(
                LockScreenExpandedAlbumArtOverlay(
                    artSize: artSize,
                    shadowBleed: shadowBleed,
                    sourceOffset: transitionParameters.offset,
                    sourceScale: transitionParameters.scale,
                    onClose: { [weak self] in
                        guard let self, self.canToggleExpandedArtwork() else { return }
                        self.panelAnimator.isAlbumArtExpanded = false
                    }
                )
                    .ignoresSafeArea()
            )
        )
        hosting.frame = NSRect(origin: .zero, size: overlayFrame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        if !hasDelegatedExpandedArtwork {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegatedExpandedArtwork = true
        }

        window.orderFrontRegardless()
    }

    private func expandedArtworkTransitionParameters(
        screen: NSScreen,
        overlayFrame: NSRect,
        artSize: CGFloat
    ) -> (offset: CGSize, scale: CGFloat) {
        let sourceRect = expandedArtworkSourceRect(on: screen)
        let sourceCenter = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        let overlayCenter = CGPoint(x: overlayFrame.midX, y: overlayFrame.midY)
        let offset = CGSize(
            width: sourceCenter.x - overlayCenter.x,
            height: sourceCenter.y - overlayCenter.y
        )
        let scale = max(0.34, min(0.48, (LockScreenMusicPanel.compactAlbumArtSize / artSize) + 0.10))
        return (offset, scale)
    }

    private func expandedArtworkSourceRect(on screen: NSScreen) -> NSRect {
        let panelRect = panelWindow?.frame ?? latestFrame ?? panelFrame(
            for: screen.frame,
            showsMediaCard: panelAnimator.showsMediaCard,
            timerCount: activeQuickTimersForLockScreen.count
        )
        let artSize = LockScreenMusicPanel.compactAlbumArtSize
        let mediaCardHeight = LockScreenMusicPanel.mediaCardSize(
            progress: panelAnimator.albumArtPanelMorphProgress,
            availableWidth: panelRect.width
        ).height
        return NSRect(
            x: panelRect.minX + LockScreenMusicPanel.collapsedContentLeadingPadding,
            y: panelRect.minY + (mediaCardHeight / 2) - (artSize / 2) + LockScreenMusicPanel.compactAlbumArtVerticalOffset,
            width: artSize,
            height: artSize
        )
    }

    private func showExpandedArtworkBackdrop() {
        guard panelWindow?.isVisible == true,
              let screen = currentScreen() else {
            return
        }

        guard !panelAnimator.isAlbumArtTransitioning else { return }

        expandedArtworkRestoreSequence &+= 1
        expandedArtworkRestoreTask?.cancel()
        expandedArtworkRestoreTask = nil

        panelAnimator.isAlbumArtTransitioning = false

        let backdropFrame = screen.frame
        let backdropSize = screen.frame.size

        let window: NSWindow
        if let existingWindow = expandedArtworkBackdropWindow {
            window = existingWindow
        } else {
            let newWindow = QuartzNotchWindow(
                contentRect: backdropFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .normal
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false
            newWindow.ignoresMouseEvents = true
            expandedArtworkBackdropWindow = newWindow
            window = newWindow
            hasDelegatedExpandedArtworkBackdrop = false
        }

        window.setFrame(backdropFrame, display: true)

        if window.isVisible {
            showLoginOverlay()
            window.orderFrontRegardless()
            panelWindow?.orderFrontRegardless()
            return
        }

        let backdropRootView: AnyView
        if #available(macOS 15.0, *) {
            backdropRootView = AnyView(
                LockScreenExpandedAlbumArtBackdropOverlay(size: backdropSize).ignoresSafeArea()
            )
        } else {
            backdropRootView = AnyView(Color.black.ignoresSafeArea())
        }
        let hosting = NSHostingView(rootView: backdropRootView)
        hosting.frame = NSRect(origin: .zero, size: backdropFrame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        showLoginOverlay()

        LockScreenBackdropSkyLightOperator.shared.delegateWindow(window)
        hasDelegatedExpandedArtworkBackdrop = true
        window.orderFrontRegardless()
        panelWindow?.orderFrontRegardless()
    }

    private func hideExpandedArtworkBackdrop() {
        panelAnimator.isAlbumArtTransitioning = false
        guard let window = expandedArtworkBackdropWindow else { return }
        expandedArtworkBackdropWindow = nil
        let wasDelegated = hasDelegatedExpandedArtworkBackdrop
        hasDelegatedExpandedArtworkBackdrop = false
        hideLoginOverlay()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.contentView = nil
            window.alphaValue = 1
            if wasDelegated {
                LockScreenBackdropSkyLightOperator.shared.undelegateWindow(window)
            }
        })
    }

    // MARK: - LoginUIKit reconstruction overlay

    private func showLoginOverlay() {
        guard let screen = currentScreen() else { return }
        let overlayFrame = screen.frame

        let window: NSWindow
        if let existingWindow = loginOverlayWindow {
            window = existingWindow
        } else {
            let newWindow = QuartzNotchWindow(
                contentRect: overlayFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .normal
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false
            newWindow.ignoresMouseEvents = true
            loginOverlayWindow = newWindow
            window = newWindow
            hasDelegatedLoginOverlay = false
        }

        window.setFrame(overlayFrame, display: true)

        if window.isVisible {
            window.orderFrontRegardless()
            panelWindow?.orderFrontRegardless()
            return
        }

        let uikitView = LockScreenUIKitReconstructionNSView()
        uikitView.frame = NSRect(origin: .zero, size: overlayFrame.size)
        uikitView.autoresizingMask = [.width, .height]
        window.contentView = uikitView

        let baseLevel = LockScreenBackdropSkyLightOperator.shared.lockScreenLevel
        LockScreenBackdropSkyLightOperator.shared.delegateWindow(window, level: baseLevel + 5)
        hasDelegatedLoginOverlay = true

        window.alphaValue = 0
        window.orderFrontRegardless()
        panelWindow?.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak window] in
            guard let window, window.isVisible else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1
            }
        }
    }

    private func hideLoginOverlay() {
        guard let window = loginOverlayWindow else { return }
        loginOverlayWindow = nil
        let wasDelegated = hasDelegatedLoginOverlay
        hasDelegatedLoginOverlay = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.contentView = nil
            window.alphaValue = 1
            if wasDelegated {
                LockScreenBackdropSkyLightOperator.shared.undelegateWindow(window)
            }
        })
    }

    private func hideExpandedArtworkOverlay(animated: Bool = true) {
        guard let window = expandedArtworkWindow else { return }
        if !animated {
            window.alphaValue = 0
            window.orderOut(nil)
            window.contentView = nil
            window.alphaValue = 1
            return
        }

        if let contentLayer = window.contentView?.layer {
            contentLayer.removeAnimation(forKey: "expandedArtworkDismissMotion")
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 1.0
            scaleAnimation.toValue = expandedArtworkSourceScale
            let translateXAnimation = CABasicAnimation(keyPath: "transform.translation.x")
            translateXAnimation.fromValue = 0
            translateXAnimation.toValue = expandedArtworkSourceOffset.width
            let translateYAnimation = CABasicAnimation(keyPath: "transform.translation.y")
            translateYAnimation.fromValue = 0
            translateYAnimation.toValue = expandedArtworkSourceOffset.height
            let dismissMotion = CAAnimationGroup()
            dismissMotion.animations = [scaleAnimation, translateXAnimation, translateYAnimation]
            dismissMotion.duration = 0.22
            dismissMotion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentLayer.add(dismissMotion, forKey: "expandedArtworkDismissMotion")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.transform = expandedArtworkDismissTransform()
            CATransaction.commit()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            if let contentLayer = window.contentView?.layer {
                contentLayer.removeAnimation(forKey: "expandedArtworkDismissMotion")
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                contentLayer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
            window.orderOut(nil)
            window.contentView = nil
            window.alphaValue = 1
        }
    }

    private func expandedArtworkDismissTransform() -> CATransform3D {
        var transform = CATransform3DIdentity
        transform = CATransform3DScale(transform, expandedArtworkSourceScale, expandedArtworkSourceScale, 1)
        transform = CATransform3DTranslate(
            transform,
            expandedArtworkSourceOffset.width,
            expandedArtworkSourceOffset.height,
            0
        )
        return transform
    }

    private var usesLightCompatibilityFallbackStyling: Bool {
        let fallbackActive = Defaults[.forceLiquidGlassCompatibilityFallback]
            || (NSClassFromString("NSGlassEffectView") as? NSView.Type) == nil
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let interfaceStyle = globalDomain?["AppleInterfaceStyle"] as? String
        let isSystemLightAppearance = interfaceStyle?.lowercased() != "dark"
        return fallbackActive && isSystemLightAppearance
    }

    private var usesCompatibilityFallbackStyling: Bool {
        Defaults[.forceLiquidGlassCompatibilityFallback]
            || (NSClassFromString("NSGlassEffectView") as? NSView.Type) == nil
    }

    private func startBackdropRefreshIfNeeded() {
        stopBackdropRefresh()
        guard usesCompatibilityFallbackStyling, !panelAnimator.usesWindowBackdropFallback else { return }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let frame = self.latestFrame else { return }
                self.refreshBackdropSnapshot(panelFrame: frame, excluding: self.panelWindow)
            }
        }
        backdropRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBackdropRefresh() {
        backdropRefreshTimer?.invalidate()
        backdropRefreshTimer = nil
    }

    private func refreshBackdropSnapshot(panelFrame: NSRect, excluding window: NSWindow?) {
        guard usesCompatibilityFallbackStyling else {
            panelAnimator.fallbackBackdropSnapshot = nil
            return
        }
        let windowNumber = window?.windowNumber
        guard !backdropCaptureInFlight else {
            pendingBackdropCapture = (panelFrame: panelFrame, windowNumber: windowNumber)
            return
        }

        backdropCaptureInFlight = true
        backdropCaptureRequestID &+= 1
        let requestID = backdropCaptureRequestID
        let desktopBounds = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.union(frame)
            }
        let captureRect = Self.quartzCaptureRect(for: panelFrame, in: desktopBounds)
        let targetScreenFrame = Self.targetScreenFrame(for: panelFrame) ?? panelFrame
        let wallpaperSearchRect = targetScreenFrame
        let ciContext = backdropCIContext

        backdropCaptureQueue.async { [captureRect, wallpaperSearchRect] in
            let wallpaperWindowID = Self.desktopWallpaperWindowID(intersecting: wallpaperSearchRect)
            let snapshot = wallpaperWindowID.flatMap { wallpaperWindowID in
                Self.makeBlurredBackdropSnapshot(
                    captureRect: captureRect,
                    wallpaperWindowID: wallpaperWindowID,
                    ciContext: ciContext
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.backdropCaptureInFlight = false

                if requestID == self.backdropCaptureRequestID,
                   let snapshot {
                    self.panelAnimator.fallbackBackdropSnapshot = snapshot
                }

                if let pending = self.pendingBackdropCapture {
                    self.pendingBackdropCapture = nil
                    self.refreshBackdropSnapshot(
                        panelFrame: pending.panelFrame,
                        excluding: pending.windowNumber.flatMap { number in
                            self.panelWindow?.windowNumber == number ? self.panelWindow : nil
                        }
                    )
                }
            }
        }
    }

    private nonisolated static func makeBlurredBackdropSnapshot(
        captureRect: CGRect,
        wallpaperWindowID: CGWindowID,
        ciContext: CIContext
    ) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            wallpaperWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let clamped = ciImage.clampedToExtent()
        guard let blur = CIFilter(name: "CIGaussianBlur") else {
            return NSImage(cgImage: cgImage, size: NSSize(width: captureRect.width, height: captureRect.height))
        }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(18.0, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: ciImage.extent) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: captureRect.width, height: captureRect.height))
        }

        guard let blurredCGImage = ciContext.createCGImage(output, from: ciImage.extent) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: captureRect.width, height: captureRect.height))
        }

        let imageSize = NSSize(width: captureRect.width, height: captureRect.height)
        return NSImage(cgImage: blurredCGImage, size: imageSize)
    }

    private nonisolated static func desktopWallpaperWindowID(intersecting targetRect: CGRect) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return windowList
            .compactMap { windowInfo -> (windowID: CGWindowID, bounds: CGRect, score: CGFloat)? in
                guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                      ownerName == "Dock",
                      let windowName = windowInfo[kCGWindowName as String] as? String,
                      windowName.hasPrefix("Wallpaper-"),
                      let windowNumber = windowInfo[kCGWindowNumber as String] as? NSNumber,
                      let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
                else {
                    return nil
                }

                let intersection = bounds.intersection(targetRect)
                guard !intersection.isNull, !intersection.isEmpty else {
                    return nil
                }

                return (CGWindowID(windowNumber.uint32Value), bounds, intersection.width * intersection.height)
            }
            .max(by: { $0.score < $1.score })?
            .windowID
    }

    private nonisolated static func targetScreenFrame(for panelFrame: NSRect) -> NSRect? {
        let midpoint = NSPoint(x: panelFrame.midX, y: panelFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(midpoint) })?.frame
    }

    private nonisolated static func quartzCaptureRect(for cocoaRect: NSRect, in desktopBounds: CGRect) -> CGRect {
        let captureX = cocoaRect.minX
        let captureY = desktopBounds.maxY - cocoaRect.maxY

        return CGRect(
            x: captureX,
            y: captureY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    private func restoreExpandedArtworkWallpaper(for screenUUID: String? = nil) {
        let targetUUID = screenUUID ?? expandedArtworkWallpaperScreenUUID
        guard let targetUUID else { return }
        defer {
            if expandedArtworkWallpaperScreenUUID == targetUUID {
                expandedArtworkWallpaperScreenUUID = nil
            }
            if let generatedURL = generatedDesktopImageURLs.removeValue(forKey: targetUUID) {
                try? FileManager.default.removeItem(at: generatedURL)
            }
            originalDesktopImages.removeValue(forKey: targetUUID)
        }

        guard let screen = NSScreen.screen(withUUID: targetUUID),
              let original = originalDesktopImages[targetUUID] else { return }

        do {
            try NSWorkspace.shared.setDesktopImageURL(original.url, for: screen, options: original.options)
        } catch {
            print("Failed to restore desktop wallpaper: \(error)")
        }
    }

}
