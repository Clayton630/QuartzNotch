import Defaults
import ObjectiveC.runtime
import QuartzCore
import SkyLightWindow
import SwiftUI

// MARK: - Lock Screen Music Panel

@MainActor
final class LockScreenPanelAnimator: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var fallbackBackdropSnapshot: NSImage?
    @Published var showsMediaCard: Bool = true
    @Published var isAlbumArtExpanded: Bool = false
    @Published var isAlbumArtTransitioning: Bool = false
    @Published var albumArtPanelMorphProgress: CGFloat = 0
    @Published var usesWindowBackdropFallback: Bool = false
    @Published var defersLyricsRenderingDuringResize: Bool = false
    @Published var lyricsExpansionProgress: CGFloat = Defaults[.enableLyrics] ? 1 : 0
    @Published var volumeExpansionProgress: CGFloat = OpenNotchPlayerAccessoryState.shared.isLockScreenVolumeSliderExpanded ? 1 : 0
    @Published var timerExitingCount: Int = 0
    @Published var releasedBackdropTimerIDs: Set<UUID> = []
}

private struct ExitingTimerOverlay: Identifiable {
    let id: UUID
    let snapshot: NSImage
    let baseOffset: CGFloat
}

private struct LockScreenLiquidGlassBackground<Content: View>: NSViewRepresentable {
    let variant: Int
    let cornerRadius: CGFloat
    let trigger: Double
    let forceFallback: Bool
    let fallbackPrimaryMaterial: NSVisualEffectView.Material
    let fallbackPrimaryAlpha: CGFloat
    let fallbackSecondaryMaterial: NSVisualEffectView.Material
    let fallbackSecondaryAlpha: CGFloat
    let fallbackTertiaryMaterial: NSVisualEffectView.Material
    let fallbackTertiaryAlpha: CGFloat
    let content: Content

    init(
        variant: Int = 11,
        cornerRadius: CGFloat,
        trigger: Double = 0,
        forceFallback: Bool = false,
        fallbackPrimaryMaterial: NSVisualEffectView.Material = .menu,
        fallbackPrimaryAlpha: CGFloat = 0.40,
        fallbackSecondaryMaterial: NSVisualEffectView.Material = .menu,
        fallbackSecondaryAlpha: CGFloat = 0,
        fallbackTertiaryMaterial: NSVisualEffectView.Material = .menu,
        fallbackTertiaryAlpha: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.trigger = trigger
        self.forceFallback = forceFallback
        self.fallbackPrimaryMaterial = fallbackPrimaryMaterial
        self.fallbackPrimaryAlpha = fallbackPrimaryAlpha
        self.fallbackSecondaryMaterial = fallbackSecondaryMaterial
        self.fallbackSecondaryAlpha = fallbackSecondaryAlpha
        self.fallbackTertiaryMaterial = fallbackTertiaryMaterial
        self.fallbackTertiaryAlpha = fallbackTertiaryAlpha
        self.content = content()
    }

    private var nativeGlassCornerRadius: CGFloat { 0 }
    private var nativeGlassType: NSView.Type? {
        guard !forceFallback else { return nil }
        return NSClassFromString("NSGlassEffectView") as? NSView.Type
    }

