
import AVFoundation
import AVKit
import AppKit
import Combine
import Foundation
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

private struct BottomBleedClipShape: Shape {
    let extraBottom: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height + max(0, extraBottom)
        ))
    }
}

private struct BottomTrailingBleedClipShape: Shape {
    let extraBottom: CGFloat
    let extraTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width + max(0, extraTrailing),
            height: rect.height + max(0, extraBottom)
        ))
    }
}

private struct NotchLiquidGlassBackground<Content: View>: NSViewRepresentable {
    let variant: Int
    let cornerRadius: CGFloat
    let trigger: Double
    let forceFallback: Bool
    let content: Content

    init(
        variant: Int = 11,
        cornerRadius: CGFloat,
        trigger: Double = 0,
        forceFallback: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.trigger = trigger
        self.forceFallback = forceFallback
        self.content = content()
    }

    private var nativeGlassType: NSView.Type? {
        guard !forceFallback else { return nil }
        return NSClassFromString("NSGlassEffectView") as? NSView.Type
    }

    func makeNSView(context: Context) -> NSView {
        if let glassType = nativeGlassType {
            let glass = glassType.init(frame: .zero)
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            setVariant(on: glass, value: variant)

            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(host, forKey: "contentView")
            return glass
        }

        let fallback = NSVisualEffectView()
        configureFallback(fallback)

        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            host.topAnchor.constraint(equalTo: fallback.topAnchor),
            host.bottomAnchor.constraint(equalTo: fallback.bottomAnchor),
        ])
        return fallback
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let glassType = nativeGlassType,
           nsView.isKind(of: glassType),
           let host = nsView.value(forKey: "contentView") as? NSHostingView<Content>
        {
            host.rootView = content
            nsView.setValue(cornerRadius, forKey: "cornerRadius")
            setVariant(on: nsView, value: variant)
        } else if let fallback = nsView as? NSVisualEffectView,
                  let host = fallback.subviews.first as? NSHostingView<Content> {
            host.rootView = content
            configureFallback(fallback)
        }

        let baseAlpha: CGFloat = nativeGlassType == nil ? 0.90 : 1.0
        if abs(nsView.alphaValue - baseAlpha) > 0.001 {
            nsView.alphaValue = baseAlpha
        }
    }

    private typealias VariantSetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void

    private func setVariant(on object: AnyObject, value: Int) {
        let selector = NSSelectorFromString("set_variant:")
        guard
            let method = class_getInstanceMethod(object_getClass(object), selector)
        else { return }
        let imp = method_getImplementation(method)
        let function = unsafeBitCast(imp, to: VariantSetterIMP.self)
        function(object, selector, value)
    }

    private func configureFallback(_ fallback: NSVisualEffectView) {
        fallback.material = .underWindowBackground
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        fallback.isEmphasized = false
        fallback.alphaValue = 0.90
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = cornerRadius
        fallback.layer?.masksToBounds = true
        fallback.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct NotchRefractionBackdrop: NSViewRepresentable {
    let opacity: CGFloat
    let strength: CGFloat
    let cornerRadius: CGFloat
    let sampleScale: CGFloat

    func makeNSView(context: Context) -> NotchRefractionBackdropView {
        let view = NotchRefractionBackdropView()
        view.opacity = opacity
        view.strength = strength
        view.cornerRadius = cornerRadius
        view.sampleScale = sampleScale
        return view
    }

    func updateNSView(_ nsView: NotchRefractionBackdropView, context: Context) {
        nsView.apply(opacity: opacity, strength: strength, cornerRadius: cornerRadius, sampleScale: sampleScale)
    }
}

private final class NotchRefractionBackdropView: NSView {
    var opacity: CGFloat = 1 {
        didSet { alphaValue = max(0, min(1, opacity)) }
    }

    var strength: CGFloat = 1 {
        didSet {
            guard abs(strength - oldValue) > 0.001 else { return }
            updateFilters()
        }
    }

    var cornerRadius: CGFloat = 14 {
        didSet {
            if abs(oldValue - cornerRadius) > 0.001 {
                needsLayout = true
            }
        }
    }

    var sampleScale: CGFloat = 0.5 {
        didSet {
            guard abs(sampleScale - oldValue) > 0.001 else { return }
            backdrop.setValue(sampleScale, forKey: "scale")
        }
    }

    private let backdrop: CALayer = {
        guard let backdropType = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            return CALayer()
        }
        return backdropType.init()
    }()

    private let sdfLayer: CALayer = {
        guard let layerType = NSClassFromString("CASDFLayer") as? CALayer.Type else {
            return CALayer()
        }
        let layer = layerType.init()
        layer.name = "@0"
        return layer
    }()

    private let sdfElementLayer: CALayer = {
        guard let layerType = NSClassFromString("CASDFElementLayer") as? CALayer.Type else {
            return CALayer()
        }
        return layerType.init()
    }()

    private let containerLayer = CALayer()
    private let sdfBleed: CGFloat = 3

    private let groupName = "quartznotch.notch.refraction.\(UUID().uuidString)"

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        backdrop.frame = bounds
        backdrop.bounds = bounds
        sdfLayer.frame = bounds
        sdfLayer.bounds = bounds
        containerLayer.frame = bounds
        containerLayer.bounds = bounds

        let sdfFrame = bounds.insetBy(dx: -sdfBleed, dy: -sdfBleed)
        sdfElementLayer.frame = sdfFrame
        sdfElementLayer.bounds = CGRect(origin: .zero, size: sdfFrame.size)
        sdfElementLayer.cornerRadius = min(
            cornerRadius + sdfBleed,
            min(sdfFrame.width, sdfFrame.height) / 2
        )

        layer?.cornerRadius = 0
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        backdrop.setValue(window != nil, forKey: "windowServerAware")
        window?.setValue(false, forKey: "shouldAutoFlattenLayerTree")
        window?.setValue(true, forKey: "canHostLayersInWindowServer")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        backdrop.contentsScale = scale
        sdfLayer.contentsScale = scale
        containerLayer.contentsScale = scale
        sdfElementLayer.contentsScale = scale
        CATransaction.commit()
    }

    @objc private func _shouldAutoFlattenLayerTree() -> Bool {
        false
    }

    func apply(
        opacity newOpacity: CGFloat,
        strength newStrength: CGFloat,
        cornerRadius newCornerRadius: CGFloat,
        sampleScale newSampleScale: CGFloat
    ) {
        if abs(opacity - newOpacity) > 0.001 {
            opacity = newOpacity
        }
        if abs(strength - newStrength) > 0.001 {
            strength = newStrength
        }
        if abs(cornerRadius - newCornerRadius) > 0.001 {
            cornerRadius = newCornerRadius
        }
        if abs(sampleScale - newSampleScale) > 0.001 {
            sampleScale = newSampleScale
        }
    }

    func updateFilters() {
        let amount = max(0.1, strength)

        guard let glass = Self.makeFilter(type: "glassBackground") else {
            backdrop.filters = nil
            return
        }

        glass.setValue(3.2, forKey: "inputBlurRadius")
        glass.setValue(0.38, forKey: "inputBlurOpacity0")
        glass.setValue(0.31, forKey: "inputBlurOpacity1")
        glass.setValue(0.26, forKey: "inputBlurOpacity2")
        glass.setValue(0.31, forKey: "inputBlurOpacity3")
        glass.setValue(0.38, forKey: "inputBlurOpacity4")
        glass.setValue(0.0, forKey: "inputBlurFillBlurRadius")
        glass.setValue(0.0, forKey: "inputBlurFillLightenOpacity")
        glass.setValue(0.0, forKey: "inputBlurFillDarkenOpacity")
        glass.setValue(0.0, forKey: "inputBlurFillNormalOpacity")
        glass.setValue("@0", forKey: "inputSourceSublayerName")
        glass.setValue(0.08, forKey: "inputFaceOpacity")
        glass.setValue(0.0, forKey: "inputShadowOpacity")
        glass.setValue(0.0, forKey: "inputRingShadowOpacity")
        glass.setValue(0.0, forKey: "inputKeyFillHighlightAmount")
        glass.setValue(0.0, forKey: "inputBleedOpacity")
        glass.setValue(0.0, forKey: "inputAberrationAmount")

        glass.setValue(-52.0 * amount, forKey: "inputInnerRefractionAmount")
        glass.setValue(38.0 * amount, forKey: "inputOuterRefractionAmount")
        glass.setValue(18.0 * amount, forKey: "inputInnerRefractionHeight")
        glass.setValue(24.0 * amount, forKey: "inputOuterRefractionHeight")
        glass.setValue(1.0, forKey: "inputRefractionOpacity")
        glass.setValue(-1.0, forKey: "inputRefractionDistance0")
        glass.setValue(-0.5, forKey: "inputRefractionDistance1")
        glass.setValue(0.0, forKey: "inputBleedBlurRadius")
        glass.setValue(0.0, forKey: "inputBleedAmount")

        backdrop.filters = [glass]
        backdrop.setNeedsDisplay()
    }

    private func commonInit() {
        wantsLayer = true
        layerUsesCoreImageFilters = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        configureSDFLayers()

        backdrop.name = "notch-refraction-backdrop"
        backdrop.backgroundColor = NSColor.clear.cgColor
        backdrop.allowsGroupOpacity = true
        backdrop.setValue(true, forKey: "allowsGroupBlending")
        backdrop.setValue(false, forKey: "allowsEdgeAntialiasing")
        backdrop.setValue(true, forKey: "allowsInPlaceFiltering")
        backdrop.setValue(true, forKey: "disablesOccludedBackdropBlurs")
        backdrop.setValue(true, forKey: "ignoresOffscreenGroups")
        backdrop.setValue(true, forKey: "tracksLuma")
        backdrop.setValue(true, forKey: "allowsFilteredLuma")
        backdrop.setValue(sampleScale, forKey: "scale")
        backdrop.setValue(0.0, forKey: "bleedAmount")
        backdrop.setValue(groupName, forKey: "groupName")
        backdrop.sublayers = [sdfLayer]
        layer?.addSublayer(backdrop)
        updateFilters()
    }

    private func configureSDFLayers() {
        sdfLayer.name = "@0"
        sdfLayer.anchorPoint = .zero
        sdfLayer.setValue(8.0, forKey: "smoothness")

        if let effectType = NSClassFromString("CASDFOutputEffect") as? NSObject.Type {
            let effect = effectType.init()
            effect.setValue(-1000.0, forKey: "minimum")
            effect.setValue(1.0, forKey: "maximum")
            sdfLayer.setValue(effect, forKey: "effect")
        }

        sdfElementLayer.anchorPoint = .zero
        sdfElementLayer.setValue(0.5, forKey: "gradientOvalization")
        sdfElementLayer.setValue("bounds", forKey: "mode")
        sdfElementLayer.setValue("union", forKey: "operation")
        if let delegate = NSClassFromString("_SwiftUISDFLayerDelegate") {
            sdfElementLayer.perform(NSSelectorFromString("setDelegate:"), with: delegate)
        }

        containerLayer.anchorPoint = .zero
        containerLayer.sublayers = [sdfElementLayer]
        sdfLayer.sublayers = [containerLayer]
    }

    private static func makeFilter(type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
    }

}

private struct FocusLiveActivity: View {
    struct Layout {
        let leftPadding: CGFloat
        let rightPadding: CGFloat
        let leftWidth: CGFloat
        let rightWidth: CGFloat
        let fontSize: CGFloat
    }

    let notchWidth: CGFloat
    let baseHeight: CGFloat
    let symbolName: String
    let statusText: String
    let tint: Color
    let layout: Layout

    @ViewBuilder
    private func focusSymbolView(size: CGFloat) -> some View {
        if NSImage(named: NSImage.Name(symbolName)) != nil {
            let customSize = size * 1.08
            Image(symbolName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: customSize, height: customSize)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size, weight: .semibold, design: .rounded))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            focusSymbolView(size: layout.fontSize + 0.8)
                .foregroundStyle(tint)
                .symbolRenderingMode(.monochrome)
                .frame(width: layout.leftWidth, alignment: .leading)
                .padding(.leading, layout.leftPadding)
                .frame(height: baseHeight)

            Spacer(minLength: notchWidth)

            Text(statusText)
                .font(.system(size: layout.fontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(tint)
                .frame(width: layout.rightWidth, alignment: .trailing)
                .padding(.trailing, layout.rightPadding)
                .frame(height: baseHeight)
        }
        .frame(height: baseHeight, alignment: .center)
    }
}

private struct OpenShoulderShape: Shape {
    enum Side { case left, right }
    let side: Side

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height)
        let h = max(rect.height, r)
        let cornerRadius = max(1, min(r * 0.72, r - 0.5))
        var p = Path()

        switch side {
        case .left:
            p.move(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: r - cornerRadius, y: 0))
            p.addQuadCurve(
                to: CGPoint(x: r, y: cornerRadius),
                control: CGPoint(x: r, y: 0)
            )
            p.addLine(to: CGPoint(x: r, y: h))
            p.addLine(to: CGPoint(x: r, y: 0))
            p.closeSubpath()
        case .right:
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: cornerRadius, y: 0))
            p.addQuadCurve(
                to: CGPoint(x: 0, y: cornerRadius),
                control: CGPoint(x: 0, y: 0)
            )
            p.addLine(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }

        return p
    }
}

private struct OpenShoulderOuterStroke: Shape {
    enum Side { case left, right }
    let side: Side

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height)
        let cornerRadius = max(1, min(r * 0.72, r - 0.5))
        var p = Path()

        switch side {
        case .left:
            p.move(to: CGPoint(x: r - cornerRadius, y: 0))
            p.addQuadCurve(
                to: CGPoint(x: r, y: cornerRadius),
                control: CGPoint(x: r, y: 0)
            )
        case .right:
            p.move(to: CGPoint(x: cornerRadius, y: 0))
            p.addQuadCurve(
                to: CGPoint(x: 0, y: cornerRadius),
                control: CGPoint(x: 0, y: 0)
            )
        }

        return p
    }
}

private struct DetachedTimerNeedlePivotModifier: ViewModifier {
    let length: CGFloat
    let pivotFraction: CGFloat
    let angle: Double

    func body(content: Content) -> some View {
        let pivot = max(2, min(length - 2, length * pivotFraction))
        let anchor = UnitPoint(x: pivot / max(1, length), y: 0.5)
        return content
            .offset(x: length / 2 - pivot)
            .rotationEffect(.degrees(angle), anchor: anchor)
    }
}

private struct SecondaryDetachedSlideModifier: ViewModifier {
    let x: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .scaleEffect(x: scale, y: 1.0, anchor: .leading)
    }
}

private struct DetachedSecondaryContentFade<Content: View>: View {
    let baseOpacity: CGFloat
    let trigger: Int
    let appearDelayMs: UInt64
    let appearDuration: Double
    @ViewBuilder let content: () -> Content

    @State private var progress: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        content()
            .opacity(baseOpacity * progress)
            .onAppear {
                task?.cancel()
                progress = 0
                task = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(appearDelayMs))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: appearDuration)) {
                        progress = 1
                    }
                }
            }
            .onDisappear {
                task?.cancel()
                task = nil
                progress = 0
            }
            .onChange(of: trigger) { _, _ in
                task?.cancel()
                progress = 0
                task = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(appearDelayMs))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: appearDuration)) {
                        progress = 1
                    }
                }
            }
    }
}

private struct LiquidBottomArcMask: View {
    let sideLiftProgress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                verticalMask

                if sideLiftProgress > 0 {
                    SideTransparencyLift(side: .left)
                        .frame(width: geo.size.width * 0.36, height: geo.size.height)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .blur(radius: 42)
                        .opacity(sideLiftProgress)
                        .blendMode(.destinationOut)

                    SideTransparencyLift(side: .right)
                        .frame(width: geo.size.width * 0.36, height: geo.size.height)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .blur(radius: 42)
                        .opacity(sideLiftProgress)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
        }
    }

    private var verticalMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.00),
                .init(color: .black.opacity(0.98), location: 0.58),
                .init(color: .black.opacity(0.82), location: 0.74),
                .init(color: .black.opacity(0.58), location: 0.87),
                .init(color: .black.opacity(0.40), location: 0.955),
                .init(color: .black.opacity(0.30), location: 0.99),
                .init(color: .black.opacity(0.28), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private struct SideTransparencyLift: Shape {
        enum Side {
            case left
            case right
        }

        let side: Side

        func path(in rect: CGRect) -> Path {
            let mirrored = side == .right
            let edgeX = mirrored ? rect.maxX : rect.minX
            let innerX = mirrored ? rect.minX : rect.maxX
            let direction: CGFloat = mirrored ? -1 : 1

            var path = Path()
            path.move(to: CGPoint(x: edgeX, y: rect.height * 0.58))
            path.addCurve(
                to: CGPoint(x: edgeX + direction * rect.width * 0.46, y: rect.height * 0.84),
                control1: CGPoint(x: edgeX + direction * rect.width * 0.08, y: rect.height * 0.65),
                control2: CGPoint(x: edgeX + direction * rect.width * 0.28, y: rect.height * 0.74)
            )
            path.addCurve(
                to: CGPoint(x: innerX, y: rect.height),
                control1: CGPoint(x: edgeX + direction * rect.width * 0.66, y: rect.height * 0.94),
                control2: CGPoint(x: edgeX + direction * rect.width * 0.84, y: rect.height)
            )
            path.addLine(to: CGPoint(x: edgeX, y: rect.height))
            path.closeSubpath()
            return path
        }
    }
}

@MainActor
struct ContentView: View {
    private enum OverlaySwitchDirection {
        case none
        case toCalendar
        case toCamera
    }
    private enum ClosedLiveActivityMode {
        case standard
        case compactMode
    }

    private enum ClosedActivityKind {
        case bluetooth
        case focus
        case timer
        case fileTray
        case music
    }

    private enum BluetoothTakeoverExitKind {
        case focus
        case timer
        case fileTray
        case music
    }

    @EnvironmentObject var vm: QuartzViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared

    @StateObject private var tvm = ShelfStateViewModel.shared

    @ObservedObject private var lockScreenState = LockScreenState.shared

    @ObservedObject private var lockTransition = LockTransitionState.shared

    @ObservedObject var bluetoothModel = BluetoothStatusViewModel.shared
    @StateObject private var focusModeManager = FocusModeLiveActivityManager.shared

    @StateObject private var quickTimerManager = QuickTimerManager.shared
    @Default(.debugLargeScreenLayoutPreviewMode) private var debugLargeScreenLayoutPreviewMode
    @Default(.showOnLockScreen) private var showOnLockScreen
    @Default(.liveActivityLockScreen) private var liveActivityLockScreen
    @Default(.cinemaMode) private var cinemaMode

    @State private var lockSuppressionProgress: CGFloat = 0

    @State private var hoverTask: Task<Void, Never>?
    @State private var liquidCloseTransitionTask: Task<Void, Never>?
    @State private var liquidTransitionPerfTask: Task<Void, Never>?
    @State private var liquidVisualBlend: CGFloat = 0
    @State private var liquidStrokeReveal: CGFloat = 0
    @State private var liquidTransitionPerfMode: Bool = false
    @State private var keepLiquidVisualDuringClose: Bool = false
    @State private var isHovering: Bool = false
    @State private var detachedSecondaryAppearToken: Int = 0

    @State private var isBluetoothPopupHovering: Bool = false
    @State private var isBluetoothSidesHovering: Bool = false
    @State private var isBluetoothCenterHovering: Bool = false
    @State private var isBluetoothPopupTransitioning: Bool = false
    @State private var bluetoothCenterHoverTask: Task<Void, Never>?
    @State private var bluetoothSidesHoverTask: Task<Void, Never>?
    @State private var bluetoothTransitionTask: Task<Void, Never>?
    @State private var bluetoothPopupCloseTask: Task<Void, Never>?

    @State private var isTimerPopupHovering: Bool = false
    @State private var isTimerExpandedHovering: Bool = false
    @State private var isTimerPopupTransitioning: Bool = false
    @State private var isTimerPopupHoverArmed: Bool = true
    @State private var suppressTimerPopupAutoOpenUntil: Date = .distantPast
    @State private var keepTimerPopupOpenForFinishedAlert: Bool = false

    @State private var isTimerSidesHovering: Bool = false
    @State private var timerSidesHoverTask: Task<Void, Never>?
    @State private var timerTransitionTask: Task<Void, Never>?
    @State private var timerPopupRearmTask: Task<Void, Never>?
    @State private var timerPopupCloseTask: Task<Void, Never>?
    @State private var timerReservedFooterHeight: CGFloat = 0
    @State private var timerReservedTargetWidth: CGFloat = 0
    @State private var timerWindowReservationReleaseTask: Task<Void, Never>?

    @State private var hostWindow: NSWindow?
    @State private var timerGlobalMouseMonitor: Any?
    @State private var nowPlayingClickMonitor: Any?
    @State private var isTimerProximityHovering: Bool = false
    @State private var closedPopupFailsafeTask: Task<Void, Never>?
    @State private var timerAlarmBackgroundImpulseX: CGFloat = 0
    @State private var timerAlarmBackgroundDirection: CGFloat = -1
    @State private var timerAlarmBackgroundSettleTask: Task<Void, Never>?
    @State private var lastTimerAlertHapticAt: Date = .distantPast
    @State private var isNowPlayingLeftHovering: Bool = false
    @State private var isNowPlayingRightHovering: Bool = false
    @State private var isNowPlayingSneakPeekForcedByHover: Bool = false
    @State private var musicExitPending: Bool = false
    @State private var musicExitTask: Task<Void, Never>? = nil
    @State private var musicHiddenByExpandingView: Bool = false
    @State private var showMusicExitOverlay: Bool = false
    @State private var animateMusicExitOverlay: Bool = false
    @State private var bluetoothTakeoverExitPending: Bool = false
    @State private var bluetoothTakeoverExitTask: Task<Void, Never>? = nil
    @State private var bluetoothHiddenClosedActivity: BluetoothTakeoverExitKind? = nil
    @State private var bluetoothTakeoverExitOverlayKind: BluetoothTakeoverExitKind? = nil
    @State private var animateBluetoothTakeoverExitOverlay: Bool = false
    @State private var bluetoothClosedOverlaySuppressed: Bool = false
    @State private var bluetoothReturnSuppressed: Bool = false
    @State private var bluetoothReturnSuppressTask: Task<Void, Never>? = nil
    @State private var suppressNotchHoverHapticUntil: Date = .distantPast
    @State private var nowPlayingSneakPeekWatchdogTask: Task<Void, Never>?
    @State private var nowPlayingSneakPeekCloseTask: Task<Void, Never>?
    @State private var suppressNowPlayingRightActionUntil: Date = .distantPast

    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics: Bool = false
    @State private var suppressAutoCloseUntil: Date = .distantPast
    @State private var suppressNotchOpenUntilAfterTimerPopupClose: Date = .distantPast
    @State private var openingFromNowPlayingCenterHover: Bool = false
    @State private var frozenHoverExitTask: Task<Void, Never>?
    @State private var frozenHoverZoneWidth: CGFloat = 0
    @State private var frozenHoverZoneActive: Bool = false
    @State private var frozenHoverStartPointer: CGPoint = .zero
    @State private var frozenHoverPointerMoved: Bool = false
    @State private var frozenHoverOutsideTicks: Int = 0
    @State private var openHoverWatchdogTask: Task<Void, Never>?
    @State private var openContentRevealTask: Task<Void, Never>?

    @State private var ignoreHoverExitUntil: Date = .distantPast

    @State private var isSwitchingOverlay: Bool = false
    @State private var overlaySwitchToken: Int = 0
    private let overlaySwitchDelayMs: UInt64 = 140
    @State private var overlayWidthHold: CGFloat = 0
    @State private var overlayHeightHold: CGFloat = 0
    @State private var calendarRestoreAfterCamera: Bool = false
    @State private var calendarToCameraExitOffsetX: CGFloat = 0
    @State private var calendarToCameraTrailingReserve: CGFloat = 0
    @State private var deferCameraOverlayDuringToCameraSwitch: Bool = false
    @State private var overlaySwitchDirection: OverlaySwitchDirection = .none
    @State private var openContentRevealProgress: CGFloat = 0
    @State private var openHeaderWidthProgress: CGFloat = 0
    @State private var notchOpenHorizontalToken: Int = 0
    @State private var lastNotchHoverHapticAt: Date = .distantPast
    private let calendarOverlayContentWidth: CGFloat = 215
    private let calendarOverlayLeadingGutterWidth: CGFloat = 6
    private var calendarOverlayTotalWidth: CGFloat {
        calendarOverlayContentWidth + calendarOverlayLeadingGutterWidth
    }
    private var calendarMonthLeadingSafetyInset: CGFloat {
        guard vm.notchState == .open else { return 0 }

        let physicalNotchRightEdge = (openWidthValueComputed + vm.closedNotchSize.width) / 2
        let calendarLeadingEdge = openWidthValueComputed - calendarOverlayTotalWidth
        let monthLeadingEdge = calendarLeadingEdge + calendarOverlayLeadingGutterWidth + 4

        return max(0, physicalNotchRightEdge - monthLeadingEdge)
    }

    private struct NowPlayingEdgeTrackingMetrics {
        let leftEdgeWidth: CGFloat
        let rightEdgeWidth: CGFloat
        let totalWidth: CGFloat
        let totalHeight: CGFloat
        let xOffset: CGFloat
        let yOffset: CGFloat
    }

    @State private var isPagerScrollEnabled: Bool = true
    private var isPagerScrollEffectivelyEnabled: Bool {
        isPagerScrollEnabled && !vm.anyDropZoneTargeting
    }

    @State private var batteryChinFrom: CGFloat = 0
    @State private var batteryChinTo: CGFloat = 0
    @State private var batteryChinPhase: CGFloat = 1

    private let batteryAppearDuration: Double = 0.21
    private let batteryDisappearDuration: Double = 0.46

 // MARK: - Battery closed live activity content reveal
    private var batteryClosedContentProgress: CGFloat {
        guard vm.notchState == .closed else { return isBatteryClosedNotificationShowing ? 1 : 0 }
        guard closedActivityVisibility > 0.001 else { return 0 }
        guard Defaults[.showPowerStatusNotifications] else { return 0 }
        guard coordinator.expandingView.type == .battery else { return isBatteryClosedNotificationShowing ? 1 : 0 }

        let mode: OrganicBatteryEasing.Mode = (batteryChinTo >= batteryChinFrom) ? .appear : .disappear
        let p = OrganicBatteryEasing.map(batteryChinPhase, mode: mode)

        let gammaAppear: CGFloat = 1.15
        let gammaDisappear: CGFloat = 2.05
        let q: CGFloat = (mode == .appear) ? pow(p, gammaAppear) : pow(p, gammaDisappear)

        return (mode == .appear) ? q : (1 - q)
    }