    func makeNSView(context: Context) -> NSView {
        if let glassType = nativeGlassType {
            let glass = glassType.init(frame: .zero)
            glass.setValue(nativeGlassCornerRadius, forKey: "cornerRadius")
            setVariant(on: glass, value: variant)

            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(host, forKey: "contentView")
            return glass
        }

        let fallback = NSView()
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = cornerRadius
        fallback.layer?.masksToBounds = true
        fallback.layer?.backgroundColor = NSColor.clear.cgColor

        let primaryBlur = NSVisualEffectView()
        configureFallback(primaryBlur, material: fallbackPrimaryMaterial, alpha: fallbackPrimaryAlpha)
        let secondaryBlur = NSVisualEffectView()
        configureFallback(secondaryBlur, material: fallbackSecondaryMaterial, alpha: fallbackSecondaryAlpha)
        let tertiaryBlur = NSVisualEffectView()
        configureFallback(tertiaryBlur, material: fallbackTertiaryMaterial, alpha: fallbackTertiaryAlpha)
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        primaryBlur.translatesAutoresizingMaskIntoConstraints = false
        secondaryBlur.translatesAutoresizingMaskIntoConstraints = false
        tertiaryBlur.translatesAutoresizingMaskIntoConstraints = false

        fallback.addSubview(primaryBlur)
        fallback.addSubview(secondaryBlur)
        fallback.addSubview(tertiaryBlur)
        fallback.addSubview(host)
        NSLayoutConstraint.activate([
            primaryBlur.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            primaryBlur.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            primaryBlur.topAnchor.constraint(equalTo: fallback.topAnchor),
            primaryBlur.bottomAnchor.constraint(equalTo: fallback.bottomAnchor),

            secondaryBlur.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            secondaryBlur.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            secondaryBlur.topAnchor.constraint(equalTo: fallback.topAnchor),
            secondaryBlur.bottomAnchor.constraint(equalTo: fallback.bottomAnchor),

            tertiaryBlur.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            tertiaryBlur.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            tertiaryBlur.topAnchor.constraint(equalTo: fallback.topAnchor),
            tertiaryBlur.bottomAnchor.constraint(equalTo: fallback.bottomAnchor),

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
           let host = nsView.value(forKey: "contentView") as? NSHostingView<Content> {
            host.rootView = content
            nsView.setValue(nativeGlassCornerRadius, forKey: "cornerRadius")
            setVariant(on: nsView, value: variant)
        } else if nsView.subviews.count >= 4,
                  let primaryBlur = nsView.subviews[0] as? NSVisualEffectView,
                  let secondaryBlur = nsView.subviews[1] as? NSVisualEffectView,
                  let tertiaryBlur = nsView.subviews[2] as? NSVisualEffectView,
                  let host = nsView.subviews[3] as? NSHostingView<Content> {
            host.rootView = content
            configureFallback(primaryBlur, material: fallbackPrimaryMaterial, alpha: fallbackPrimaryAlpha)
            configureFallback(secondaryBlur, material: fallbackSecondaryMaterial, alpha: fallbackSecondaryAlpha)
            configureFallback(tertiaryBlur, material: fallbackTertiaryMaterial, alpha: fallbackTertiaryAlpha)
        }
        let baseAlpha: CGFloat = nativeGlassType == nil ? 1.0 : 1.0
        if abs(nsView.alphaValue - baseAlpha) > 0.001 {
            nsView.alphaValue = baseAlpha
        }
    }

    private typealias VariantSetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void

    private func setVariant(on object: AnyObject, value: Int) {
        let selector = NSSelectorFromString("set_variant:")
        guard let method = class_getInstanceMethod(object_getClass(object), selector) else { return }
        let imp = method_getImplementation(method)
        let function = unsafeBitCast(imp, to: VariantSetterIMP.self)
        function(object, selector, value)
    }

    private func configureFallback(
        _ fallback: NSVisualEffectView,
        material: NSVisualEffectView.Material,
        alpha: CGFloat
    ) {
        fallback.material = material
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        fallback.isEmphasized = false
        fallback.alphaValue = alpha
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = cornerRadius
        fallback.layer?.masksToBounds = true
        fallback.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct LockScreenPanelRefractionBackdrop: NSViewRepresentable {
    let opacity: CGFloat
    let strength: CGFloat
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> LockScreenPanelRefractionBackdropView {
        let view = LockScreenPanelRefractionBackdropView()
        view.opacity = opacity
        view.strength = strength
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: LockScreenPanelRefractionBackdropView, context: Context) {
        nsView.apply(opacity: opacity, strength: strength, cornerRadius: cornerRadius)
    }
}

private final class LockScreenPanelRefractionBackdropView: NSView {
    var opacity: CGFloat = 1 {
        didSet { alphaValue = max(0, min(1, opacity)) }
    }

    var strength: CGFloat = 1 {
        didSet {
            guard abs(strength - oldValue) > 0.001 else { return }
            updateFilters()
        }
    }

    var cornerRadius: CGFloat = 22 {
        didSet {
            if oldValue != cornerRadius {
                needsLayout = true
            }
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
    private let sdfBleed: CGFloat = 10
    private let groupName = "quartznotch.lock-panel.refraction.\(UUID().uuidString)"

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

    func apply(opacity newOpacity: CGFloat, strength newStrength: CGFloat, cornerRadius newCornerRadius: CGFloat) {
        if abs(opacity - newOpacity) > 0.001 {
            opacity = newOpacity
        }
        if abs(strength - newStrength) > 0.001 {
            strength = newStrength
        }
        if abs(cornerRadius - newCornerRadius) > 0.001 {
            cornerRadius = newCornerRadius
        }
    }

    func updateFilters() {
        let amount = max(0.1, strength)

        guard let glass = Self.makeFilter(type: "glassBackground") else {
            backdrop.filters = nil
            return
        }

        glass.setValue(1.2, forKey: "inputBlurRadius")
        glass.setValue(0.07, forKey: "inputBlurOpacity0")
        glass.setValue(0.055, forKey: "inputBlurOpacity1")
        glass.setValue(0.045, forKey: "inputBlurOpacity2")
        glass.setValue(0.055, forKey: "inputBlurOpacity3")
        glass.setValue(0.07, forKey: "inputBlurOpacity4")
        glass.setValue(0.0, forKey: "inputBlurFillBlurRadius")
        glass.setValue(0.0, forKey: "inputBlurFillLightenOpacity")
        glass.setValue(0.0, forKey: "inputBlurFillDarkenOpacity")
        glass.setValue(0.0, forKey: "inputBlurFillNormalOpacity")
        glass.setValue("@0", forKey: "inputSourceSublayerName")
        glass.setValue(0.0, forKey: "inputFaceOpacity")
        glass.setValue(0.0, forKey: "inputShadowOpacity")
        glass.setValue(0.0, forKey: "inputRingShadowOpacity")
        glass.setValue(0.0, forKey: "inputKeyFillHighlightAmount")
        glass.setValue(0.0, forKey: "inputBleedOpacity")
        glass.setValue(0.0, forKey: "inputAberrationAmount")

        glass.setValue(-56.0 * amount, forKey: "inputInnerRefractionAmount")
        glass.setValue(40.0 * amount, forKey: "inputOuterRefractionAmount")
        glass.setValue(14.0 * amount, forKey: "inputInnerRefractionHeight")
        glass.setValue(18.0 * amount, forKey: "inputOuterRefractionHeight")
        glass.setValue(0.98, forKey: "inputRefractionOpacity")
        glass.setValue(-0.62, forKey: "inputRefractionDistance0")
        glass.setValue(-0.28, forKey: "inputRefractionDistance1")
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

        backdrop.name = "lock-panel-refraction-backdrop"
        backdrop.backgroundColor = NSColor.clear.cgColor
        backdrop.allowsGroupOpacity = true
        backdrop.setValue(true, forKey: "allowsGroupBlending")
        backdrop.setValue(false, forKey: "allowsEdgeAntialiasing")
        backdrop.setValue(false, forKey: "allowsInPlaceFiltering")
        backdrop.setValue(true, forKey: "disablesOccludedBackdropBlurs")
        backdrop.setValue(true, forKey: "ignoresOffscreenGroups")
        backdrop.setValue(true, forKey: "tracksLuma")
        backdrop.setValue(true, forKey: "allowsFilteredLuma")
        backdrop.setValue(0.5, forKey: "scale")
        backdrop.setValue(0.0, forKey: "bleedAmount")
        backdrop.setValue(groupName, forKey: "groupName")
        backdrop.sublayers = [sdfLayer]
        layer?.addSublayer(backdrop)
        updateFilters()
    }

    private func configureSDFLayers() {
        sdfLayer.name = "@0"
        sdfLayer.anchorPoint = .zero
        sdfLayer.setValue(14.0, forKey: "smoothness")

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

struct LockScreenMusicPanel: View {
    static let panelCornerRadius: CGFloat = 22
    static let albumCornerRadius: CGFloat = 9.2
    static let compactAlbumArtSize: CGFloat = 121
    static let collapsedContentLeadingPadding: CGFloat = 24
    static let compactAlbumArtVerticalOffset: CGFloat = 1
    static let collapsedHeight: CGFloat = 170
    static let lyricsHeight: CGFloat = 236
    static let volumeHeight: CGFloat = 20
    static let expandedWidthReduction: CGFloat = 56
    static let expandedHeightReduction: CGFloat = 18
    static let timerCardHeight: CGFloat = 76
    static let stackSpacing: CGFloat = 12
    static let morphAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.18)
    static var macOS27ShadowRenderBleed: CGFloat {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? 34 : 0
    }
    static func renderBleed(showsMediaCard: Bool) -> CGFloat {
        showsMediaCard ? macOS27ShadowRenderBleed : 0
    }
    static var baseCollapsedSize: CGSize {
        let configuredWidth = CGFloat(Defaults[.lockScreenMusicPanelWidth])
        let effectiveWidth = max(358, configuredWidth - 38)
        return CGSize(width: effectiveWidth, height: collapsedHeight)
    }
    static var collapsedSize: CGSize {
        let baseSize = baseCollapsedSize
        return CGSize(
            width: baseSize.width,
            height: baseSize.height
                + (Defaults[.enableLyrics] ? lyricsHeight : 0)
        )
    }
    static func mediaCardSize(
        progress rawProgress: CGFloat,
        availableWidth: CGFloat? = nil,
        includesLyrics: Bool = true
    ) -> CGSize {
        let progress = min(max(rawProgress, 0), 1)
        let baseSize = baseCollapsedSize
        let lyricsExtra = includesLyrics && Defaults[.enableLyrics] ? lyricsHeight : 0
        let widthProgress = includesLyrics && Defaults[.enableLyrics] ? 0 : progress
        let preferredWidth = baseSize.width - (expandedWidthReduction * widthProgress)
        let preferredHeight = baseSize.height + lyricsExtra - (expandedHeightReduction * progress)
        if let availableWidth {
            return CGSize(
                width: min(preferredWidth, availableWidth),
                height: preferredHeight
            )
        }
        return CGSize(width: preferredWidth, height: preferredHeight)
    }
    static func mediaCardSize(isExpanded: Bool, availableWidth: CGFloat? = nil) -> CGSize {
        mediaCardSize(progress: isExpanded ? 1 : 0, availableWidth: availableWidth)
    }
    static func size(
        showsMediaCard: Bool,
        timerCount: Int,
        mediaProgress: CGFloat,
        availableWidth: CGFloat? = nil
    ) -> CGSize {
        let effectiveProgress = showsMediaCard ? mediaProgress : 0
        let mediaSize = mediaCardSize(progress: effectiveProgress, availableWidth: availableWidth)
        let totalCards = timerCount + (showsMediaCard ? 1 : 0)
        let stackHeight =
            (CGFloat(timerCount) * timerCardHeight)
            + (showsMediaCard ? mediaSize.height : 0)
            + (CGFloat(max(0, totalCards - 1)) * stackSpacing)
        let bleed = renderBleed(showsMediaCard: showsMediaCard)
        return CGSize(
            width: mediaSize.width + (bleed * 2),
            height: stackHeight + (bleed * 2)
        )
    }

    @ObservedObject private var animator: LockScreenPanelAnimator
    @ObservedObject private var timerManager = QuickTimerManager.shared
    @ObservedObject private var accessoryState = OpenNotchPlayerAccessoryState.shared
    @Default(.forceLiquidGlassCompatibilityFallback) private var forceLiquidGlassCompatibilityFallback
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.enableLyrics) private var enableLyrics
    @StateObject private var lockVM = QuartzViewModel()
    @Namespace private var albumArtNamespace
    @State private var didConfigureVM = false
    @State private var exitingTimerProgress: [UUID: CGFloat] = [:]
    @State private var timerRemovalTasks: [UUID: Task<Void, Never>] = [:]
    @State private var timerBackdropReleaseTasks: [UUID: Task<Void, Never>] = [:]
    @State private var hiddenLiveTimerIDs: Set<UUID> = []
    @State private var exitingTimerOverlays: [UUID: ExitingTimerOverlay] = [:]
    @State private var rendersLyricsBlock = false
    @State private var lyricsContentOpacity: Double = 0
    @State private var lyricsRenderTask: Task<Void, Never>?
    private let lyricsOpenRenderDelay: Duration = .milliseconds(210)
    private let lyricsCloseRemovalDelay: Duration = .milliseconds(260)
    private let lyricsContentFadeDuration: TimeInterval = 0.14
    private var isSystemLightAppearance: Bool {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let interfaceStyle = globalDomain?["AppleInterfaceStyle"] as? String
        return interfaceStyle?.lowercased() != "dark"
    }
    private var liquidGlassCompatibilityFallbackActive: Bool {
        forceLiquidGlassCompatibilityFallback
            || (NSClassFromString("NSGlassEffectView") as? NSView.Type) == nil
    }
    private var isMacOS27OrNewer: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }
    private var usesLightCompatibilityFallbackStyling: Bool {
        liquidGlassCompatibilityFallbackActive && isSystemLightAppearance
    }
    private var usesDarkCompatibilityFallbackStyling: Bool {
        liquidGlassCompatibilityFallbackActive && !usesLightCompatibilityFallbackStyling
    }
    private var strokeBaseColor: Color {
        usesDarkCompatibilityFallbackStyling ? Color(white: 0.52) : .white
    }
    private var contourStrokePrimaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.018 : 0.0150)
    }
    private var contourStrokeSecondaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.010 : 0.0087)
    }
    private var contourStrokeTertiaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.006 : 0.0053)
    }
    private var contourStrokeBlendMode: BlendMode {
        liquidGlassCompatibilityFallbackActive ? .screen : .plusLighter
    }
    private var specularStrokePrimaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.30 : 0.205)
    }
    private var specularStrokeGlowColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.06 : 0.0)
    }
    private var specularStrokeBlendMode: BlendMode {
        liquidGlassCompatibilityFallbackActive ? .screen : .plusLighter
    }
    private var balanceStrokePrimaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.07 : 0.058)
    }
    private var balanceStrokeGlowColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.035 : 0.0)
    }
    private var panelOuterShadowPrimaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.08 : 0.0)
    }
    private var panelOuterShadowSecondaryColor: Color {
        strokeBaseColor.opacity(liquidGlassCompatibilityFallbackActive ? 0.04 : 0.0)
    }
    private var isExpandedLayout: Bool {
        animator.isAlbumArtExpanded
    }
    private var morphProgress: CGFloat {
        min(max(animator.albumArtPanelMorphProgress, 0), 1)
    }
    private var visualMorphProgress: CGFloat {
        let t = morphProgress
        return t * t * t * (t * ((t * 6) - 15) + 10)
    }
    private var lyricsExpansionProgress: CGFloat {
        min(max(animator.lyricsExpansionProgress, 0), 1)
    }
    private var isMorphingAlbumArtPanel: Bool {
        morphProgress > 0.001 && morphProgress < 0.999
    }
    private var centersMusicInfoLayout: Bool {
        isExpandedLayout && morphProgress >= 0.985
    }
    private func snapped(_ value: CGFloat) -> CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }
    private func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + ((to - from) * visualMorphProgress)
    }
    private var panelSize: CGSize {
        let mediaSize = visualMediaCardSize(includesLyrics: true)
        let timerCount = activeQuickTimersForLockScreen.count
        let totalCards = timerCount + (animator.showsMediaCard ? 1 : 0)
        let stackHeight =
            (CGFloat(timerCount) * Self.timerCardHeight)
            + (animator.showsMediaCard ? mediaSize.height : 0)
            + (CGFloat(max(0, totalCards - 1)) * Self.stackSpacing)
        let size = CGSize(width: mediaSize.width, height: stackHeight)
        return CGSize(width: snapped(size.width), height: snapped(size.height))
    }
    private var mediaCardSize: CGSize {
        let size = visualMediaCardSize(includesLyrics: true)
        return CGSize(width: snapped(size.width), height: snapped(size.height))
    }
    private var mediaControlsAreaHeight: CGFloat {
        snapped(visualMediaCardSize(includesLyrics: false, includesVolume: false).height)
    }
    private var timerCardSize: CGSize {
        CGSize(width: panelSize.width, height: Self.timerCardHeight)
    }
    private var slotCollapseProgress: CGFloat {
        let delayed = min(max((visualMorphProgress - 0.12) / 0.88, 0), 1)
        return delayed * delayed * (3 - (2 * delayed))
    }
    private var albumArtSlotWidth: CGFloat {
        snapped(Self.compactAlbumArtSize * (1 - slotCollapseProgress))
    }
    private var showsAlbumArtSlotInLayout: Bool {
        albumArtSlotWidth > 0.5
    }
    private var compactAlbumArtScale: CGFloat {
        interpolate(1, 0.38)
    }
    private var compactAlbumArtOpacity: Double {
        Double(max(0, 1 - min(CGFloat(1), visualMorphProgress * 1.12)))
    }
    private var compactAlbumArtHorizontalOffset: CGFloat {
        if isExpandedLayout {
            return interpolate(0, 18)
        }
        return -interpolate(0, 18)
    }
    private var compactAlbumArtVerticalMotionOffset: CGFloat {
        if isExpandedLayout {
            return -interpolate(0, 14)
        }
        return interpolate(0, 10)
    }
    private var contentSpacing: CGFloat {
        snapped(interpolate(6, 0))
    }
    private var contentLeadingPadding: CGFloat {
        snapped(interpolate(Self.collapsedContentLeadingPadding, 16))
    }
    private var contentTrailingPadding: CGFloat {
        snapped(interpolate(18, 16))
    }
    private var contentVerticalPadding: CGFloat {
        snapped(interpolate(0, 4))
    }
    private var lockScreenLyricsHeight: CGFloat {
        max(0, snapped(mediaCardSize.height - mediaControlsAreaHeight - lockScreenVolumeHeight))
    }
    private var lockScreenVolumeHeight: CGFloat {
        snapped(Self.volumeHeight * animator.volumeExpansionProgress)
    }
    private var keepsLyricsAreaInLayout: Bool {
        enableLyrics || rendersLyricsBlock || lyricsExpansionProgress > 0.001
    }
    private var keepsVolumeAreaInLayout: Bool {
        accessoryState.isLockScreenVolumeSliderExpanded || animator.volumeExpansionProgress > 0.001
    }
    private var activeQuickTimersForLockScreen: [QuickTimer] {
        guard enableLockScreenTimerWidget else { return [] }

        var timers = timerManager.timers
            .filter { $0.remainingSeconds > 0 || $0.didFinish }

        if let mirrored = timerManager.mirroredSystemQuickTimer {
            timers.append(mirrored)
        }

        return timers
    }
    private var visibleQuickTimersForStack: [QuickTimer] {
        activeQuickTimersForLockScreen
    }
    private var timerCardLiquidRefreshRate: Double {
        isMorphingAlbumArtPanel ? 0 : (animator.isPresented ? (1.0 / 30.0) : 0.25)
    }
    private var renderBleed: CGFloat {
        animator.showsMediaCard ? Self.macOS27ShadowRenderBleed : 0
    }
    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }

    private func visualMediaCardSize(includesLyrics: Bool, includesVolume: Bool = true) -> CGSize {
        let progress = morphProgress
        let baseSize = Self.baseCollapsedSize
        let lyricsExtra = includesLyrics ? Self.lyricsHeight * lyricsExpansionProgress : 0
        let volumeExtra = includesVolume ? Self.volumeHeight * animator.volumeExpansionProgress : 0
        let widthProgress = includesLyrics && keepsLyricsAreaInLayout
            ? progress * (1 - lyricsExpansionProgress)
            : progress
        return CGSize(
            width: baseSize.width - (Self.expandedWidthReduction * widthProgress),
            height: baseSize.height + lyricsExtra + volumeExtra - (Self.expandedHeightReduction * progress)
        )
    }

    private func updateLyricsRenderState(enabled: Bool, deferring: Bool, delay: Duration = .milliseconds(70)) {
        lyricsRenderTask?.cancel()
        lyricsRenderTask = nil

        guard enabled else {
            guard rendersLyricsBlock else { return }
            lyricsContentOpacity = 0
            lyricsRenderTask = Task { @MainActor in
                try? await Task.sleep(for: lyricsCloseRemovalDelay)
                guard !Task.isCancelled else { return }
                rendersLyricsBlock = false
                lyricsRenderTask = nil
            }
            return
        }

        guard deferring else {
            rendersLyricsBlock = false
            lyricsRenderTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                rendersLyricsBlock = true
                lyricsContentOpacity = 0
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                lyricsContentOpacity = 1
                lyricsRenderTask = nil
            }
            return
        }

        lyricsContentOpacity = 0
        rendersLyricsBlock = false
    }

    @ViewBuilder
    private func panelCard<Content: View>(
        size: CGSize,
        liquidRefreshRate: Double,
        darkTintOpacity: Double = 0,
        usesSharedBackdropSnapshot: Bool = true,
        sharedBackdropOrigin: CGPoint? = nil,
        contentAlignment: Alignment = .leading,
        usesMacOS27PanelChrome: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let usesMacOS27Chrome = isMacOS27OrNewer
            && usesMacOS27PanelChrome
            && !liquidGlassCompatibilityFallbackActive

        ZStack {
            Group {
                if usesMacOS27Chrome {
                    LockScreenPanelRefractionBackdrop(
                        opacity: 1,
                        strength: 2.35,
                        cornerRadius: Self.panelCornerRadius
                    )
                } else if liquidGlassCompatibilityFallbackActive,
                   animator.usesWindowBackdropFallback {
                    Color.clear
                } else if liquidGlassCompatibilityFallbackActive,
                   usesSharedBackdropSnapshot,
                   let snapshot = animator.fallbackBackdropSnapshot,
                   let sharedBackdropOrigin {
                    Image(nsImage: snapshot)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
                        .offset(x: -sharedBackdropOrigin.x, y: -sharedBackdropOrigin.y)
                } else {
                    LockScreenLiquidGlassBackground(
                        variant: 11,
                        cornerRadius: Self.panelCornerRadius,
                        trigger: 0,
                        forceFallback: forceLiquidGlassCompatibilityFallback,
                        fallbackPrimaryMaterial: usesLightCompatibilityFallbackStyling ? .hudWindow : .menu,
                        fallbackPrimaryAlpha: usesLightCompatibilityFallbackStyling ? 0.22 : 0.26,
                        fallbackSecondaryMaterial: usesLightCompatibilityFallbackStyling ? .popover : .popover,
                        fallbackSecondaryAlpha: usesLightCompatibilityFallbackStyling ? 0.18 : 0,
                        fallbackTertiaryMaterial: usesLightCompatibilityFallbackStyling ? .menu : .menu,
                        fallbackTertiaryAlpha: usesLightCompatibilityFallbackStyling ? 0.14 : 0
                    ) {
                        Color.clear
                    }
                    .id(forceLiquidGlassCompatibilityFallback ? "compat-static" : "native-static")
                    .blur(
                        radius: usesLightCompatibilityFallbackStyling
                            ? 0
                            : (liquidGlassCompatibilityFallbackActive ? 1.25 : 2.55)
                    )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
            .overlay {
                if !usesMacOS27Chrome {
                    shadowBalanceHighlights()
                }
            }
            .overlay(
                ZStack {
                    if !usesMacOS27Chrome {
                        if usesLightCompatibilityFallbackStyling {
                            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.055))

                            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.004))
                                .blendMode(.screen)
                        } else if usesDarkCompatibilityFallbackStyling {
                            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                                .fill(Color.black.opacity(0.165))

                            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                                .fill(Color.black.opacity(0.045))
                                .blendMode(.multiply)
                        } else {
                            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                                .fill(Color.black.opacity(liquidGlassCompatibilityFallbackActive ? 0.022 : 0.05))
                                .blendMode(.multiply)

                            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(liquidGlassCompatibilityFallbackActive ? 0.060 : 0.15))
                                .blendMode(.overlay)
                        }
                    }
                }
                .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(darkTintOpacity))
                    .allowsHitTesting(false)
            )
            .overlay(
                ZStack {
                    if !usesMacOS27Chrome {
                        RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                            .inset(by: 1.0)
                            .stroke(
                                contourStrokePrimaryColor,
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: liquidGlassCompatibilityFallbackActive ? 1.8 : 0.72)

                        RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                            .inset(by: 3.8)
                            .stroke(
                                contourStrokeSecondaryColor,
                                style: StrokeStyle(lineWidth: 8.2, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: liquidGlassCompatibilityFallbackActive ? 3.8 : 1.62)

                        RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                            .inset(by: 8.0)
                            .stroke(
                                contourStrokeTertiaryColor,
                                style: StrokeStyle(lineWidth: 12.3, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: liquidGlassCompatibilityFallbackActive ? 6.4 : 3.18)
                    }
                }
                .blendMode(contourStrokeBlendMode)
                .allowsHitTesting(false)
            )
            .overlay {
                if usesMacOS27Chrome {
                    macOS27PanelChromeLayer()
                } else {
                    specularHighlights()
                }
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
                .shadow(color: Color.black.opacity(0.18), radius: 6.2, x: 0, y: 1.8)
                .shadow(color: Color.black.opacity(0.08), radius: 13.0, x: 0, y: 3.4)
                .environment(\.colorScheme, usesLightCompatibilityFallbackStyling ? .light : .dark)
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        .shadow(
            color: usesMacOS27Chrome ? Color.black.opacity(0.070) : .clear,
            radius: usesMacOS27Chrome ? 5 : 0,
            x: 0,
            y: usesMacOS27Chrome ? 2 : 0
        )
        .shadow(
            color: usesMacOS27Chrome ? Color.black.opacity(0.030) : .clear,
            radius: usesMacOS27Chrome ? 9 : 0,
            x: 0,
            y: usesMacOS27Chrome ? 4 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func macOS27PanelChromeLayer() -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)

        ZStack {
            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.050), location: 0.00),
                            .init(color: Color.black.opacity(0.022), location: 0.42),
                            .init(color: Color.black.opacity(0.042), location: 1.00),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 5.5
                )
                .blur(radius: 5.8)
                .blendMode(.multiply)

            shape
                .strokeBorder(Color.black.opacity(0.012), lineWidth: 6.5)
                .blur(radius: 7.5)
                .blendMode(.multiply)

            shape
                .strokeBorder(Color.white.opacity(0.020), lineWidth: 0.45)
                .blur(radius: 0.7)
                .blendMode(.screen)

            shape
                .fill(Color.white.opacity(0.018))
                .blendMode(.screen)

            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.18), location: 0.00),
                            .init(color: Color.white.opacity(0.090), location: 0.30),
                            .init(color: Color.white.opacity(0.018), location: 0.56),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 22
                )
                .blur(radius: 12)
                .blendMode(.screen)

            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.070), location: 0.00),
                            .init(color: .clear, location: 0.34),
                            .init(color: .clear, location: 0.72),
                            .init(color: Color.black.opacity(0.018), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 16
                )
                .blur(radius: 10)
                .blendMode(.softLight)

            shape
                .strokeBorder(Color.white.opacity(0.58), lineWidth: 0.90)
                .blur(radius: 0.52)
                .blendMode(.colorDodge)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.00),
                            .init(color: .black.opacity(0.38), location: 0.10),
                            .init(color: .clear, location: 0.22),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .black, location: 0.10),
                                .init(color: .black, location: 0.90),
                                .init(color: .clear, location: 1.00),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }

            shape
                .strokeBorder(Color.white.opacity(0.64), lineWidth: 0.96)
                .blur(radius: 0.52)
                .blendMode(.colorDodge)
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
                                .init(color: .black, location: 0.10),
                                .init(color: .black, location: 0.90),
                                .init(color: .clear, location: 1.00),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }

            shape
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.56)
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

            shape
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.42)
                .blur(radius: 0.24)
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
        .mask(shape)
        .allowsHitTesting(false)
    }

    private var mediaPanelContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: contentSpacing) {
                if showsAlbumArtSlotInLayout {
                    ZStack {
                        AlbumArtView(
                            vm: lockVM,
                            albumArtNamespace: albumArtNamespace,
                            revealCompensationProgress: 1.0,
                            customCornerRadius: Self.albumCornerRadius,
                            disablePausedScaleShrink: true,
                            showsSourceAppIcon: false,
                            showsStaticPausedDarkOverlay: false,
                            tapAction: {
                                guard LockScreenPanelManager.shared.canToggleExpandedArtwork() else { return }
                                animator.isAlbumArtExpanded = true
                            }
                        )
                        .frame(width: Self.compactAlbumArtSize, height: Self.compactAlbumArtSize)
                        .clipShape(RoundedRectangle(cornerRadius: Self.albumCornerRadius, style: .continuous))
                        .shadow(color: Color.black.opacity(0.10), radius: 3.2, x: 0, y: 0.9)
                        .shadow(color: Color.black.opacity(0.04), radius: 7.2, x: 0, y: 1.8)
                        .offset(x: compactAlbumArtHorizontalOffset)
                        .offset(y: Self.compactAlbumArtVerticalOffset + compactAlbumArtVerticalMotionOffset)
                        .opacity(compactAlbumArtOpacity)
                        .scaleEffect(compactAlbumArtScale, anchor: .center)
                        .allowsHitTesting(!isExpandedLayout && morphProgress < 0.08)
                    }
                    .frame(width: Self.compactAlbumArtSize, height: Self.compactAlbumArtSize, alignment: .center)
                    .frame(width: albumArtSlotWidth, height: Self.compactAlbumArtSize + 6, alignment: .leading)
                    .clipped()
                }

                MusicControlsView(
                    forceLightGrayUI: !usesLightCompatibilityFallbackStyling,
                    forceDarkUI: usesLightCompatibilityFallbackStyling,
                    iconButtonSize: 30,
                    prefersCenteredInfoLayout: centersMusicInfoLayout,
                    showsInlineLyrics: false,
                    controlsLockScreenLyrics: true,
                    usesVerticalVolumeSlider: true,
                    controlsLockScreenVolume: true
                )
                    .environmentObject(lockVM)
                    .compositingGroup()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, contentVerticalPadding)
            }
            .frame(maxWidth: .infinity, minHeight: mediaControlsAreaHeight, maxHeight: mediaControlsAreaHeight, alignment: .center)
            .animation(Self.morphAnimation, value: albumArtSlotWidth)
            .animation(Self.morphAnimation, value: mediaControlsAreaHeight)
            .animation(Self.morphAnimation, value: contentSpacing)
            .animation(Self.morphAnimation, value: contentVerticalPadding)

            if keepsVolumeAreaInLayout {
                HStack(spacing: contentSpacing) {
                    if showsAlbumArtSlotInLayout {
                        Color.clear
                            .frame(width: albumArtSlotWidth, height: 1)
                    }

                    OpenNotchVolumeSection(
                        forceLightGrayUI: !usesLightCompatibilityFallbackStyling,
                        forceDarkUI: usesLightCompatibilityFallbackStyling,
                        horizontalPadding: 6,
                        height: 24
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: lockScreenVolumeHeight, alignment: .top)
                .offset(y: -8 * animator.volumeExpansionProgress)
                .opacity(min(1, max(0, Double(animator.volumeExpansionProgress))))
                .allowsHitTesting(accessoryState.isLockScreenVolumeSliderExpanded)
                .animation(Self.morphAnimation, value: albumArtSlotWidth)
                .animation(.easeInOut(duration: 0.24), value: lockScreenVolumeHeight)
                .animation(Self.morphAnimation, value: contentSpacing)
            }

            if keepsLyricsAreaInLayout {
                Group {
                    if !rendersLyricsBlock || animator.defersLyricsRenderingDuringResize {
                        Color.clear
                    } else {
                        LockScreenLyricsBlock(
                            forceDarkUI: usesLightCompatibilityFallbackStyling,
                            isCentered: false
                        )
                        .opacity(lyricsContentOpacity)
                    }
                }
                .frame(height: lockScreenLyricsHeight, alignment: .center)
                .offset(y: -10)
                .animation(.easeOut(duration: lyricsContentFadeDuration), value: lyricsContentOpacity)
                .animation(Self.morphAnimation, value: lockScreenLyricsHeight)
            }
        }
        .padding(.leading, contentLeadingPadding)
        .padding(.trailing, contentTrailingPadding)
        .padding(.vertical, 0)
        .animation(Self.morphAnimation, value: contentLeadingPadding)
        .animation(Self.morphAnimation, value: contentTrailingPadding)
        .animation(Self.morphAnimation, value: lyricsExpansionProgress)
        .animation(Self.morphAnimation, value: mediaCardSize.width)
        .animation(.easeInOut(duration: 0.24), value: animator.volumeExpansionProgress)
    }

    private struct LockScreenLyricsBlock: View {
        @ObservedObject private var musicManager = MusicManager.shared
        @StateObject private var layoutCache = LyricsLayoutCache()
        @State private var scrollResetGeneration = 0
        @State private var manualBrowseCenterY: CGFloat?
        @State private var pendingSeekAnchorY: CGFloat?
        @State private var pauseIndexHoldUntil: Date?
        @State private var lastResolvedCurrentIndex = 0
        @State private var lastResolvedLayoutKey = ""
        let forceDarkUI: Bool
        let isCentered: Bool

        private var primaryColor: Color {
            forceDarkUI ? .black.opacity(0.88) : .white.opacity(0.96)
        }

        private var secondaryColor: Color {
            forceDarkUI ? .black.opacity(0.44) : .white.opacity(0.46)
        }

        private var textAlignment: TextAlignment {
            isCentered ? .center : .leading
        }

        private var stackAlignment: HorizontalAlignment {
            isCentered ? .center : .leading
        }

        private let secondaryLineSlotHeight: CGFloat = 56
        private let currentLineSlotHeight: CGFloat = 76
        private let singleLineSlotHeight: CGFloat = 48
        private let lyricsGroupSpacing: CGFloat = 18
        private let secondaryFontSize: CGFloat = 18.6
        private let currentFontSize: CGFloat = 25.2
        private let secondaryPreludeFontSize: CGFloat = 11.4
        private let currentPreludeFontSize: CGFloat = 14.2
        private let secondaryTracking: CGFloat = 0.36
        private let currentTracking: CGFloat = 0.42
        private let preludeTracking: CGFloat = 1.55
        private let lyricVisualLeadTime: TimeInterval = 0.10
        private let pauseIndexHoldDuration: TimeInterval = 0.55
        private let renderedNeighborCount = 5
        private let manualScrollResetDelay: TimeInterval = 3.0
        private let lyricsHitTestTopInset: CGFloat = 22
        private let preludeDots = "● ● ●"

        private struct LyricEntry: Identifiable {
            let id: String
            let text: String
            var isPrelude: Bool = false
            var startTime: TimeInterval?
            var endTime: TimeInterval?
        }

        private struct LyricRenderState {
            let entries: [LyricEntry]
            let currentIndex: Int

            var layoutKey: String {
                entries.map { entry in
                    [
                        entry.id,
                        entry.text,
                        entry.isPrelude ? "prelude" : "lyric",
                        entry.startTime.map { String($0) } ?? "",
                        entry.endTime.map { String($0) } ?? ""
                    ].joined(separator: "\u{1F}")
                }
                .joined(separator: "\u{1E}")
            }

            var currentID: String {
                entries.indices.contains(currentIndex) ? entries[currentIndex].id : ""
            }
        }

        private struct PreparedLyricsLayout {
            let entries: [LyricEntry]
            let sourceStartIndices: [Int]
            let sourceChunkCounts: [Int]
            let lineCounts: [Int]
            let rowHeights: [CGFloat]
            let rowOffsets: [CGFloat]

            func expandedIndex(for sourceIndex: Int, chunkOffset: Int) -> Int {
                guard sourceStartIndices.indices.contains(sourceIndex),
                      sourceChunkCounts.indices.contains(sourceIndex) else {
                    return 0
                }
                let clampedChunk = min(max(0, chunkOffset), max(0, sourceChunkCounts[sourceIndex] - 1))
                return sourceStartIndices[sourceIndex] + clampedChunk
            }
        }

        private final class LyricsLayoutCache: ObservableObject {
            private var key: String = ""
            private var width: CGFloat = 0
            private var layout: PreparedLyricsLayout?

            func layout(for key: String, width: CGFloat, build: () -> PreparedLyricsLayout) -> PreparedLyricsLayout {
                let roundedWidth = (width * 2).rounded() / 2
                if self.key == key, self.width == roundedWidth, let layout {
                    return layout
                }

                let nextLayout = build()
                self.key = key
                self.width = roundedWidth
                self.layout = nextLayout
                return nextLayout
            }
        }

        private struct LyricsEventMonitorView: NSViewRepresentable {
            let onScroll: (CGFloat) -> Void
            let onClick: (CGFloat) -> Void

            func makeNSView(context: Context) -> MonitorView {
                let view = MonitorView()
                view.onScroll = onScroll
                view.onClick = onClick
                view.installMonitorIfNeeded()
                return view
            }

            func updateNSView(_ nsView: MonitorView, context: Context) {
                nsView.onScroll = onScroll
                nsView.onClick = onClick
                nsView.installMonitorIfNeeded()
            }

            final class MonitorView: NSView {
                var onScroll: ((CGFloat) -> Void)?
                var onClick: ((CGFloat) -> Void)?
                private var monitor: Any?
                private var lastDragY: CGFloat?
                private var dragDistance: CGFloat = 0

                deinit {
                    if let monitor {
                        NSEvent.removeMonitor(monitor)
                    }
                }

                override func hitTest(_ point: NSPoint) -> NSView? {
                    nil
                }

                func installMonitorIfNeeded() {
                    guard monitor == nil else { return }
                    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]) { [weak self] event in
                        guard let self else { return event }
                        guard self.eventIsInside(event) else {
                            if event.type == .leftMouseUp {
                                self.lastDragY = nil
                                self.dragDistance = 0
                            }
                            return event
                        }

                        switch event.type {
                        case .scrollWheel:
                            let delta = event.hasPreciseScrollingDeltas
                                ? event.scrollingDeltaY
                                : event.deltaY * 12
                            self.onScroll?(delta)
                            return nil
                        case .leftMouseDown:
                            self.lastDragY = self.localY(for: event)
                            self.dragDistance = 0
                            return nil
                        case .leftMouseDragged:
                            let y = self.localY(for: event)
                            if let lastDragY = self.lastDragY {
                                let delta = y - lastDragY
                                self.dragDistance += abs(delta)
                                self.onScroll?(delta)
                            }
                            self.lastDragY = y
                            return nil
                        case .leftMouseUp:
                            if self.dragDistance < 4 {
                                self.onClick?(self.topOriginY(for: event))
                            }
                            self.lastDragY = nil
                            self.dragDistance = 0
                            return nil
                        default:
                            return event
                        }
                    }
                }

                private func eventIsInside(_ event: NSEvent) -> Bool {
                    guard let window, event.window === window else { return false }
                    let point = convert(event.locationInWindow, from: nil)
                    return bounds.contains(point)
                }

                private func localY(for event: NSEvent) -> CGFloat {
                    convert(event.locationInWindow, from: nil).y
                }

                private func topOriginY(for event: NSEvent) -> CGFloat {
                    bounds.height - localY(for: event)
                }
            }
        }

        private func estimatedElapsed(at date: Date) -> Double {
            if let preview = musicManager.playbackPreviewPosition {
                return preview
            }
            return musicManager.estimatedPlaybackPosition(at: date)
        }

        private func lyricState(at elapsed: Double) -> LyricRenderState {
            if musicManager.isFetchingLyrics {
                return LyricRenderState(
                    entries: [LyricEntry(id: "loading-current", text: preludeDots, isPrelude: true)],
                    currentIndex: 0
                )
            }

            if musicManager.lyricsSnapshot.state == .instrumental {
                return LyricRenderState(
                    entries: [LyricEntry(id: "instrumental-current", text: "Instrumental")],
                    currentIndex: 0
                )
            }

            let synced = musicManager.lyricsSnapshot.syncedLines
            if !synced.isEmpty {
                let preludeEntry = LyricEntry(
                    id: "synced-prelude",
                    text: preludeDots,
                    isPrelude: true,
                    startTime: 0,
                    endTime: synced.first?.startTime
                )
                let isBeforeFirstLine = elapsed < (synced.first?.startTime ?? 0)
                let lyricIndex = max(0, musicManager.lyricIndex(at: elapsed))

                return LyricRenderState(
                    entries: [preludeEntry] + synced.enumerated().map { offset, lyric in
                        let text = lyric.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let isSilence = text.isEmpty
                        return LyricEntry(
                            id: "synced-\(lyric.id)-\(offset)",
                            text: isSilence ? preludeDots : lyric.text,
                            isPrelude: isSilence,
                            startTime: lyric.startTime,
                            endTime: lyric.endTime
                        )
                    },
                    currentIndex: isBeforeFirstLine ? 0 : lyricIndex + 1
                )
            }

            let plainLines = musicManager.currentLyrics
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if plainLines.isEmpty {
                return LyricRenderState(
                    entries: [LyricEntry(id: "empty-current", text: "No lyrics found")],
                    currentIndex: 0
                )
            }

            return LyricRenderState(
                entries: plainLines.enumerated().map { index, line in
                    LyricEntry(id: "plain-\(index)-\(line)", text: line)
                },
                currentIndex: 0
            )
        }

        private func measuredTextWidth(_ text: String, pointSize: CGFloat, weight: NSFont.Weight, tracking: CGFloat) -> CGFloat {
            let font = NSFont.systemFont(ofSize: pointSize, weight: weight)
            let baseWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            return baseWidth + max(0, CGFloat(text.count - 1) * tracking)
        }

        private func wrappedLines(_ text: String, maxWidth: CGFloat, pointSize: CGFloat, weight: NSFont.Weight, tracking: CGFloat) -> [String] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            guard measuredTextWidth(trimmed, pointSize: pointSize, weight: weight, tracking: tracking) > maxWidth else {
                return [trimmed]
            }

            let words = trimmed.split(separator: " ").map(String.init)
            return fittedLines(from: words, maxLines: 2, maxWidth: maxWidth, pointSize: pointSize, weight: weight, tracking: tracking).lines
        }

        private func fittedLines(
            from words: [String],
            maxLines: Int,
            maxWidth: CGFloat,
            pointSize: CGFloat,
            weight: NSFont.Weight,
            tracking: CGFloat
        ) -> (lines: [String], consumedWords: Int) {
            guard maxLines > 0 else { return ([], 0) }
            var lines: [String] = []
            var currentLine = ""
            var consumed = 0

            for word in words {
                let candidate = currentLine.isEmpty ? word : "\(currentLine) \(word)"
                let candidateFits = measuredTextWidth(candidate, pointSize: pointSize, weight: weight, tracking: tracking) <= maxWidth

                if candidateFits || currentLine.isEmpty {
                    currentLine = candidate
                    consumed += 1
                    continue
                }

                lines.append(currentLine)
                if lines.count >= maxLines {
                    return (lines, consumed)
                }

                currentLine = word
                consumed += 1
            }

            if !currentLine.isEmpty, lines.count < maxLines {
                lines.append(currentLine)
            }
            return (lines, consumed)
        }

        private func visualLines(from words: [String], maxWidth: CGFloat, pointSize: CGFloat, weight: NSFont.Weight, tracking: CGFloat) -> [(text: String, wordCount: Int)] {
            var lines: [(text: String, wordCount: Int)] = []
            var cursor = 0

            while cursor < words.count {
                let result = fittedLines(
                    from: Array(words[cursor...]),
                    maxLines: 1,
                    maxWidth: maxWidth,
                    pointSize: pointSize,
                    weight: weight,
                    tracking: tracking
                )
                guard result.consumedWords > 0, let line = result.lines.first else { break }
                lines.append((line, result.consumedWords))
                cursor += result.consumedWords
            }

            return lines
        }

        private func maxWordsForTwoLines(from words: [String], startIndex: Int, maxWidth: CGFloat) -> Int {
            guard words.indices.contains(startIndex) else { return 0 }
            let result = fittedLines(
                from: Array(words[startIndex...]),
                maxLines: 2,
                maxWidth: maxWidth,
                pointSize: currentFontSize,
                weight: .semibold,
                tracking: currentTracking
            )
            return max(1, result.consumedWords)
        }

        private func chunkVisualWidth(for words: [String], range: Range<Int>, maxWidth: CGFloat) -> CGFloat {
            let lines = displayLines(for: words[range].joined(separator: " "), maxWidth: maxWidth)
            return lines.reduce(0) { partial, line in
                partial + measuredTextWidth(line, pointSize: currentFontSize, weight: .semibold, tracking: currentTracking)
            }
        }

        private func balancedWordRanges(for words: [String], maxWidth: CGFloat) -> [Range<Int>] {
            let lines = visualLines(
                from: words,
                maxWidth: maxWidth,
                pointSize: currentFontSize,
                weight: .semibold,
                tracking: currentTracking
            )
            guard lines.count > 2 else {
                return words.isEmpty ? [] : [0..<words.count]
            }

            let chunkCount = Int(ceil(Double(lines.count) / 2.0))
            let totalVisualWidth = chunkVisualWidth(for: words, range: 0..<words.count, maxWidth: maxWidth)
            let targetVisualWidth = totalVisualWidth / Double(chunkCount)
            var memo: [String: (cost: Double, ranges: [Range<Int>])] = [:]

            func solve(start: Int, chunksRemaining: Int) -> (cost: Double, ranges: [Range<Int>])? {
                if start >= words.count {
                    return chunksRemaining == 0 ? (0, []) : nil
                }
                guard chunksRemaining > 0 else { return nil }

                let key = "\(start)-\(chunksRemaining)"
                if let cached = memo[key] { return cached }

                let maxEnd = min(words.count, start + maxWordsForTwoLines(from: words, startIndex: start, maxWidth: maxWidth))
                var best: (cost: Double, ranges: [Range<Int>])?

                for end in (start + 1)...maxEnd {
                    let wordsInChunk = end - start
                    let remainingWords = words.count - end
                    if chunksRemaining > 1, remainingWords < chunksRemaining - 1 { continue }

                    let remaining = solve(start: end, chunksRemaining: chunksRemaining - 1)
                    guard let remaining else { continue }

                    let visualWidth = chunkVisualWidth(for: words, range: start..<end, maxWidth: maxWidth)
                    let balanceCost = pow((visualWidth - targetVisualWidth) / max(targetVisualWidth, 1), 2)
                    let orphanCost = chunksRemaining > 1 && wordsInChunk == 1 ? 0.35 : 0
                    let totalCost = balanceCost + orphanCost + remaining.cost
                    if best == nil || totalCost < best!.cost {
                        best = (totalCost, [start..<end] + remaining.ranges)
                    }
                }

                if let best {
                    memo[key] = best
                }
                return best
            }

            return solve(start: 0, chunksRemaining: chunkCount)?.ranges ?? [0..<words.count]
        }

        private func capitalizedChunkText(_ text: String) -> String {
            guard let firstIndex = text.firstIndex(where: { !$0.isWhitespace }) else { return text }
            let uppercased = String(text[firstIndex]).uppercased()
            return String(text[..<firstIndex]) + uppercased + String(text[text.index(after: firstIndex)...])
        }

        private func chunkedEntries(from entry: LyricEntry, maxWidth: CGFloat) -> [LyricEntry] {
            guard !entry.isPrelude else { return [entry] }
            let words = entry.text
                .split(separator: " ")
                .map(String.init)
            guard !words.isEmpty else { return [entry] }

            let ranges = balancedWordRanges(for: words, maxWidth: maxWidth)
            let chunks = ranges.enumerated().map { offset, range in
                let rawText = words[range].joined(separator: " ")
                let chunkStart: TimeInterval?
                let chunkEnd: TimeInterval?
                if let start = entry.startTime,
                   let end = entry.endTime,
                   end > start,
                   ranges.count > 1 {
                    let duration = end - start
                    chunkStart = start + (duration * Double(offset) / Double(ranges.count))
                    chunkEnd = start + (duration * Double(offset + 1) / Double(ranges.count))
                } else {
                    chunkStart = entry.startTime
                    chunkEnd = entry.endTime
                }
                return LyricEntry(
                    id: "\(entry.id)-chunk-\(offset)",
                    text: offset == 0 ? rawText : capitalizedChunkText(rawText),
                    startTime: chunkStart,
                    endTime: chunkEnd
                )
            }
            return chunks.isEmpty ? [entry] : chunks
        }

        private func activeChunkIndex(for entry: LyricEntry, chunkCount: Int, elapsed: TimeInterval) -> Int {
            guard chunkCount > 1,
                  let start = entry.startTime,
                  let end = entry.endTime,
                  end > start else {
                return 0
            }

            let progress = min(max((elapsed - start) / (end - start), 0), 0.999)
            return min(chunkCount - 1, max(0, Int(floor(progress * Double(chunkCount)))))
        }

        private func preparedLayout(from state: LyricRenderState, maxWidth: CGFloat) -> PreparedLyricsLayout {
            var expandedEntries: [LyricEntry] = []
            var sourceStartIndices: [Int] = []
            var sourceChunkCounts: [Int] = []

            for entry in state.entries {
                let chunks = chunkedEntries(from: entry, maxWidth: maxWidth)
                sourceStartIndices.append(expandedEntries.count)
                sourceChunkCounts.append(chunks.count)
                expandedEntries.append(contentsOf: chunks)
            }

            let lineCounts = expandedEntries.map { displayLines(for: $0.text, maxWidth: maxWidth).count }
            let rowHeights = lineCounts.map { $0 > 1 ? currentLineSlotHeight : singleLineSlotHeight }

            return PreparedLyricsLayout(
                entries: expandedEntries,
                sourceStartIndices: sourceStartIndices,
                sourceChunkCounts: sourceChunkCounts,
                lineCounts: lineCounts,
                rowHeights: rowHeights,
                rowOffsets: rowTopOffsets(heights: rowHeights)
            )
        }

        private func currentExpandedIndex(for state: LyricRenderState, layout: PreparedLyricsLayout, elapsed: TimeInterval) -> Int {
            guard state.entries.indices.contains(state.currentIndex),
                  layout.sourceChunkCounts.indices.contains(state.currentIndex) else {
                return 0
            }

            let entry = state.entries[state.currentIndex]
            let chunkOffset = activeChunkIndex(
                for: entry,
                chunkCount: layout.sourceChunkCounts[state.currentIndex],
                elapsed: elapsed
            )
            return layout.expandedIndex(for: state.currentIndex, chunkOffset: chunkOffset)
        }

        private func lyricLine(
            _ text: String,
            fontSize: CGFloat,
            tracking: CGFloat,
            color: Color,
            opacity: Double,
            blurRadius: CGFloat
        ) -> some View {
            Text(text)
                .font(.custom("SF Pro Display", size: fontSize).weight(.semibold))
                .tracking(tracking)
                .foregroundStyle(color)
                .opacity(text.isEmpty ? 0 : opacity)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(textAlignment)
                .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
                .blur(radius: text.isEmpty ? 0 : blurRadius)
        }

        private func displayLines(for text: String, maxWidth: CGFloat) -> [String] {
            wrappedLines(
                text,
                maxWidth: maxWidth,
                pointSize: currentFontSize,
                weight: .semibold,
                tracking: currentTracking
            )
        }

        private func rowHeight(for entry: LyricEntry, maxWidth: CGFloat) -> CGFloat {
            displayLines(for: entry.text, maxWidth: maxWidth).count > 1
                ? currentLineSlotHeight
                : singleLineSlotHeight
        }

        private func rowTopOffsets(heights: [CGFloat]) -> [CGFloat] {
            var offsets: [CGFloat] = []
            var cursor: CGFloat = 0
            for index in heights.indices {
                offsets.append(cursor)
                cursor += heights[index]
                if index < heights.count - 1 {
                    cursor += lyricsGroupSpacing
                }
            }
            return offsets
        }

        private func rowCenterY(at index: Int, offsets: [CGFloat], heights: [CGFloat]) -> CGFloat {
            guard heights.indices.contains(index) else { return 0 }
            let top = offsets.indices.contains(index) ? offsets[index] : 0
            return top + heights[index] / 2
        }

        private func interpolatedCenterY(for position: CGFloat, offsets: [CGFloat], heights: [CGFloat]) -> CGFloat {
            guard !heights.isEmpty else { return 0 }
            let lowerIndex = min(max(Int(floor(position)), 0), heights.count - 1)
            let upperIndex = min(lowerIndex + 1, heights.count - 1)
            let progress = min(max(position - CGFloat(lowerIndex), 0), 1)
            let lowerCenter = rowCenterY(at: lowerIndex, offsets: offsets, heights: heights)
            let upperCenter = rowCenterY(at: upperIndex, offsets: offsets, heights: heights)
            return lowerCenter + ((upperCenter - lowerCenter) * progress)
        }

        private func clampedScrollOffset(_ offset: CGFloat, activeCenterY: CGFloat, offsets: [CGFloat], heights: [CGFloat]) -> CGFloat {
            guard !heights.isEmpty else { return 0 }
            let firstCenter = rowCenterY(at: 0, offsets: offsets, heights: heights)
            let lastCenter = rowCenterY(at: heights.count - 1, offsets: offsets, heights: heights)
            let upperBound = activeCenterY - firstCenter
            let lowerBound = activeCenterY - lastCenter
            return min(max(offset, lowerBound), upperBound)
        }

        private func nearestRowIndex(to centerY: CGFloat, offsets: [CGFloat], heights: [CGFloat]) -> Int {
            guard !heights.isEmpty else { return 0 }
            var bestIndex = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for index in heights.indices {
                let distance = abs(rowCenterY(at: index, offsets: offsets, heights: heights) - centerY)
                if distance < bestDistance {
                    bestIndex = index
                    bestDistance = distance
                }
            }
            return bestIndex
        }

        private func clampedBrowseCenterY(_ centerY: CGFloat, offsets: [CGFloat], heights: [CGFloat]) -> CGFloat {
            guard !heights.isEmpty else { return centerY }
            let firstCenter = rowCenterY(at: 0, offsets: offsets, heights: heights)
            let lastCenter = rowCenterY(at: heights.count - 1, offsets: offsets, heights: heights)
            return min(max(centerY, firstCenter), lastCenter)
        }

        private func rowIndex(atVisibleY visibleY: CGFloat, ribbonOffset: CGFloat, manualOffset: CGFloat, offsets: [CGFloat], heights: [CGFloat]) -> Int {
            let contentY = visibleY - ribbonOffset - manualOffset + 2
            for index in heights.indices {
                let top = offsets.indices.contains(index) ? offsets[index] : 0
                if contentY >= top, contentY <= top + heights[index] {
                    return index
                }
            }

            return nearestRowIndex(to: contentY, offsets: offsets, heights: heights)
        }

        private func seek(to entry: LyricEntry?, anchorY: CGFloat?) {
            guard let time = entry?.startTime else { return }
            scrollResetGeneration += 1
            pendingSeekAnchorY = anchorY
            manualBrowseCenterY = anchorY
            musicManager.seek(to: time)
            scheduleScrollReset()
        }

        private func scheduleScrollReset() {
            scrollResetGeneration += 1
            let generation = scrollResetGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + manualScrollResetDelay) {
                guard generation == scrollResetGeneration else { return }
                withAnimation(.spring(response: 0.62, dampingFraction: 0.9, blendDuration: 0.12)) {
                    pendingSeekAnchorY = nil
                    manualBrowseCenterY = nil
                }
            }
        }

        private func lyricStyle(distance: CGFloat, browseDistance: CGFloat? = nil) -> (
            fontSize: CGFloat,
            tracking: CGFloat,
            color: Color,
            opacity: Double,
            blurRadius: CGFloat,
            lineOpacity: (Int, Int) -> Double,
            lineBlur: (Int, Int) -> CGFloat
        ) {
            let absDistance = abs(distance)
            let clamped = min(absDistance, 2)
            let focus = max(0, 1 - min(absDistance, 1))
            let fontSize = secondaryFontSize + (currentFontSize - secondaryFontSize) * focus
            let tracking = secondaryTracking + (currentTracking - secondaryTracking) * focus
            let opacity = max(0, 1 - Double(clamped) * 0.32)
            let browseFocus = browseDistance.map { max(0, 1 - min(abs($0), 1)) } ?? 0
            let blur = (clamped * 1.45) * (1 - browseFocus)
            let lineBlurPenalty = 1 - browseFocus
            let color = focus > 0.5 ? primaryColor : secondaryColor

            return (
                fontSize,
                tracking,
                color,
                opacity,
                blur,
                { lineIndex, lineCount in
                    guard lineCount > 1 else { return opacity }
                    if distance < 0 {
                        return lineIndex == 0 ? opacity * 0.62 : opacity
                    }
                    if distance > 0 {
                        return lineIndex == 1 ? opacity * 0.62 : opacity
                    }
                    return opacity
                },
                { lineIndex, lineCount in
                    guard lineCount > 1 else { return blur }
                    if distance < 0 {
                        return lineIndex == 0 ? blur + (1.05 * lineBlurPenalty) : blur
                    }
                    if distance > 0 {
                        return lineIndex == 1 ? blur + (1.05 * lineBlurPenalty) : blur
                    }
                    return blur
                }
            )
        }

        @ViewBuilder
        private func lyricRow(_ entry: LyricEntry, distance: CGFloat, browseDistance: CGFloat?, maxWidth: CGFloat, height: CGFloat) -> some View {
            let style = lyricStyle(distance: distance, browseDistance: browseDistance)
            let lines = displayLines(for: entry.text, maxWidth: maxWidth)
            let focus = max(0, 1 - min(abs(distance), 1))
            let browseFocus = browseDistance.map { max(0, 1 - min(abs($0), 1)) } ?? 0
            let fontSize = entry.isPrelude
                ? secondaryPreludeFontSize + ((currentPreludeFontSize - secondaryPreludeFontSize) * focus)
                : style.fontSize
            let tracking = entry.isPrelude ? preludeTracking : style.tracking
            let targetFontSize = entry.isPrelude ? currentPreludeFontSize : currentFontSize
            let browseScale = 1 + (browseFocus * max(0, (targetFontSize / max(fontSize, 1)) - 1))

            VStack(alignment: stackAlignment, spacing: distance == 0 ? 5 : 4) {
                lyricLine(
                    lines.first ?? "",
                    fontSize: fontSize,
                    tracking: tracking,
                    color: style.color,
                    opacity: style.lineOpacity(0, lines.count),
                    blurRadius: style.lineBlur(0, lines.count)
                )
                if lines.count > 1 {
                    lyricLine(
                        lines[1],
                        fontSize: fontSize,
                        tracking: tracking,
                        color: style.color,
                        opacity: style.lineOpacity(1, lines.count),
                        blurRadius: style.lineBlur(1, lines.count)
                    )
                }
            }
            .frame(
                height: height,
                alignment: distance < -0.35 ? .bottom : .top
            )
            .scaleEffect(browseScale, anchor: isCentered ? .center : .leading)
            .animation(.spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.04), value: browseScale)
        }

        var body: some View {
            TimelineView(.animation(minimumInterval: musicManager.isPlaying ? (1.0 / 30.0) : nil)) { timeline in
                let elapsed = estimatedElapsed(at: timeline.date)
                let visualElapsed = musicManager.songDuration > 0
                    ? min(elapsed + lyricVisualLeadTime, musicManager.songDuration)
                    : elapsed + lyricVisualLeadTime
                let state = lyricState(at: visualElapsed)

                GeometryReader { geometry in
                    let layout = layoutCache.layout(for: state.layoutKey, width: geometry.size.width) {
                        preparedLayout(from: state, maxWidth: geometry.size.width)
                    }
                    let proposedCurrentIndex = currentExpandedIndex(for: state, layout: layout, elapsed: visualElapsed)
                    let canHoldPauseIndex =
                        !musicManager.isPlaying
                        && lastResolvedLayoutKey == state.layoutKey
                        && (pauseIndexHoldUntil.map { timeline.date < $0 } ?? false)
                    let heldCurrentIndex = canHoldPauseIndex
                        ? max(proposedCurrentIndex, min(lastResolvedCurrentIndex, max(0, layout.entries.count - 1)))
                        : proposedCurrentIndex
                    let currentIndex = min(max(heldCurrentIndex, 0), max(0, layout.entries.count - 1))
                    let lyricPosition = CGFloat(currentIndex)
                    let rowHeights = layout.rowHeights
                    let rowOffsets = layout.rowOffsets
                    let activeCenterY = interpolatedCenterY(for: lyricPosition, offsets: rowOffsets, heights: rowHeights)
                    let resolvedSeekAnchorY = pendingSeekAnchorY.map { clampedBrowseCenterY($0, offsets: rowOffsets, heights: rowHeights) }
                    let pendingAnchorResolved = resolvedSeekAnchorY.map { abs($0 - activeCenterY) < 1.5 } ?? false
                    let browseCenterY = manualBrowseCenterY.map { clampedBrowseCenterY($0, offsets: rowOffsets, heights: rowHeights) }
                    let ribbonOffset = (geometry.size.height / 2) - activeCenterY
                    let manualOffset = browseCenterY.map { activeCenterY - $0 } ?? 0
                    let browsedCenterIndex = nearestRowIndex(to: activeCenterY - manualOffset, offsets: rowOffsets, heights: rowHeights)
                    let isBrowsing = browseCenterY != nil
                    let visibleCenterIndex = isBrowsing ? browsedCenterIndex : currentIndex
                    let focusPosition = CGFloat(visibleCenterIndex)
                    let visibleStart = max(0, min(currentIndex, visibleCenterIndex) - renderedNeighborCount)
                    let visibleEnd = min(layout.entries.count - 1, max(currentIndex, visibleCenterIndex) + renderedNeighborCount)
                    let currentRenderedID = layout.entries.indices.contains(currentIndex) ? layout.entries[currentIndex].id : state.currentID

                    ZStack(alignment: .topLeading) {
                        if visibleStart <= visibleEnd {
                            ForEach(visibleStart...visibleEnd, id: \.self) { index in
                                let entry = layout.entries[index]
                                lyricRow(
                                    entry,
                                    distance: CGFloat(index) - lyricPosition,
                                    browseDistance: isBrowsing ? CGFloat(index) - focusPosition : nil,
                                    maxWidth: geometry.size.width,
                                    height: rowHeights.indices.contains(index) ? rowHeights[index] : currentLineSlotHeight
                                )
                                .offset(y: rowOffsets.indices.contains(index) ? rowOffsets[index] : 0)
                            }
                        }
                    }
                    .onChange(of: currentIndex) { _, newValue in
                        lastResolvedCurrentIndex = newValue
                        lastResolvedLayoutKey = state.layoutKey
                    }
                    .onChange(of: state.layoutKey) { _, newValue in
                        lastResolvedLayoutKey = newValue
                        lastResolvedCurrentIndex = currentIndex
                    }
                    .onChange(of: currentRenderedID) { _, _ in
                        guard pendingAnchorResolved else { return }
                        pendingSeekAnchorY = nil
                        manualBrowseCenterY = nil
                    }
                    .frame(width: geometry.size.width)
                    .offset(y: ribbonOffset + manualOffset)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .offset(y: -2)
                    .contentShape(Rectangle())
                    .overlay {
                        LyricsEventMonitorView(
                            onScroll: { delta in
                                pendingSeekAnchorY = nil
                                let currentBrowseCenterY = browseCenterY ?? activeCenterY
                                manualBrowseCenterY = clampedBrowseCenterY(
                                    currentBrowseCenterY - delta,
                                    offsets: rowOffsets,
                                    heights: rowHeights
                                )
                                scheduleScrollReset()
                            },
                            onClick: { visibleY in
                                let adjustedVisibleY = visibleY + lyricsHitTestTopInset
                                let tappedIndex = rowIndex(
                                    atVisibleY: adjustedVisibleY,
                                    ribbonOffset: ribbonOffset,
                                    manualOffset: manualOffset,
                                    offsets: rowOffsets,
                                    heights: rowHeights
                                )
                                let tappedCenterY = rowCenterY(at: tappedIndex, offsets: rowOffsets, heights: rowHeights)
                                seek(
                                    to: layout.entries.indices.contains(tappedIndex) ? layout.entries[tappedIndex] : nil,
                                    anchorY: tappedCenterY
                                )
                            }
                        )
                        .allowsHitTesting(false)
                    }
                    .animation(.spring(response: 0.50, dampingFraction: 0.9, blendDuration: 0.08), value: currentRenderedID)
                }
                .clipped()
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .white.opacity(0.35), location: 0.46),
                                .init(color: .white, location: 1.00),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                            .frame(height: 25)
                        Rectangle().fill(Color.white)
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.00),
                                .init(color: .white.opacity(0.35), location: 0.54),
                                .init(color: .clear, location: 1.00),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                            .frame(height: 25)
                    }
                }
            }
            .onChange(of: musicManager.isPlaying) { _, isPlaying in
                if isPlaying {
                    pauseIndexHoldUntil = nil
                } else {
                    pauseIndexHoldUntil = Date().addingTimeInterval(pauseIndexHoldDuration)
                }
            }
        }

    }

    @ViewBuilder
    private var stackContent: some View {
        let timers = visibleQuickTimersForStack
        ZStack(alignment: .bottomLeading) {
            if animator.showsMediaCard {
                panelCard(
                    size: mediaCardSize,
                    liquidRefreshRate: animator.isPresented ? (1.0 / 30.0) : 0.25,
                    sharedBackdropOrigin: CGPoint(
                        x: 0,
                        y: max(0, panelSize.height - mediaCardSize.height)
                    )
                ) {
                    mediaPanelContent
                }
                .zIndex(0)
            }

            ForEach(Array(timers.enumerated()), id: \.element.id) { index, timer in
                let isReadOnly = timerManager.isMirroredSystemTimer(timer)
                let rawExitProgress = exitingTimerProgress[timer.id] ?? 0
                let visualExitProgress = timerVisualExitProgress(rawExitProgress)
                let verticalOffset = timerVerticalOffset(
                    for: index,
                    timers: timers,
                    exitProgresses: exitingTimerProgress
                )

                Group {
                    if animator.usesWindowBackdropFallback, hiddenLiveTimerIDs.contains(timer.id) {
                        Color.clear
                            .frame(width: timerCardSize.width, height: timerCardSize.height)
                    } else {
                        panelCard(
                            size: timerCardSize,
                            liquidRefreshRate: timerCardLiquidRefreshRate,
                            darkTintOpacity: usesLightCompatibilityFallbackStyling ? 0.62 : 0.72,
                            sharedBackdropOrigin: CGPoint(
                                x: 0,
                                y: max(0, panelSize.height - timerCardSize.height - verticalOffset)
                            ),
                            usesMacOS27PanelChrome: false
                            ) {
                            LockScreenTimerPanelContent(
                                timer: timer,
                                isReadOnly: isReadOnly,
                                compactProgress: visualMorphProgress,
                                onRemove: {
                                    beginTimerRemoval(timer)
                                }
                            )
                        }
                        .modifier(
                            LockScreenTimerCardRemovalModifier(
                                progress: visualExitProgress,
                                usesWindowBackdropFallback: animator.usesWindowBackdropFallback
                            )
                        )
                    }
                }
                .offset(y: -verticalOffset)
                .allowsHitTesting(visualExitProgress == 0 && !hiddenLiveTimerIDs.contains(timer.id))
                .zIndex(
                    Double(timers.count - index)
                        + ((visualExitProgress > 0 && !animator.usesWindowBackdropFallback) ? 100 : 0)
                )
            }

            ForEach(Array(exitingTimerOverlays.values)) { overlay in
                let rawExitProgress = exitingTimerProgress[overlay.id] ?? 0
                let visualExitProgress = timerVisualExitProgress(rawExitProgress)

                Image(nsImage: overlay.snapshot)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: timerCardSize.width, height: timerCardSize.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
                    .modifier(
                        LockScreenTimerOverlayRemovalModifier(
                            progress: visualExitProgress,
                            usesWindowBackdropFallback: true
                        )
                    )
                    .offset(y: -overlay.baseOffset)
                    .allowsHitTesting(false)
                    .zIndex(500)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .bottomLeading)
    }

    @ViewBuilder
    private func specularHighlights() -> some View {
        GeometryReader { geo in
            let cornerMaskWidth = min(geo.size.width * 0.98, 388)
                let cornerMaskHeight = min(geo.size.height * 0.88, 156)
                let cornerFadeRadius = max(cornerMaskWidth, cornerMaskHeight) * 0.96
                let cornerMask = ZStack(alignment: .topLeading) {
                    RadialGradient(
                        stops: [
                            .init(color: .white, location: 0.00),
                            .init(color: .white, location: 0.56),
                            .init(color: .clear, location: 1.00),
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: cornerFadeRadius
                    )
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0.00),
                                    .init(color: .white, location: 0.58),
                                    .init(color: .clear, location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: cornerMaskWidth, height: cornerMaskHeight)

                    RadialGradient(
                        stops: [
                            .init(color: .white, location: 0.00),
                            .init(color: .white, location: 0.56),
                            .init(color: .clear, location: 1.00),
                        ],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: cornerFadeRadius
                    )
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0.00),
                                    .init(color: .white, location: 0.58),
                                    .init(color: .clear, location: 1.00),
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: cornerMaskWidth, height: cornerMaskHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                    .stroke(specularStrokePrimaryColor, style: StrokeStyle(lineWidth: 2.28, lineCap: .round, lineJoin: .round))
                    .mask(cornerMask)
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                            .stroke(specularStrokeGlowColor, style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round))
                            .blur(radius: liquidGlassCompatibilityFallbackActive ? 0.82 : 0.46)
                            .mask(cornerMask)
                    )
                    .blendMode(specularStrokeBlendMode)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func shadowBalanceHighlights() -> some View {
        GeometryReader { geo in
            let cornerMaskWidth = min(geo.size.width * 0.92, 360)
            let cornerMaskHeight = min(geo.size.height * 0.84, 148)
            let cornerFadeRadius = max(cornerMaskWidth, cornerMaskHeight) * 0.96
            let balanceMask = ZStack(alignment: .topLeading) {
                RadialGradient(
                    stops: [
                        .init(color: .white, location: 0.00),
                        .init(color: .white, location: 0.52),
                        .init(color: .clear, location: 1.00),
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: cornerFadeRadius
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.00),
                            .init(color: .white, location: 0.60),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: cornerMaskWidth, height: cornerMaskHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                RadialGradient(
                    stops: [
                        .init(color: .white, location: 0.00),
                        .init(color: .white, location: 0.52),
                        .init(color: .clear, location: 1.00),
                    ],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: cornerFadeRadius
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.00),
                            .init(color: .white, location: 0.60),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: cornerMaskWidth, height: cornerMaskHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .stroke(
                    balanceStrokePrimaryColor,
                    style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                )
                .mask(balanceMask)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                        .stroke(
                            balanceStrokeGlowColor,
                            style: StrokeStyle(lineWidth: 3.9, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: liquidGlassCompatibilityFallbackActive ? 0.82 : 0.46)
                        .mask(balanceMask)
                )
                .blendMode(specularStrokeBlendMode)
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        stackContent
        .padding(renderBleed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .shadow(color: panelOuterShadowPrimaryColor, radius: 16, x: 0, y: 7)
        .shadow(color: panelOuterShadowSecondaryColor, radius: 22, x: 0, y: 2)
        .animation(Self.morphAnimation, value: morphProgress)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: animator.showsMediaCard)
        .animation(.easeOut(duration: 0.16), value: animator.defersLyricsRenderingDuringResize)
        .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(
            animator.isPresented
                ? .spring(response: 0.24, dampingFraction: 0.90)
                : .spring(response: 0.52, dampingFraction: 0.80),
            value: animator.isPresented
        )
        .onAppear {
            guard !didConfigureVM else { return }
            lockVM.open()
            scheduleFinishedTimerRemovalsIfNeeded()
            rendersLyricsBlock = enableLyrics && !animator.defersLyricsRenderingDuringResize
            lyricsContentOpacity = rendersLyricsBlock ? 1 : 0
            didConfigureVM = true
        }
        .onChange(of: enableLyrics) { enabled in
            updateLyricsRenderState(
                enabled: enabled,
                deferring: animator.defersLyricsRenderingDuringResize,
                delay: enabled ? lyricsOpenRenderDelay : .milliseconds(0)
            )
        }
        .onChange(of: animator.defersLyricsRenderingDuringResize) { deferring in
            updateLyricsRenderState(enabled: enableLyrics, deferring: deferring)
        }
        .onChange(of: activeQuickTimersForLockScreen.map { "\($0.id.uuidString)-\($0.didFinish)-\($0.remainingSeconds <= 0)" }) { _ in
            scheduleFinishedTimerRemovalsIfNeeded()
        }
        .onDisappear {
            lyricsRenderTask?.cancel()
            lyricsRenderTask = nil
            timerRemovalTasks.values.forEach { $0.cancel() }
            timerRemovalTasks.removeAll()
            timerBackdropReleaseTasks.values.forEach { $0.cancel() }
            timerBackdropReleaseTasks.removeAll()
            exitingTimerProgress.removeAll()
            hiddenLiveTimerIDs.removeAll()
            exitingTimerOverlays.removeAll()
            animator.timerExitingCount = 0
            animator.releasedBackdropTimerIDs.removeAll()
        }
    }

    private func timerVerticalOffset(
        for index: Int,
        timers: [QuickTimer],
        exitProgresses: [UUID: CGFloat]
    ) -> CGFloat {
        let mediaBase = animator.showsMediaCard ? (mediaCardSize.height + Self.stackSpacing) : 0
        guard index < timers.count else { return mediaBase }

        var offset = mediaBase
        if index == timers.count - 1 {
            return offset
        }

        for belowIndex in stride(from: timers.count - 1, through: index + 1, by: -1) {
            let belowTimer = timers[belowIndex]
            let progress = timerLayoutCollapseProgress(exitProgresses[belowTimer.id] ?? 0)
            let heightContribution = timerCardSize.height * (1 - progress)
            let spacingContribution = Self.stackSpacing * (1 - progress)
            offset += heightContribution + spacingContribution
        }

        return offset
    }

    private func scheduleFinishedTimerRemovalsIfNeeded() {
        for timer in activeQuickTimersForLockScreen {
            guard !timerManager.isMirroredSystemTimer(timer) else { continue }
            guard timer.didFinish || timer.remainingSeconds <= 0 else { continue }
            beginTimerRemoval(timer)
        }
    }

    private func beginTimerRemoval(_ timer: QuickTimer) {
        guard !timerManager.isMirroredSystemTimer(timer) else { return }
        guard timerRemovalTasks[timer.id] == nil else { return }

        exitingTimerProgress[timer.id] = 0
        animator.releasedBackdropTimerIDs.remove(timer.id)
        animator.timerExitingCount += 1
        var usesOverlayExit = false
        if animator.usesWindowBackdropFallback {
            let timers = activeQuickTimersForLockScreen
            if let index = timers.firstIndex(where: { $0.id == timer.id }) {
                let baseOffset = timerVerticalOffset(
                    for: index,
                    timers: timers,
                    exitProgresses: exitingTimerProgress
                )
                let cardRect = CGRect(
                    x: 0,
                    y: baseOffset,
                    width: timerCardSize.width,
                    height: timerCardSize.height
                )
                if let snapshot = LockScreenPanelManager.shared.captureTimerCardSnapshot(
                    panelSize: panelSize,
                    cardRect: cardRect
                ) {
                    exitingTimerOverlays[timer.id] = ExitingTimerOverlay(
                        id: timer.id,
                        snapshot: snapshot,
                        baseOffset: baseOffset
                    )
                    hiddenLiveTimerIDs.insert(timer.id)
                    usesOverlayExit = true
                }
            }
        }

        if usesOverlayExit {
            animator.releasedBackdropTimerIDs.insert(timer.id)
        } else {
            timerBackdropReleaseTasks[timer.id] = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                animator.releasedBackdropTimerIDs.insert(timer.id)
                animator.timerExitingCount = max(0, animator.timerExitingCount - 1)
                timerBackdropReleaseTasks[timer.id] = nil
            }
        }
        withAnimation(.timingCurve(0.18, 0.96, 0.16, 1.0, duration: 0.56)) {
            exitingTimerProgress[timer.id] = 1
        }
        timerRemovalTasks[timer.id] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(575))
            guard !Task.isCancelled else { return }
            if let backdropReleaseTask = timerBackdropReleaseTasks.removeValue(forKey: timer.id) {
                backdropReleaseTask.cancel()
                animator.timerExitingCount = max(0, animator.timerExitingCount - 1)
            } else if usesOverlayExit {
                animator.timerExitingCount = max(0, animator.timerExitingCount - 1)
            }
            animator.releasedBackdropTimerIDs.remove(timer.id)
            hiddenLiveTimerIDs.remove(timer.id)
            exitingTimerOverlays.removeValue(forKey: timer.id)
            QuickTimerManager.shared.stopTimer(timer)
            exitingTimerProgress.removeValue(forKey: timer.id)
            timerRemovalTasks[timer.id] = nil
        }
    }

    private func timerVisualExitProgress(_ raw: CGFloat) -> CGFloat {
        let lead = normalizedProgress(raw, start: 0.0, end: 0.88)
        let tail = normalizedProgress(raw, start: 0.52, end: 1.0)
        let shapedLead = smootherstep(lead)
        let shapedTail = smoothstep(tail)
        return min(1, (shapedLead * 0.76) + (shapedTail * 0.24))
    }

    private func timerLayoutCollapseProgress(_ raw: CGFloat) -> CGFloat {
        let start = animator.usesWindowBackdropFallback ? 0.30 : 0.14
        let end = animator.usesWindowBackdropFallback ? 1.0 : 0.98
        let shifted = normalizedProgress(raw, start: start, end: end)
        let body = smootherstep(shifted)
        let tail = smoothstep(normalizedProgress(shifted, start: 0.58, end: 1.0))
        return min(1, (body * 0.82) + (tail * 0.18))
    }

    private func normalizedProgress(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - (2 * clamped))
    }

    private func smootherstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * clamped * (clamped * ((clamped * 6) - 15) + 10)
    }
}