    private var calendarOverlayTransition: AnyTransition {
        switch overlaySwitchDirection {
        case .toCalendar:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .toCamera:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .identity
            )
        case .none:
            return .opacity.combined(with: .scale(scale: 0.98))
        }
    }

    private var cameraOverlayTransition: AnyTransition {
        switch overlaySwitchDirection {
        case .toCamera:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .toCalendar:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .none:
            return .opacity.combined(with: .scale(scale: 0.98))
        }
    }

    private var closedLiveActivityTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
        )
    }

    private struct OrganicBatteryEasing {
        enum Mode { case appear, disappear }

        private static func makeTable(
            n: Int,
            tailStart: Double,
            powEarly: Double,
            powLate: Double,
            bumpT0: Double,
            bumpSigma: Double,
            bumpAmp: Double
        ) -> [CGFloat] {
            var v = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let t = Double(i) / Double(n - 1)
                let oneMinus = max(0.0, 1.0 - t)

                let x = min(max((t - tailStart) / (1.0 - tailStart), 0.0), 1.0)
                let gate = x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

                let effectivePow = powEarly + gate * (powLate - powEarly)
                let base = pow(oneMinus, effectivePow)

                let g = exp(-pow((t - bumpT0) / bumpSigma, 2))
                let bump = bumpAmp * g * pow(oneMinus, 2) * pow(1.0 - gate, 2)

                v[i] = max(1e-6, base + bump)
            }

            let dt = 1.0 / Double(n - 1)
            var area = 0.0
            var p = [Double](repeating: 0, count: n)
            p[0] = 0
            for i in 1..<n {
                area += 0.5 * (v[i - 1] + v[i]) * dt
                p[i] = area
            }

            let total = max(1e-9, p[n - 1])
            return p.map { CGFloat($0 / total) }
        }

        private static let n = 701

        private static let appearTable: [CGFloat] =
            makeTable(
                n: n,
                tailStart: 0.9965,
                powEarly: 0.95,
                powLate: 1.55,
                bumpT0: 0.9930,
                bumpSigma: 0.0040,
                bumpAmp: 0.035
            )

        private static let disappearTable: [CGFloat] =
            makeTable(
                n: n,
                tailStart: 0.920,
                powEarly: 0.85,
                powLate: 70.0,
                bumpT0: 0.0,
                bumpSigma: 1.0,
                bumpAmp: 0.0
            )

        static func map(_ t: CGFloat, mode: Mode) -> CGFloat {
            let table = (mode == .appear) ? appearTable : disappearTable
            let clamped = min(max(t, 0), 1)
            let maxIdx = table.count - 1
            let x = clamped * CGFloat(maxIdx)
            let i0 = Int(floor(x))
            let i1 = min(i0 + 1, maxIdx)
            let f = x - CGFloat(i0)
            return table[i0] * (1 - f) + table[i1] * f
        }
    }

    private let batteryClosedSidePadding: CGFloat = 2
    private let batteryClosedSideWidth: CGFloat = 72
    private let batteryClosedFontSize: CGFloat = 12.4
    private var batteryClosedStatusText: String { String(localized: "Charging") }

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.showCalendar) var showCalendar
    @Default(.showMirror) var showMirror
    @Default(.hideFromScreenRecordingMode) private var hideFromScreenRecordingMode

    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    @Default(.forceLiquidGlassCompatibilityFallback) private var forceLiquidGlassCompatibilityFallback
    private let animationSpring = NotchMotion.notchOpen

    private let timerLiveActivityMode: ClosedLiveActivityMode = .standard
    private let fileTrayLiveActivityMode: ClosedLiveActivityMode = .standard
    private let nowPlayingLiveActivityMode: ClosedLiveActivityMode = .standard

    private var isTimerCompactMode: Bool { timerLiveActivityMode == .compactMode }
    private var isFileTrayCompactMode: Bool { fileTrayLiveActivityMode == .compactMode }
    private var isNowPlayingCompactMode: Bool { nowPlayingLiveActivityMode == .compactMode }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private let closedActivityTopCornerRadius: CGFloat = 7
    private var liquidGlassCompatibilityFallbackActive: Bool {
        forceLiquidGlassCompatibilityFallback
            || (NSClassFromString("NSGlassEffectView") as? NSView.Type) == nil
    }

    private var isMacOS27OrNewer: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private var presentationEnabledViews: [NotchViews] {
        presentableNotchViewsInConfiguredOrder(currentView: coordinator.currentView)
    }

 // MARK: - Closed state helpers

    private var isBatteryClosedNotificationShowing: Bool {
        coordinator.expandingView.type == .battery
        && coordinator.expandingView.show
        && !musicExitPending
        && !bluetoothTakeoverExitPending
        && vm.notchState == .closed
        && closedActivityVisibility > 0.001
        && Defaults[.showPowerStatusNotifications]
    }

    private var wantsBluetoothClosedNotification: Bool {
        coordinator.expandingView.type == .bluetooth
        && coordinator.expandingView.show
        && vm.notchState == .closed
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && vm.effectiveClosedNotchHeight > 0
    }

    private var isBluetoothClosedNotificationShowing: Bool {
        wantsBluetoothClosedNotification
        && !bluetoothClosedOverlaySuppressed
        && !musicExitPending
    }

    private struct FocusVisualStyle {
        let symbol: String
        let color: Color
        let fallbackName: String
    }

    private var focusActivityStyle: FocusVisualStyle {
        let mode = FocusModeType.resolve(
            identifier: focusModeManager.currentFocusModeIdentifier,
            name: focusModeManager.currentFocusModeName
        )
        let symbolFallback = (mode == .custom) ? mode.getCustomIconFromFile() : mode.sfSymbol
        let symbol = validFocusSymbolName(resolvedFocusSymbolName ?? symbolFallback, mode: mode)
        let color = resolvedFocusTintColor ?? (mode == .custom ? .indigo : mode.accentColor)
        let fallback = mode.displayName.isEmpty ? "Focus" : mode.displayName
        return .init(symbol: symbol, color: color, fallbackName: fallback)
    }

    private func validFocusSymbolName(_ symbol: String, mode: FocusModeType) -> String {
        let candidate = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty,
           (NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil
            || NSImage(named: NSImage.Name(candidate)) != nil) {
            return candidate
        }
        if NSImage(systemSymbolName: mode.sfSymbol, accessibilityDescription: nil) != nil {
            return mode.sfSymbol
        }
        return "moon.fill"
    }

    private var resolvedFocusSymbolName: String? {
        let raw = focusModeManager.currentFocusSymbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let genericRaw = raw.lowercased()
        if genericRaw == "app.badge" || genericRaw == "app.badge.fill" || genericRaw == "focus" || genericRaw == "none" {
            return nil
        }
        let normalized = raw
            .replacingOccurrences(of: " ", with: ".")
            .replacingOccurrences(of: "_", with: ".")
            .lowercased()
        let candidate = normalized.contains(".") ? normalized : (normalized + ".fill")
        if NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
            return candidate
        }
        if NSImage(named: NSImage.Name(candidate)) != nil {
            return candidate
        }
        return nil
    }

    private var resolvedFocusTintColor: Color? {
        let source = focusModeManager.currentFocusTintName
        if let dynamic = dynamicSystemColor(named: source) {
            return dynamic
        }

        let raw = source
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !raw.isEmpty else { return nil }
        if raw.contains("red") { return .red }
        if raw.contains("orange") { return .orange }
        if raw.contains("yellow") { return .yellow }
        if raw.contains("green") { return .green }
        if raw.contains("mint") { return .mint }
        if raw.contains("teal") { return .teal }
        if raw.contains("cyan") { return .cyan }
        if raw.contains("blue") { return .blue }
        if raw.contains("indigo") { return .indigo }
        if raw.contains("purple") { return .purple }
        if raw.contains("pink") { return .pink }
        if raw.contains("gray") || raw.contains("grey") { return .gray }
        return nil
    }

    private func dynamicSystemColor(named raw: String) -> Color? {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        let selector = NSSelectorFromString(candidate)
        guard NSColor.responds(to: selector),
              let unmanaged = NSColor.perform(selector),
              let nsColor = unmanaged.takeUnretainedValue() as? NSColor else {
            return nil
        }
        return Color(nsColor)
    }

    @ViewBuilder
    private func focusSymbolGlyph(_ name: String, size: CGFloat, tint: Color) -> some View {
        if NSImage(named: NSImage.Name(name)) != nil {
            let customSize = size * 1.08
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: customSize, height: customSize)
        } else {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    private var focusActivityStatusText: String {
        AppLocalizer.localized(
            focusModeManager.latestTransitionIsActive ? "Focus enabled" : "Focus disabled"
        )
    }

    private var focusActivitySymbolName: String { focusActivityStyle.symbol }
    private var focusActivityTint: Color {
        focusModeManager.latestTransitionIsActive ? focusActivityStyle.color : Color.gray.opacity(0.58)
    }

    private var focusActivityLayout: FocusLiveActivity.Layout {
        let fontSize: CGFloat = 12.2
        let leftPadding: CGFloat = 4
        let rightPadding: CGFloat = 4
        let symbolSize = fontSize + 0.8
        let leftWidth: CGFloat = max(16, ceil(symbolSize) + 3)
        let measured = Self.measureSystemWidth(focusActivityStatusText, fontSize: fontSize, weight: .semibold)
        let rightWidth = max(28, ceil(measured) + 10)
        return .init(
            leftPadding: leftPadding,
            rightPadding: rightPadding,
            leftWidth: leftWidth,
            rightWidth: rightWidth,
            fontSize: fontSize
        )
    }

 // MARK: - Timer closed live activity (Quick Timers page)

    private var activeQuickTimers: [QuickTimer] {
        var timers = quickTimerManager.timers
            .filter { $0.remainingSeconds > 0 || $0.didFinish }

        if let mirrored = quickTimerManager.mirroredSystemQuickTimer {
            timers.append(mirrored)
        }

        return timers.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            if lhs.didFinish != rhs.didFinish {
                return lhs.didFinish && !rhs.didFinish
            }
            return lhs.remainingSeconds < rhs.remainingSeconds
        }
    }

    private var shouldShowTimerActivityClosed: Bool {
        guard vm.notchState == .closed else { return false }
        guard closedActivityVisibility > 0.001 else { return false }
        if quickTimerManager.mirroredSystemQuickTimer == nil {
            guard Defaults[.liveActivityTimerEnabled] else { return false }
        }
        guard vm.effectiveClosedNotchHeight > 0 else { return false }
        guard !bluetoothTakeoverExitPending else { return false }
        guard !isBluetoothClosedNotificationShowing else { return false }
        return !activeQuickTimers.isEmpty
    }

    private var hasFinishedQuickTimers: Bool {
        quickTimerManager.timers.contains { $0.didFinish }
    }

    private var timerActivityText: String {
        activeQuickTimers.first?.displayTime ?? "0:00"
    }

    private var timerActivityExtraCount: Int {
        max(0, activeQuickTimers.count - 1)
    }

    private var timerActivityProgressRemaining: Double {
        guard let t = activeQuickTimers.first else { return 0 }
        return max(0, min(1, 1 - t.progress))
    }

    private static func measureMonospacedWidth(_ text: String, fontSize: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func measureSystemWidth(_ text: String, fontSize: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private var timerActivityLayout: TimerLiveActivity.Layout {
        let fontSize: CGFloat = 12.4
        let sidePadding: CGFloat = 3

        let ringSize: CGFloat = fontSize + 5

        let leftWidth = max(16, ceil(ringSize) + 1)

        let extra = timerActivityExtraCount > 0 ? " +\(timerActivityExtraCount)" : ""
        let rightW = Self.measureMonospacedWidth(timerActivityText + extra, fontSize: fontSize, weight: .semibold)
        let rightWidth = ceil(rightW) + 4

        return .init(sidePadding: sidePadding, leftWidth: leftWidth, rightWidth: rightWidth, fontSize: fontSize)
    }

    private var timerExpandedTargetWidth: CGFloat {
        let controlsWidth: CGFloat = 84
        let rowHorizontalPadding: CGFloat = 1 * 2
        let centerGapWidth = timerExpandedCenterGapWidth
        let timeWidth = timerExpandedTimeWidth
        let breathingRoom: CGFloat = 0

        return max(
            vm.closedNotchSize.width,
            ceil(rowHorizontalPadding + controlsWidth + centerGapWidth + timeWidth + breathingRoom)
        )
    }

    private var timerExpandedCenterGapWidth: CGFloat {
        max(0, vm.closedNotchSize.width - 175)
    }

    private var timerExpandedTimeWidth: CGFloat {
        let longestTime = activeQuickTimers.map(\.displayTime).max(by: { $0.count < $1.count }) ?? "00:00"
        let measuredTime = Self.measureMonospacedWidth(longestTime, fontSize: 42, weight: .regular)
        return max(118, ceil(measuredTime) + 1)
    }

    private var timerExpandedRowHeight: CGFloat { 46 }
    private var timerExpandedRowsSpacing: CGFloat { 22 }
    private var timerExpandedTopPadding: CGFloat { 10 }
    private var timerExpandedBottomPadding: CGFloat { timerExpandedRowsSpacing }

    private var timerExpandedFooterHeight: CGFloat {
        let rowsCount = max(1, activeQuickTimers.count)
        return timerExpandedTopPadding
            + CGFloat(rowsCount) * timerExpandedRowHeight
            + CGFloat(max(0, rowsCount - 1)) * timerExpandedRowsSpacing
            + timerExpandedBottomPadding
    }

    private var shouldVibrateExpandedTimerBackground: Bool {
        vm.notchState == .closed
            && shouldShowTimerActivityClosed
            && isTimerPopupHovering
            && hasFinishedQuickTimers
    }

    private var timerExpandedBackgroundOffset: CGSize {
        guard shouldVibrateExpandedTimerBackground else { return .zero }
        return CGSize(width: timerAlarmBackgroundImpulseX, height: 0)
    }

    private func performTimerAlertHapticPulse(strength: CGFloat) {
        guard Defaults[.enableHaptics] else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTimerAlertHapticAt) >= 0.045 else { return }
        lastTimerAlertHapticAt = now

        let performer = NSHapticFeedbackManager.defaultPerformer
        let pattern: NSHapticFeedbackManager.FeedbackPattern = strength >= 0.95 ? .levelChange : .alignment
        performer.perform(pattern, performanceTime: .now)

        if strength >= 1.18 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    @ViewBuilder
    private func timerExpandedButtonsOverlayView() -> some View {
        if shouldShowTimerActivityClosed, isTimerPopupHovering, !activeQuickTimers.isEmpty {
            let rowHeight = timerExpandedRowHeight
            let rowSpacing = timerExpandedRowsSpacing
            let topPadding = timerExpandedTopPadding
            let bottomPadding = timerExpandedBottomPadding
            let horizontalPadding: CGFloat = 6

            VStack(spacing: rowSpacing) {
                ForEach(activeQuickTimers) { timer in
                    let isReadOnly = quickTimerManager.isMirroredSystemTimer(timer)
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                        if isReadOnly {
                            Circle().fill(Color.clear)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                                .allowsHitTesting(false)

                            Circle().fill(Color.clear)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                                .allowsHitTesting(false)
                        } else {
                            Button(action: {
                                keepTimerPopupOpenForFinishedAlert = false
                                withAnimation(NotchMotion.notchLayout) {
                                    quickTimerManager.stopTimer(timer)
                                }
                            }) {
                                Circle().fill(Color.clear)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                keepTimerPopupOpenForFinishedAlert = false
                                quickTimerManager.toggleTimer(timer)
                            }) {
                                Circle().fill(Color.clear)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        }
                        .frame(width: 84, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: rowHeight)
                }
            }
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(width: timerExpandedTargetWidth, height: timerExpandedFooterHeight, alignment: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                isTimerExpandedHovering = hovering
                if hovering {
                    isTimerSidesHovering = true
                    timerPopupCloseTask?.cancel()
                    timerPopupCloseTask = nil
                } else {
                    scheduleTimerPopupCloseIfNeeded(delayMs: 120)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }


    private var closedChinOffsetX: CGFloat {
        if shouldShowTimerActivityClosed && isTimerCompactMode {
            let ext = (timerActivityLayout.sidePadding + timerActivityLayout.leftWidth + 2) * closedActivityVisibility
            return -(ext / 2)
        }
        if shouldShowFileTrayActivityClosed && isFileTrayCompactMode {
            let side = max(0, vm.effectiveClosedNotchHeight - 12)
            let ext = (side + 10) * closedActivityVisibility
            return -(ext / 2)
        }
        if shouldShowMusicActivityClosed && isNowPlayingCompactMode {
            let side = max(0, vm.effectiveClosedNotchHeight - 12)
            let ext = (side + 10) * closedActivityVisibility
            return -(ext / 2)
        }

        if shouldShowFocusActivityClosed {
            let leftExtra = focusActivityLayout.leftPadding + focusActivityLayout.leftWidth
            let rightExtra = focusActivityLayout.rightPadding + focusActivityLayout.rightWidth
            let delta = (rightExtra - leftExtra) / 2
            return delta * closedActivityVisibility
        }

        guard shouldShowTimerActivityClosed else { return 0 }
        if isTimerPopupHovering { return 0 }

        let leftExtra = timerActivityLayout.sidePadding + timerActivityLayout.leftWidth
        let rightExtra = timerActivityLayout.sidePadding + timerActivityLayout.rightWidth
        let delta = (rightExtra - leftExtra) / 2

        return delta * closedActivityVisibility
    }

    private var isInlineHUDFloatingClosed: Bool {
        coordinator.sneakPeek.show
        && Defaults[.inlineHUD]
        && (coordinator.sneakPeek.type != .music)
        && (coordinator.sneakPeek.type != .battery)
        && (coordinator.sneakPeek.type != .bluetooth)
        && vm.notchState == .closed
        && closedActivityVisibility > 0.001
    }

    private var shouldShowLockActivityClosed: Bool {
        vm.notchState == .closed
        && showOnLockScreen
        && liveActivityLockScreen
        && lockScreenState.isLocked
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && vm.effectiveClosedNotchHeight > 0
    }

    @ViewBuilder
    private func closedTimerLiveActivityView() -> some View {
        TimerLiveActivity(
            text: timerActivityText,
            extraCount: timerActivityExtraCount,
            progressRemaining: timerActivityProgressRemaining,
            timers: activeQuickTimers,
            layout: timerActivityLayout,
            notchWidth: vm.closedNotchSize.width,
            baseHeight: vm.effectiveClosedNotchHeight,
            isCompactMode: isTimerCompactMode,
            expandedCenterGapWidth: timerExpandedCenterGapWidth,
            expandedTimeWidth: timerExpandedTimeWidth,
            expandedRowHeight: timerExpandedRowHeight,
            expandedRowsSpacing: timerExpandedRowsSpacing,
            expandedTopPadding: timerExpandedTopPadding,
            expandedBottomPadding: timerExpandedBottomPadding,
            isExpanded: isTimerPopupHovering,
            onSidesHoverChanged: { hovering in
                isTimerSidesHovering = hovering
                if hovering {
                    timerPopupCloseTask?.cancel()
                    timerPopupCloseTask = nil
                }
                timerSidesHoverTask?.cancel()
                timerTransitionTask?.cancel()

                if hovering {
                    guard isTimerPopupHoverArmed else { return }
                    guard Date() >= suppressTimerPopupAutoOpenUntil else { return }
                    isTimerPopupTransitioning = true
                    timerTransitionTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        guard !Task.isCancelled else { return }
                        isTimerPopupTransitioning = false
                    }
                    withAnimation(NotchMotion.popupHover) {
                        isTimerPopupHovering = true
                    }
                } else {
                    isTimerPopupHoverArmed = Date() >= suppressTimerPopupAutoOpenUntil
                    scheduleTimerPopupCloseIfNeeded(delayMs: 150)
                }
            },
            isTimerReadOnly: { timer in
                quickTimerManager.isMirroredSystemTimer(timer)
            },
            onToggleTimer: { timer in
                if quickTimerManager.isMirroredSystemTimer(timer) { return }
                keepTimerPopupOpenForFinishedAlert = false
                quickTimerManager.toggleTimer(timer)
            },
            onStopTimer: { timer in
                if quickTimerManager.isMirroredSystemTimer(timer) { return }
                keepTimerPopupOpenForFinishedAlert = false
                withAnimation(NotchMotion.notchLayout) {
                    quickTimerManager.stopTimer(timer)
                }
            },
            animatedValue: activeQuickTimers.first?.remainingSeconds ?? 0
        )
    }

    private var shouldShowFocusActivityClosed: Bool {
        vm.notchState == .closed
        && Defaults[.focusLiveActivityEnabled]
        && focusModeManager.isFocusToastVisible
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && vm.effectiveClosedNotchHeight > 0
        && !isInlineHUDFloatingClosed
        && !shouldShowLockActivityClosed
        && !isBatteryClosedNotificationShowing
        && !bluetoothTakeoverExitPending
        && !isBluetoothClosedNotificationShowing
    }

    private var fileTrayCount: Int { tvm.items.count }

    private var shouldShowFileTrayActivityClosed: Bool {
        vm.notchState == .closed
        && Defaults[.boringShelf]
        && Defaults[.liveActivityShelfContent]
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && fileTrayCount > 0
        && !coordinator.expandingView.show
        && !bluetoothTakeoverExitPending
        && !isBluetoothClosedNotificationShowing
        && !isInlineHUDFloatingClosed
        && !shouldShowLockActivityClosed
    }

    private var shouldShowMusicActivityClosed: Bool {
        !musicHiddenByExpandingView
        && vm.notchState == .closed
        && (musicManager.isPlaying || !musicManager.isPlayerIdle)
        && coordinator.musicLiveActivityEnabled
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && !bluetoothTakeoverExitPending
        && !isBluetoothClosedNotificationShowing
        && !shouldShowLockActivityClosed
        && !shouldShowFocusActivityClosed
        && !shouldShowFileTrayActivityClosed
    }

    private var hasNowPlayingLiveActivityActive: Bool {
        !musicHiddenByExpandingView
        && (musicManager.isPlaying || !musicManager.isPlayerIdle)
        && coordinator.musicLiveActivityEnabled
        && !vm.hideOnClosed
        && !shouldShowLockActivityClosed
        && !shouldShowFocusActivityClosed
        && !shouldShowFileTrayActivityClosed
    }

    private var shouldKeepNowPlayingEdgeTrackingMounted: Bool {
        vm.notchState == .closed
        && (musicManager.isPlaying || !musicManager.isPlayerIdle)
        && coordinator.musicLiveActivityEnabled
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && !shouldShowLockActivityClosed
        && !shouldShowFocusActivityClosed
        && !shouldShowFileTrayActivityClosed
    }

    private var isMusicSneakPeekVisibleClosed: Bool {
        coordinator.sneakPeek.show
        && coordinator.sneakPeek.type == .music
        && vm.notchState == .closed
        && !vm.hideOnClosed
    }

    private var shouldShowFaceClosed: Bool {
        !coordinator.expandingView.show
        && vm.notchState == .closed
        && (!musicManager.isPlaying && musicManager.isPlayerIdle)
        && Defaults[.showNotHumanFace]
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && !bluetoothTakeoverExitPending
        && !isBluetoothClosedNotificationShowing
        && !shouldShowLockActivityClosed
        && !shouldShowFocusActivityClosed
        && !shouldShowFileTrayActivityClosed
        && !shouldShowTimerActivityClosed
        && !shouldShowMusicActivityClosed
    }

    private var shouldUseClosedActivityTopRadius: Bool {
        vm.notchState == .closed
        && vm.effectiveClosedNotchHeight > 0
        && closedActivityVisibility > 0.001
        && (isBatteryClosedNotificationShowing
            || isBluetoothClosedNotificationShowing
            || bluetoothTakeoverExitPending
            || shouldShowLockActivityClosed
            || shouldShowFocusActivityClosed
            || isInlineHUDFloatingClosed
            || shouldShowFileTrayActivityClosed
            || shouldShowTimerActivityClosed
            || shouldShowMusicActivityClosed)
    }

    private var hasClosedLiveActivityForRecordingPolicy: Bool {
        let batteryActive = coordinator.expandingView.type == .battery && coordinator.expandingView.show
        let bluetoothActive = coordinator.expandingView.type == .bluetooth && coordinator.expandingView.show
        let lockActive = lockScreenState.isLocked || shouldShowLockActivityClosed
        let focusActive = Defaults[.focusLiveActivityEnabled] && focusModeManager.isFocusToastVisible
        let fileTrayActive = Defaults[.boringShelf] && Defaults[.liveActivityShelfContent] && fileTrayCount > 0
        let timerActive = Defaults[.liveActivityTimerEnabled] && !activeQuickTimers.isEmpty
        let musicActive = coordinator.musicLiveActivityEnabled && (musicManager.isPlaying || !musicManager.isPlayerIdle)

        return batteryActive || bluetoothActive || lockActive || focusActive || fileTrayActive || timerActive || musicActive
    }

    private func applyScreenRecordingVisibilityPolicy() {
        guard let window = hostWindow else { return }
        let isClosed = (vm.notchState == .closed)
        let isInUse = hasClosedLiveActivityForRecordingPolicy

        if let notchWindow = window as? QuartzNotchSkyLightWindow {
            notchWindow.updateScreenRecordingContext(isClosed: isClosed, isInUse: isInUse)
            return
        }

        let shouldHide: Bool
        switch hideFromScreenRecordingMode {
        case .disabled:
            shouldHide = false
        case .fullyHidden:
            shouldHide = true
        case .onlyWhenClosed:
            shouldHide = isClosed
        case .onlyWhenNotInUse:
            shouldHide = isClosed && !isInUse
        }
        let targetSharingType: NSWindow.SharingType = shouldHide ? .none : .readWrite
        if window.sharingType != targetSharingType {
            window.sharingType = targetSharingType
        }
    }

    private func applyDynamicWindowFrame() {
        guard let window = hostWindow, let screen = window.screen else { return }

        let targetSize = dynamicWindowSizeComputed
        let screenFrame = screen.frame
        let targetFrame = NSRect(
            x: screenFrame.midX - targetSize.width / 2,
            y: screenFrame.maxY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        guard abs(window.frame.width - targetFrame.width) > 0.5
            || abs(window.frame.height - targetFrame.height) > 0.5
            || abs(window.frame.minX - targetFrame.minX) > 0.5
            || abs(window.frame.minY - targetFrame.minY) > 0.5
        else { return }

        window.setFrame(targetFrame, display: true)
    }

    private func updateTimerWindowReservation(allowShrink: Bool = false) {
        timerWindowReservationReleaseTask?.cancel()
        timerWindowReservationReleaseTask = nil

        guard !activeQuickTimers.isEmpty else {
            timerReservedFooterHeight = 0
            timerReservedTargetWidth = 0
            applyDynamicWindowFrame()
            return
        }

        if allowShrink {
            timerReservedFooterHeight = timerExpandedFooterHeight
            timerReservedTargetWidth = timerExpandedTargetWidth
        } else {
            timerReservedFooterHeight = max(timerReservedFooterHeight, timerExpandedFooterHeight)
            timerReservedTargetWidth = max(timerReservedTargetWidth, timerExpandedTargetWidth)
        }

        applyDynamicWindowFrame()
    }

    private func scheduleTimerWindowReservationShrink() {
        timerWindowReservationReleaseTask?.cancel()
        timerWindowReservationReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            updateTimerWindowReservation(allowShrink: true)
        }
    }

    private var shouldShowMusicActivityAsSecondaryClosed: Bool {
        (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
        && vm.notchState == .closed
        && (musicManager.isPlaying || !musicManager.isPlayerIdle)
        && coordinator.musicLiveActivityEnabled
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && !shouldShowLockActivityClosed
        && !isInlineHUDFloatingClosed
    }

    private var closedPrimaryActivityKind: ClosedActivityKind? {
        if isBluetoothClosedNotificationShowing { return .bluetooth }
        if shouldShowFocusActivityClosed { return .focus }
        if shouldShowTimerActivityClosed { return .timer }
        if shouldShowFileTrayActivityClosed { return .fileTray }
        if shouldShowMusicActivityClosed { return .music }
        return nil
    }

    private var bluetoothTakeoverSourceKind: BluetoothTakeoverExitKind? {
        guard vm.notchState == .closed else { return nil }
        guard closedActivityVisibility > 0.001 else { return nil }
        guard !vm.hideOnClosed else { return nil }
        guard !shouldShowLockActivityClosed else { return nil }
        guard !isInlineHUDFloatingClosed else { return nil }

        if Defaults[.focusLiveActivityEnabled],
           focusModeManager.isFocusToastVisible,
           vm.effectiveClosedNotchHeight > 0 {
            return .focus
        }

        if (quickTimerManager.mirroredSystemQuickTimer != nil || Defaults[.liveActivityTimerEnabled]),
           vm.effectiveClosedNotchHeight > 0,
           !activeQuickTimers.isEmpty {
            return .timer
        }

        if Defaults[.boringShelf],
           Defaults[.liveActivityShelfContent],
           fileTrayCount > 0 {
            return .fileTray
        }

        if (musicManager.isPlaying || !musicManager.isPlayerIdle),
           coordinator.musicLiveActivityEnabled,
           !shouldShowFocusActivityClosed,
           !shouldShowFileTrayActivityClosed {
            return .music
        }

        return nil
    }

    private var isClosedPrimaryActivityExpanded: Bool {
        guard vm.notchState == .closed, let primary = closedPrimaryActivityKind else { return false }

        switch primary {
        case .timer:
            return isTimerPopupHovering || isTimerPopupTransitioning || isTimerExpandedHovering
        case .bluetooth:
            return isBluetoothPopupHovering || isBluetoothPopupTransitioning
        case .focus, .fileTray, .music:
            return false
        }
    }

    private var closedSecondaryCompactActivityKind: ClosedActivityKind? {
        guard let primary = closedPrimaryActivityKind else { return nil }

        switch primary {
        case .bluetooth:
            return nil
        case .focus:
            if shouldShowTimerActivityClosed { return .timer }
            if shouldShowFileTrayActivityClosed { return .fileTray }
            if shouldShowMusicActivityAsSecondaryClosed { return .music }
            return nil
        case .timer:
            if shouldShowFileTrayActivityClosed { return .fileTray }
            if shouldShowMusicActivityAsSecondaryClosed { return .music }
            return nil
        case .fileTray:
            if shouldShowMusicActivityAsSecondaryClosed { return .music }
            return nil
        case .music:
            return nil
        }
    }

    private var shouldRenderClosedSecondaryDetachedActivity: Bool {
        vm.notchState == .closed
        && !isClosedPrimaryActivityExpanded
        && closedSecondaryCompactActivityKind != nil
    }

    private var closedSecondaryCompactWidth: CGFloat {
        guard shouldRenderClosedSecondaryDetachedActivity else { return 0 }
        return max(0, vm.closedNotchSize.height - 12)
    }

    private var closedDetachedCompactSpacing: CGFloat {
        guard shouldRenderClosedSecondaryDetachedActivity else { return 0 }
        return 0
    }

    private var closedDetachedCompactBubbleWidth: CGFloat {
        guard shouldRenderClosedSecondaryDetachedActivity else { return 0 }
        return closedSecondaryCompactWidth + 34
    }

    private var closedDetachedLeadGap: CGFloat {
        guard closedSecondaryCompactActivityKind != nil else { return 0 }
        let safeClearance: CGFloat = 6
        return max(0, safeClearance + closedDetachedCompactSpacing)
    }

    private var closedDetachedCompactCenterOffsetX: CGFloat {
        let safeClearance: CGFloat = 6
        return closedPrimaryRightEdgeX
            + safeClearance
            + closedDetachedCompactSpacing
            + (closedDetachedCompactBubbleWidth / 2)
    }

    private var closedPrimaryRightExtra: CGFloat? {
        guard let primary = closedPrimaryActivityKind else { return nil }

        let side = max(0, vm.effectiveClosedNotchHeight - 12)

        switch primary {
        case .bluetooth:
            let hoverExtra: CGFloat = isBluetoothPopupHovering ? (110 / 2) : 0
            return side + 10 + hoverExtra
        case .focus:
            return focusActivityLayout.rightPadding + focusActivityLayout.rightWidth
        case .timer:
            if isTimerCompactMode { return nil }
            return timerActivityLayout.sidePadding + timerActivityLayout.rightWidth
        case .fileTray:
            if isFileTrayCompactMode { return nil }
            return max(0, side - (cornerRadiusInsets.closed.top / 2))
        case .music:
            if isNowPlayingCompactMode { return nil }
            return side + 10
        }
    }

    private var closedPrimaryRightEdgeX: CGFloat {
        if let rightExtra = closedPrimaryRightExtra {
            return (vm.closedNotchSize.width / 2) + (rightExtra * closedActivityVisibility)
        }

        return closedChinOffsetX + (displayedChinWidthComputed / 2)
    }

    private var closedDetachedCompactLeftEdgeX: CGFloat {
        closedDetachedCompactCenterOffsetX - (closedDetachedCompactBubbleWidth / 2)
    }

    private var closedDetachedGapWidth: CGFloat {
        max(0, closedDetachedCompactLeftEdgeX - closedPrimaryRightEdgeX)
    }

    private var closedDetachedBridgeWidth: CGFloat {
        guard closedDetachedLeadGap > 0 else { return 0 }
        return min(20, max(12, closedDetachedLeadGap * 0.42))
    }

    private var closedDetachedBridgeHeight: CGFloat {
        max(6.4, min(vm.effectiveClosedNotchHeight * 0.25, closedDetachedBridgeWidth * 0.72))
    }

    private var closedDetachedBridgeLineWidth: CGFloat {
        max(2.4, min(vm.effectiveClosedNotchHeight * 0.09, closedDetachedBridgeWidth * 0.28))
    }

    private var closedDetachedBridgeCenterOffsetX: CGFloat {
        closedPrimaryRightEdgeX + (closedDetachedLeadGap / 2) + 6.5
    }

    private var closedDetachedBridgeOffsetY: CGFloat {
        -5
    }

    private var secondaryDetachedSlideProgress: CGFloat {
        isClosedPrimaryActivityExpanded ? 0 : 1
    }

    private var secondaryDetachedBubbleSlideX: CGFloat {
        let hiddenDistance = closedDetachedCompactBubbleWidth + closedDetachedLeadGap + 12
        return (1 - secondaryDetachedSlideProgress) * hiddenDistance
    }

    private var secondaryDetachedBridgeSlideX: CGFloat {
        let hiddenDistance = max(12, closedDetachedCompactBubbleWidth * 0.44)
        return (1 - secondaryDetachedSlideProgress) * hiddenDistance
    }

    private var detachedCompactTopRadius: CGFloat {
        cornerRadiusInsets.closed.top
    }

    private var detachedCompactBottomRadius: CGFloat {
        cornerRadiusInsets.closed.bottom
    }

    private var closedSecondaryDetachedTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SecondaryDetachedSlideModifier(x: -64, scale: 0.90),
                identity: SecondaryDetachedSlideModifier(x: 0, scale: 1.0)
            ),
            removal: .modifier(
                active: SecondaryDetachedSlideModifier(x: -82, scale: 0.86),
                identity: SecondaryDetachedSlideModifier(x: 0, scale: 1.0)
            )
        )
    }

    private var secondaryDetachedContentOpacity: CGFloat {
        let slideP = max(0, min(1, secondaryDetachedSlideProgress))
        return pow(slideP, 1.35)
    }

    private var topCornerRadius: CGFloat {
        if vm.notchState == .open {
            return 0
        }

        if isBluetoothClosedNotificationShowing && isBluetoothPopupHovering {
            return 10
        }

        if shouldShowTimerActivityClosed && isTimerPopupHovering {
            return 10
        }

        if shouldUseClosedActivityTopRadius { return closedActivityTopCornerRadius }
        return cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        if (vm.notchState == .open) && Defaults[.cornerRadiusScaling] {
            return cornerRadiusInsets.opened.bottom
        }

        if isBluetoothClosedNotificationShowing && isBluetoothPopupHovering {
            return 18
        }

        if shouldShowTimerActivityClosed && isTimerPopupHovering {
            return 18
        }

        if isMusicSneakPeekVisibleClosed {
            return cornerRadiusInsets.closed.bottom + 2
        }

        return cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            useExactBounds: vm.notchState == .open
        )
    }

    private var computedPrimaryChinWidthRaw: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if isBatteryClosedNotificationShowing {
            chinWidth = vm.closedNotchSize.width + 2 * (batteryClosedSideWidth + batteryClosedSidePadding)
        } else if shouldShowLockActivityClosed {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if isBluetoothClosedNotificationShowing {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)

            if isBluetoothPopupHovering {
                chinWidth += 110
            }
        } else if shouldShowFocusActivityClosed {
            chinWidth = vm.closedNotchSize.width
                + focusActivityLayout.leftPadding
                + focusActivityLayout.rightPadding
                + focusActivityLayout.leftWidth
                + focusActivityLayout.rightWidth
        } else if shouldShowTimerActivityClosed {
            if isTimerCompactMode {
                chinWidth = vm.closedNotchSize.width
                    + timerActivityLayout.sidePadding
                    + timerActivityLayout.leftWidth
                    + 2
            } else {
                chinWidth = vm.closedNotchSize.width
                    + 2 * timerActivityLayout.sidePadding
                    + timerActivityLayout.leftWidth
                    + timerActivityLayout.rightWidth
            }
            if isTimerPopupHovering {
                chinWidth = max(chinWidth, timerExpandedTargetWidth)
            }

        } else if shouldShowFileTrayActivityClosed {
            if isFileTrayCompactMode {
                chinWidth += (max(0, vm.effectiveClosedNotchHeight - 12) + 10)
            } else {
                chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
            }
        }
          else if shouldShowMusicActivityClosed {
            if isNowPlayingCompactMode {
                chinWidth += (max(0, vm.effectiveClosedNotchHeight - 12) + 10)
            } else {
                chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
            }
        } else if shouldShowFaceClosed {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    private func closedActivityWidth(for kind: BluetoothTakeoverExitKind) -> CGFloat {
        switch kind {
        case .focus:
            return vm.closedNotchSize.width
                + focusActivityLayout.leftPadding
                + focusActivityLayout.rightPadding
                + focusActivityLayout.leftWidth
                + focusActivityLayout.rightWidth
        case .timer:
            let baseWidth: CGFloat
            if isTimerCompactMode {
                baseWidth = vm.closedNotchSize.width
                    + timerActivityLayout.sidePadding
                    + timerActivityLayout.leftWidth
                    + 2
            } else {
                baseWidth = vm.closedNotchSize.width
                    + 2 * timerActivityLayout.sidePadding
                    + timerActivityLayout.leftWidth
                    + timerActivityLayout.rightWidth
            }
            if isTimerPopupHovering {
                return max(baseWidth, timerExpandedTargetWidth)
            }
            return baseWidth
        case .fileTray:
            if isFileTrayCompactMode {
                return vm.closedNotchSize.width + (max(0, vm.effectiveClosedNotchHeight - 12) + 10)
            }
            return vm.closedNotchSize.width + (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        case .music:
            if isNowPlayingCompactMode {
                return vm.closedNotchSize.width + (max(0, vm.effectiveClosedNotchHeight - 12) + 10)
            }
            return vm.closedNotchSize.width + (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }
    }

    private var bluetoothClosedActivityWidth: CGFloat {
        var chinWidth = vm.closedNotchSize.width + (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        if isBluetoothPopupHovering {
            chinWidth += 110
        }
        return chinWidth
    }

    private var computedChinWidthRaw: CGFloat {
        return computedPrimaryChinWidthRaw
    }

    private var computedChinWidth: CGFloat {
        let base = vm.closedNotchSize.width
        return base + (computedChinWidthRaw - base) * closedActivityVisibility
    }

    private var closedActivityVisibility: CGFloat {
        if !lockTransition.suppressClosedActivities {
            return 1
        }
        return 1 - min(max(lockSuppressionProgress, 0), 1)
    }

 // MARK: - Compile-time simplification (fix “unable to type-check…”)

    private var isCameraVisibleComputed: Bool {
        guard vm.notchState == .open else { return false }
        return showMirror && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var isCalendarVisibleComputed: Bool {
        guard vm.notchState == .open else { return false }
        return showCalendar
    }

    private var isLayoutExpandedComputed: Bool {
        isCameraVisibleComputed || isCalendarVisibleComputed
    }

    private var openWidthValueComputed: CGFloat {
        guard vm.notchState == .open else { return vm.closedNotchSize.width }
        return targetOpenWidthValueComputed
    }

    private var targetOpenWidthValueComputed: CGFloat {
        let base: CGFloat = 420

        let extraCameraWidth: CGFloat = isCameraVisibleComputed ? 160 : 0
        let extraCalendarWidth: CGFloat = {
            if isSwitchingOverlay && overlaySwitchDirection == .toCamera { return 0 }
            return isCalendarVisibleComputed ? 230 : 0
        }()
        let overlaySwitchWidthHold: CGFloat =
            (isSwitchingOverlay && overlaySwitchDirection == .toCalendar) ? 230 : 0
        let legacyOpenTopRadius = Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
        let exactBoundsWidthCompensation: CGFloat = 2 * legacyOpenTopRadius

        return max(
            vm.closedNotchSize.width,
            base + max(extraCameraWidth, extraCalendarWidth, overlayWidthHold, overlaySwitchWidthHold) - exactBoundsWidthCompensation
        )
    }

    private var openHeightValueComputed: CGFloat? {
        guard vm.notchState == .open else { return nil }
        return targetOpenHeightValueComputed
    }

    private var targetOpenHeightValueComputed: CGFloat {
        max(vm.notchSize.height, overlayHeightHold)
    }

    private var dynamicWindowSizeComputed: CGSize {
        let baseSize = getWindowSize(screenUUID: vm.screenUUID)
        guard shouldReserveWindowSpaceForTimerPopup else { return baseSize }

        return CGSize(
            width: max(baseSize.width, reservedTimerExpandedTargetWidth + openNotchHorizontalOverhang * 2),
            height: max(baseSize.height, timerExpandedWindowHeight)
        )
    }

    private var shouldReserveWindowSpaceForTimerPopup: Bool {
        !activeQuickTimers.isEmpty
    }

    private var timerExpandedWindowHeight: CGFloat {
        vm.effectiveClosedNotchHeight
            + reservedTimerExpandedFooterHeight
            + shadowPadding
            + 12
    }

    private var reservedTimerExpandedFooterHeight: CGFloat {
        max(timerReservedFooterHeight, timerExpandedFooterHeight)
    }

    private var reservedTimerExpandedTargetWidth: CGFloat {
        max(timerReservedTargetWidth, timerExpandedTargetWidth)
    }

    private var openContentVerticalLiftComputed: CGFloat {
        guard vm.notchState == .open else { return 0 }
        return getOpenContentVerticalLift(screenUUID: vm.screenUUID)
    }

    private var openContentLayoutScaleComputed: CGFloat {
        guard vm.notchState == .open else { return 1 }
        return getOpenContentLayoutScale(screenUUID: vm.screenUUID)
    }

    private var openLayoutCompressionComputed: CGFloat {
        guard vm.notchState == .open else { return 0 }
        return getOpenLayoutCompression(screenUUID: vm.screenUUID)
    }

    private var openBaseContentWidthComputed: CGFloat {
        guard vm.notchState == .open else { return 0 }
        let base: CGFloat = 420
        let legacyOpenTopRadius = Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
        let exactBoundsWidthCompensation: CGFloat = 2 * legacyOpenTopRadius
        return max(vm.closedNotchSize.width, base - exactBoundsWidthCompensation)
    }

    private var openContentViewportHeightComputed: CGFloat {
        guard vm.notchState == .open else { return 0 }
        return getOpenContentViewportHeight()
    }

    private var openHeaderReferenceHeightComputed: CGFloat {
        guard vm.notchState == .open else { return vm.effectiveClosedNotchHeight }
        return max(24, getOpenHeaderLayoutSpacerHeight())
    }

    private var openHeaderSpacerHeightComputed: CGFloat {
        guard vm.notchState == .open else { return vm.effectiveClosedNotchHeight }
        return max(24, getOpenHeaderLayoutSpacerHeight())
    }

    private var manualOpenAutoCloseSuppressed: Bool {
        Date() < vm.manualOpenUntil
    }

    private var openNotchHUDIsShowing: Bool {
        guard vm.notchState == .open else { return false }
        guard Defaults[.showOpenNotchHUD] else { return false }
        guard coordinator.sneakPeek.show else { return false }

        switch coordinator.sneakPeek.type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }

    private var shouldUseOrganicBatteryWidthComputed: Bool {
        guard vm.notchState == .closed else { return false }
        guard !lockTransition.suppressClosedActivities else { return false }
        guard Defaults[.showPowerStatusNotifications] else { return false }
        guard coordinator.expandingView.type == .battery else { return false }
        return true
    }

    private var displayedChinWidthComputed: CGFloat {
        guard shouldUseOrganicBatteryWidthComputed else { return computedChinWidth }
        let mode: OrganicBatteryEasing.Mode = (batteryChinTo >= batteryChinFrom) ? .appear : .disappear
        let p = OrganicBatteryEasing.map(batteryChinPhase, mode: mode)
        return batteryChinFrom + (batteryChinTo - batteryChinFrom) * p
    }

    @ViewBuilder
    private func liquidV11Layer(cornerRadius: CGFloat, tintOpacity: Double, perfMode: Bool) -> some View {
        let effectiveTintOpacity = liquidGlassCompatibilityFallbackActive ? (tintOpacity * 0.55) : tintOpacity
        NotchLiquidGlassBackground(
            variant: 11,
            cornerRadius: cornerRadius,
            trigger: 0,
            forceFallback: forceLiquidGlassCompatibilityFallback
        ) {
            Color.white.opacity(effectiveTintOpacity)
        }
        .id(forceLiquidGlassCompatibilityFallback ? "compat" : "native")
    }

    @ViewBuilder
    private func liquidCornerShadowLayer() -> some View {
        let topCornerSpan = max(30, topCornerRadius * 3.1)
        let bottomCornerSpan = max(42, bottomCornerRadius * 2.45)
        let edgeBand = max(12, topCornerRadius * 0.78)

        ZStack {
            currentNotchShape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.020), location: 0.00),
                            .init(color: Color.black.opacity(0.042), location: 0.52),
                            .init(color: Color.black.opacity(0.075), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(
                        lineWidth: 4.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .blur(radius: 3.15)
                .blendMode(.multiply)
                .opacity(0.74)
                .mask {
                    liquidEdgeCornerMask(
                        topCornerSpan: topCornerSpan,
                        bottomCornerSpan: bottomCornerSpan,
                        edgeBand: edgeBand
                    )
                }
                .mask(liquidStrokeMask())
                .allowsHitTesting(false)
        }
        .compositingGroup()
        .clipShape(currentNotchShape)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func liquidBlackVeilLayer(isLiquidTransitioningNow: Bool, liquidVeilOpacity: CGFloat) -> some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let barHeight = max(2, topCornerRadius + 15)
            let topOpaqueHeight = min(h, max(0, openHeaderReferenceHeightComputed))
            let topOpaqueRatio = min(0.94, max(0.0, topOpaqueHeight / h))
            let seam = min(0.94, max(topOpaqueRatio - 0.01, (barHeight - 5) / h))
            let fade1 = min(1.0, seam + 0.02)
            let fade2 = min(1.0, seam + 0.07)
            let fade3 = min(1.0, seam + 0.17)
            let fade4 = min(1.0, seam + 0.36)
            let fade5 = min(1.0, seam + 0.58)
            let fade6 = min(1.0, seam + 0.78)
            let fade7 = min(1.0, seam + 0.84)
            let fade8 = min(1.0, seam + 0.92)
            let tail = min(1.0, seam + 0.97)
            let lowerVeilScale: CGFloat = liquidGlassCompatibilityFallbackActive ? 0.68 : 1.0

            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(1.00), location: 0.00),
                        .init(color: Color.black.opacity(1.00), location: seam),
                        .init(color: Color.black.opacity(0.98), location: fade1),
                        .init(color: Color.black.opacity(0.94), location: fade2),
                        .init(color: Color.black.opacity(0.86), location: fade3),
                        .init(color: Color.black.opacity(0.72), location: fade4),
                        .init(color: Color.black.opacity(0.54 * lowerVeilScale), location: fade5),
                        .init(color: Color.black.opacity(0.36 * lowerVeilScale), location: fade6),
                        .init(color: Color.black.opacity(0.025 * lowerVeilScale), location: fade7),
                        .init(color: .clear, location: fade8),
                        .init(color: .clear, location: tail),
                        .init(color: .clear, location: 1.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.horizontal, -28)
                .blur(
                    radius: isLiquidTransitioningNow
                        ? (liquidGlassCompatibilityFallbackActive ? 5.4 : 4.6)
                        : (liquidGlassCompatibilityFallbackActive ? 9.6 : 8.2)
                )

                Rectangle()
                    .fill(Color.black)
                    .frame(height: topOpaqueHeight)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.86),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: liquidGlassCompatibilityFallbackActive ? 1.35 : 0)
            }
        }
        .clipShape(currentNotchShape)
        .opacity(liquidVeilOpacity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func macOS27BottomClearMask(sideLiftProgress: CGFloat) -> some View {
        LiquidBottomArcMask(sideLiftProgress: sideLiftProgress)
    }

    @ViewBuilder
    private func macOS27InnerShadowLayer(opacity: CGFloat) -> some View {
        ZStack {
            currentNotchShape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.18), location: 0.00),
                            .init(color: Color.black.opacity(0.075), location: 0.48),
                            .init(color: Color.black.opacity(0.14), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 14.0, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 10.5)
                .blendMode(.multiply)

            currentNotchShape
                .strokeBorder(
                    Color.black.opacity(0.055),
                    style: StrokeStyle(lineWidth: 20.0, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 17.0)
                .blendMode(.multiply)

            currentNotchShape
                .strokeBorder(
                    Color.white.opacity(0.020),
                    style: StrokeStyle(lineWidth: 0.45, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.7)
                .blendMode(.screen)

            currentNotchShape
                .strokeBorder(
                    Color.white.opacity(0.92),
                    style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.55)
                .blendMode(.screen)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.78),
                            .init(color: .black.opacity(0.45), location: 0.90),
                            .init(color: .black, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .black, location: 0.13),
                                .init(color: .black, location: 0.87),
                                .init(color: .clear, location: 1.00),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
        }
        .mask(currentNotchShape)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func macOS27OuterStrokeLayer(opacity: CGFloat) -> some View {
        ZStack {
            currentNotchShape
                .strokeBorder(
                    Color.black.opacity(0.44),
                    style: StrokeStyle(lineWidth: 0.72, lineCap: .round, lineJoin: .round)
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.00),
                            .init(color: .black, location: 0.74),
                            .init(color: .clear, location: 0.96),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            currentNotchShape
                .strokeBorder(
                    Color.black.opacity(0.31),
                    style: StrokeStyle(lineWidth: 0.52, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.45)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.76),
                            .init(color: .black, location: 0.94),
                            .init(color: .black, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func liquidCloseDarkenOpacity(for currentHeight: CGFloat) -> CGFloat {
        guard keepLiquidVisualDuringClose, vm.notchState == .closed else { return 0 }

        let closedHeight = max(1, vm.effectiveClosedNotchHeight)
        let startHeight = closedHeight + max(58, closedHeight * 1.9)
        let endHeight = closedHeight + 10
        let rawProgress = 1 - ((currentHeight - endHeight) / max(1, startHeight - endHeight))
        let progress = min(max(rawProgress, 0), 1)
        return progress * progress * (3 - 2 * progress)
    }

    private func liquidBottomArcRevealProgress(for currentHeight: CGFloat) -> CGFloat {
        let closedHeight = max(1, vm.effectiveClosedNotchHeight)
        let startHeight = closedHeight + 18
        let endHeight = closedHeight + 92
        let rawProgress = (currentHeight - startHeight) / max(1, endHeight - startHeight)
        let progress = min(max(rawProgress, 0), 1)
        return progress * progress * (3 - 2 * progress)
    }

    @ViewBuilder
    private func liquidEdgeCornerMask(topCornerSpan: CGFloat, bottomCornerSpan: CGFloat, edgeBand: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .frame(height: edgeBand)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle()
                .frame(height: edgeBand + 1.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            Rectangle()
                .frame(width: edgeBand)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .frame(width: edgeBand)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            HStack(spacing: 0) {
                Rectangle().frame(width: topCornerSpan, height: topCornerSpan)
                Spacer(minLength: 0)
                Rectangle().frame(width: topCornerSpan, height: topCornerSpan)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 0) {
                Rectangle().frame(width: bottomCornerSpan, height: bottomCornerSpan)
                Spacer(minLength: 0)
                Rectangle().frame(width: bottomCornerSpan, height: bottomCornerSpan)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .mask(currentNotchShape)
    }

    @ViewBuilder
    private func liquidSpecularReflections() -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let longStroke = max(98, min(w, h) * 0.94)
            let shortStroke = longStroke * 0.74
            let thickness = max(2.2, topCornerRadius * 0.14)

            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: Color.white.opacity(0.92), location: 0.52),
                                .init(color: .clear, location: 1.00),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: longStroke, height: thickness)
                    .rotationEffect(.degrees(45))
                    .offset(x: -w * 0.26, y: -h * 0.28)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: Color.white.opacity(0.78), location: 0.50),
                                .init(color: .clear, location: 1.00),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: shortStroke, height: max(1.7, thickness * 0.82))
                    .rotationEffect(.degrees(-45))
                    .offset(x: w * 0.26, y: -h * 0.28)
            }
            .blur(radius: 0.82)
            .blendMode(.screen)
            .opacity(0.98)
            .frame(width: w, height: h)
            .mask(currentNotchShape)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.00),
                        .init(color: .black, location: 0.34),
                        .init(color: .clear, location: 0.86),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func liquidStrokeMask() -> some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let extraTopExclusion: CGFloat = liquidGlassCompatibilityFallbackActive ? 10 : 4
            let topCut = min(0.78, max(0.20, (openHeaderReferenceHeightComputed + 14 + extraTopExclusion) / h))
            let fadeStart = max(0.0, topCut - (liquidGlassCompatibilityFallbackActive ? 0.18 : 0.22))
            let fadeMid1 = min(1.0, fadeStart + 0.08)
            let fadeMid2 = min(1.0, fadeStart + 0.15)
            let fadeMid3 = min(1.0, fadeStart + 0.22)
            let fadeEnd = min(1.0, topCut + (liquidGlassCompatibilityFallbackActive ? 0.10 : 0.14))
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: fadeStart),
                    .init(color: .black.opacity(0.18), location: fadeMid1),
                    .init(color: .black.opacity(0.40), location: fadeMid2),
                    .init(color: .black.opacity(0.72), location: fadeMid3),
                    .init(color: .black, location: fadeEnd),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func openShoulderExtension(
        side: OpenShoulderShape.Side,
        progress: CGFloat,
        freezeRevealForLiquidOpen: Bool
    ) -> some View {
        let arcRadius: CGFloat = 29
        let shoulderHeight: CGFloat = 30
        let shoulderWidthPx = arcRadius.rounded(.toNearestOrAwayFromZero)
        let shoulderHeightPx = shoulderHeight.rounded(.toNearestOrAwayFromZero)
        let leftJoinOverlap: CGFloat = 2.0
        let rightJoinOverlap: CGFloat = 1.0
        let leftXOffsetFineTune: CGFloat = -1.0
        let leftInwardCompensation: CGFloat = 0.0
        let rightInwardCompensation: CGFloat = 0.0
        let shoulderOutwardOffset: CGFloat = -0.5
        let shoulderTopAlignOffset: CGFloat = -0.5
        let progressClamped = max(0.001, min(1, progress))
        let revealScale = freezeRevealForLiquidOpen ? 1.0 : progressClamped
        let innerJoinOverlapPx: CGFloat = 1.0
        let fillScaleX = 1.0 + (innerJoinOverlapPx / max(1, shoulderWidthPx))

        let leftOffsetX = leftJoinOverlap - shoulderWidthPx + leftXOffsetFineTune + leftInwardCompensation - shoulderOutwardOffset
        let rightOffsetX = shoulderWidthPx - rightJoinOverlap - rightInwardCompensation + shoulderOutwardOffset
        let offsetX = (side == .left) ? leftOffsetX : rightOffsetX

        let strokeSide: OpenShoulderOuterStroke.Side = (side == .left) ? .left : .right
        let shoulderLayer = ZStack {
            OpenShoulderShape(side: side)
                .fill(Color.black)
                .scaleEffect(
                    x: fillScaleX,
                    y: 1,
                    anchor: side == .left ? .leading : .trailing
                )

            OpenShoulderOuterStroke(side: strokeSide)
                .stroke(
                    Color.black,
                    style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter)
                )
        }
        .frame(width: shoulderWidthPx, height: shoulderHeightPx)

        shoulderLayer
            .scaleEffect(
                x: revealScale,
                y: revealScale,
                anchor: side == .left ? .topTrailing : .topLeading
            )
        .offset(
            x: offsetX,
            y: shoulderTopAlignOffset.rounded(.toNearestOrAwayFromZero)
        )
        .allowsHitTesting(false)
    }

    var body: some View {
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()

        let notchStateAnimation: Animation = {
            if vm.notchState == .open {
                if pageUseLiquidGlassBackground {
                    return .smooth(duration: 0.30)
                }
                return NotchMotion.notchOpen
            }
            return NotchMotion.notchClose
        }()
        let notchLayoutAnimation: Animation = NotchMotion.notchLayout
        let openShoulderProgress: CGFloat = (vm.notchState == .open) ? 1 : 0
        let useLiquidPageBackground = pageUseLiquidGlassBackground
            && (vm.notchState == .open || keepLiquidVisualDuringClose)
        let resolvedLiquidBlend = min(max(liquidVisualBlend, 0), 1)
        let liquidGlassBlend: CGFloat = min(max((resolvedLiquidBlend - 0.08) / 0.92, 0), 1)
        let liquidVeilBlendRaw: CGFloat = min(max((resolvedLiquidBlend - 0.26) / 0.74, 0), 1)
        let liquidVeilBlend: CGFloat = liquidVeilBlendRaw * liquidVeilBlendRaw
        let liquidChromeOpacity: CGFloat = liquidGlassBlend * min(max(liquidStrokeReveal, 0), 1)
        let liquidVeilOpacity: CGFloat = {
            let isLiquidOpeningOrClosing = useLiquidPageBackground && (vm.notchState == .open || keepLiquidVisualDuringClose)
            let base = isLiquidOpeningOrClosing ? 1 : liquidVeilBlend
            return liquidGlassCompatibilityFallbackActive ? (base * 0.94) : base
        }()
        let notchTopLineColor: Color = useLiquidPageBackground ? .clear : .black
        let isLiquidTransitioningNow: Bool = useLiquidPageBackground && liquidTransitionPerfMode
        let headerRevealProgress: CGFloat = {
            guard vm.notchState == .open else { return 0 }
            let t = min(max((openContentRevealProgress - 0.52) / 0.34, 0), 1)
            return t * t * (3 - 2 * t)
        }()
        let headerWidthProgress: CGFloat = {
            guard vm.notchState == .open else { return 0 }
            let t = min(max((openHeaderWidthProgress - 0.40) / 0.46, 0), 1)
            return t * t * (3 - 2 * t)
        }()
        let headerYOffset: CGFloat = {
            guard vm.notchState == .open else { return -34 }
            return -30 + (18 * headerRevealProgress)
        }()
        let headerScaleX: CGFloat = 0.42 + (0.58 * headerWidthProgress)

        let baseView = ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let timerBackgroundShakeX = timerExpandedBackgroundOffset.width
                let timerBackgroundShakeY = timerExpandedBackgroundOffset.height
                let openInnerHorizontalPadding: CGFloat = vm.notchState == .open
                    ? max(0, cornerRadiusInsets.opened.top - 15)
                    : cornerRadiusInsets.closed.bottom
                let openOuterHorizontalPadding: CGFloat = vm.notchState == .open ? 1 : 0
                let openBottomPadding: CGFloat = vm.notchState == .open ? getOpenContentBottomPadding() : 0
                let mainLayout = NotchLayout()
                    .offset(
                        x: -timerBackgroundShakeX,
                        y: -timerBackgroundShakeY
                    )
                    .frame(alignment: .top)
                    .frame(maxWidth: vm.notchState == .open ? openWidthValueComputed : nil)
                    .padding(
                        .horizontal,
                        openInnerHorizontalPadding
                    )
                    .padding(.horizontal, openOuterHorizontalPadding)
                    .padding(.bottom, openBottomPadding)
                    .padding(.top, vm.notchState == .open ? -10 : 0)
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(NotchMotion.notchOpenHorizontal, value: notchOpenHorizontalToken)
                    .animation(notchLayoutAnimation, value: isLayoutExpandedComputed)
                    .animation(
                        (isSwitchingOverlay && overlaySwitchDirection == .toCamera) ? nil : notchLayoutAnimation,
                        value: showCalendar
                    )

                mainLayout
                    .background {
                        ZStack(alignment: .top) {
                            currentNotchShape
                                .fill(.black)
                                .opacity(useLiquidPageBackground ? 0 : 1)

                            if useLiquidPageBackground {
                                GeometryReader { geo in
                                    let closeDarkenOpacity = liquidCloseDarkenOpacity(for: geo.size.height)
                                    let bottomArcRevealProgress = liquidBottomArcRevealProgress(for: geo.size.height)
                                    let liquidBackdropCornerRadius = cornerRadiusInsets.opened.bottom

                                    ZStack {
                                        if liquidGlassCompatibilityFallbackActive {
                                            NotchLiquidGlassBackground(
                                                variant: 11,
                                                cornerRadius: liquidBackdropCornerRadius,
                                                trigger: 0,
                                                forceFallback: true
                                            ) {
                                                Color.white.opacity(0.045 * Double(liquidGlassBlend))
                                            }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        } else {
                                            NotchRefractionBackdrop(
                                                opacity: liquidGlassBlend,
                                                strength: 2.35,
                                                cornerRadius: liquidBackdropCornerRadius,
                                                sampleScale: 0.5
                                            )
                                            .frame(
                                                width: targetOpenWidthValueComputed,
                                                height: targetOpenHeightValueComputed
                                            )
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                        }

                                        ZStack {
                                            liquidBlackVeilLayer(
                                                isLiquidTransitioningNow: isLiquidTransitioningNow,
                                                liquidVeilOpacity: liquidVeilOpacity
                                            )

                                            currentNotchShape
                                                .fill(Color.black.opacity(0.12 * liquidGlassBlend))
                                        }
                                        .mask(macOS27BottomClearMask(sideLiftProgress: bottomArcRevealProgress))

                                        macOS27InnerShadowLayer(opacity: liquidChromeOpacity)

                                        macOS27OuterStrokeLayer(opacity: liquidChromeOpacity)

                                        currentNotchShape
                                            .fill(Color.black.opacity(0.96 * closeDarkenOpacity))
                                    }
                                    .allowsHitTesting(false)
                                }
                            }

                            Rectangle()
                                .fill(notchTopLineColor)
                                .frame(height: 1)
                                .padding(.horizontal, topCornerRadius + 3)

                        }
                        .clipShape(currentNotchShape)
                    }
                    .clipShape(currentNotchShape)
                    .background(alignment: .topLeading) {
                        openShoulderExtension(
                            side: .left,
                            progress: openShoulderProgress,
                            freezeRevealForLiquidOpen: false
                        )
                        .animation(notchStateAnimation, value: vm.notchState)
                    }
                    .background(alignment: .topTrailing) {
                        openShoulderExtension(
                            side: .right,
                            progress: openShoulderProgress,
                            freezeRevealForLiquidOpen: false
                        )
                        .animation(notchStateAnimation, value: vm.notchState)
                    }
                    .overlay(alignment: .top) {
                        if vm.notchState == .open {
                            QuartzHeader()
                                .frame(height: openHeaderReferenceHeightComputed)
                                .padding(.top, 6)
                                .offset(y: headerYOffset)
                                .scaleEffect(x: headerScaleX, y: 1.0, anchor: .top)
                                .opacity(
                                    (gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                                    * headerRevealProgress
                                )
                                .zIndex(3000)
                                .allowsHitTesting(headerRevealProgress > 0.65)
                        }
                    }
                    .shadow(
                        color: ((vm.notchState == .closed && isHovering) && Defaults[.enableShadow])
                        ? .black.opacity(0.55) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 5 : 3
                    )
                    .padding(.bottom, (vm.notchState == .closed && vm.effectiveClosedNotchHeight == 0) ? 10 : 0)
                    .frame(
                        width: vm.notchState == .closed ? displayedChinWidthComputed : nil,
                        height: openHeightValueComputed
                    )
                    .frame(width: vm.notchState == .open ? openWidthValueComputed : nil)
                    .offset(
                        x: (vm.notchState == .closed ? closedChinOffsetX : 0) + timerBackgroundShakeX,
                        y: timerBackgroundShakeY
                    )
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(NotchMotion.notchOpenHorizontal, value: notchOpenHorizontalToken)
                    .animation(notchLayoutAnimation, value: isLayoutExpandedComputed)
                    .animation(
                        (isSwitchingOverlay && overlaySwitchDirection == .toCamera) ? nil : notchLayoutAnimation,
                        value: showCalendar
                    )
                    .animation(notchLayoutAnimation, value: activeQuickTimers.count)
                    .animation(notchLayoutAnimation, value: gestureProgress)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if vm.notchState == .closed {
                            if shouldShowTimerActivityClosed && isTimerPopupHovering { return }
                            if isBluetoothClosedNotificationShowing && isBluetoothPopupHovering { return }
                            if shouldShowMusicActivityClosed && (isNowPlayingLeftHovering || isNowPlayingRightHovering) {
                                if isNowPlayingRightHovering {
                                    performNowPlayingRightButtonAction()
                                }
                                return
                            }
                        }
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view.panGesture(direction: .down) { translation, phase in
                            handleDownGesture(translation: translation, phase: phase)
                        }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view.panGesture(direction: .up) { translation, phase in
                            handleUpGesture(translation: translation, phase: phase)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive && !manualOpenAutoCloseSuppressed {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open
                                        && !self.isHovering
                                        && !self.vm.isBatteryPopoverActive
                                        && !self.manualOpenAutoCloseSuppressed
                                        && !SharingStateManager.shared.preventNotchClose
                                    {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if pageUseLiquidGlassBackground {
                            liquidTransitionPerfTask?.cancel()
                            liquidTransitionPerfMode = true
                            liquidTransitionPerfTask = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(520))
                                guard !Task.isCancelled else { return }
                                liquidTransitionPerfMode = false
                            }
                        } else {
                            liquidTransitionPerfTask?.cancel()
                            liquidTransitionPerfMode = false
                        }

                        liquidCloseTransitionTask?.cancel()
                        liquidCloseTransitionTask = nil

                        if pageUseLiquidGlassBackground {
                            if newState == .open {
                                keepLiquidVisualDuringClose = true
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    liquidVisualBlend = 1
                                }
                                withAnimation(.easeOut(duration: 0.26)) {
                                    liquidStrokeReveal = 1
                                }
                            } else {
                                liquidVisualBlend = 1
                                keepLiquidVisualDuringClose = true
                                withAnimation(.easeOut(duration: 0.18)) {
                                    liquidStrokeReveal = 0
                                }
                                liquidCloseTransitionTask = Task {
                                    try? await Task.sleep(nanoseconds: UInt64(NotchMotion.notchCloseDuration * 1_000_000_000))
                                    guard !Task.isCancelled else { return }
                                    await MainActor.run {
                                        keepLiquidVisualDuringClose = false
                                        liquidVisualBlend = 0
                                        liquidCloseTransitionTask = nil
                                    }
                                }
                            }
                        } else {
                            keepLiquidVisualDuringClose = false
                            liquidVisualBlend = 0
                            liquidStrokeReveal = 0
                        }

                        if newState == .open {
                            notchOpenHorizontalToken &+= 1
                            ignoreHoverExitUntil = Date().addingTimeInterval(
                                openingFromNowPlayingCenterHover ? 0.48 : 0.25
                            )
                            restartOpenContentRevealAnimation()
                            if openingFromNowPlayingCenterHover {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(16))
                                    guard vm.notchState == .open else { return }
                                    activateFrozenHoverZone()
                                }
                            }
                            startOpenHoverWatchdogIfNeeded()
                        } else if newState == .closed {
                            openingFromNowPlayingCenterHover = false
                            openContentRevealTask?.cancel()
                            openContentRevealTask = nil
                            openContentRevealProgress = 0
                            openHeaderWidthProgress = 0
                            openHoverWatchdogTask?.cancel()
                            openHoverWatchdogTask = nil
                            suppressTimerPopupAutoOpenUntil = Date().addingTimeInterval(0.35)
                            timerSidesHoverTask?.cancel()
                            timerTransitionTask?.cancel()
                            timerPopupRearmTask?.cancel()
                            timerPopupCloseTask?.cancel()
                            timerPopupCloseTask = nil
                            isTimerPopupHovering = false
                            isTimerSidesHovering = false
                            isTimerExpandedHovering = false
                            isTimerProximityHovering = false
                            isTimerPopupTransitioning = false
                            isTimerPopupHoverArmed = false
                            scheduleTimerPopupRearmAfterClose()
                        }

                        if newState == .closed && isHovering {
                            withAnimation(NotchMotion.notchClose) { isHovering = false }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) { _, _ in
                        if !vm.isBatteryPopoverActive
                            && !isHovering
                            && vm.notchState == .open
                            && !manualOpenAutoCloseSuppressed
                            && !SharingStateManager.shared.preventNotchClose
                        {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }

                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive
                                        && !self.isHovering
                                        && self.vm.notchState == .open
                                        && !self.manualOpenAutoCloseSuppressed
                                        && !SharingStateManager.shared.preventNotchClose
                                    {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: pageUseLiquidGlassBackground) { _, enabled in
                        liquidCloseTransitionTask?.cancel()
                        liquidCloseTransitionTask = nil
                        if !enabled {
                            liquidTransitionPerfTask?.cancel()
                            liquidTransitionPerfMode = false
                        }
                        keepLiquidVisualDuringClose = enabled && vm.notchState == .open
                        liquidVisualBlend = (enabled && vm.notchState == .open) ? 1 : 0
                        liquidStrokeReveal = (enabled && vm.notchState == .open) ? 1 : 0
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .accentContextMenu(
                        actions: [
                            AccentContextMenuAction(
                                title: String(localized: "Settings"),
                                keyboardShortcut: "⌘,",
                                action: {
                                    SettingsWindowController.shared.showWindow()
                                }
                            )
                        ]
                    )

                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: displayedChinWidthComputed, height: vm.chinHeight)
                        .offset(x: vm.notchState == .closed ? closedChinOffsetX : 0)
                }

            }

            if vm.notchState == .closed,
               shouldShowTimerActivityClosed,
               isTimerPopupHovering {
                timerExpandedButtonsOverlayView()
                    .offset(x: closedChinOffsetX, y: vm.effectiveClosedNotchHeight - 2)
                    .zIndex(7)
            }

            if shouldRenderClosedSecondaryDetachedActivity,
               let secondaryCompact = closedSecondaryCompactActivityKind {
                closedDetachedBridgeArcView()
                    .offset(
                        x: closedDetachedBridgeCenterOffsetX - secondaryDetachedBridgeSlideX,
                        y: closedDetachedBridgeOffsetY
                    )
                    .allowsHitTesting(false)
                    .transition(closedSecondaryDetachedTransition)
                    .zIndex(-3)

                closedDetachedCompactActivity(kind: secondaryCompact)
                    .offset(x: closedDetachedCompactCenterOffsetX - secondaryDetachedBubbleSlideX, y: 0)
                    .scaleEffect(
                        x: 0.90 + 0.10 * secondaryDetachedSlideProgress,
                        y: 1.0,
                        anchor: .leading
                    )
                    .allowsHitTesting(false)
                    .transition(closedSecondaryDetachedTransition)
                    .zIndex(-2)
            }
        }
        .padding(.bottom, 8)
        .frame(
            maxWidth: dynamicWindowSizeComputed.width,
            maxHeight: dynamicWindowSizeComputed.height,
            alignment: .top
        )
        .compositingGroup()
        .scaleEffect(x: gestureScale, y: gestureScale, anchor: .top)
        .animation(NotchMotion.notchLayout, value: gestureProgress)
        .animation(
            bluetoothTakeoverExitPending ? NotchMotion.liveActivityOut : NotchMotion.liveActivityIn,
            value: closedPrimaryActivityKind
        )
        .animation(NotchMotion.liveActivityIn, value: closedSecondaryCompactActivityKind)
        .animation(NotchMotion.liveActivityOut, value: isClosedPrimaryActivityExpanded)
        .background(WindowAccessor { hostWindow = $0 })
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)

        withLifecycleHandlers(baseView)
    }

    private func withLifecycleHandlers<Content: View>(_ content: Content) -> some View {
        let s1 = withStartupHandlers(content)
        let s2 = withSystemStateHandlers(s1)
        let s3 = withOverlayStateHandlers(s2)
        let s4 = withPopupStateHandlers(s3)
        return withTimerPulseHandlers(s4)
    }

    private func withStartupHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                keepLiquidVisualDuringClose = pageUseLiquidGlassBackground && vm.notchState == .open
                liquidVisualBlend = (pageUseLiquidGlassBackground && vm.notchState == .open) ? 1 : 0
                liquidStrokeReveal = (pageUseLiquidGlassBackground && vm.notchState == .open) ? 1 : 0
                lockSuppressionProgress = lockTransition.suppressClosedActivities ? 1 : 0
                openContentRevealProgress = (vm.notchState == .open) ? 1 : 0
                openHeaderWidthProgress = (vm.notchState == .open) ? 1 : 0
                let w = computedChinWidth
                batteryChinFrom = w
                batteryChinTo = w
                batteryChinPhase = 1
                applyScreenRecordingVisibilityPolicy()
                installNowPlayingClickMonitorIfNeeded()
                if vm.notchState == .open {
                    startOpenHoverWatchdogIfNeeded()
                }
            }
            .onDisappear {
                liquidCloseTransitionTask?.cancel()
                liquidCloseTransitionTask = nil
                liquidTransitionPerfTask?.cancel()
                liquidTransitionPerfTask = nil
                liquidTransitionPerfMode = false
                openHoverWatchdogTask?.cancel()
                openHoverWatchdogTask = nil
                openContentRevealTask?.cancel()
                openContentRevealTask = nil
                bluetoothPopupCloseTask?.cancel()
                bluetoothPopupCloseTask = nil
                timerPopupCloseTask?.cancel()
                timerPopupCloseTask = nil
                nowPlayingSneakPeekWatchdogTask?.cancel()
                nowPlayingSneakPeekWatchdogTask = nil
                nowPlayingSneakPeekCloseTask?.cancel()
                nowPlayingSneakPeekCloseTask = nil
                timerPopupRearmTask?.cancel()
                timerPopupRearmTask = nil
                if let m = timerGlobalMouseMonitor {
                    NSEvent.removeMonitor(m)
                    timerGlobalMouseMonitor = nil
                }
                if let m = nowPlayingClickMonitor {
                    NSEvent.removeMonitor(m)
                    nowPlayingClickMonitor = nil
                }
                closedPopupFailsafeTask?.cancel()
                closedPopupFailsafeTask = nil
            }
    }

    private func withSystemStateHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: lockTransition.suppressClosedActivities) { _, suppress in
                let d = suppress ? 0.18 : 0.24
                withAnimation(NotchMotion.visibility(duration: d)) {
                    lockSuppressionProgress = suppress ? 1 : 0
                }
            }
            .onChange(of: closedSecondaryCompactActivityKind) { oldKind, newKind in
                if oldKind == nil, newKind != nil {
                    detachedSecondaryAppearToken &+= 1
                }
            }
            .onChange(of: isBatteryClosedNotificationShowing) { _, _ in
                let newWidth = computedChinWidth
                guard vm.notchState == .closed,
                      !lockTransition.suppressClosedActivities,
                      Defaults[.showPowerStatusNotifications],
                      coordinator.expandingView.type == .battery
                else {
                    batteryChinFrom = newWidth
                    batteryChinTo = newWidth
                    batteryChinPhase = 1
                    return
                }

                let current = batteryChinFrom + (batteryChinTo - batteryChinFrom) * OrganicBatteryEasing.map(
                    batteryChinPhase,
                    mode: (batteryChinTo >= batteryChinFrom) ? .appear : .disappear
                )
                batteryChinFrom = current
                batteryChinTo = newWidth
                batteryChinPhase = 0
                withAnimation(
                    NotchMotion.widthMorph(
                        duration: ((batteryChinTo >= batteryChinFrom) ? batteryAppearDuration : batteryDisappearDuration)
                    )
                ) {
                    batteryChinPhase = 1
                }
            }
            .onChange(of: pageUseLiquidGlassBackground) { _, enabled in
                liquidCloseTransitionTask?.cancel()
                liquidCloseTransitionTask = nil
                keepLiquidVisualDuringClose = enabled && vm.notchState == .open
                liquidVisualBlend = (enabled && vm.notchState == .open) ? 1 : 0
                liquidStrokeReveal = (enabled && vm.notchState == .open) ? 1 : 0
            }
            .onChange(of: hostWindow?.windowNumber) { _, _ in
                applyScreenRecordingVisibilityPolicy()
                applyDynamicWindowFrame()
            }
            .onChange(of: hideFromScreenRecordingMode) { _, _ in
                applyScreenRecordingVisibilityPolicy()
            }
            .onChange(of: vm.notchState) { _, _ in
                applyScreenRecordingVisibilityPolicy()
                applyDynamicWindowFrame()
            }
            .onChange(of: hasClosedLiveActivityForRecordingPolicy) { _, _ in
                applyScreenRecordingVisibilityPolicy()
            }
            .onChange(of: shouldReserveWindowSpaceForTimerPopup) { _, _ in
                updateTimerWindowReservation(allowShrink: !shouldReserveWindowSpaceForTimerPopup)
            }
            .onChange(of: timerExpandedFooterHeight) { _, _ in
                if timerExpandedFooterHeight > timerReservedFooterHeight {
                    updateTimerWindowReservation()
                } else if !isTimerPopupHovering && !isTimerPopupTransitioning && !isTimerExpandedHovering {
                    scheduleTimerWindowReservationShrink()
                }
            }
            .onChange(of: timerExpandedTargetWidth) { _, _ in
                if timerExpandedTargetWidth > timerReservedTargetWidth {
                    updateTimerWindowReservation()
                } else if !isTimerPopupHovering && !isTimerPopupTransitioning && !isTimerExpandedHovering {
                    scheduleTimerWindowReservationShrink()
                }
            }
    }

    private func withOverlayStateHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: isLayoutExpandedComputed) { oldExpanded, newExpanded in
                guard vm.notchState == .open else { return }
                if oldExpanded && !newExpanded {
                    activateFrozenHoverZone()
                } else if newExpanded {
                    deactivateFrozenHoverZone()
                }
            }
            .onChange(of: showCalendar) { oldCalendarOn, calendarOn in
                if calendarOn {
                    calendarToCameraExitOffsetX = 0
                    calendarToCameraTrailingReserve = 0
                    deferCameraOverlayDuringToCameraSwitch = false
                    vm.suppressCameraLayoutInOpenContent = false
                }
                if calendarOn { calendarRestoreAfterCamera = false }
                if oldCalendarOn && !calendarOn && !isCameraVisibleComputed {
                    activateFrozenHoverZone(widthHint: 230)
                }

                suppressAutoCloseUntil = Date().addingTimeInterval(0.45)
                guard !isSwitchingOverlay else { return }

                if calendarOn, vm.isCameraExpanded {
                    overlaySwitchToken &+= 1
                    let token = overlaySwitchToken
                    isSwitchingOverlay = true
                    overlaySwitchDirection = .toCalendar

                    overlayHeightHold = vm.notchSize.height
                    let currentExtra: CGFloat = 160
                    overlayWidthHold = currentExtra

                    withAnimation(animationSpring) { showCalendar = false }
                    withAnimation(animationSpring) { vm.toggleCameraPreview() }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: overlaySwitchDelayMs * 1_000_000)
                        guard token == overlaySwitchToken else { return }
                        withAnimation(animationSpring) { showCalendar = true }

                        try? await Task.sleep(nanoseconds: 180 * 1_000_000)
                        guard token == overlaySwitchToken else { return }
                        withAnimation(NotchMotion.notchLayout) {
                            overlayWidthHold = 0
                            overlayHeightHold = 0
                        }

                        isSwitchingOverlay = false
                        overlaySwitchDirection = .none
                    }
                }
            }
            .onChange(of: showMirror) { _, _ in
                suppressAutoCloseUntil = Date().addingTimeInterval(0.45)
            }
            .onChange(of: vm.isCameraExpanded) { oldCameraOn, cameraOn in
                suppressAutoCloseUntil = Date().addingTimeInterval(0.45)
                if !cameraOn {
                    vm.suppressCameraLayoutInOpenContent = false
                }
                if oldCameraOn && !cameraOn && !showCalendar {
                    activateFrozenHoverZone(widthHint: 160)
                }
                if cameraOn, showCalendar {
                    calendarRestoreAfterCamera = true
                    overlaySwitchToken &+= 1
                    let token = overlaySwitchToken

                    isSwitchingOverlay = true
                    overlaySwitchDirection = .toCamera
                    deferCameraOverlayDuringToCameraSwitch = true
                    vm.suppressCameraLayoutInOpenContent = true
                    calendarToCameraTrailingReserve = calendarOverlayTotalWidth

                    let currentExtra: CGFloat = (isCalendarVisibleComputed ? 230 : 0)
                    overlayWidthHold = max(160, currentExtra)

                    withAnimation(animationSpring) {
                        calendarToCameraExitOffsetX = 170
                    }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: overlaySwitchDelayMs * 1_000_000)
                        guard token == overlaySwitchToken else { return }
                        var tx = Transaction()
                        tx.animation = nil
                        withTransaction(tx) {
                            showCalendar = false
                        }
                        deferCameraOverlayDuringToCameraSwitch = false
                        withAnimation(NotchMotion.notchLayout) {
                            overlayWidthHold = 160
                            calendarToCameraTrailingReserve = 0
                            vm.suppressCameraLayoutInOpenContent = false
                        }
                    }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: overlaySwitchDelayMs * 1_000_000)
                        guard token == overlaySwitchToken else { return }
                        if !vm.isCameraExpanded {
                            withAnimation(animationSpring) { vm.toggleCameraPreview() }
                        }

                        try? await Task.sleep(nanoseconds: 180 * 1_000_000)
                        guard token == overlaySwitchToken else { return }
                        withAnimation(NotchMotion.notchLayout) {
                            overlayWidthHold = 0
                            calendarToCameraExitOffsetX = 0
                            calendarToCameraTrailingReserve = 0
                            vm.suppressCameraLayoutInOpenContent = false
                        }
                        isSwitchingOverlay = false
                        overlaySwitchDirection = .none
                    }
                    return
                }

                guard !isSwitchingOverlay else { return }

                if !cameraOn, calendarRestoreAfterCamera {
                    overlaySwitchToken &+= 1
                    let token = overlaySwitchToken
                    calendarRestoreAfterCamera = false
                    isSwitchingOverlay = true
                    overlaySwitchDirection = .toCalendar
                    calendarToCameraTrailingReserve = 0
                    deferCameraOverlayDuringToCameraSwitch = false
                    vm.suppressCameraLayoutInOpenContent = false

                    overlayWidthHold = 230
                    withAnimation(animationSpring) { showCalendar = true }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180 * 1_000_000)
                        guard token == overlaySwitchToken else { return }
                        withAnimation(NotchMotion.notchLayout) {
                            overlayWidthHold = 0
                        }

                        isSwitchingOverlay = false
                        overlaySwitchDirection = .none
                    }
                    return
                }
            }
    }

    private func withPopupStateHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: isBluetoothClosedNotificationShowing) { _, showing in
                if showing { return }

                bluetoothPopupCloseTask?.cancel()
                bluetoothPopupCloseTask = nil
                bluetoothCenterHoverTask?.cancel()
                bluetoothSidesHoverTask?.cancel()
                bluetoothTransitionTask?.cancel()
                isBluetoothPopupHovering = false
                isBluetoothSidesHovering = false
                isBluetoothCenterHovering = false
                isBluetoothPopupTransitioning = false
                withAnimation(animationSpring) { isHovering = false }
                coordinator.resumeExpandingViewAutoHide()
            }
            .onChange(of: isBluetoothPopupHovering) { _, isOpen in
                if isOpen {
                    bluetoothPopupCloseTask?.cancel()
                    bluetoothPopupCloseTask = nil
                    ensureClosedPopupFailsafeRunning()
                } else if !isTimerPopupHovering {
                    closedPopupFailsafeTask?.cancel()
                    closedPopupFailsafeTask = nil
                }
            }
            .onChange(of: shouldShowTimerActivityClosed) { _, showing in
                if showing {
                    isTimerPopupHoverArmed = Date() >= suppressTimerPopupAutoOpenUntil
                    return
                }
                timerPopupRearmTask?.cancel()
                timerPopupRearmTask = nil
                timerPopupCloseTask?.cancel()
                timerPopupCloseTask = nil
                timerSidesHoverTask?.cancel()
                timerTransitionTask?.cancel()
                isTimerPopupHovering = false
                isTimerSidesHovering = false
                isTimerExpandedHovering = false
                isTimerPopupTransitioning = false
                isTimerPopupHoverArmed = false
            }
            .onChange(of: isTimerPopupHovering) { _, isOpen in
                if isOpen {
                    updateTimerWindowReservation()
                    ensureClosedPopupFailsafeRunning()
                } else if !isBluetoothPopupHovering {
                    suppressNotchOpenUntilAfterTimerPopupClose = Date().addingTimeInterval(0.35)
                    closedPopupFailsafeTask?.cancel()
                    closedPopupFailsafeTask = nil

                    timerSidesHoverTask?.cancel()
                    timerTransitionTask?.cancel()
                    timerPopupCloseTask?.cancel()
                    timerPopupCloseTask = nil
                    isTimerSidesHovering = false
                    isTimerExpandedHovering = false
                    isTimerProximityHovering = false
                    isTimerPopupTransitioning = false
                    isTimerPopupHoverArmed = Date() >= suppressTimerPopupAutoOpenUntil

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(10))
                        handleHover(isHovering)
                    }
                    scheduleTimerWindowReservationShrink()
                }
            }
            .onChange(of: isTimerProximityHovering) { _, hovering in
                if hovering {
                    timerPopupCloseTask?.cancel()
                    timerPopupCloseTask = nil
                } else if isTimerPopupHovering {
                    scheduleTimerPopupCloseIfNeeded(delayMs: 150)
                }
            }
            .onChange(of: activeQuickTimers.count) { _, count in
                if count > 0 {
                    updateTimerWindowReservation()
                    return
                }

                timerPopupRearmTask?.cancel()
                timerPopupRearmTask = nil
                timerPopupCloseTask?.cancel()
                timerPopupCloseTask = nil
                timerSidesHoverTask?.cancel()
                timerTransitionTask?.cancel()
                isTimerPopupHovering = false
                isTimerSidesHovering = false
                isTimerExpandedHovering = false
                isTimerProximityHovering = false
                isTimerPopupTransitioning = false
                isTimerPopupHoverArmed = false
                keepTimerPopupOpenForFinishedAlert = false
                updateTimerWindowReservation(allowShrink: true)

                handleHover(isHovering)
            }
            .onChange(of: shouldShowMusicActivityClosed) { _, showing in
                if showing { return }
                isNowPlayingLeftHovering = false
                isNowPlayingRightHovering = false
                nowPlayingSneakPeekWatchdogTask?.cancel()
                nowPlayingSneakPeekWatchdogTask = nil
                nowPlayingSneakPeekCloseTask?.cancel()
                nowPlayingSneakPeekCloseTask = nil
                if isNowPlayingSneakPeekForcedByHover {
                    isNowPlayingSneakPeekForcedByHover = false
                    if coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music {
                        coordinator.toggleSneakPeek(status: false, type: .music)
                    }
                }
            }
            .onChange(of: coordinator.expandingView.show) { _, isShowing in
                handleExpandingViewStateChange(
                    isShowing: isShowing,
                    activityType: coordinator.expandingView.type
                )
            }
            .onChange(of: coordinator.expandingView.type) { _, activityType in
                guard coordinator.expandingView.show else { return }
                handleExpandingViewStateChange(
                    isShowing: true,
                    activityType: activityType
                )
            }
    }

    private func withTimerPulseHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: quickTimerManager.finishEventTick) { _, _ in
                guard vm.notchState == .closed else { return }
                guard shouldShowTimerActivityClosed else { return }

                keepTimerPopupOpenForFinishedAlert = true
                isTimerPopupHoverArmed = false
                isTimerPopupTransitioning = true
                timerTransitionTask?.cancel()
                timerTransitionTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    isTimerPopupTransitioning = false
                }
                withAnimation(NotchMotion.popupHover) {
                    isTimerPopupHovering = true
                }
            }
            .onChange(of: hasFinishedQuickTimers) { _, hasFinished in
                if !hasFinished {
                    keepTimerPopupOpenForFinishedAlert = false
                }
            }
            .onChange(of: quickTimerManager.alertPulseToken) { _, _ in
                guard shouldVibrateExpandedTimerBackground else { return }

                timerAlarmBackgroundSettleTask?.cancel()
                timerAlarmBackgroundDirection *= -1

                let pulse = max(0.65, min(1.35, quickTimerManager.alertPulseStrength))
                let kick = timerAlarmBackgroundDirection * (1.34 * pulse)
                performTimerAlertHapticPulse(strength: pulse)

                withAnimation(.easeOut(duration: 0.042)) {
                    timerAlarmBackgroundImpulseX = kick
                }

                timerAlarmBackgroundSettleTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(92))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        timerAlarmBackgroundImpulseX = 0
                    }
                }
            }
            .onChange(of: shouldVibrateExpandedTimerBackground) { _, shouldVibrate in
                guard !shouldVibrate else { return }
                timerAlarmBackgroundSettleTask?.cancel()
                timerAlarmBackgroundSettleTask = nil
                timerAlarmBackgroundDirection = -1
                withAnimation(.easeOut(duration: 0.16)) {
                    timerAlarmBackgroundImpulseX = 0
                }
            }
    }

    private func handleExpandingViewStateChange(isShowing: Bool, activityType: SneakContentType) {
        guard isShowing else {
            musicExitTask?.cancel()
            musicExitTask = nil
            bluetoothTakeoverExitTask?.cancel()
            bluetoothTakeoverExitTask = nil
            bluetoothClosedOverlaySuppressed = false
            musicExitPending = false
            showMusicExitOverlay = false
            animateMusicExitOverlay = false
            bluetoothTakeoverExitOverlayKind = nil
            animateBluetoothTakeoverExitOverlay = false
            bluetoothHiddenClosedActivity = nil

            if activityType == .bluetooth {
                bluetoothReturnSuppressTask?.cancel()
                bluetoothReturnSuppressTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    guard !Task.isCancelled else { return }
                    withAnimation(NotchMotion.liveActivityIn) {
                        bluetoothTakeoverExitPending = false
                    }
                    withAnimation(NotchMotion.nowPlayingIn) {
                        musicHiddenByExpandingView = false
                    }
                }
            } else {
                withAnimation(NotchMotion.liveActivityIn) {
                    bluetoothTakeoverExitPending = false
                }
                withAnimation(NotchMotion.nowPlayingIn) {
                    musicHiddenByExpandingView = false
                }
            }
            suppressNotchHoverHapticUntil = Date().addingTimeInterval(0.45)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                handleHover(isHovering)
            }
            return
        }

        if activityType != .bluetooth {
            bluetoothClosedOverlaySuppressed = false
            bluetoothTakeoverExitPending = false
            bluetoothTakeoverExitOverlayKind = nil
            animateBluetoothTakeoverExitOverlay = false
            bluetoothHiddenClosedActivity = nil
        }

        if activityType == .bluetooth {
            let shouldCloseClassicalActivities = bluetoothTakeoverSourceKind != nil

            guard shouldCloseClassicalActivities else {
                bluetoothClosedOverlaySuppressed = false
                bluetoothTakeoverExitPending = false
                bluetoothHiddenClosedActivity = nil
                bluetoothTakeoverExitOverlayKind = nil
                animateBluetoothTakeoverExitOverlay = false
                return
            }

            musicExitTask?.cancel()
            musicExitTask = nil
            musicExitPending = false
            showMusicExitOverlay = false
            animateMusicExitOverlay = false
            bluetoothClosedOverlaySuppressed = true
            withAnimation(NotchMotion.liveActivityOut) {
                bluetoothTakeoverExitPending = true
            }
            bluetoothHiddenClosedActivity = nil
            bluetoothTakeoverExitOverlayKind = nil
            animateBluetoothTakeoverExitOverlay = false
            bluetoothTakeoverExitTask?.cancel()
            bluetoothTakeoverExitTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 380_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(NotchMotion.liveActivityBluetoothIn) {
                    bluetoothClosedOverlaySuppressed = false
                }
            }
            return
        }

        let musicIsVisible = !musicHiddenByExpandingView
            && vm.notchState == .closed
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
            && closedActivityVisibility > 0.001
            && !vm.hideOnClosed
            && !shouldShowLockActivityClosed
            && !shouldShowFocusActivityClosed
            && !shouldShowFileTrayActivityClosed
        if musicIsVisible {
            if activityType == .bluetooth {
                bluetoothClosedOverlaySuppressed = true
            }
            musicExitPending = true
            showMusicExitOverlay = true
            animateMusicExitOverlay = false
            musicExitTask?.cancel()
            musicExitTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(NotchMotion.nowPlayingOut) {
                    musicHiddenByExpandingView = true
                    animateMusicExitOverlay = true
                }
                try? await Task.sleep(nanoseconds: 380_000_000)
                guard !Task.isCancelled else { return }
                let animation: Animation = switch activityType {
                case .bluetooth: NotchMotion.liveActivityBluetoothIn
                case .battery: NotchMotion.liveActivityBatteryIn
                default: NotchMotion.liveActivityIn
                }
                showMusicExitOverlay = false
                animateMusicExitOverlay = false
                withAnimation(animation) {
                    if activityType == .bluetooth {
                        bluetoothClosedOverlaySuppressed = false
                    }
                    musicExitPending = false
                }
            }
        } else {
            musicHiddenByExpandingView = true
            showMusicExitOverlay = false
            animateMusicExitOverlay = false
        }
    }

 // MARK: - Layout

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    })
                    .frame(width: getClosedNotchSize().width, height: 80)
                    .padding(.top, 40)
                    Spacer()
                } else {
                    ZStack {
                        HStack(spacing: 0) {
                            Group {
                            if isBatteryClosedNotificationShowing {
                                let sidePadding: CGFloat = batteryClosedSidePadding
                                let sideWidth: CGFloat = batteryClosedSideWidth
                                let fontSize: CGFloat = batteryClosedFontSize

                                let r = Double(min(max(batteryClosedContentProgress, 0), 1))
                                let minOpacity = 0.085
                                let maxBlur = 18.0
                                let opacity = minOpacity + (1.0 - minOpacity) * pow(r, 3.0)
                                let blurRadius = maxBlur * pow(1.0 - r, 1.05)
                                let scale = 0.985 + 0.015 * pow(r, 1.25)
                                let isCriticalBattery = batteryModel.levelBattery < 20
                                let batteryAccentColor: Color = isCriticalBattery
                                    ? .red
                                    : (batteryModel.isInLowPowerMode ? .yellow : .green)

                                HStack(spacing: 0) {
                                    Text(batteryClosedStatusText)
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .allowsTightening(true)
                                        .opacity(opacity)
                                        .blur(radius: blurRadius)
                                        .scaleEffect(scale, anchor: .leading)
                                        .compositingGroup()
                                        .frame(width: sideWidth, alignment: .leading)

                                    Rectangle()
                                        .fill(.black)
                                        .frame(width: vm.closedNotchSize.width)

                                    HStack(spacing: 3) {
                                        Text("\(Int(batteryModel.levelBattery))%")
                                            .font(.system(size: fontSize, weight: .medium))
                                            .foregroundStyle(batteryAccentColor)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                            .allowsTightening(true)

                                        NotificationBatteryIcon(
                                            levelBattery: batteryModel.levelBattery,
                                            isLowPowerMode: batteryModel.isInLowPowerMode
                                        )
                                            .frame(width: 29, height: 12)
                                    }
                                    .opacity(opacity)
                                    .blur(radius: blurRadius)
                                    .scaleEffect(scale, anchor: .trailing)
                                    .compositingGroup()
                                    .frame(width: sideWidth, alignment: .trailing)
                                }
                                .padding(.horizontal, sidePadding)
                                .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                                .clipped()
                            }
                            else if shouldShowLockActivityClosed {
                                LockScreenLiveActivity(
                                    isLocked: lockScreenState.isLocked,
                                    contentWidth: vm.closedNotchSize.width - 20,
                                    height: vm.effectiveClosedNotchHeight
                                )
                            }
                            else if isInlineHUDFloatingClosed {
                                InlineHUD(
                                    type: $coordinator.sneakPeek.type,
                                    value: $coordinator.sneakPeek.value,
                                    icon: $coordinator.sneakPeek.icon,
                                    hoverAnimation: $isHovering,
                                    gestureProgress: $gestureProgress
                                )
                                .transition(.opacity)
                            }
                            else if shouldShowFocusActivityClosed {
                                closedFocusLiveActivityView()
                                    .transition(closedLiveActivityTransition)
                            }
                            else if shouldShowTimerActivityClosed {
                                closedTimerLiveActivityView()
                                    .transition(closedLiveActivityTransition)
                            }
                            else if shouldShowFileTrayActivityClosed {
                                FileTrayLiveActivity(count: fileTrayCount, isCompactMode: isFileTrayCompactMode)
                                    .transition(closedLiveActivityTransition)
                            }
                            else if shouldShowMusicActivityClosed {
                                MusicLiveActivity(
                                    isCompactMode: isNowPlayingCompactMode,
                                    showPauseOnRight: isNowPlayingRightHovering,
                                    onHoverZonesChanged: { hoveringLeft, hoveringRight, _ in
                                        isNowPlayingLeftHovering = hoveringLeft
                                        isNowPlayingRightHovering = hoveringRight
                                        updateNowPlayingSneakPeekHoverState()
                                    },
                                    onPauseRequested: {
                                        performNowPlayingRightButtonAction()
                                    }
                                )
                                .frame(alignment: .center)
                                .transition(closedLiveActivityTransition)
                            }
                            else if shouldShowFaceClosed {
                                QuartzFaceAnimation()
                                    .transition(closedLiveActivityTransition)
                            }
                            else if vm.notchState == .open {
                                Rectangle()
                                    .fill(.clear)
                                    .frame(height: openHeaderSpacerHeightComputed)
                                    .padding(.top, 6)
                            } else {
                                Rectangle()
                                    .fill(.clear)
                                    .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                            }
                        }
                        }
                        .opacity(vm.notchState == .closed ? closedActivityVisibility : 1)
                        .blur(radius: vm.notchState == .closed ? (1 - closedActivityVisibility) * 12 : 0)
                        .scaleEffect(vm.notchState == .closed ? (0.985 + 0.015 * closedActivityVisibility) : 1, anchor: .top)
                        .allowsHitTesting(vm.notchState == .open || closedActivityVisibility > 0.95)
                        .animation(
                            shouldShowMusicActivityClosed ? NotchMotion.nowPlayingIn : NotchMotion.nowPlayingOut,
                            value: shouldShowMusicActivityClosed
                        )
                        .animation(
                            bluetoothTakeoverExitPending ? NotchMotion.liveActivityOut : NotchMotion.liveActivityIn,
                            value: bluetoothTakeoverExitPending
                        )
                        .overlay(alignment: .topLeading) {
                            if shouldKeepNowPlayingEdgeTrackingMounted {
                                let trackingMetrics = nowPlayingEdgeTrackingMetrics(isCompactMode: isNowPlayingCompactMode)
                                NowPlayingEdgeHoverTrackingView(
                                    leftEdgeWidth: trackingMetrics.leftEdgeWidth,
                                    rightEdgeWidth: trackingMetrics.rightEdgeWidth,
                                    isTrackingEnabled: shouldShowMusicActivityClosed,
                                    onHoverZonesChanged: { hoveringLeft, hoveringRight, _ in
                                        isNowPlayingLeftHovering = hoveringLeft
                                        isNowPlayingRightHovering = hoveringRight
                                        updateNowPlayingSneakPeekHoverState()
                                    },
                                    onRightEdgeTap: {
                                        performNowPlayingRightButtonAction()
                                    }
                                )
                                .frame(
                                    width: trackingMetrics.totalWidth,
                                    height: trackingMetrics.totalHeight,
                                    alignment: .topLeading
                                )
                                .offset(x: trackingMetrics.xOffset, y: trackingMetrics.yOffset)
                                .opacity(shouldShowMusicActivityClosed ? 1 : 0.001)
                            }
                        }
                        .overlay {
                            if showMusicExitOverlay {
                                MusicLiveActivity(
                                    isCompactMode: isNowPlayingCompactMode,
                                    showPauseOnRight: false,
                                    albumArtGeometryID: "albumArtExitOverlay",
                                    onHoverZonesChanged: { _, _, _ in },
                                    onPauseRequested: {}
                                )
                                .opacity(animateMusicExitOverlay ? 0 : 1)
                                .scaleEffect(animateMusicExitOverlay ? 0.985 : 1, anchor: .top)
                                .frame(alignment: .center)
                                .allowsHitTesting(false)
                            }
                        }

                        if isBluetoothClosedNotificationShowing {
                            bluetoothClosedNotificationView()
                                .frame(alignment: .center)
                                .zIndex(1)
                        }
                    }

                    if coordinator.sneakPeek.show && closedActivityVisibility > 0.001 {
                        if (coordinator.sneakPeek.type != .music)
                            && (coordinator.sneakPeek.type != .battery)
                            && !Defaults[.inlineHUD]
                            && vm.notchState == .closed
                        {
                            SystemEventIndicatorModifier(
                                eventType: $coordinator.sneakPeek.type,
                                value: $coordinator.sneakPeek.value,
                                icon: $coordinator.sneakPeek.icon,
                                sendEventBack: { newVal in
                                    switch coordinator.sneakPeek.type {
                                    case .volume:
                                        VolumeManager.shared.setAbsolute(Float32(newVal))
                                    case .brightness:
                                        BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                    default:
                                        break
                                    }
                                }
                            )
                            .padding(.bottom, 10)
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                        } else if coordinator.sneakPeek.type == .music {
                            if vm.notchState == .closed
                                && !vm.hideOnClosed
                            {
                                let sneakPeekTextWidth = max(60, computedPrimaryChinWidthRaw - 2)
                                MarqueeText(
                                    .constant(musicManager.songTitle + " - " + musicManager.artistName),
                                    font: .system(size: 12, weight: .medium),
                                    nsFont: .caption1,
                                    textColor: Defaults[.playerColorTinting]
                                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                    : .gray,
                                    minDuration: 1,
                                    frameWidth: sneakPeekTextWidth,
                                    useEdgeFade: true,
                                    measuredPointSize: 12,
                                    measuredWeight: .medium,
                                    isPaused: !musicManager.isPlaying
                                )
                                .frame(width: sneakPeekTextWidth, height: 16, alignment: .leading)
                                .foregroundStyle(.gray)
                                .offset(y: -7)
                                .transition(
                                    .asymmetric(
                                        insertion: .identity,
                                        removal: .opacity.combined(with: .move(edge: .top))
                                    )
                                )
                                .animation(.easeOut(duration: 0.045), value: coordinator.sneakPeek.show)
                            }
                        }
                    }
                }
            }
            .conditionalModifier(
                (coordinator.sneakPeek.show
                 && (coordinator.sneakPeek.type != .music)
                 && vm.notchState == .closed)
            ) { view in
                view.fixedSize()
            }
            .zIndex(2)

            if vm.notchState == .open {
                let revealRaw = max(0, openContentRevealProgress)
                let revealP = min(1, revealRaw)
                let revealOvershoot = min(0.045, max(0, revealRaw - 1))
                let contentRevealEase = revealP * revealP * (3 - 2 * revealP)
                let contentLiftEase = CGFloat(1 - pow(Double(1 - revealP), 3))
                let contentScaleX = 0.978 + (0.022 * contentRevealEase)
                let contentScaleY = contentScaleX + (revealOvershoot * 0.055)
                let contentBlur = 1.6 * CGFloat(pow(Double(1 - contentRevealEase), 1.7))
                ZStack(alignment: .topTrailing) {
                    let isCameraOverlayVisible: Bool =
                        Defaults[.showMirror]
                        && webcamManager.cameraAvailable
                        && vm.isCameraExpanded
                        && !(isSwitchingOverlay
                             && overlaySwitchDirection == .toCamera
                             && deferCameraOverlayDuringToCameraSwitch)
                    let reservedTrailing: CGFloat = {
                        if isSwitchingOverlay && overlaySwitchDirection == .toCalendar {
                            return calendarOverlayTotalWidth
                        }
                        if isSwitchingOverlay && overlaySwitchDirection == .toCamera {
                            return max(
                                showCalendar ? calendarOverlayTotalWidth : 0,
                                calendarToCameraTrailingReserve
                            )
                        }
                        return showCalendar ? calendarOverlayTotalWidth : 0
                    }()

                    GeometryReader { geo in
                        let contentWidth = max(0, min(geo.size.width, openBaseContentWidthComputed))
                        let contentHeight = min(max(0, geo.size.height), openContentViewportHeightComputed)
                        let usableContentHeight = max(0, contentHeight + getOpenContentTopLift())
                        let fixedPageHeight = min(max(0, geo.size.height), OpenNotchLayoutMetrics.contentViewportHeight)
                        let fixedPageYOffset = getOpenContentTopLift() + max(0, contentHeight - fixedPageHeight) / 2

                        let enabledViews = presentationEnabledViews
                        let enabledCount = enabledViews.count

                        Group {
                            if enabledCount <= 1 {
                                let singlePageHeight = (enabledViews.first ?? .home) == .home
                                    ? contentHeight
                                    : fixedPageHeight
                                let singlePageYOffset = (enabledViews.first ?? .home) == .home
                                    ? 0
                                    : fixedPageYOffset
                                switch enabledViews.first ?? .home {
                                case .home:
                                    NotchHomeView(
                                        albumArtNamespace: albumArtNamespace,
                                        albumRevealCompensationProgress: hasNowPlayingLiveActivityActive ? revealP : 1
                                    )
                                    .frame(width: contentWidth, height: singlePageHeight, alignment: .topLeading)
                                    .offset(y: singlePageYOffset)
                                    .onAppear { coordinator.currentView = .home }
                                case .shelf:
                                    ShelfView(isPagerScrollEnabled: .constant(false))
                                        .frame(width: contentWidth, height: singlePageHeight, alignment: .topLeading)
                                        .offset(y: singlePageYOffset)
                                        .onAppear { coordinator.currentView = .shelf }
                                case .third:
                                    NotchThirdView(isPagerScrollEnabled: .constant(false))
                                        .frame(width: contentWidth, height: singlePageHeight, alignment: .topLeading)
                                        .offset(y: singlePageYOffset)
                                        .onAppear { coordinator.currentView = .third }
                                }
                            } else {
                                NotchPagerDynamic(
                                    selection: $coordinator.currentView,
                                    isScrollEnabled: .constant(isPagerScrollEffectivelyEnabled),
                                    enabledViews: enabledViews,
                                    fixedPageHeight: fixedPageHeight,
                                    fixedPageYOffset: fixedPageYOffset,
                                    page: { view in
                                        switch view {
                                        case .home:
                                            AnyView(
                                                NotchHomeView(
                                                    albumArtNamespace: albumArtNamespace,
                                                    albumRevealCompensationProgress: hasNowPlayingLiveActivityActive ? revealP : 1
                                                )
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            )
                                        case .shelf:
                                            AnyView(
                                                ShelfView(isPagerScrollEnabled: $isPagerScrollEnabled)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            )
                                        case .third:
                                            AnyView(
                                                NotchThirdView(isPagerScrollEnabled: $isPagerScrollEnabled)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            )
                                        }
                                    }
                                )
                            }
                        }
                        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                        .offset(y: -getOpenContentTopLift() - openContentVerticalLiftComputed)
                        .scaleEffect(openContentLayoutScaleComputed, anchor: .top)
                        .environment(\.openNotchContentUsableHeight, usableContentHeight)
                        .environment(\.openNotchLayoutCompression, openLayoutCompressionComputed)
                        .clipShape(BottomBleedClipShape(extraBottom: getOpenContentBottomBleed()))
                        .compositingGroup() // Render the pager as an independent group before parent clipping.
                        .animation(NotchMotion.notchLayout, value: reservedTrailing)
                    }

                    if showCalendar {
                        CalendarOverlayView(monthLeadingSafetyInset: calendarMonthLeadingSafetyInset)
                            .environmentObject(vm)
                            .frame(width: calendarOverlayTotalWidth, height: OpenNotchLayoutMetrics.contentViewportHeight)
                            .offset(x: calendarToCameraExitOffsetX)
                            .clipShape(BottomTrailingBleedClipShape(extraBottom: getOpenContentBottomBleed(), extraTrailing: 14))
                            .transition(calendarOverlayTransition)
                            .zIndex(998)
                    }

                    if isCameraOverlayVisible {
                        CameraPreviewView(webcamManager: webcamManager)
                            .padding(.trailing, 7)
                            .transition(cameraOverlayTransition)
                            .zIndex(999)
                    }
                }
                .animation(
                    (isSwitchingOverlay && overlaySwitchDirection == .toCamera) ? nil : animationSpring,
                    value: showCalendar
                )
                .animation(
                    (isSwitchingOverlay && overlaySwitchDirection == .toCamera) ? nil : animationSpring,
                    value: vm.isCameraExpanded
                )
                .offset(y: -52 * (1 - contentLiftEase))
                .scaleEffect(x: contentScaleX, y: contentScaleY, anchor: .top)
                .blur(radius: contentBlur)
                .opacity(0.72 + (0.28 * contentRevealEase))
                .zIndex(1)
                .allowsHitTesting(true)
                .opacity(
                    gestureProgress != 0
                    ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3)
                    : 1.0
                )
            }
        }
    }

 // MARK: - Closed activity: Bluetooth

    private typealias BluetoothDeviceKind = BluetoothActivityManager.BluetoothDeviceKind

    @ViewBuilder
    private func BluetoothLiveActivity(
        deviceName: String,
        kind: BluetoothDeviceKind,
        batteryPercent: Int?,
        isExpanded: Bool,
        onHoverZonesChanged: @escaping (_ hoveringSides: Bool, _ hoveringCenter: Bool) -> Void
    ) -> some View {
        BluetoothLiveActivityView(
            vm: vm,
            deviceName: deviceName,
            kind: kind,
            batteryPercent: batteryPercent,
            isExpanded: isExpanded,
            closedTopCornerInset: cornerRadiusInsets.closed.top,
            onHoverZonesChanged: onHoverZonesChanged
        )
    }

 // MARK: - AirPods Pro icon (looping video)

    private final class AirPodsProVideoPlayerModel: ObservableObject {
        let player: AVPlayer = AVPlayer()

        private var endObserver: NSObjectProtocol?
        private var hasSetupItem = false

        init() {
            player.isMuted = true
            player.actionAtItemEnd = .none
        }

        func start() {
            if !hasSetupItem {
                guard let url = Bundle.main.url(forResource: "AirPods_Pro3", withExtension: "mov") else {
                    return
                }
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                hasSetupItem = true

                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.player.seek(to: .zero)
                    self.player.play()
                }
            }

            player.play()
        }

        func stop() {
            player.pause()
        }

        deinit {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
        }
    }

    
 // MARK: - DualSense icon (looping video)

    private final class DualSenseVideoPlayerModel: ObservableObject {
        let player: AVPlayer = AVPlayer()

        private var endObserver: NSObjectProtocol?
        private var hasSetupItem = false

        init() {
            player.isMuted = true
            player.actionAtItemEnd = .none
        }

        func start() {
            if !hasSetupItem {
                guard let url = Bundle.main.url(forResource: "AnimationApple_PS5Controller-HEVC", withExtension: "mov") else {
                    return
                }
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                hasSetupItem = true

                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.player.seek(to: .zero)
                    self.player.play()
                }
            }

            player.play()
        }

        func stop() {
            player.pause()
        }

        deinit {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
        }
    }

    private struct DualSenseVideoNSView: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = .none
            view.videoGravity = .resizeAspect
            return view
        }

        func updateNSView(_ nsView: AVPlayerView, context: Context) {
            if nsView.player !== player {
                nsView.player = player
            }
        }
    }

     struct DualSenseVideoIcon: View {
        let side: CGFloat
        @StateObject private var model = DualSenseVideoPlayerModel()

        var body: some View {
            DualSenseVideoNSView(player: model.player)
                .frame(width: side, height: side)
                .clipped()
                .cornerRadius(6)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
                .accessibilityLabel("DualSense")
        }
    }

private struct AirPodsProVideoNSView: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = .none
            view.videoGravity = .resizeAspect
            return view
        }

        func updateNSView(_ nsView: AVPlayerView, context: Context) {
            if nsView.player !== player {
                nsView.player = player
            }
        }
    }

     struct AirPodsProVideoIcon: View {
        let side: CGFloat
        @StateObject private var model = AirPodsProVideoPlayerModel()

        var body: some View {
            AirPodsProVideoNSView(player: model.player)
                .frame(width: side, height: side)
                .clipped()
                .cornerRadius(6)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
                .accessibilityLabel("AirPods Pro")
        }
    }

     struct BatteryRing: View {
        let percent: Int
        let isExpanded: Bool

        var body: some View {
            let clamped = max(0, min(100, percent))

            return GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)

                let trackColor = Color(red: 0x3F / 255.0, green: 0x61 / 255.0, blue: 0x4C / 255.0)
                let fillColor  = Color(red: 0x53 / 255.0, green: 0xE2 / 255.0, blue: 0x7E / 255.0)

                let lw: CGFloat = {
                    if isExpanded {
                        return max(2, s * 0.095)
                    } else {
                        return 2
                    }
                }()

                let pad: CGFloat = {
                    if isExpanded {
                        return max(1, lw * 0.15)
                    } else {
                        return 2
                    }
                }()

                ZStack {
                    Circle()
                        .stroke(trackColor, lineWidth: lw)

                    Circle()
                        .trim(from: 0, to: CGFloat(clamped) / 100.0)
                        .stroke(
                            fillColor,
                            style: StrokeStyle(lineWidth: lw, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    if isExpanded {
                        Text("\(clamped)")
                            .font(.system(size: max(9, s * 0.33), weight: .semibold, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(fillColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(pad)
            }
            .accessibilityLabel("Battery")
            .accessibilityValue("\(clamped) percent")
        }
    }

 // MARK: - Closed activity: Focus / File Tray

    @ViewBuilder
    private func bluetoothTakeoverExitOverlayView(_ kind: BluetoothTakeoverExitKind) -> some View {
        switch kind {
        case .focus:
            closedFocusLiveActivityView()
        case .timer:
            closedTimerLiveActivityView()
        case .fileTray:
            FileTrayLiveActivity(count: fileTrayCount, isCompactMode: isFileTrayCompactMode)
        case .music:
            MusicLiveActivity(
                isCompactMode: isNowPlayingCompactMode,
                showPauseOnRight: false,
                albumArtGeometryID: "albumArtBluetoothTakeoverOverlay",
                onHoverZonesChanged: { _, _, _ in },
                onPauseRequested: {}
            )
        }
    }

    @ViewBuilder
    private func bluetoothClosedNotificationView() -> some View {
        BluetoothLiveActivity(
            deviceName: bluetoothModel.lastConnectedAliasName ?? bluetoothModel.lastConnectedDeviceName,
            kind: bluetoothModel.lastConnectedDeviceKind,
            batteryPercent: bluetoothModel.lastConnectedBatteryPercent,
            isExpanded: isBluetoothPopupHovering,
            onHoverZonesChanged: { hoveringSides, hoveringCenter in
                if hoveringSides {
                    bluetoothPopupCloseTask?.cancel()
                    bluetoothPopupCloseTask = nil
                    bluetoothSidesHoverTask?.cancel()
                    bluetoothCenterHoverTask?.cancel()

                    if !isBluetoothSidesHovering {
                        isBluetoothSidesHovering = true
                    }
                    if isBluetoothCenterHovering {
                        isBluetoothCenterHovering = false
                    }

                    if coordinator.expandingView.show && coordinator.expandingView.type == .bluetooth {
                        coordinator.pauseExpandingViewAutoHide()
                    }

                    if !isBluetoothPopupHovering {
                        isBluetoothPopupTransitioning = true
                        bluetoothTransitionTask?.cancel()
                        bluetoothTransitionTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(260))
                            guard !Task.isCancelled else { return }
                            self.isBluetoothPopupTransitioning = false
                        }
                        withAnimation(NotchMotion.popupHover) {
                            isBluetoothPopupHovering = true
                        }
                    }
                    return
                }

                if hoveringCenter {
                    bluetoothPopupCloseTask?.cancel()
                    bluetoothPopupCloseTask = nil
                    bluetoothSidesHoverTask?.cancel()
                    bluetoothCenterHoverTask?.cancel()
                    isBluetoothCenterHovering = true

                    if isBluetoothPopupHovering || isBluetoothPopupTransitioning {
                        if coordinator.expandingView.show && coordinator.expandingView.type == .bluetooth {
                            coordinator.pauseExpandingViewAutoHide()
                        }
                        if isBluetoothSidesHovering {
                            isBluetoothSidesHovering = false
                        }
                        return
                    }

                    if isBluetoothSidesHovering {
                        isBluetoothSidesHovering = false
                        if coordinator.expandingView.show && coordinator.expandingView.type == .bluetooth {
                            coordinator.resumeExpandingViewAutoHide()
                        }
                    }

                    if vm.notchState == .closed,
                       Defaults[.openNotchOnHover],
                       !isBluetoothSidesHovering,
                       !isBluetoothPopupHovering,
                       !isBluetoothPopupTransitioning {
                        bluetoothCenterHoverTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                            guard !Task.isCancelled else { return }
                            guard self.isBluetoothCenterHovering,
                                  !self.isBluetoothSidesHovering,
                                  !self.isBluetoothPopupHovering,
                                  !self.isBluetoothPopupTransitioning,
                                  self.vm.notchState == .closed,
                                  self.isBluetoothClosedNotificationShowing else { return }
                            self.doOpen()
                        }
                    }
                } else {
                    isBluetoothCenterHovering = false
                    bluetoothCenterHoverTask?.cancel()

                    if isBluetoothSidesHovering || isBluetoothPopupHovering {
                        self.isBluetoothSidesHovering = false
                        if self.coordinator.expandingView.show && self.coordinator.expandingView.type == .bluetooth {
                            self.coordinator.resumeExpandingViewAutoHide()
                        }
                        scheduleBluetoothPopupCloseIfNeeded(delayMs: 120)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func closedFocusLiveActivityView() -> some View {
        FocusLiveActivity(
            notchWidth: vm.closedNotchSize.width,
            baseHeight: vm.effectiveClosedNotchHeight,
            symbolName: focusActivitySymbolName,
            statusText: focusActivityStatusText,
            tint: focusActivityTint,
            layout: focusActivityLayout
        )
    }

    @ViewBuilder
    private func closedDetachedBridgeArcView() -> some View {
        let w = closedDetachedBridgeWidth
        let archH = closedDetachedBridgeHeight
        let totalH = max(vm.effectiveClosedNotchHeight, archH + 2)
        let line = closedDetachedBridgeLineWidth
        if w > 0.01, archH > 0.01, totalH > 0.01 {
            let halfLine = line * 0.5
            let baseline = max(halfLine + 0.5, totalH - halfLine - 2.5)
            let left = CGPoint(x: halfLine, y: baseline)
            let right = CGPoint(x: w - halfLine, y: baseline)
            let peakY = baseline - archH * 0.30
            let peakLeft = CGPoint(x: w * 0.45, y: peakY)
            let peakRight = CGPoint(x: w * 0.55, y: peakY)

            let leftC1 = CGPoint(x: w * 0.12, y: baseline)
            let leftC2 = CGPoint(x: w * 0.28, y: peakY)
            let topC1 = CGPoint(x: w * 0.475, y: peakY)
            let topC2 = CGPoint(x: w * 0.525, y: peakY)
            let rightC1 = CGPoint(x: w * 0.72, y: peakY)
            let rightC2 = CGPoint(x: w * 0.88, y: baseline)

            ZStack {
                Path { path in
                    path.move(to: left)
                    path.addCurve(to: peakLeft, control1: leftC1, control2: leftC2)
                    path.addCurve(to: peakRight, control1: topC1, control2: topC2)
                    path.addCurve(to: right, control1: rightC1, control2: rightC2)
                    path.addLine(to: CGPoint(x: right.x, y: 0))
                    path.addLine(to: CGPoint(x: left.x, y: 0))
                    path.closeSubpath()
                }
                .fill(.black)

                Path { path in
                    path.move(to: left)
                    path.addCurve(to: peakLeft, control1: leftC1, control2: leftC2)
                    path.addCurve(to: peakRight, control1: topC1, control2: topC2)
                    path.addCurve(to: right, control1: rightC1, control2: rightC2)
                }
                .stroke(
                    .black,
                    style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(width: w, height: totalH)
            .offset(y: 0)
        }
    }

    @ViewBuilder
    private func closedDetachedCompactActivity(kind: ClosedActivityKind) -> some View {
        let w = closedDetachedCompactBubbleWidth
        let h = vm.effectiveClosedNotchHeight
        if w > 0.01, h > 0.01 {
            ZStack {
                Rectangle()
                    .fill(.black)
                DetachedSecondaryContentFade(
                    baseOpacity: secondaryDetachedContentOpacity,
                    trigger: detachedSecondaryAppearToken,
                    appearDelayMs: 90,
                    appearDuration: 0.30
                ) {
                    closedSecondaryCompactActivity(kind: kind)
                }
            }
            .frame(width: w, height: h)
            .clipShape(
                NotchShape(
                    topCornerRadius: detachedCompactTopRadius,
                    bottomCornerRadius: detachedCompactBottomRadius
                )
            )
        }
    }

    @ViewBuilder
    private func closedSecondaryCompactActivity(kind: ClosedActivityKind) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack(spacing: 0) {
            switch kind {
            case .music:
                AlbumArtFlipView(
                    currentImage: musicManager.albumArt,
                    eventID: musicManager.albumArtFlipEventID,
                    incomingImage: musicManager.albumArtFlipImage,
                    direction: musicManager.albumArtFlipDirection,
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                    geometryID: "albumArtDetachedCompact",
                    namespace: albumArtNamespace
                )
                .frame(width: side, height: side)

            case .focus:
                focusSymbolGlyph(focusActivitySymbolName, size: side, tint: focusActivityTint)

            case .fileTray:
                let trayBlue = Color(nsColor: .systemBlue)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(trayBlue.opacity(0.30))
                    .frame(width: side, height: side)
                    .overlay {
                        Text("\(fileTrayCount)")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(trayBlue.opacity(0.98))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }

            case .timer:
                timerCompactRingView(size: side)
                    .frame(width: side, height: side)

            case .bluetooth:
                if let p = bluetoothModel.lastConnectedBatteryPercent {
                    BatteryRing(percent: p, isExpanded: false)
                        .frame(width: side, height: side)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.95))
                        .frame(width: side, height: side)
                }
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .frame(width: side, alignment: .center)
    }

    @ViewBuilder
    private func timerCompactRingView(size: CGFloat) -> some View {
        let ringSize: CGFloat = timerActivityLayout.fontSize + 5
        let ringLineWidth: CGFloat = 2.2
        let needleThickness: CGFloat = 2.49
        let clamped = max(0, min(1, timerActivityProgressRemaining))
        let angle = -90 + (360 * clamped)

        ZStack {
            Circle()
                .stroke(Color(red: 0x5A / 255.0, green: 0x41 / 255.0, blue: 0x22 / 255.0), lineWidth: ringLineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    Color(nsColor: .systemOrange).opacity(0.95),
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timerActivityProgressRemaining)

            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2
                let pathRadius = radius - ringLineWidth / 2
                let inset: CGFloat = 1.2
                let needleLength = max(2, pathRadius - needleThickness / 2 - inset)

                RoundedRectangle(cornerRadius: needleThickness / 2, style: .continuous)
                    .fill(Color(nsColor: .systemOrange))
                    .frame(width: needleLength, height: needleThickness)
                    .modifier(DetachedTimerNeedlePivotModifier(length: needleLength, pivotFraction: 0.18, angle: angle))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .animation(.linear(duration: 1), value: timerActivityProgressRemaining)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .frame(width: size, height: size, alignment: .center)
    }

    @ViewBuilder
    private func FileTrayLiveActivity(count: Int, isCompactMode: Bool) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let trayBlue = Color(nsColor: .systemBlue)

        HStack(spacing: 0) {
            if !isCompactMode {
                ZStack {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(trayBlue.opacity(0.95))
                }
                .frame(width: side, height: side)
            }

            Rectangle()
                .fill(.black)
                .frame(width: isCompactMode
                       ? (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top + side + 10)
                       : (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top))

            ZStack {
                if isCompactMode {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(trayBlue.opacity(0.30))
                        .frame(width: side, height: side)
                        .overlay {
                            Text("\(count)")
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(trayBlue.opacity(0.98))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                } else {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(trayBlue.opacity(0.98))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func QuartzFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private func nowPlayingEdgeTrackingMetrics(isCompactMode: Bool) -> NowPlayingEdgeTrackingMetrics {
        let hoverTopExtension: CGFloat = 26
        let hoverLeftExtension: CGFloat = 18
        let sideWidth = max(0, vm.effectiveClosedNotchHeight - 12 + gestureProgress / 2)
        let centerSegmentWidth = isCompactMode
            ? (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top + sideWidth + 10)
            : (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)
        let leftSegmentWidth = isCompactMode ? 0 : sideWidth
        let rightSegmentWidth = sideWidth

        let hitLeftWidth = isCompactMode ? 0 : max(leftSegmentWidth + hoverLeftExtension, 32)
        let hitCenterWidth = max(0, centerSegmentWidth)
        let hitRightWidth = max(rightSegmentWidth, 44)
        let hitTotalWidth = max(0, hitLeftWidth + hitCenterWidth + hitRightWidth)

        return .init(
            leftEdgeWidth: hitLeftWidth + hoverLeftExtension,
            rightEdgeWidth: hitRightWidth,
            totalWidth: hitTotalWidth,
            totalHeight: vm.effectiveClosedNotchHeight + hoverTopExtension,
            xOffset: isCompactMode ? 0 : -hoverLeftExtension,
            yOffset: -hoverTopExtension
        )
    }

    private func pointerIsInNowPlayingEdgeZone() -> Bool {
        guard shouldShowMusicActivityClosed else { return false }
        guard vm.notchState == .closed else { return false }
        guard let window = hostWindow, let contentView = window.contentView else { return false }

        let metrics = nowPlayingEdgeTrackingMetrics(isCompactMode: isNowPlayingCompactMode)
        let pointer = window.mouseLocationOutsideOfEventStream

        let chinMinX = contentView.bounds.midX - (displayedChinWidthComputed / 2) + closedChinOffsetX
        let trackingMinX = chinMinX + metrics.xOffset
        let trackingMaxX = trackingMinX + metrics.totalWidth

        guard pointer.x >= trackingMinX, pointer.x <= trackingMaxX else { return false }

        let hoveringLeft = pointer.x <= (trackingMinX + metrics.leftEdgeWidth)
        let hoveringRight = pointer.x >= (trackingMaxX - metrics.rightEdgeWidth)
        return hoveringLeft || hoveringRight
    }

    private func closedLiveActivityEdgeZoneWidths() -> (left: CGFloat, right: CGFloat)? {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)

        if isBatteryClosedNotificationShowing {
            let edge = batteryClosedSideWidth + batteryClosedSidePadding
            return (edge, edge)
        }

        if isBluetoothClosedNotificationShowing {
            let edge = side + 10
            return (edge, edge)
        }

        if shouldShowFocusActivityClosed {
            return (
                focusActivityLayout.leftPadding + focusActivityLayout.leftWidth,
                focusActivityLayout.rightPadding + focusActivityLayout.rightWidth
            )
        }

        if shouldShowTimerActivityClosed {
            if isTimerCompactMode {
                return (timerActivityLayout.sidePadding + timerActivityLayout.leftWidth + 2, 0)
            }
            return (
                timerActivityLayout.sidePadding + timerActivityLayout.leftWidth,
                timerActivityLayout.sidePadding + timerActivityLayout.rightWidth
            )
        }

        if shouldShowFileTrayActivityClosed {
            if isFileTrayCompactMode {
                return (0, side + 10)
            }
            return (side + 10, side + 10)
        }

        if shouldShowMusicActivityClosed {
            if isNowPlayingCompactMode {
                return (0, side + 10)
            }
            return (side + 10, side + 10)
        }

        return nil
    }

    private func pointerIsInClosedLiveActivityEdgeZone() -> Bool {
        guard vm.notchState == .closed else { return false }
        guard let edgeWidths = closedLiveActivityEdgeZoneWidths() else { return false }
        guard let window = hostWindow, let contentView = window.contentView else { return false }

        let pointer = window.mouseLocationOutsideOfEventStream
        let chinMinX = contentView.bounds.midX - (displayedChinWidthComputed / 2) + closedChinOffsetX
        let chinMaxX = chinMinX + displayedChinWidthComputed

        guard pointer.x >= chinMinX, pointer.x <= chinMaxX else { return false }

        let hoveringLeft = edgeWidths.left > 0 && pointer.x <= (chinMinX + edgeWidths.left)
        let hoveringRight = edgeWidths.right > 0 && pointer.x >= (chinMaxX - edgeWidths.right)
        return hoveringLeft || hoveringRight
    }

    @ViewBuilder
    func MusicLiveActivity(
        isCompactMode: Bool,
        showPauseOnRight: Bool,
        albumArtGeometryID: String = "albumArt",
        onHoverZonesChanged: @escaping (_ hoveringLeft: Bool, _ hoveringRight: Bool, _ hoveringCenter: Bool) -> Void,
        onPauseRequested: @escaping () -> Void
    ) -> some View {
        let sideWidth = max(0, vm.effectiveClosedNotchHeight - 12 + gestureProgress / 2)
        let centerSegmentWidth = isCompactMode
            ? (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top + sideWidth + 10)
            : (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)
        let rightSegmentWidth = sideWidth
        let waveformTintTop: Color =
            (Defaults[.coloredSpectrogram]
             ? Color(nsColor: musicManager.spectrogramTopColor)
             : Color.gray).opacity(0.95)
        let waveformTintBottom: Color =
            (Defaults[.coloredSpectrogram]
             ? Color(nsColor: musicManager.spectrogramBottomColor)
             : Color.gray).opacity(0.95)
        let waveformArtwork: NSImage? = Defaults[.coloredSpectrogram] ? musicManager.albumArt : nil

        HStack {
            if !isCompactMode {
                AlbumArtFlipView(
                    currentImage: musicManager.albumArt,
                    eventID: musicManager.albumArtFlipEventID,
                    incomingImage: musicManager.albumArtFlipImage,
                    direction: musicManager.albumArtFlipDirection,
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                    geometryID: albumArtGeometryID,
                    namespace: albumArtNamespace
                )
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )
            }

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show && coordinator.expandingView.type == .music {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor)
                                : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(0)

                            Spacer(minLength: vm.closedNotchSize.width)

                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor)
                                    : Color.gray
                                )
                                .opacity(0)
                        }
                    }
                )
                .frame(width: centerSegmentWidth)

            HStack {
                if isCompactMode {
                    AlbumArtFlipView(
                        currentImage: musicManager.albumArt,
                        eventID: musicManager.albumArtFlipEventID,
                        incomingImage: musicManager.albumArtFlipImage,
                        direction: musicManager.albumArtFlipDirection,
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                        geometryID: albumArtGeometryID,
                        namespace: albumArtNamespace
                    )
                } else {
                    NowPlayingAudioGlyph(
                        progress: showPauseOnRight ? 1 : 0,
                        isPlaying: musicManager.isPlaying,
                        shouldAnimateWaveform: musicManager.isPlaying && musicManager.playbackRate > 0.01,
                        tintTop: waveformTintTop,
                        tintBottom: waveformTintBottom,
                        artwork: waveformArtwork
                    )
                    .frame(width: 24, height: 24, alignment: .center)
                    .animation(.spring(response: 0.34, dampingFraction: 0.87), value: showPauseOnRight)
                    .animation(.spring(response: 0.24, dampingFraction: 0.85), value: musicManager.isPlaying)
                }
            }
            .frame(
                width: rightSegmentWidth,
                height: max(0, vm.effectiveClosedNotchHeight - 12),
                alignment: .center
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        guard showPauseOnRight else { return }
                        onPauseRequested()
                    }
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onHover { hovering in
            if !hovering {
                onHoverZonesChanged(false, false, false)
            }
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf]
            && NotchViews.shelf.visibilityMode != .disabled
            && vm.notchState == .closed
        {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        isTargeted: $vm.dragDetectorTargeting) { providers in
                    vm.dropEvent = true
                    ShelfStateViewModel.shared.load(providers)
                    return true
                }
        } else {
            EmptyView()
        }
    }



 // MARK: - Timer proximity hover (multi-display robustness)

    private func updateTimerProximityHover() {
        guard shouldShowTimerActivityClosed, vm.notchState == .closed else {
            isTimerProximityHovering = false
            return
        }
        guard let w = hostWindow else {
            isTimerProximityHovering = false
            return
        }

        let mouse = NSEvent.mouseLocation
        let f = w.frame

        let yAboveTolerance: CGFloat = 12
        let yBelowTolerance: CGFloat = 4

        let leftZoneW  = timerActivityLayout.sidePadding + timerActivityLayout.leftWidth
        let rightZoneW = timerActivityLayout.sidePadding + timerActivityLayout.rightWidth

        let leftRect = CGRect(
            x: f.minX,
            y: f.minY - yBelowTolerance,
            width: leftZoneW,
            height: f.height + yAboveTolerance + yBelowTolerance
        )

        let rightRect = CGRect(
            x: f.maxX - rightZoneW,
            y: f.minY - yBelowTolerance,
            width: rightZoneW,
            height: f.height + yAboveTolerance + yBelowTolerance
        )

        let isInLeftRect = leftRect.contains(mouse)
        let isInRightRect = rightRect.contains(mouse)
        
        isTimerProximityHovering = isInLeftRect || isInRightRect
    }

    private func scheduleTimerPopupRearmAfterClose() {
        timerPopupRearmTask?.cancel()
        let unlockAt = suppressTimerPopupAutoOpenUntil

        timerPopupRearmTask = Task { @MainActor in
            let delay = max(0, unlockAt.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }

            isTimerPopupHoverArmed = true

            guard vm.notchState == .closed,
                  shouldShowTimerActivityClosed,
                  isTimerSidesHovering,
                  !isTimerPopupHovering,
                  !isTimerExpandedHovering else { return }

            isTimerPopupTransitioning = true
            timerTransitionTask?.cancel()
            timerTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                isTimerPopupTransitioning = false
            }
            withAnimation(NotchMotion.popupHover) {
                isTimerPopupHovering = true
            }
        }
    }

    private func closeTimerPopupIfNeeded() {
        guard isTimerPopupHovering else { return }
        isTimerPopupTransitioning = true
        timerTransitionTask?.cancel()
        timerTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            isTimerPopupTransitioning = false
        }
        withAnimation(NotchMotion.popupHover) {
            isTimerPopupHovering = false
        }
    }

    private func scheduleTimerPopupCloseIfNeeded(delayMs: UInt64 = 140) {
        timerPopupCloseTask?.cancel()
        timerPopupCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delayMs)))
            guard !Task.isCancelled else {
                timerPopupCloseTask = nil
                return
            }
            guard vm.notchState == .closed else {
                timerPopupCloseTask = nil
                return
            }
            if keepTimerPopupOpenForFinishedAlert {
                timerPopupCloseTask = nil
                return
            }
            if isTimerSidesHovering || isTimerExpandedHovering || isTimerProximityHovering || isHovering {
                timerPopupCloseTask = nil
                return
            }
            closeTimerPopupIfNeeded()
            timerPopupCloseTask = nil
        }
    }

    private func closeBluetoothPopupIfNeeded() {
        guard isBluetoothPopupHovering else { return }
        isBluetoothPopupTransitioning = true
        bluetoothTransitionTask?.cancel()
        bluetoothTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            isBluetoothPopupTransitioning = false
        }
        withAnimation(NotchMotion.popupHover) {
            isBluetoothPopupHovering = false
        }
    }

    private func scheduleBluetoothPopupCloseIfNeeded(delayMs: UInt64 = 120) {
        bluetoothPopupCloseTask?.cancel()
        bluetoothPopupCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delayMs)))
            guard !Task.isCancelled else {
                bluetoothPopupCloseTask = nil
                return
            }
            guard vm.notchState == .closed else {
                bluetoothPopupCloseTask = nil
                return
            }
            if isBluetoothSidesHovering || isBluetoothCenterHovering || isHovering {
                bluetoothPopupCloseTask = nil
                return
            }
            closeBluetoothPopupIfNeeded()
            bluetoothPopupCloseTask = nil
        }
    }

    private func doOpen() {
        if isBatteryClosedNotificationShowing { return }
        if isBluetoothClosedNotificationShowing
            && (isBluetoothSidesHovering || isBluetoothPopupHovering || isBluetoothPopupTransitioning) { return }
        let isNowPlayingCenterOpen =
            shouldShowMusicActivityClosed
            && !isNowPlayingLeftHovering
            && !isNowPlayingRightHovering
        openingFromNowPlayingCenterHover = isNowPlayingCenterOpen

        if pageUseLiquidGlassBackground {
            keepLiquidVisualDuringClose = true
            liquidVisualBlend = max(liquidVisualBlend, 0.35)
            liquidStrokeReveal = max(liquidStrokeReveal, 0.05)
            withAnimation(.easeOut(duration: 0.26)) {
                liquidStrokeReveal = 1
            }
        }
        ignoreHoverExitUntil = Date().addingTimeInterval(isNowPlayingCenterOpen ? 0.48 : 0.25)
        vm.open()
    }

    private func restartOpenContentRevealAnimation() {
        openContentRevealTask?.cancel()
        openContentRevealTask = nil
        var resetTransaction = Transaction()
        resetTransaction.animation = nil
        withTransaction(resetTransaction) {
            openContentRevealProgress = 0
            openHeaderWidthProgress = 0
        }

        openContentRevealTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else {
                openContentRevealTask = nil
                return
            }
            guard vm.notchState == .open else {
                openContentRevealTask = nil
                return
            }
            withAnimation(NotchMotion.openContentReveal) {
                openContentRevealProgress = 1
            }
            withAnimation(NotchMotion.openHeaderWidth) {
                openHeaderWidthProgress = 1
            }
            openContentRevealTask = nil
        }
    }

    private func closedPopupHoverBoundsContainsMouse() -> Bool {
        guard let w = hostWindow else { return true }
        let f = w.frame
        let bounds = CGRect(
            x: f.minX - 12,
            y: f.minY - 8,
            width: f.width + 24,
            height: f.height + 22
        )
        return bounds.contains(NSEvent.mouseLocation)
    }

    private func ensureClosedPopupFailsafeRunning() {
        guard closedPopupFailsafeTask == nil else { return }
        closedPopupFailsafeTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { break }

                if vm.notchState != .closed || (!isTimerPopupHovering && !isBluetoothPopupHovering) {
                    break
                }

                if isTimerPopupHovering && keepTimerPopupOpenForFinishedAlert {
                    continue
                }

                if closedPopupHoverBoundsContainsMouse() { continue }

                timerSidesHoverTask?.cancel()
                bluetoothSidesHoverTask?.cancel()
                bluetoothCenterHoverTask?.cancel()
                withAnimation(NotchMotion.popupHover) {
                    isTimerPopupHovering = false
                    isTimerSidesHovering = false
                    isTimerExpandedHovering = false
                    isTimerProximityHovering = false
                    isBluetoothPopupHovering = false
                    isBluetoothSidesHovering = false
                    isBluetoothCenterHovering = false
                }
                break
            }
            closedPopupFailsafeTask = nil
        }
    }

    private func updateNowPlayingSneakPeekHoverState() {
        let shouldForceMusicSneakPeek = isNowPlayingLeftHovering
            && shouldShowMusicActivityClosed
            && vm.notchState == .closed

        if shouldForceMusicSneakPeek {
            nowPlayingSneakPeekCloseTask?.cancel()
            nowPlayingSneakPeekCloseTask = nil
            if !isNowPlayingSneakPeekForcedByHover {
                isNowPlayingSneakPeekForcedByHover = true
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .music,
                    duration: 60,
                    animationOverride: .spring(duration: 0.24, bounce: 0.03, blendDuration: 0.03)
                )
            }
            startNowPlayingSneakPeekWatchdogIfNeeded()
            return
        }

        guard isNowPlayingSneakPeekForcedByHover else { return }
        scheduleNowPlayingSneakPeekCloseIfNeeded()
        startNowPlayingSneakPeekWatchdogIfNeeded()
    }

    private func scheduleNowPlayingSneakPeekCloseIfNeeded() {
        nowPlayingSneakPeekCloseTask?.cancel()
        nowPlayingSneakPeekCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else {
                nowPlayingSneakPeekCloseTask = nil
                return
            }
            guard isNowPlayingSneakPeekForcedByHover else {
                nowPlayingSneakPeekCloseTask = nil
                return
            }
            guard shouldShowMusicActivityClosed, vm.notchState == .closed else {
                isNowPlayingSneakPeekForcedByHover = false
                if coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music {
                    coordinator.toggleSneakPeek(status: false, type: .music)
                }
                nowPlayingSneakPeekCloseTask = nil
                return
            }
            guard !isNowPlayingLeftHovering else {
                nowPlayingSneakPeekCloseTask = nil
                return
            }

            isNowPlayingSneakPeekForcedByHover = false
            if coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music {
                coordinator.toggleSneakPeek(status: false, type: .music)
            }
            nowPlayingSneakPeekCloseTask = nil
        }
    }

    private func startNowPlayingSneakPeekWatchdogIfNeeded() {
        guard nowPlayingSneakPeekWatchdogTask == nil else { return }
        nowPlayingSneakPeekWatchdogTask = Task { @MainActor in
            var staleHoverTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { break }

                guard isNowPlayingSneakPeekForcedByHover else { break }
                guard shouldShowMusicActivityClosed, vm.notchState == .closed else {
                    isNowPlayingSneakPeekForcedByHover = false
                    if coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music {
                        coordinator.toggleSneakPeek(status: false, type: .music)
                    }
                    break
                }

                let pointerInsidePopupVicinity = closedPopupHoverBoundsContainsMouse()
                if isNowPlayingLeftHovering && !pointerInsidePopupVicinity {
                    staleHoverTicks += 1
                    if staleHoverTicks >= 2 {
                        isNowPlayingLeftHovering = false
                        scheduleNowPlayingSneakPeekCloseIfNeeded()
                        staleHoverTicks = 0
                    }
                } else {
                    staleHoverTicks = 0
                }
            }
            nowPlayingSneakPeekWatchdogTask = nil
        }
    }

 // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        if lockScreenState.isLocked { return }

        if isBluetoothClosedNotificationShowing {
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        if isBatteryClosedNotificationShowing { return }

        if shouldShowTimerActivityClosed && (isTimerPopupHovering || isTimerSidesHovering || isTimerProximityHovering) { return }
        if pointerIsInClosedLiveActivityEdgeZone() { return }

        let timerHoverBlocksOpen = shouldShowTimerActivityClosed
            && (isTimerPopupHovering || isTimerSidesHovering || isTimerProximityHovering)
        let nowPlayingHoverBlocksOpen = shouldShowMusicActivityClosed
            && (isNowPlayingLeftHovering || isNowPlayingRightHovering || pointerIsInNowPlayingEdgeZone())

        hoverTask?.cancel()

        if hovering {
            deactivateFrozenHoverZone()
            withAnimation(animationSpring) { isHovering = true }

            if vm.notchState == .closed && Defaults[.enableHaptics] && Date() >= suppressNotchHoverHapticUntil {
                let now = Date()
                if now.timeIntervalSince(lastNotchHoverHapticAt) >= 0.28 {
                    lastNotchHoverHapticAt = now
                    haptics.toggle()
                }
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  !isBatteryClosedNotificationShowing,
                  Date() >= suppressNotchOpenUntilAfterTimerPopupClose,
                  !timerHoverBlocksOpen,
                  !nowPlayingHoverBlocksOpen,
                  Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    let timerStillBlocks = self.shouldShowTimerActivityClosed
                        && (self.isTimerSidesHovering || self.isTimerProximityHovering)
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show,
                          !self.isBatteryClosedNotificationShowing,
                          !timerStillBlocks,
                          !(self.shouldShowMusicActivityClosed && (self.isNowPlayingLeftHovering || self.isNowPlayingRightHovering)) else { return }
                    self.doOpen()
                }
            }
        } else {
            if Date() < ignoreHoverExitUntil { return }
            if Date() < suppressAutoCloseUntil { return }
            if frozenHoverZoneActive { return }
            if manualOpenAutoCloseSuppressed { return }
            if vm.notchState == .open { return }

            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) { self.isHovering = false }

                    if self.vm.notchState == .open
                        && !self.vm.isBatteryPopoverActive
                        && !SharingStateManager.shared.preventNotchClose
                    {
                        self.vm.close()
                    }
                }
            }
        }
    }

    private func activateFrozenHoverZone(widthHint: CGFloat? = nil) {
        guard vm.notchState == .open else { return }
        hoverTask?.cancel()
        hoverTask = nil
        let hintedWidth: CGFloat = {
            guard let extra = widthHint else { return openWidthValueComputed }
            let base: CGFloat = 420
            let legacyOpenTopRadius = Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
            let compensation: CGFloat = 2 * legacyOpenTopRadius
            return max(vm.closedNotchSize.width, base + extra - compensation)
        }()
        frozenHoverZoneWidth = max(hintedWidth, frozenHoverZoneWidth)
        frozenHoverZoneActive = true
        frozenHoverStartPointer = hostWindow?.mouseLocationOutsideOfEventStream ?? .zero
        frozenHoverPointerMoved = false
        frozenHoverOutsideTicks = 0
        suppressAutoCloseUntil = Date().addingTimeInterval(0.45)
        ignoreHoverExitUntil = Date().addingTimeInterval(0.45)
        isHovering = true

        frozenHoverExitTask?.cancel()
        frozenHoverExitTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                guard frozenHoverZoneActive else { return }
                guard vm.notchState == .open else { return }
                guard !vm.isBatteryPopoverActive else { continue }

                if let pointer = hostWindow?.mouseLocationOutsideOfEventStream {
                    if !frozenHoverPointerMoved {
                        let dx = pointer.x - frozenHoverStartPointer.x
                        let dy = pointer.y - frozenHoverStartPointer.y
                        let dist2 = dx * dx + dy * dy
                        if dist2 >= 1.0 {
                            frozenHoverPointerMoved = true
                        } else {
                            continue
                        }
                    }
                }

                if frozenHoverPointerMoved {
                    if !isPointerInsideFrozenHoverZone() {
                        frozenHoverOutsideTicks += 1
                        if frozenHoverOutsideTicks >= 3 {
                            deactivateFrozenHoverZone()
                            withAnimation(animationSpring) { isHovering = false }
                            if !SharingStateManager.shared.preventNotchClose {
                                vm.close()
                            }
                            return
                        }
                    } else {
                        frozenHoverOutsideTicks = 0
                    }
                }
            }
        }
    }

    private func deactivateFrozenHoverZone() {
        frozenHoverZoneActive = false
        frozenHoverZoneWidth = 0
        frozenHoverPointerMoved = false
        frozenHoverOutsideTicks = 0
        frozenHoverExitTask?.cancel()
        frozenHoverExitTask = nil
    }

    private func startOpenHoverWatchdogIfNeeded() {
        guard openHoverWatchdogTask == nil else { return }
        openHoverWatchdogTask = Task { @MainActor in
            var outsideTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                guard vm.notchState == .open else { return }
                guard !vm.isBatteryPopoverActive else { continue }
                guard !SharingStateManager.shared.preventNotchClose else { continue }
                guard !manualOpenAutoCloseSuppressed else {
                    outsideTicks = 0
                    continue
                }
                guard !frozenHoverZoneActive else {
                    outsideTicks = 0
                    continue
                }

                if isPointerInsideOpenHoverZone() {
                    outsideTicks = 0
                } else {
                    outsideTicks += 1
                    if outsideTicks >= 3 {
                        withAnimation(animationSpring) { isHovering = false }
                        vm.close()
                        return
                    }
                }
            }
        }
    }

    private func isPointerInsideOpenHoverZone() -> Bool {
        guard let window = hostWindow else { return isHovering }
        guard let contentView = window.contentView else { return isHovering }

        let cs: CGFloat = cinemaMode ? cinemaModeScale : 1
        let pointer = window.mouseLocationOutsideOfEventStream
        let width = max(vm.closedNotchSize.width, openWidthValueComputed) * cs
        let halfWidth = (width / 2) + 10
        let height = max(vm.notchSize.height, openHeightValueComputed ?? vm.notchSize.height) * cs
        let minY = contentView.bounds.height - (height + 9)
        let centerX = contentView.bounds.midX

        let insideX = abs(pointer.x - centerX) <= halfWidth
        let insideY = pointer.y >= minY
        return insideX && insideY
    }

    private func isPointerInsideFrozenHoverZone() -> Bool {
        guard let window = hostWindow else { return true }
        guard let contentView = window.contentView else { return true }

        let cs: CGFloat = cinemaMode ? cinemaModeScale : 1
        let width = max(vm.closedNotchSize.width, frozenHoverZoneWidth) * cs
        let height = max(vm.notchSize.height, vm.effectiveClosedNotchHeight) * cs
        let pointer = window.mouseLocationOutsideOfEventStream

        let centerX = contentView.bounds.midX
        let halfWidth = (width / 2) + 10
        let minY = contentView.bounds.height - (height + 12)

        let insideX = abs(pointer.x - centerX) <= halfWidth
        let insideY = pointer.y >= minY
        return insideX && insideY
    }

 // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed && isPagerScrollEffectivelyEnabled else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] { haptics.toggle() }
            withAnimation(animationSpring) { gestureProgress = .zero }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar && isPagerScrollEffectivelyEnabled else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) { isHovering = false }

            if !SharingStateManager.shared.preventNotchClose {
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] { haptics.toggle() }
        }
    }

    private func performNowPlayingRightButtonAction() {
        let now = Date()
        guard now >= suppressNowPlayingRightActionUntil else { return }
        suppressNowPlayingRightActionUntil = now.addingTimeInterval(0.35)

        if musicManager.isPlaying {
            musicManager.pause()
        } else {
            musicManager.play()
        }
    }

    private func installNowPlayingClickMonitorIfNeeded() {
        guard nowPlayingClickMonitor == nil else { return }
        nowPlayingClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard vm.notchState == .closed else { return event }
            guard shouldShowMusicActivityClosed else { return event }
            guard isNowPlayingRightHovering else { return event }
            performNowPlayingRightButtonAction()
            return nil
        }
    }

    private func sendSystemPlayPauseMediaKey() {
        let keyTypePlayPause = 16

        let keyDownData1 = (keyTypePlayPause << 16) | (0xA << 8)
        if let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyDownData1,
            data2: -1
        )?.cgEvent {
            keyDown.post(tap: .cghidEventTap)
        }

        let keyUpData1 = (keyTypePlayPause << 16) | (0xB << 8)
        if let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xB00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyUpData1,
            data2: -1
        )?.cgEvent {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Bluetooth expanded view

fileprivate struct NowPlayingEdgeHoverTrackingView: NSViewRepresentable {
    let leftEdgeWidth: CGFloat
    let rightEdgeWidth: CGFloat
    let isTrackingEnabled: Bool
    let onHoverZonesChanged: (_ hoveringLeft: Bool, _ hoveringRight: Bool, _ hoveringCenter: Bool) -> Void
    let onRightEdgeTap: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HoverView()
        view.leftEdgeWidth = leftEdgeWidth
        view.rightEdgeWidth = rightEdgeWidth
        view.isTrackingEnabled = isTrackingEnabled
        view.onHoverZonesChanged = onHoverZonesChanged
        view.onRightEdgeTap = onRightEdgeTap
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HoverView else { return }
        view.leftEdgeWidth = leftEdgeWidth
        view.rightEdgeWidth = rightEdgeWidth
        view.isTrackingEnabled = isTrackingEnabled
        view.onHoverZonesChanged = onHoverZonesChanged
        view.onRightEdgeTap = onRightEdgeTap
        view.syncHoverStateToCurrentMouseLocation()
    }

    final class HoverView: NSView {
        var leftEdgeWidth: CGFloat = 0
        var rightEdgeWidth: CGFloat = 0
        var isTrackingEnabled: Bool = true
        var onHoverZonesChanged: ((_ hoveringLeft: Bool, _ hoveringRight: Bool, _ hoveringCenter: Bool) -> Void)?
        var onRightEdgeTap: (() -> Void)?
        private var trackingArea: NSTrackingArea?
        private var lastReportedHoverState: (Bool, Bool, Bool) = (false, false, false)

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isTrackingEnabled else { return nil }
            return isPointInRightZone(point) ? self : nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncHoverStateToCurrentMouseLocation()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea { removeTrackingArea(existing) }
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .assumeInside]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            if let trackingArea { addTrackingArea(trackingArea) }
            syncHoverStateToCurrentMouseLocation()
        }

        func syncHoverStateToCurrentMouseLocation() {
            guard isTrackingEnabled else {
                emitHoverZonesChanged(false, false, false)
                return
            }
            guard let window = window else { return }
            let mouseInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            updateHoverAtPoint(mouseInView)
        }

        override func mouseEntered(with event: NSEvent) { updateHover(with: event) }
        override func mouseMoved(with event: NSEvent) { updateHover(with: event) }
        override func mouseExited(with event: NSEvent) { emitHoverZonesChanged(false, false, false) }
        override func mouseDown(with event: NSEvent) {
            guard isTrackingEnabled else { return }
            let p = convert(event.locationInWindow, from: nil)
            if isPointInRightZone(p) {
                onRightEdgeTap?()
            }
        }

        private func isPointInRightZone(_ p: NSPoint) -> Bool {
            guard isTrackingEnabled else { return false }
            guard bounds.contains(p) else { return false }
            let right = max(0, rightEdgeWidth)
            return p.x >= (bounds.width - right)
        }

        private func updateHover(with event: NSEvent) {
            updateHoverAtPoint(convert(event.locationInWindow, from: nil))
        }

        private func updateHoverAtPoint(_ p: NSPoint) {
            guard isTrackingEnabled else {
                emitHoverZonesChanged(false, false, false)
                return
            }
            guard bounds.contains(p) else {
                emitHoverZonesChanged(false, false, false)
                return
            }

            let left = max(0, leftEdgeWidth)
            let right = max(0, rightEdgeWidth)
            let x = p.x
            let w = bounds.width

            let hoveringLeft = x <= left
            let hoveringRight = x >= (w - right)
            let hoveringCenter = !hoveringLeft && !hoveringRight
            emitHoverZonesChanged(hoveringLeft, hoveringRight, hoveringCenter)
        }

        private func emitHoverZonesChanged(_ hoveringLeft: Bool, _ hoveringRight: Bool, _ hoveringCenter: Bool) {
            let nextState = (hoveringLeft, hoveringRight, hoveringCenter)
            guard nextState != lastReportedHoverState else { return }
            lastReportedHoverState = nextState
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onHoverZonesChanged?(hoveringLeft, hoveringRight, hoveringCenter)
            }
        }
    }
}