private struct LockScreenTimerCardRemovalModifier: ViewModifier {
    let progress: CGFloat
    let usesWindowBackdropFallback: Bool

    func body(content: Content) -> some View {
        let clamped = min(max(progress, 0), 1)
        let fallbackBlurProgress = smootherstep(normalizedProgress(clamped, start: 0.0, end: 0.68))
        let fallbackOpacityProgress = smootherstep(normalizedProgress(clamped, start: 0.42, end: 0.84))
        let visualProgress = usesWindowBackdropFallback ? fallbackBlurProgress : clamped
        let xScale = 1 - (visualProgress * 0.016)
        let yScale = 1 - (visualProgress * 0.074)
        let downwardDrift = usesWindowBackdropFallback ? (visualProgress * 3.4) : (visualProgress * 5.2)
        let blurRadius = usesWindowBackdropFallback ? 0.0 : (clamped * 13)
        let opacity = 1 - Double(usesWindowBackdropFallback ? fallbackOpacityProgress : visualProgress)
        let saturation = usesWindowBackdropFallback ? 1.0 : Double(1 - (clamped * 0.28))
        let brightness = usesWindowBackdropFallback ? 0.0 : (-0.025 * Double(clamped))

        content
            .compositingGroup()
            .scaleEffect(x: xScale, y: yScale, anchor: .center)
            .blur(radius: blurRadius)
            .saturation(saturation)
            .brightness(brightness)
            .offset(y: downwardDrift)
            .opacity(opacity)
    }