fileprivate struct BluetoothEdgeHoverTrackingView: NSViewRepresentable {
    let leftEdgeWidth: CGFloat
    let rightEdgeWidth: CGFloat
    let isExpanded: Bool
    let onHoverZonesChanged: (_ hoveringSides: Bool, _ hoveringCenter: Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HoverView()
        view.leftEdgeWidth = leftEdgeWidth
        view.rightEdgeWidth = rightEdgeWidth
        view.isExpanded = isExpanded
        view.onHoverZonesChanged = onHoverZonesChanged
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HoverView else { return }
        view.leftEdgeWidth = leftEdgeWidth
        view.rightEdgeWidth = rightEdgeWidth
        view.isExpanded = isExpanded
        view.onHoverZonesChanged = onHoverZonesChanged
    }

    final class HoverView: NSView {
        var leftEdgeWidth: CGFloat = 0
        var rightEdgeWidth: CGFloat = 0
        var isExpanded: Bool = false
        var onHoverZonesChanged: ((_ hoveringSides: Bool, _ hoveringCenter: Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea { removeTrackingArea(existing) }

            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect
            ]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            if let trackingArea { addTrackingArea(trackingArea) }
        }

        override func mouseEntered(with event: NSEvent) { updateHover(with: event) }
        override func mouseMoved(with event: NSEvent) { updateHover(with: event) }
        override func mouseExited(with event: NSEvent) { onHoverZonesChanged?(false, false) }

        private func updateHover(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if isExpanded {
                let tolerantBounds = bounds.insetBy(dx: -10, dy: -10)
                guard tolerantBounds.contains(p) else {
                    onHoverZonesChanged?(false, false)
                    return
                }
                if !bounds.contains(p) {
                    onHoverZonesChanged?(false, true)
                    return
                }
            }

            guard bounds.contains(p) else {
                onHoverZonesChanged?(false, false)
                return
            }

            let left = max(0, leftEdgeWidth)
            let right = max(0, rightEdgeWidth)
            let w = bounds.width
            let x = p.x

            let onLeftEdge = x <= left
            let onRightEdge = x >= (w - right)
            let onSides = onLeftEdge || onRightEdge
            let onCenter = !onSides
            onHoverZonesChanged?(onSides, onCenter)
        }
    }
}

fileprivate struct BluetoothLiveActivityView: View {
    let vm: QuartzViewModel
    let deviceName: String
    let kind: BluetoothActivityManager.BluetoothDeviceKind
    let batteryPercent: Int?
    let isExpanded: Bool
    let closedTopCornerInset: CGFloat
    let onHoverZonesChanged: (_ hoveringSides: Bool, _ hoveringCenter: Bool) -> Void

    var body: some View {
        let baseHeight = vm.effectiveClosedNotchHeight

        let barExtraHeight: CGFloat = isExpanded ? 12 : 0
        let barHeight = baseHeight + barExtraHeight

        let footerHeight: CGFloat = isExpanded ? 28 : 0
        let contentHeight = isExpanded ? (barHeight + footerHeight) : baseHeight

        let centerExtraWidth: CGFloat = isExpanded ? 110 : 24

        let sideBase = max(0, barHeight - 12)
        let side = sideBase
        let airPodsVideoSide = sideBase + (isExpanded ? 20 : 6)
        let dualSenseVideoSide = sideBase + (isExpanded ? 12 : 2)

        let label = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = label.isEmpty ? "Bluetooth connected" : label

        let leftIconName: String = {
            switch kind {
            case .airpodsLegacy: return "airpods"
            case .airpodsBasic: return "airpods"
            case .airpodsPro: return "airpodspro"
            case .airpodsMax: return "airpodsmax"
            case .audio: return "headphones"
            case .keyboard: return "keyboard"
            case .mouse: return "mouse"
            case .keyboardMouseCombo: return "keyboard.fill"
            case .computer: return "laptopcomputer"
            case .phone: return "iphone"
            case .gamepad: return "gamecontroller"
            case .dualsense: return "gamecontroller"
            case .other: return "bolt.horizontal.circle.fill"
            }
        }()

        let leftInset: CGFloat = isExpanded ? 32 : 4
        let rightInset: CGFloat = isExpanded ? 18 : 4

        let centerWidth = max(
            0,
            (vm.closedNotchSize.width + -closedTopCornerInset + centerExtraWidth) - (leftInset + rightInset)
        )

        let hitLeftInset: CGFloat = 4
        let hitRightInset: CGFloat = 4
        let hitSide = max(0, baseHeight - 12)
        let hitCenterExtraWidth: CGFloat = 24
        let hitCenterWidth = max(
            0,
            (vm.closedNotchSize.width + -closedTopCornerInset + hitCenterExtraWidth) - (hitLeftInset + hitRightInset)
        )
        let hitLeftWidth = max(hitLeftInset + hitSide, 32)
        let hitRightWidth = max(hitSide + hitRightInset, 44)
        let expandedTotalWidth = max(0, leftInset + side + centerWidth + side + rightInset)
        let hitTotalWidth = max(hitLeftWidth + hitCenterWidth + hitRightWidth, expandedTotalWidth)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: leftInset)

                ZStack {
                    if kind == .airpodsPro {
                        ContentView.AirPodsProVideoIcon(side: airPodsVideoSide)
                    } else if kind == .dualsense {
                        ContentView.DualSenseVideoIcon(side: dualSenseVideoSide)
                            .offset(x: isExpanded ? -8 : 0, y: isExpanded ? 6 : 0)
                    } else {
                        Image(systemName: leftIconName)
                            .font(.system(size: isExpanded ? 16 : 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.9))
                    }
                }
                .frame(width: side, height: side)
                .zIndex(10)

                Rectangle()
                    .fill(.black)
                    .frame(width: centerWidth)

                ZStack {
                    if let p = batteryPercent {
                        ContentView.BatteryRing(percent: p, isExpanded: isExpanded)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: isExpanded ? 16 : 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.95))
                    }
                }
                .frame(width: side, height: side)
                .padding(.top, isExpanded ? 8 : 0)

                Color.clear.frame(width: rightInset)
            }
            .frame(height: barHeight, alignment: .center)
            .padding(.top, isExpanded ? 10 : 0)

            if isExpanded {
                VStack(spacing: 2) {
                    Text("Connected")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(.gray.opacity(0.9))

                    Text(finalLabel)
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, -23)      // Lift with top padding instead of an extra offset.
                .padding(.bottom, 10)    // Keep bottom padding.
            }
        }
        .frame(height: contentHeight, alignment: .top)
        .overlay(alignment: .topLeading) {
            BluetoothEdgeHoverTrackingView(
                leftEdgeWidth: hitLeftWidth,
                rightEdgeWidth: hitRightWidth,
                isExpanded: isExpanded,
                onHoverZonesChanged: onHoverZonesChanged
            )
            .frame(width: hitTotalWidth, height: contentHeight, alignment: .topLeading)
        }
        .onHover { hovering in
            if !hovering, !isExpanded {
                onHoverZonesChanged(false, false)
            }
        }
    }
}