    private func normalizedProgress(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - (2 * clamped))
    }

    private func smootherstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * clamped * (clamped * ((clamped * 6) - 15) + 10)
    }
}

private struct LockScreenTimerOverlayRemovalModifier: ViewModifier {
    let progress: CGFloat
    let usesWindowBackdropFallback: Bool

    func body(content: Content) -> some View {
        let clamped = min(max(progress, 0), 1)
        let blurProgress = smootherstep(normalizedProgress(clamped, start: 0.02, end: 0.58))
        let opacityProgress = smootherstep(normalizedProgress(clamped, start: 0.14, end: 0.92))
        let scaleProgress = smootherstep(normalizedProgress(clamped, start: 0.0, end: 0.82))
        let xScale = 1 - (scaleProgress * 0.012)
        let yScale = 1 - (scaleProgress * 0.060)
        let downwardDrift = scaleProgress * 1.8
        let blurRadius = usesWindowBackdropFallback ? 0.0 : (blurProgress * 13.0)
        let opacity = 1 - Double(opacityProgress)
        let saturation = usesWindowBackdropFallback ? 1.0 : Double(1 - (clamped * 0.12))
        let brightness = usesWindowBackdropFallback ? 0.0 : (-0.008 * Double(clamped))

        content
            .compositingGroup()
            .scaleEffect(x: xScale, y: yScale, anchor: .center)
            .blur(radius: blurRadius)
            .saturation(saturation)
            .brightness(brightness)
            .offset(y: downwardDrift)
            .opacity(opacity)
    }