// MARK: - Drop Delegates

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) { isTargeted = true }
    func dropExited(info _: DropInfo) { isTargeted = false }
    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}

struct GeneralDropTargetDelegateLocal: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info _: DropInfo) { isTargeted = false }
    func dropUpdated(info _: DropInfo) -> DropProposal? { DropProposal(operation: .cancel) }
    func performDrop(info _: DropInfo) -> Bool { false }
}





// MARK: - NotchPagerDynamic (2-3 pages, swipe)

struct NotchPagerDynamic: View {
    @Binding var selection: NotchViews
    @Binding var isScrollEnabled: Bool

    let enabledViews: [NotchViews]
    let fixedPageHeight: CGFloat?
    let fixedPageYOffset: CGFloat
    let page: (NotchViews) -> AnyView

    @State private var dragOffset: CGFloat = 0
    @State private var filteredDeltaX: CGFloat = 0
    @State private var swipeStartBoostSamples: Int = 0
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var isSwipeSettling: Bool = false

    private var currentIndex: Int {
        enabledViews.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalOffset = -(CGFloat(currentIndex) * width) + dragOffset

            HStack(spacing: 0) {
                ForEach(Array(enabledViews.enumerated()), id: \.offset) { _, view in
                    page(view)
                        .frame(width: width, height: fixedPageHeight ?? geo.size.height, alignment: .topLeading)
                        .offset(y: view == .home ? 0 : fixedPageYOffset)
                        .compositingGroup() // Force independent rendering for each page.
                        .allowsHitTesting(!isDragging)
                }
            }
            .frame(width: width * CGFloat(max(1, enabledViews.count)), alignment: .leading)
            .offset(x: totalOffset)
            .animation(
                isDragging
                ? nil
                : (isSwipeSettling ? NotchMotion.pagerSwipeSnap : NotchMotion.pagerProgrammatic),
                value: totalOffset
            )
        }
        .clipShape(BottomBleedClipShape(extraBottom: getOpenContentBottomBleed()))
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovering = hovering }
        .onChange(of: selection) { _, _ in
            dragOffset = 0
            filteredDeltaX = 0
            swipeStartBoostSamples = 0
            isDragging = false
        }
        .background(
            GeometryReader { geo in
                ScrollSpy(
                    isHovering: isHovering,
                    isScrollEnabled: isScrollEnabled,
                    onScroll: { deltaX in
                        handleScroll(deltaX: deltaX, width: geo.size.width)
                    },
                    onEnd: { velocity in
                        snapToPage(velocity: velocity, width: geo.size.width)
                    }
                )
            }
        )
    }

    private func handleScroll(deltaX: CGFloat, width: CGFloat) {
        guard enabledViews.count > 1 else { return }

        if !isDragging && abs(deltaX) > 0 {
            isDragging = true
            filteredDeltaX = deltaX * 2.8
            swipeStartBoostSamples = 8
        }

        let jitterDeadZone: CGFloat = 0.04
        let input = abs(deltaX) < jitterDeadZone ? 0 : deltaX
        let alpha: CGFloat = 0.42
        filteredDeltaX += (input - filteredDeltaX) * alpha

        let startBoost: CGFloat = swipeStartBoostSamples > 0 ? 2.35 : 1.0
        let newOffset = dragOffset + (filteredDeltaX * 0.52 * startBoost)
        if swipeStartBoostSamples > 0 { swipeStartBoostSamples -= 1 }
        let rubberBand: CGFloat = 130

        let minOffset = -(CGFloat(enabledViews.count - 1 - currentIndex) * width) - rubberBand
            let maxOffset: CGFloat = (CGFloat(currentIndex) * width) + rubberBand

        if newOffset > maxOffset {
            dragOffset = maxOffset + (newOffset - maxOffset) * 0.22
        } else if newOffset < minOffset {
            dragOffset = minOffset + (newOffset - minOffset) * 0.22
        } else {
            dragOffset = newOffset
        }
    }

    private func snapToPage(velocity: CGFloat, width: CGFloat) {
        guard enabledViews.count > 1 else { return }

        let threshold = width * 0.05
        var nextIndex = currentIndex

        if dragOffset < -threshold || velocity < -0.30 {
            nextIndex = min(currentIndex + 1, enabledViews.count - 1)
        } else if dragOffset > threshold || velocity > 0.30 {
            nextIndex = max(currentIndex - 1, 0)
        }

        isDragging = false
        filteredDeltaX = 0
        swipeStartBoostSamples = 0
        if nextIndex != currentIndex {
            isSwipeSettling = true
            selection = enabledViews[nextIndex]
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(460))
                isSwipeSettling = false
            }
        } else {
            isSwipeSettling = true
            dragOffset = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                isSwipeSettling = false
            }
        }
    }
}

// MARK: - NotchPager

struct NotchPager<First: View, Second: View>: View {
    @Binding var selection: NotchViews
    @Binding var isScrollEnabled: Bool
    let first: First
    let second: Second

    @State private var dragOffset: CGFloat = 0
    @State private var filteredDeltaX: CGFloat = 0
    @State private var swipeStartBoostSamples: Int = 0
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var isSwipeSettling: Bool = false

    init(
        selection: Binding<NotchViews>,
        isScrollEnabled: Binding<Bool>,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self._selection = selection
        self._isScrollEnabled = isScrollEnabled
        self.first = first()
        self.second = second()
    }

    private var currentIndex: Int { selection == .home ? 0 : 1 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalOffset = -(CGFloat(currentIndex) * width) + dragOffset

            HStack(spacing: 0) {
                first
                    .frame(width: width)
                    .compositingGroup() // Force independent rendering.
                    .allowsHitTesting(!isDragging)

                second
                    .frame(width: width)
                    .compositingGroup() // Force independent rendering.
                    .allowsHitTesting(!isDragging)
            }
            .frame(width: width * 2, alignment: .leading)
            .offset(x: totalOffset)
            .animation(
                isDragging
                ? nil
                : (isSwipeSettling ? NotchMotion.pagerSwipeSnap : NotchMotion.pagerProgrammatic),
                value: totalOffset
            )
        }
        .clipShape(BottomBleedClipShape(extraBottom: getOpenContentBottomBleed()))
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovering = hovering }
        .onChange(of: selection) { _, _ in
            dragOffset = 0
            filteredDeltaX = 0
            swipeStartBoostSamples = 0
            isDragging = false
        }
        .background(
            GeometryReader { geo in
                ScrollSpy(
                    isHovering: isHovering,
                    isScrollEnabled: isScrollEnabled,
                    onScroll: { deltaX in
                        handleScroll(deltaX: deltaX, width: geo.size.width)
                    },
                    onEnd: { velocity in
                        snapToPage(velocity: velocity, width: geo.size.width)
                    }
                )
            }
        )
    }

    func handleScroll(deltaX: CGFloat, width: CGFloat) {
        if !isDragging && abs(deltaX) > 0 {
            isDragging = true
            filteredDeltaX = deltaX * 2.8
            swipeStartBoostSamples = 8
        }

        let jitterDeadZone: CGFloat = 0.04
        let input = abs(deltaX) < jitterDeadZone ? 0 : deltaX
        let alpha: CGFloat = 0.42
        filteredDeltaX += (input - filteredDeltaX) * alpha

        let startBoost: CGFloat = swipeStartBoostSamples > 0 ? 2.35 : 1.0
        let newOffset = dragOffset + (filteredDeltaX * 0.52 * startBoost)
        if swipeStartBoostSamples > 0 { swipeStartBoostSamples -= 1 }
        let rubberBand: CGFloat = 130

        if currentIndex == 0 {
            if newOffset > rubberBand { dragOffset = rubberBand + (newOffset - rubberBand) * 0.22 }
            else if newOffset < -(width + rubberBand) {
                let minOffset = -(width + rubberBand)
                dragOffset = minOffset + (newOffset - minOffset) * 0.22
            }
            else { dragOffset = newOffset }
        } else {
            if newOffset > (width + rubberBand) {
                let maxOffset = (width + rubberBand)
                dragOffset = maxOffset + (newOffset - maxOffset) * 0.22
            }
            else if newOffset < -rubberBand {
                let minOffset = -rubberBand
                dragOffset = minOffset + (newOffset - minOffset) * 0.22
            }
            else { dragOffset = newOffset }
        }
    }

    func snapToPage(velocity: CGFloat, width: CGFloat) {
        let threshold = width * 0.05
        var nextIndex = currentIndex

        if currentIndex == 0 {
            if dragOffset < -threshold || velocity < -0.30 { nextIndex = 1 }
        } else {
            if dragOffset > threshold || velocity > 0.30 { nextIndex = 0 }
        }

        isDragging = false
        filteredDeltaX = 0
        swipeStartBoostSamples = 0

        if nextIndex != currentIndex {
            isSwipeSettling = true
            selection = (nextIndex == 0) ? .home : .shelf
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(460))
                isSwipeSettling = false
            }
        } else {
            isSwipeSettling = true
            dragOffset = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                isSwipeSettling = false
            }
        }
    }
}

// MARK: - ScrollSpy (Anti-Inertia)

struct ScrollSpy: NSViewRepresentable {
    var isHovering: Bool
    var isScrollEnabled: Bool
    var onScroll: (CGFloat) -> Void
    var onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.setupMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isHovering = isHovering
        context.coordinator.isScrollEnabled = isScrollEnabled
        context.coordinator.onScroll = onScroll
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var monitor: Any?
        var isHovering: Bool = false
        var isScrollEnabled: Bool = true
        var onScroll: ((CGFloat) -> Void)?
        var onEnd: ((CGFloat) -> Void)?

        func setupMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, self.isHovering else { return event }
                guard self.isScrollEnabled else { return event }

                if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) { return event }
                if event.momentumPhase != [] { return nil }

                if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .began {
                    self.onEnd?(event.scrollingDeltaX)
                    return nil
                }

                if event.scrollingDeltaX != 0 {
                    self.onScroll?(event.scrollingDeltaX)
                    return nil
                }
                return event
            }
        }

        deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
    }
}

// MARK: - Battery notification icon (custom fill/outline)

private struct NotificationBatteryIcon: View {
    let levelBattery: Float
    let isLowPowerMode: Bool

    private let emptyAssetName = "battery_empty"
    private let fullAssetName  = "battery_full"
    private let lowPowerFillColor = Color(red: 1.0, green: 0.86, blue: 0.18)
    private let criticalFillColor = Color(red: 1.0, green: 0.23, blue: 0.19)
    private let lowPowerTrackColor = Color(red: 0.62, green: 0.50, blue: 0.08)
    private let criticalTrackColor = Color(red: 0.54, green: 0.11, blue: 0.10)

    private static let nativeAspectRatio: CGFloat = 109.394295 / 52.0

    private var fillFraction: CGFloat {
        let p = CGFloat(levelBattery)
        if p >= 100.0 { return 1.0 }

        let clamped = min(max(p, 0.0), 99.0)
        return clamped / 110.0
    }

    private var isCriticalBattery: Bool {
        levelBattery < 20
    }

    @ViewBuilder
    private var fillImage: some View {
        if isCriticalBattery {
            Image(fullAssetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(criticalFillColor)
                .scaledToFit()
        } else if isLowPowerMode {
            Image(fullAssetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(lowPowerFillColor)
                .scaledToFit()
        } else {
            Image(fullAssetName)
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var backgroundImage: some View {
        if isCriticalBattery {
            Image(emptyAssetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(criticalTrackColor)
                .scaledToFit()
        } else if isLowPowerMode {
            Image(emptyAssetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(lowPowerTrackColor)
                .scaledToFit()
        } else {
            Image(emptyAssetName)
                .resizable()
                .scaledToFit()
        }
    }

    var body: some View {
        GeometryReader { geo in
            let renderedWidth = min(geo.size.width, geo.size.height * Self.nativeAspectRatio)
            let fillWidth = renderedWidth * fillFraction

            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    backgroundImage

                    fillImage
                        .frame(width: renderedWidth, height: geo.size.height, alignment: .leading)
                        .clipped()
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: fillWidth, height: geo.size.height)
                                Spacer(minLength: 0)
                            }
                        )
                }
                .frame(width: renderedWidth, height: geo.size.height, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .clipped()
    }
}



// MARK: - Window accessor (NSWindow discovery)

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onResolve(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}


#Preview {
    let vm = QuartzViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