    private func normalizedProgress(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - (2 * clamped))
    }

    private func smootherstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * clamped * (clamped * ((clamped * 6) - 15) + 10)
    }
}

private struct LockScreenTimerProgressRing: View {
    let progressRemaining: Double

    private var clampedProgress: Double {
        max(0, min(1, progressRemaining))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 6)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    Color(nsColor: .systemOrange),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: clampedProgress)
        }
    }
}

private struct LockScreenTimerActionButton: View {
    let systemImage: String
    let isEnabled: Bool
    let fillColor: Color
    let foregroundColor: Color
    let strokeColor: Color?
    let iconSize: CGFloat
    let iconWeight: Font.Weight
    let iconOffsetX: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                if let strokeColor {
                    Circle()
                        .stroke(strokeColor, lineWidth: 1)
                }
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: iconWeight))
                    .foregroundStyle(foregroundColor)
                    .offset(x: iconOffsetX)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct LockScreenAnimatedTimerDigitsText: View {
    let text: String
    let value: Int
    let color: Color
    let font: Font
    let reservedText: String

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(reservedText)
                .font(font)
                .monospacedDigit()
                .opacity(0)
                .accessibilityHidden(true)

            Text(text)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .allowsTightening(true)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.22), value: value)
        }
        .drawingGroup()
    }
}

private struct LockScreenTimerPanelContent: View {
    @ObservedObject var timer: QuickTimer
    let isReadOnly: Bool
    let compactProgress: CGFloat
    let onRemove: () -> Void

    private let timerOrange = Color(nsColor: .systemOrange)
    private var isFinished: Bool {
        timer.didFinish || timer.remainingSeconds <= 0
    }
    private var clampedCompactProgress: CGFloat {
        min(max(compactProgress, 0), 1)
    }
    private var timerLabelOpacity: Double {
        Double(max(0, 1 - min(1, clampedCompactProgress * 1.8)))
    }
    private var timerLabelWidth: CGFloat {
        76 * (1 - clampedCompactProgress)
    }
    private var timerLabelScale: CGFloat {
        1 - (clampedCompactProgress * 0.06)
    }

    var body: some View {
        let timerReservedText = String(
            repeating: "0",
            count: max(1, timer.displayTime.count - 3)
        ) + ":00"

        HStack(spacing: 10) {
            LockScreenTimerActionButton(
                systemImage: "xmark",
                isEnabled: !isReadOnly,
                fillColor: isReadOnly ? Color.white.opacity(0.04) : Color.white.opacity(0.20),
                foregroundColor: isReadOnly ? Color.white.opacity(0.20) : Color.white.opacity(0.96),
                strokeColor: isReadOnly ? Color.white.opacity(0.14) : nil,
                iconSize: 21,
                iconWeight: .semibold,
                iconOffsetX: 0
            ) {
                onRemove()
            }

            LockScreenTimerActionButton(
                systemImage: isFinished ? "arrow.clockwise" : (timer.isRunning ? "pause.fill" : "play.fill"),
                isEnabled: !isReadOnly,
                fillColor: isReadOnly ? Color.white.opacity(0.04) : timerOrange.opacity(0.28),
                foregroundColor: isReadOnly ? Color.white.opacity(0.20) : timerOrange,
                strokeColor: isReadOnly ? Color.white.opacity(0.14) : nil,
                iconSize: 19,
                iconWeight: .heavy,
                iconOffsetX: isFinished ? 0 : (timer.isRunning ? 0 : 1.2)
            ) {
                QuickTimerManager.shared.toggleTimer(timer)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 8) {
                Text("Timer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(timerOrange)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .multilineTextAlignment(.trailing)
                    .frame(width: timerLabelWidth, alignment: .trailing)
                    .padding(.bottom, 5)
                    .opacity(timerLabelOpacity)
                    .scaleEffect(timerLabelScale, anchor: .trailing)
                    .layoutPriority(10)
                    .zIndex(10)

                LockScreenAnimatedTimerDigitsText(
                    text: timer.displayTime,
                    value: timer.remainingSeconds,
                    color: timerOrange,
                    font: .system(size: 39, weight: .light),
                    reservedText: timerReservedText
                )
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.trailing)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct LockScreenExpandedAlbumArtOverlay: View {
    let artSize: CGFloat
    let shadowBleed: CGFloat
    let sourceOffset: CGSize
    let sourceScale: CGFloat
    let onClose: () -> Void
    @State private var displayedAlbumArt: NSImage = MusicManager.shared.albumArt
    @State private var incomingAlbumArt: NSImage?
    @State private var incomingOpacity: CGFloat = 0
    @State private var crossfadeTask: Task<Void, Never>?
    @State private var isVisible = false

    @ViewBuilder
    private func albumArtImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
    }

    private func startCrossfade(to image: NSImage) {
        crossfadeTask?.cancel()
        incomingAlbumArt = image
        incomingOpacity = 0

        withAnimation(.easeInOut(duration: 0.18)) {
            incomingOpacity = 1
        }

        crossfadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(190))
            displayedAlbumArt = image
            incomingAlbumArt = nil
            incomingOpacity = 0
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .frame(width: artSize - 2, height: artSize - 2)
                    .blur(radius: 18)
                    .offset(y: 10)

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: artSize + 14, height: artSize + 14)
                    .blur(radius: 34)
                    .offset(y: 20)

                ZStack {
                    albumArtImage(displayedAlbumArt)

                    if let incomingAlbumArt {
                        albumArtImage(incomingAlbumArt)
                            .opacity(incomingOpacity)
                    }
                }
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .scaleEffect(isVisible ? 1 : sourceScale)
            .offset(x: isVisible ? 0 : sourceOffset.width, y: isVisible ? 0 : -sourceOffset.height)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.84, blendDuration: 0.14), value: isVisible)
            .onTapGesture {
                onClose()
            }
        }
        .frame(width: artSize + shadowBleed * 2, height: artSize + shadowBleed * 2)
        .onAppear {
            isVisible = true
            displayedAlbumArt = MusicManager.shared.albumArt
            incomingAlbumArt = nil
            incomingOpacity = 0
        }
        .onReceive(MusicManager.shared.$albumArtFlipEventID.dropFirst()) { _ in
            startCrossfade(to: MusicManager.shared.albumArtFlipImage)
        }
        .onDisappear {
            isVisible = false
            crossfadeTask?.cancel()
            crossfadeTask = nil
        }
    }
}

// MARK: - Full-screen blurred album art backdrop

// MARK: - Album palette extraction

private enum AlbumPaletteExtractor {
    struct PaletteColor {
        var r, g, b: Float
        var weight: Float
        var color: Color { Color(red: Double(r), green: Double(g), blue: Double(b)) }
        func distanceSq(to o: PaletteColor) -> Float {
            (r-o.r)*(r-o.r) + (g-o.g)*(g-o.g) + (b-o.b)*(b-o.b)
        }
    }

    // HSV saturation (0-1) from linear RGB.
    private static func sat(r: Float, g: Float, b: Float) -> Float {
        let mx = max(r, g, b), mn = min(r, g, b)
        return mx > 0 ? (mx - mn) / mx : 0
    }

    static func extract(from image: NSImage) -> [PaletteColor] {
        let side = 64
        guard
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let ctx = CGContext(
                data: nil, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return [] }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Saturation-boosted sampling: vivid pixels are duplicated so k-means
        // doesn't drown them under a sea of flat neutrals.
        // sat > 0.5  → ×2,  sat > 0.72 → ×3
        var samples: [(Float, Float, Float)] = []
        samples.reserveCapacity(side * side * 3)
        for i in 0..<(side * side) {
            let base = i * 4
            let a = Float(px[base + 3]) / 255
            guard a > 0.3 else { continue }
            let inv = 1 / a
            let r = min(1, Float(px[base])     / 255 * inv)
            let g = min(1, Float(px[base + 1]) / 255 * inv)
            let b = min(1, Float(px[base + 2]) / 255 * inv)
            samples.append((r, g, b))
            let s = sat(r: r, g: g, b: b)
            if s > 0.50 { samples.append((r, g, b)) }
            if s > 0.72 { samples.append((r, g, b)) }
        }
        guard samples.count > 20 else { return [] }

        // k-means, k=12 for finer granularity
        let k = 12
        var centers = (0..<k).map { _ in samples[Int.random(in: 0..<samples.count)] }
        var assignments = [Int](repeating: 0, count: samples.count)
        for _ in 0..<15 {
            var changed = false
            for (i, (sr, sg, sb)) in samples.enumerated() {
                var best = 0; var bestD = Float.infinity
                for (j, (cr, cg, cb)) in centers.enumerated() {
                    let d = (sr-cr)*(sr-cr) + (sg-cg)*(sg-cg) + (sb-cb)*(sb-cb)
                    if d < bestD { bestD = d; best = j }
                }
                if assignments[i] != best { assignments[i] = best; changed = true }
            }
            if !changed { break }
            var sums = [(r: Float, g: Float, b: Float, n: Float)](repeating: (0,0,0,0), count: k)
            for (i, (sr, sg, sb)) in samples.enumerated() {
                let j = assignments[i]
                sums[j] = (sums[j].r+sr, sums[j].g+sg, sums[j].b+sb, sums[j].n+1)
            }
            for j in 0..<k where sums[j].n > 0 {
                centers[j] = (sums[j].r/sums[j].n, sums[j].g/sums[j].n, sums[j].b/sums[j].n)
            }
        }

        var counts = [Int](repeating: 0, count: k)
        for a in assignments { counts[a] += 1 }
        let total = Float(samples.count)

        // Two-tier filter: normal colors need ≥ 4%, vivid accent colors only need ≥ 0.8%.
        var palette = zip(centers, counts).compactMap { c, n -> PaletteColor? in
            guard n > 0 else { return nil }
            let w = Float(n) / total
            let s = sat(r: c.0, g: c.1, b: c.2)
            guard w >= 0.04 || (s > 0.45 && w >= 0.008) else { return nil }
            return PaletteColor(r: c.0, g: c.1, b: c.2, weight: w)
        }
        palette.sort { $0.weight > $1.weight }

        // Merge perceptually close clusters (but never merge vivid into dull).
        let mergeThresh: Float = 0.10 * 0.10
        var merged: [PaletteColor] = []
        for color in palette {
            let cs = sat(r: color.r, g: color.g, b: color.b)
            if let idx = merged.firstIndex(where: { candidate in
                // Don't absorb a vivid accent into a desaturated cluster
                let ms = sat(r: candidate.r, g: candidate.g, b: candidate.b)
                guard !(cs > 0.45 && ms < 0.30) else { return false }
                return color.distanceSq(to: candidate) < mergeThresh
            }) {
                let w0 = merged[idx].weight, w1 = color.weight, wt = w0 + w1
                merged[idx] = PaletteColor(
                    r: (merged[idx].r*w0 + color.r*w1) / wt,
                    g: (merged[idx].g*w0 + color.g*w1) / wt,
                    b: (merged[idx].b*w0 + color.b*w1) / wt,
                    weight: wt
                )
            } else {
                merged.append(color)
            }
        }
        let wSum = merged.map(\.weight).reduce(0, +)
        if wSum > 0 { for i in merged.indices { merged[i].weight /= wSum } }
        return merged.sorted { $0.weight > $1.weight }
    }

    // Fill `count` mesh slots proportionally to each color's weight, then shuffle.
    static func meshColors(from palette: [PaletteColor], count: Int) -> [Color] {
        guard !palette.isEmpty else { return [Color](repeating: .black, count: count) }
        var slots: [Color] = []
        slots.reserveCapacity(count + palette.count)
        for c in palette {
            let n = max(1, Int((c.weight * Float(count)).rounded()))
            for _ in 0..<n { slots.append(c.color) }
        }
        while slots.count < count { slots.append(palette[0].color) }
        slots = Array(slots.prefix(count))
        slots.shuffle()
        return slots
    }
}

// MARK: - Mesh gradient backdrop

@available(macOS 15.0, *)
struct LockScreenExpandedAlbumArtBackdropOverlay: View {
    let size: NSSize

    private static let gridW = 4
    private static let gridH = 4
    private static let gridCount = gridW * gridH

    @State private var displayedColors: [Color] = .init(repeating: .black, count: gridCount)
    @State private var displayedPoints: [SIMD2<Float>] = basePoints()
    @State private var incomingColors: [Color]?
    @State private var incomingPoints: [SIMD2<Float>]?
    @State private var incomingOpacity: CGFloat = 0
    @State private var crossfadeTask: Task<Void, Never>?
    @State private var extractTask: Task<Void, Never>?
    @State private var isVisible = false

    var body: some View {
        ZStack {
            meshView(colors: displayedColors, points: displayedPoints)
            if let ic = incomingColors, let ip = incomingPoints {
                meshView(colors: ic, points: ip).opacity(incomingOpacity)
            }
            LinearGradient(
                colors: [.black.opacity(0.30), .clear, .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: isVisible)
        .onAppear {
            extractAndApply(image: MusicManager.shared.albumArt, animated: false)
            withAnimation(.easeInOut(duration: 0.4)) { isVisible = true }
        }
        .onReceive(MusicManager.shared.$albumArtFlipEventID.dropFirst()) { _ in
            extractAndApply(image: MusicManager.shared.albumArtFlipImage, animated: true)
        }
        .onDisappear {
            isVisible = false
            extractTask?.cancel()
            crossfadeTask?.cancel()
        }
    }

    @ViewBuilder
    private func meshView(colors: [Color], points: [SIMD2<Float>]) -> some View {
        MeshGradient(
            width: Self.gridW, height: Self.gridH,
            points: points, colors: colors,
            smoothsColors: true
        )
        .saturation(1.2)
        .brightness(-0.05)
    }

    private func extractAndApply(image: NSImage, animated: Bool) {
        extractTask?.cancel()
        extractTask = Task.detached(priority: .userInitiated) {
            let palette = AlbumPaletteExtractor.extract(from: image)
            let colors = AlbumPaletteExtractor.meshColors(from: palette, count: Self.gridCount)
            let points = Self.jitteredPoints()
            let cancelled = Task.isCancelled
            await MainActor.run {
                guard !cancelled else { return }
                if animated {
                    startCrossfade(toColors: colors, points: points)
                } else {
                    displayedColors = colors
                    displayedPoints = points
                }
            }
        }
    }

    private func startCrossfade(toColors colors: [Color], points: [SIMD2<Float>]) {
        crossfadeTask?.cancel()
        incomingColors = colors
        incomingPoints = points
        incomingOpacity = 0
        withAnimation(.easeInOut(duration: 0.5)) { incomingOpacity = 1 }
        crossfadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            displayedColors = colors
            displayedPoints = points
            incomingColors = nil
            incomingPoints = nil
            incomingOpacity = 0
        }
    }

    private static func basePoints() -> [SIMD2<Float>] {
        (0..<gridH).flatMap { row in
            (0..<gridW).map { col in
                SIMD2(Float(col) / Float(gridW - 1), Float(row) / Float(gridH - 1))
            }
        }
    }

    private static func jitteredPoints() -> [SIMD2<Float>] {
        let jitter: Float = 0.07
        return (0..<gridH).flatMap { row in
            (0..<gridW).map { col -> SIMD2<Float> in
                let isEdge = row == 0 || row == gridH-1 || col == 0 || col == gridW-1
                let x = Float(col) / Float(gridW-1) + (isEdge ? 0 : Float.random(in: -jitter...jitter))
                let y = Float(row) / Float(gridH-1) + (isEdge ? 0 : Float.random(in: -jitter...jitter))
                return SIMD2(x, y)
            }
        }
    }
}

// MARK: - LoginUIKit lock-screen reconstruction
final class LockScreenUIKitReconstructionNSView: NSView {
    private var didInstall = false
    private var statusVC: NSViewController?
    private var dateVC: NSViewController?
    private var bigTimeVC: NSViewController?
    private var tickTimer: Timer?

    private var bigTimeTopConstraint: NSLayoutConstraint?
    private var dateTopConstraint: NSLayoutConstraint?
    private var statusTopConstraint: NSLayoutConstraint?
    private var statusTrailingConstraint: NSLayoutConstraint?
    private var recoveredBigTimeConstraintConstant: CGFloat = 134.49

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if !didInstall { didInstall = true; installControllers() }
            startTicking()
        } else {
            stopTicking()
        }
    }

    override func layout() {
        updateLoginUIKitConstraints()
        super.layout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLoginUIKitConstraints()
    }

    deinit { stopTicking() }

    // MARK: - Install

    private func installControllers() {
        guard dlopen(
            "/System/Library/PrivateFrameworks/LoginUIKit.framework/LoginUIKit",
            RTLD_NOW
        ) != nil else {
            NSLog("QuartzNotch: LoginUIKit dlopen failed – %@", String(cString: dlerror()))
            return
        }

        let statusVC  = makeVC("LUI2StatusViewController")
        let bigTimeVC = makeVC("LUI2BigTimeViewController")
        let dateVC    = makeVC("LUI2DateViewController")

        guard let bigTimeVC, let dateVC else {
            NSLog("QuartzNotch: LUI2BigTimeViewController / LUI2DateViewController unavailable")
            return
        }
        self.bigTimeVC = bigTimeVC

        applyClockSettings(to: [bigTimeVC, dateVC])
        recoveredBigTimeConstraintConstant = readBigTimeConstraintConstant() ?? 134.49

        if let sv = statusVC?.view {
            sv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sv)
            let top      = sv.topAnchor.constraint(equalTo: topAnchor)
            let trailing = sv.trailingAnchor.constraint(equalTo: trailingAnchor)
            statusTopConstraint      = top
            statusTrailingConstraint = trailing
            NSLayoutConstraint.activate([
                top,
                trailing,
                sv.heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),
            ])
            statusVC?.viewWillAppear()
            statusVC?.viewDidAppear()
        }

        let bigTimeView = bigTimeVC.view
        let dateView    = dateVC.view
        bigTimeView.translatesAutoresizingMaskIntoConstraints = false
        dateView.translatesAutoresizingMaskIntoConstraints    = false
        addSubview(dateView)
        addSubview(bigTimeView)

        let dateTop    = dateView.topAnchor.constraint(equalTo: topAnchor)
        let bigTimeTop = bigTimeView.topAnchor.constraint(equalTo: dateView.bottomAnchor)
        dateTopConstraint    = dateTop
        bigTimeTopConstraint = bigTimeTop

        NSLayoutConstraint.activate([
            dateTop,
            dateView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bigTimeTop,
            bigTimeView.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        for vc in [dateVC, bigTimeVC] {
            vc.viewWillAppear()
            vc.viewDidAppear()
        }

        updateLoginUIKitConstraints()
        tick()
    }

    // MARK: - Constraint updates

    private func updateLoginUIKitConstraints() {
        guard bounds.height > 0 else { return }
        dateTopConstraint?.constant    = effectiveLoginContentHeight * 0.09361124277114867
        bigTimeTopConstraint?.constant = recoveredBigTimeConstraintConstant * -0.148
        statusTopConstraint?.constant  = 0
        statusTrailingConstraint?.constant = -20
    }

    private var effectiveLoginContentHeight: CGFloat {
        guard let screen = window?.screen else { return bounds.height }
        let menuBarInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let topSystemInset = max(screen.safeAreaInsets.top, menuBarInset)
        return max(1, bounds.height - topSystemInset)
    }

    // MARK: - Clock settings via LUIClockSettingsManager

    private func applyClockSettings(to controllers: [NSViewController]) {
        guard
            let cls     = NSClassFromString("LUIClockSettingsManager") as? NSObject.Type,
            let manager = cls.perform(NSSelectorFromString("sharedClockSettingsManager"))?.takeUnretainedValue() as? NSObject
        else { return }

        let settingsSel = NSSelectorFromString("clockSettingsForUserWithGUID:")
        guard manager.responds(to: settingsSel) else { return }

        let guid = userGeneratedUID() as NSString?
        guard let settings = manager.perform(settingsSel, with: guid)?.takeUnretainedValue() else { return }

        let applySel = NSSelectorFromString("setClockSettings:")
        for vc in controllers where vc.responds(to: applySel) {
            vc.perform(applySel, with: settings)
        }
    }

    private func readBigTimeConstraintConstant() -> CGFloat? {
        guard let cls = NSClassFromString("LUI2UIController") as? NSObject.Type else { return nil }
        let obj = cls.init()
        let sel = NSSelectorFromString("_bigTimeConstraintConstant")
        guard obj.responds(to: sel),
              let objCls = object_getClass(obj),
              let imp    = class_getMethodImplementation(objCls, sel) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGFloat
        let value = unsafeBitCast(imp, to: Getter.self)(obj, sel)
        return value > 0 ? value : nil
    }

    private func userGeneratedUID() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        p.arguments = [".", "-read", "/Users/\(NSUserName())", "GeneratedUID"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0,
              let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return nil }
        return out.components(separatedBy: .whitespacesAndNewlines)
            .last(where: { !$0.isEmpty && $0 != "GeneratedUID:" })
    }

    // MARK: - Real-time tick

    private func startTicking() {
        guard tickTimer == nil else { return }
        let now = Date()
        let gap = ceil(now.timeIntervalSinceReferenceDate) - now.timeIntervalSinceReferenceDate
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
            self?.tick()
            let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            self?.tickTimer = t
        }
    }

    private func stopTicking() { tickTimer?.invalidate(); tickTimer = nil }

    @objc private func tick() {
        guard let vc = bigTimeVC else { return }
        let sel = NSSelectorFromString("setDate:")
        if vc.responds(to: sel) { vc.perform(sel, with: Date() as NSDate) }
        else { vc.view.setNeedsDisplay(vc.view.bounds) }
    }

    // MARK: - Helpers

    private func makeVC(_ className: String) -> NSViewController? {
        guard let cls = NSClassFromString(className) as? NSViewController.Type else {
            NSLog("QuartzNotch: LoginUIKit class not found – %@", className)
            return nil
        }
        let vc = cls.init(nibName: nil, bundle: nil)
        _ = vc.view
        return vc
    }
}
struct LockScreenLoginUIKitReconstructionView: NSViewRepresentable {
    func makeNSView(context: Context) -> LockScreenUIKitReconstructionNSView {
        LockScreenUIKitReconstructionNSView()
    }
    func updateNSView(_ nsView: LockScreenUIKitReconstructionNSView, context: Context) {}
}

struct LockScreenDesktopRestoreShieldView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

final class LockScreenLiveActivityOverlayModel: ObservableObject {
    enum Mode { case hidden, locked, unlocked }

    @Published private(set) var mode: Mode = .hidden
    @Published var opacity: CGFloat = 0
  /// Horizontal expand/collapse only. This avoids the "drop from the top" feel.
    @Published var widthScale: CGFloat = 0.01
    @Published var dismissStartTime: Date?
    @Published var dismissDuration: TimeInterval = 0
    @Published var dismissStartScale: CGFloat = 1
    @Published var dismissTargetScale: CGFloat = 1

    func setLocked() {
        resetDismiss()
        mode = .locked
        opacity = 1
        widthScale = 1
    }

    func setUnlocked() {
        resetDismiss()
        mode = .unlocked
        opacity = 1
        widthScale = 1
    }

  /// Collapse the overlay horizontally while keeping it pinned.
  /// We keep opacity at 1 so the disappearance reads as a width collapse (like music).
    func collapseForDismiss() {
        resetDismiss()
        widthScale = 0.01
    }

    func startDismiss(to targetScale: CGFloat, duration: TimeInterval) {
        dismissStartScale = widthScale
        dismissTargetScale = targetScale
        dismissDuration = duration
        dismissStartTime = Date()
    }

    func finishDismiss() {
        widthScale = dismissTargetScale
        resetDismiss()
    }

    func hide() {
        resetDismiss()
        mode = .hidden
        opacity = 0
        widthScale = 0.01
    }

    private func resetDismiss() {
        dismissStartTime = nil
        dismissDuration = 0
        dismissStartScale = 1
        dismissTargetScale = 1
    }
}

struct LockScreenLiveActivityOverlay: View {
    @ObservedObject var model: LockScreenLiveActivityOverlayModel
    let notchSize: CGSize

    private let topCornerRadius: CGFloat = 7
    private let sideBreathingRoom: CGFloat = 3

    private var indicatorSide: CGFloat { max(0, notchSize.height - 12) }
    private var physicalNotchLeadingEdge: CGFloat { (totalWidth - notchSize.width) / 2 }
    private var physicalNotchTrailingEdge: CGFloat { physicalNotchLeadingEdge + notchSize.width }
    private var physicalNotchEdgeFadeWidth: CGFloat { max(8, notchSize.height * 0.22) }
    private var physicalNotchEdgeFadeInset: CGFloat { 4 }
    private var totalWidth: CGFloat {
        notchSize.width + indicatorSide * 2 + cornerRadiusInsets.closed.bottom * 2 + sideBreathingRoom * 2
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: model.dismissStartTime == nil)) { context in
            let currentWidthScale = visualWidthScale(at: context.date)

            ZStack(alignment: .leading) {
                content
                    .scaleEffect(x: currentWidthScale, y: 1.0, anchor: .top)

                physicalNotchEdgeOcclusion
                    .mask(alignment: .leading) {
                        notchOcclusionClip(widthScale: currentWidthScale)
                    }
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            indicator
                .frame(width: indicatorSide, height: indicatorSide)
                .padding(.leading, cornerRadiusInsets.closed.bottom + sideBreathingRoom)

            Rectangle()
                .fill(.black)
                .frame(width: notchSize.width - topCornerRadius)
                .padding(.leading, 6)

            Color.clear
                .frame(width: indicatorSide, height: indicatorSide)
                .padding(.trailing, cornerRadiusInsets.closed.bottom + sideBreathingRoom)
        }
        .frame(width: totalWidth, height: notchSize.height, alignment: .leading)
        .background(.black)
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: cornerRadiusInsets.closed.bottom
            )
        )
        .opacity(model.opacity)
        .compositingGroup()
    }

    private var physicalNotchEdgeOcclusion: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.72), location: 0.58),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: physicalNotchEdgeFadeWidth, height: notchSize.height)
            .offset(x: physicalNotchLeadingEdge - physicalNotchEdgeFadeWidth + physicalNotchEdgeFadeInset)

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black.opacity(0.72), location: 0.42),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: physicalNotchEdgeFadeWidth, height: notchSize.height)
            .offset(x: physicalNotchTrailingEdge - physicalNotchEdgeFadeInset)
        }
        .frame(width: totalWidth, height: notchSize.height, alignment: .leading)
        .opacity(model.opacity)
        .allowsHitTesting(false)
    }

    private func notchOcclusionClip(widthScale: CGFloat) -> some View {
        Rectangle()
            .fill(.black)
            .frame(width: totalWidth, height: notchSize.height, alignment: .leading)
            .clipShape(
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: cornerRadiusInsets.closed.bottom
                )
            )
            .scaleEffect(x: widthScale, y: 1.0, anchor: .top)
    }

    private func visualWidthScale(at date: Date) -> CGFloat {
        guard let start = model.dismissStartTime, model.dismissDuration > 0 else {
            return model.widthScale
        }

        let elapsed = date.timeIntervalSince(start)
        let t = CGFloat(max(0, min(1, elapsed / model.dismissDuration)))
        let eased = dismissProgress(t)
        return model.dismissStartScale + (model.dismissTargetScale - model.dismissStartScale) * eased
    }

    private func dismissProgress(_ t: CGFloat) -> CGFloat {
        organicDismissProgress(t)
    }

    private func organicDismissProgress(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        let preMovementEnd: CGFloat = 0.14
        let preMovementDistance: CGFloat = 0.035

        if clamped < preMovementEnd {
            let preProgress = clamped / preMovementEnd
            return preMovementDistance * preProgress * preProgress
        }

        let mainProgress = (clamped - preMovementEnd) / (1 - preMovementEnd)
        return preMovementDistance + (1 - preMovementDistance) * mainDismissProgress(mainProgress)
    }

    private func mainDismissProgress(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))

        if clamped < 0.07 {
            return hermite(x: clamped, x0: 0, x1: 0.07, y0: 0, y1: 0.23, m0: 3.285714, m1: 2.777778)
        }

        if clamped < 0.16 {
            return hermite(x: clamped, x0: 0.07, x1: 0.16, y0: 0.23, y1: 0.48, m0: 2.777778, m1: 1.428571)
        }

        if clamped < 0.30 {
            return hermite(x: clamped, x0: 0.16, x1: 0.30, y0: 0.48, y1: 0.68, m0: 1.428571, m1: 0.7)
        }

        if clamped < 0.50 {
            return hermite(x: clamped, x0: 0.30, x1: 0.50, y0: 0.68, y1: 0.82, m0: 0.7, m1: 0.409091)
        }

        if clamped < 0.72 {
            return hermite(x: clamped, x0: 0.50, x1: 0.72, y0: 0.82, y1: 0.91, m0: 0.409091, m1: 0.305556)
        }

        if clamped < 0.90 {
            return hermite(x: clamped, x0: 0.72, x1: 0.90, y0: 0.91, y1: 0.965, m0: 0.305556, m1: 0.305556)
        }

        return hermite(x: clamped, x0: 0.90, x1: 1, y0: 0.965, y1: 1, m0: 0.305556, m1: 0)
    }

    private func hermite(x: CGFloat,
                         x0: CGFloat,
                         x1: CGFloat,
                         y0: CGFloat,
                         y1: CGFloat,
                         m0: CGFloat,
                         m1: CGFloat) -> CGFloat {
        let h = max(0.001, x1 - x0)
        let t = max(0, min(1, (x - x0) / h))
        let t2 = t * t
        let t3 = t2 * t

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        return max(0, min(1, h00 * y0 + h10 * h * m0 + h01 * y1 + h11 * h * m1))
    }

    @ViewBuilder
    private var indicator: some View {
        LockIconAnimatedView(
            isLocked: model.mode != .unlocked,
            size: 16,
            iconColor: .white
        )
    }
}

@MainActor
final class LockScreenLiveActivityWindowManager {
    static let shared = LockScreenLiveActivityWindowManager()

    private var lockWindow: NSWindow?
    private var lockHosting: NSHostingView<AnyView>?

    private var desktopWindow: NSWindow?
    private var desktopHosting: NSHostingView<AnyView>?

    private let lockModel = LockScreenLiveActivityOverlayModel()
    private let desktopModel = LockScreenLiveActivityOverlayModel()

    private var hideTask: Task<Void, Never>?
    private var isUnlockRunning = false
    private var transitionGeneration: UInt64 = 0

    private var lastScreenUUID: String?
    private var lastNotchSize: CGSize?
    private var lastTotalWidth: CGFloat?
    
    private var coverWindow: NSWindow?
    private var coverImageView: NSImageView?
    private var coverTransitionSequence: UInt64 = 0
    private var coverFadeTask: Task<Void, Never>?

    var hasPreparedDesktopRestoreCover: Bool {
        coverWindow != nil && coverImageView != nil
    }

  // MARK: - Public

  /// Show the "locked" overlay on the requested screen.
  /// - Note: if `preferredScreenUUID` is nil or invalid, fallback to the main screen.
    func showLocked(preferredScreenUUID: String?) {
        let generation = beginTransition()
        hideTask?.cancel()
        hideTask = nil
        isUnlockRunning = false

        desktopModel.hide()
        desktopWindow?.alphaValue = 0
        desktopWindow?.orderOut(nil)

        let screen: NSScreen = {
            if let uuid = preferredScreenUUID,
               let s = NSScreen.screen(withUUID: uuid) { return s }
            return NSScreen.main ?? NSScreen.screens.first!
        }()

        lastScreenUUID = screen.displayUUID

        let notchSize = getClosedNotchSize(screenUUID: screen.displayUUID)
        let (totalWidth, rect) = makeRect(for: notchSize)
        lastNotchSize = notchSize
        lastTotalWidth = totalWidth

        ensureLockWindow(rect: rect, notchSize: notchSize, totalWidth: totalWidth)
        positionWindow(lockWindow!, on: screen, width: totalWidth, height: notchSize.height)

        var tx0 = Transaction()
        tx0.disablesAnimations = true
        withTransaction(tx0) {
            lockModel.setLocked()
            lockModel.widthScale = 0.62
            lockModel.opacity = 1
        }

        if let lockWindow {
            SkyLightOperator.shared.delegateWindow(lockWindow)
            lockWindow.alphaValue = 1
            lockWindow.orderFront(nil)
        }

        if isCurrentTransition(generation) {
            withAnimation(NotchMotion.lockReveal) {
                lockModel.widthScale = 1
            }
        }
    }

    func showUnlockedAndHide(onFinished: (() -> Void)? = nil) {
        if isUnlockRunning { return }
        let generation = beginTransition()
        isUnlockRunning = true
        hideTask?.cancel()

        hideTask = Task { @MainActor in
            defer {
                self.isUnlockRunning = false
                onFinished?()
            }


            let screen: NSScreen = {
                if let uuid = lastScreenUUID, let s = NSScreen.screen(withUUID: uuid) { return s }
                return NSScreen.main ?? NSScreen.screens.first!
            }()

            let notchSize = lastNotchSize ?? getClosedNotchSize(screenUUID: screen.displayUUID)
            let (totalWidth, rect) = makeRect(for: notchSize)

            if let lockWindow {
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    lockWindow.animator().alphaValue = 1
                }
                guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

                lockWindow.setFrame(rect, display: true)
                positionWindow(lockWindow, on: screen, width: totalWidth, height: notchSize.height)

                if let cv = lockWindow.contentView {
                    cv.layoutSubtreeIfNeeded()
                    cv.needsDisplay = true
                    cv.displayIfNeeded()
                }
                lockWindow.displayIfNeeded()
                CATransaction.flush()

                lockModel.setUnlocked()

                try? await Task.sleep(nanoseconds: 960_000_000)
                guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

                await hideDesktopWithAnimation(
                    desktopWindow: lockWindow,
                    model: lockModel,
                    notchSize: notchSize,
                    totalWidth: totalWidth,
                    generation: generation
                )
                guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

                lockModel.hide()
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    lockWindow.animator().alphaValue = 0
                }
                guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

                lockWindow.orderOut(nil)
                SkyLightOperator.shared.undelegateWindow(lockWindow)
                self.lockWindow = nil
                self.lockHosting = nil
                return
            }

            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                desktopModel.setLocked()
                desktopModel.opacity = 1
                desktopModel.widthScale = 1
            }
            guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

            ensureDesktopWindow(rect: rect, notchSize: notchSize, totalWidth: totalWidth)
            guard let desktopWindow else { return }

            positionWindow(desktopWindow, on: screen, width: totalWidth, height: notchSize.height)
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                desktopWindow.animator().alphaValue = 1
            }
            guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

            desktopWindow.orderFront(nil)
            desktopModel.setUnlocked()
            try? await Task.sleep(nanoseconds: 960_000_000)
            guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

            await hideDesktopWithAnimation(desktopWindow: desktopWindow, model: desktopModel, notchSize: notchSize, totalWidth: totalWidth, generation: generation)
            guard self.isCurrentTransition(generation), !Task.isCancelled else { return }

            desktopModel.hide()
            desktopWindow.alphaValue = 0
            desktopWindow.orderOut(nil)
        }
    }

  // MARK: - Desktop dismiss animation (lock/unlock style)

    private func hideDesktopWithAnimation(
        desktopWindow: NSWindow,
        model: LockScreenLiveActivityOverlayModel,
        notchSize: CGSize,
        totalWidth: CGFloat,
        generation: UInt64
    ) async {
        await NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            desktopWindow.animator().alphaValue = 1
        }
        guard isCurrentTransition(generation), !Task.isCancelled else { return }

        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            model.opacity = 1
            model.widthScale = 1
        }

        let duration: TimeInterval = 0.58
        model.startDismiss(
            to: max(0.001, min(1.0, notchSize.width / max(totalWidth, 1))),
            duration: duration
        )
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        guard isCurrentTransition(generation), !Task.isCancelled else { return }

        model.finishDismiss()
        desktopWindow.alphaValue = 0
    }

    func hideImmediately() {
        _ = beginTransition()
        hideTask?.cancel()
        hideTask = nil
        isUnlockRunning = false

        lockModel.hide()
        desktopModel.hide()
        hideDesktopRestoreCoverImmediately()

        lockWindow?.alphaValue = 0
        lockWindow?.orderOut(nil)

        desktopWindow?.alphaValue = 0
        desktopWindow?.orderOut(nil)
    }

    private func beginTransition() -> UInt64 {
        transitionGeneration &+= 1
        return transitionGeneration
    }

    private func isCurrentTransition(_ generation: UInt64) -> Bool {
        generation == transitionGeneration
    }

  // MARK: - Internals (Geometry)

    private func makeRect(for notchSize: CGSize) -> (CGFloat, NSRect) {
        let indicatorSide = max(0, notchSize.height - 12)
        let totalWidth = notchSize.width + indicatorSide * 2 + cornerRadiusInsets.closed.bottom * 2 + 6
        let rect = NSRect(x: 0, y: 0, width: totalWidth, height: notchSize.height)
        return (totalWidth, rect)
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, width: CGFloat, height: CGFloat) {
        let screenFrame = screen.frame
        window.setFrameOrigin(NSPoint(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height))
    }

  // MARK: - Internals (Windows)

    private func ensureLockWindow(rect: NSRect, notchSize: CGSize, totalWidth: CGFloat) {
        if lockWindow == nil {
            let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
            let w = QuartzNotchWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false

            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let root = LockScreenLiveActivityOverlay(model: lockModel, notchSize: notchSize)
                .frame(width: totalWidth, height: notchSize.height)
                .ignoresSafeArea()

            let hosting = NSHostingView(rootView: AnyView(root))
            w.contentView = hosting

            lockWindow = w
            lockHosting = hosting
        } else {
            lockWindow?.setFrame(rect, display: true)

            if let hosting = lockHosting {
                let root = LockScreenLiveActivityOverlay(model: lockModel, notchSize: notchSize)
                    .frame(width: totalWidth, height: notchSize.height)
                    .ignoresSafeArea()
                hosting.rootView = AnyView(root)
            }
        }
    }

    private func ensureDesktopWindow(rect: NSRect, notchSize: CGSize, totalWidth: CGFloat) {
        if desktopWindow == nil {
            let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
            let w = QuartzNotchWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false

            w.level = .mainMenu + 3
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let root = LockScreenLiveActivityOverlay(model: desktopModel, notchSize: notchSize)
                .frame(width: totalWidth, height: notchSize.height)
                .ignoresSafeArea()

            let hosting = NSHostingView(rootView: AnyView(root))
            w.contentView = hosting

            desktopWindow = w
            desktopHosting = hosting
        } else {
            desktopWindow?.setFrame(rect, display: true)

            if let hosting = desktopHosting {
                let root = LockScreenLiveActivityOverlay(model: desktopModel, notchSize: notchSize)
                    .frame(width: totalWidth, height: notchSize.height)
                    .ignoresSafeArea()
                hosting.rootView = AnyView(root)
            }
        }
    }

    func showDesktopRestoreCover(image: NSImage, on screen: NSScreen) {
        coverTransitionSequence &+= 1
        coverFadeTask?.cancel()
        coverFadeTask = nil
        if coverWindow == nil || coverImageView == nil {
            prepareDesktopRestoreCover(image: image, on: screen)
        } else {
            coverWindow?.setFrame(screen.frame, display: true)
            coverImageView?.frame = NSRect(origin: .zero, size: screen.frame.size)
            coverImageView?.image = image
        }
        coverImageView?.layer?.removeAllAnimations()
        coverWindow?.orderFrontRegardless()
        coverWindow?.alphaValue = 1
    }

    func presentPreparedDesktopRestoreCover(on screen: NSScreen) {
        coverTransitionSequence &+= 1
        coverFadeTask?.cancel()
        coverFadeTask = nil
        guard let coverWindow, let coverImageView else { return }
        coverWindow.setFrame(screen.frame, display: true)
        coverImageView.frame = NSRect(origin: .zero, size: screen.frame.size)
        coverImageView.layer?.removeAllAnimations()
        coverWindow.orderFrontRegardless()
        coverWindow.alphaValue = 1
    }

    func prepareDesktopRestoreCover(image: NSImage, on screen: NSScreen) {
        let frame = screen.frame
        let window: NSWindow

        if let existingWindow = coverWindow {
            window = existingWindow
        } else {
            let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.animationBehavior = .none
            w.level = .mainMenu + 2
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            coverWindow = w
            window = w
        }

        if let imageView = coverImageView {
            imageView.frame = NSRect(origin: .zero, size: frame.size)
            imageView.image = image
            if window.contentView !== imageView {
                window.contentView = imageView
            }
        } else {
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageAlignment = .alignCenter
            imageView.animates = false
            imageView.autoresizingMask = [.width, .height]
            imageView.wantsLayer = true
            imageView.layer?.masksToBounds = true
            imageView.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = imageView
            coverImageView = imageView
        }

        window.setFrame(frame, display: true)
        // Keep the cover effectively alive in the compositor while remaining invisible.
        // A true zero alpha tends to reintroduce a first-frame insertion effect at unlock.
        window.alphaValue = 0.001
        window.orderFrontRegardless()
    }

    func hideDesktopRestoreCover(after delay: TimeInterval, duration: TimeInterval) {
        guard coverWindow != nil else { return }
        let sequence = coverTransitionSequence
        coverFadeTask?.cancel()
        coverFadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard let self,
                  let window = self.coverWindow,
                  self.coverTransitionSequence == sequence,
                  !Task.isCancelled else { return }

            let startAlpha = window.alphaValue
            let endAlpha: CGFloat = 0.001
            let frameDuration = max(1.0 / 120.0, 1.0 / 60.0)
            let steps = max(1, Int(duration / frameDuration))

            for step in 0...steps {
                guard self.coverTransitionSequence == sequence,
                      !Task.isCancelled else { return }
                let t = CGFloat(step) / CGFloat(steps)
                let eased = t * t * (3 - 2 * t)
                window.alphaValue = startAlpha + (endAlpha - startAlpha) * eased
                try? await Task.sleep(for: .milliseconds(Int(frameDuration * 1000)))
            }

            guard self.coverTransitionSequence == sequence else { return }
            window.alphaValue = endAlpha
            window.orderOut(nil)
            self.coverFadeTask = nil
        }
    }

    func hideDesktopRestoreCoverImmediately() {
        coverTransitionSequence &+= 1
        coverFadeTask?.cancel()
        coverFadeTask = nil
        coverWindow?.orderOut(nil)
        coverWindow?.alphaValue = 0.001
    }

  // MARK: - Manual animation (60fps, deterministic)

    private func animateWidthScaleEaseOut(model: LockScreenLiveActivityOverlayModel,
                                         from: CGFloat, to: CGFloat, duration: TimeInterval) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = easeOutCubic(t)
            model.widthScale = lerp(from, to, eased)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }
    }

  /// Three-speed curve without discontinuity (C1 continuous) to avoid
  /// perceived micro-stutter between phases 2 and 3.
  ///
  /// Implementation: three-segment Hermite spline.
  /// - t in [0..1] (time)
  /// - p in [0..1] (progress)
  /// Controls points (t, p) and dp/dt slopes at segment joints.
    private func animateWidthScaleOrganicSpline(model: LockScreenLiveActivityOverlayModel,
                                                from: CGFloat, to: CGFloat, duration: TimeInterval) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))

        let t0: CGFloat = 0
        let t1: CGFloat = 0.40
        let t2: CGFloat = 0.93
        let t3: CGFloat = 1

        let p0: CGFloat = 0
        let p1: CGFloat = 0.56
        let p2: CGFloat = 0.97
        let p3: CGFloat = 1

        let m0: CGFloat = 0.08
        let m1: CGFloat = 1.20
        let m2: CGFloat = 0.06
        let m3: CGFloat = 0.0

        func hermite(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat, _ ma: CGFloat, _ mb: CGFloat, _ h: CGFloat) -> CGFloat {
            let uu = max(0, min(1, u))
            let uu2 = uu * uu
            let uu3 = uu2 * uu
            let h00 = 2*uu3 - 3*uu2 + 1
            let h10 = uu3 - 2*uu2 + uu
            let h01 = -2*uu3 + 3*uu2
            let h11 = uu3 - uu2
            return h00*a + h10*(h*ma) + h01*b + h11*(h*mb)
        }

        func splineProgress(_ t: CGFloat) -> CGFloat {
            if t <= t1 {
                let h = (t1 - t0)
                let u = (t - t0) / h
                return hermite(u, p0, p1, m0, m1, h)
            } else if t <= t2 {
                let h = (t2 - t1)
                let u = (t - t1) / h
                return hermite(u, p1, p2, m1, m2, h)
            } else {
                let h = (t3 - t2)
                let u = (t - t2) / h
                return hermite(u, p2, p3, m2, m3, h)
            }
        }

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = max(0, min(1.0, splineProgress(t)))
            model.widthScale = lerp(from, to, p)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }

        model.widthScale = to
    }

    private func animateLockRevealOrganic(
        model: LockScreenLiveActivityOverlayModel,
        duration: TimeInterval
    ) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))

        func hermite(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat, _ ma: CGFloat, _ mb: CGFloat, _ h: CGFloat) -> CGFloat {
            let uu = max(0, min(1, u))
            let uu2 = uu * uu
            let uu3 = uu2 * uu
            let h00 = 2*uu3 - 3*uu2 + 1
            let h10 = uu3 - 2*uu2 + uu
            let h01 = -2*uu3 + 3*uu2
            let h11 = uu3 - uu2
            return h00*a + h10*(h*ma) + h01*b + h11*(h*mb)
        }

        let t0: CGFloat = 0
        let t1: CGFloat = 0.16
        let t2: CGFloat = 0.84
        let t3: CGFloat = 1

        let p0: CGFloat = 0
        let p1: CGFloat = 0.24
        let p2: CGFloat = 0.94
        let p3: CGFloat = 1

        let m0: CGFloat = 0.44
        let m1: CGFloat = 1.02
        let m2: CGFloat = 0.20
        let m3: CGFloat = 0

        func widthProgress(_ t: CGFloat) -> CGFloat {
            if t <= t1 {
                let h = t1 - t0
                let u = (t - t0) / h
                return hermite(u, p0, p1, m0, m1, h)
            } else if t <= t2 {
                let h = t2 - t1
                let u = (t - t1) / h
                return hermite(u, p1, p2, m1, m2, h)
            } else {
                let h = t3 - t2
                let u = (t - t2) / h
                return hermite(u, p2, p3, m2, m3, h)
            }
        }

        func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
            if x <= a { return 0 }
            if x >= b { return 1 }
            let u = (x - a) / (b - a)
            return u * u * (3 - 2 * u)
        }

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let w = max(0.01, min(1.0, widthProgress(t)))

            let o = smoothstep(0.00, 0.32, t)

            model.widthScale = w
            model.opacity = o
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }

        model.widthScale = 1
        model.opacity = 1
    }

    private func animateOpacityEaseOut(model: LockScreenLiveActivityOverlayModel,
                                       from: CGFloat, to: CGFloat, duration: TimeInterval) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = easeOutCubic(t)
            model.opacity = lerp(from, to, eased)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }
    }

    private func animateWidthScaleBackEase(model: LockScreenLiveActivityOverlayModel,
                                          from: CGFloat, to: CGFloat, duration: TimeInterval, overshoot: CGFloat) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = easeOutBack(t, s: overshoot)
            model.widthScale = lerp(from, to, eased)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let p = 1 - t
        return 1 - (p * p * p)
    }

    private func easeOutBack(_ t: CGFloat, s: CGFloat) -> CGFloat {
        let c1 = s * 10.0
        let c3 = c1 + 1.0
        let x = t - 1.0
        return 1.0 + (c3 * x * x * x) + (c1 * x * x)
    }
}
