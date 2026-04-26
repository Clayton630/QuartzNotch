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
        let jitter = sin(trigger * 100) * 0.000001
        let baseAlpha: CGFloat = nativeGlassType == nil ? 1.0 : 1.0
        nsView.alphaValue = baseAlpha - CGFloat(abs(jitter))
        nsView.needsDisplay = true
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

struct LockScreenMusicPanel: View {
    static let panelCornerRadius: CGFloat = 22
    static let albumCornerRadius: CGFloat = 9.2
    static let compactAlbumArtSize: CGFloat = 121
    static let collapsedContentLeadingPadding: CGFloat = 24
    static let compactAlbumArtVerticalOffset: CGFloat = 1
    static let collapsedHeight: CGFloat = 170
    static let expandedWidthReduction: CGFloat = 56
    static let expandedHeightReduction: CGFloat = 18
    static let timerCardHeight: CGFloat = 76
    static let stackSpacing: CGFloat = 12
    static let morphAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.18)
    static var collapsedSize: CGSize {
        let configuredWidth = CGFloat(Defaults[.lockScreenMusicPanelWidth])
        let effectiveWidth = max(358, configuredWidth - 38)
        return CGSize(width: effectiveWidth, height: collapsedHeight)
    }
    static func mediaCardSize(progress rawProgress: CGFloat, availableWidth: CGFloat? = nil) -> CGSize {
        let progress = min(max(rawProgress, 0), 1)
        let baseSize = collapsedSize
        let preferredWidth = baseSize.width - (expandedWidthReduction * progress)
        let preferredHeight = baseSize.height - (expandedHeightReduction * progress)
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
        return CGSize(width: mediaSize.width, height: stackHeight)
    }

    @ObservedObject private var animator: LockScreenPanelAnimator
    @ObservedObject private var timerManager = QuickTimerManager.shared
    @Default(.forceLiquidGlassCompatibilityFallback) private var forceLiquidGlassCompatibilityFallback
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @StateObject private var lockVM = BoringViewModel()
    @Namespace private var albumArtNamespace
    @State private var didConfigureVM = false
    @State private var exitingTimerProgress: [UUID: CGFloat] = [:]
    @State private var timerRemovalTasks: [UUID: Task<Void, Never>] = [:]
    @State private var timerBackdropReleaseTasks: [UUID: Task<Void, Never>] = [:]
    @State private var hiddenLiveTimerIDs: Set<UUID> = []
    @State private var exitingTimerOverlays: [UUID: ExitingTimerOverlay] = [:]
    private var isSystemLightAppearance: Bool {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let interfaceStyle = globalDomain?["AppleInterfaceStyle"] as? String
        return interfaceStyle?.lowercased() != "dark"
    }
    private var liquidGlassCompatibilityFallbackActive: Bool {
        forceLiquidGlassCompatibilityFallback
            || (NSClassFromString("NSGlassEffectView") as? NSView.Type) == nil
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
    private var isMorphingAlbumArtPanel: Bool {
        morphProgress > 0.001 && morphProgress < 0.999
    }
    private func snapped(_ value: CGFloat) -> CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }
    private func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + ((to - from) * visualMorphProgress)
    }
    private var panelSize: CGSize {
        let size = Self.size(
            showsMediaCard: animator.showsMediaCard,
            timerCount: activeQuickTimersForLockScreen.count,
            mediaProgress: morphProgress
        )
        return CGSize(width: snapped(size.width), height: snapped(size.height))
    }
    private var mediaCardSize: CGSize {
        let size = Self.mediaCardSize(progress: morphProgress)
        return CGSize(width: snapped(size.width), height: snapped(size.height))
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
        isMorphingAlbumArtPanel ? 0 : (animator.isPresented ? (1.0 / 60.0) : 0.25)
    }
    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }

    @ViewBuilder
    private func panelCard<Content: View>(
        size: CGSize,
        liquidRefreshRate: Double,
        darkTintOpacity: Double = 0,
        usesSharedBackdropSnapshot: Bool = true,
        sharedBackdropOrigin: CGPoint? = nil,
        contentAlignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Group {
                if liquidGlassCompatibilityFallbackActive,
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
                } else if liquidRefreshRate <= 0 {
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
                } else {
                    TimelineView(.periodic(from: .now, by: liquidRefreshRate)) { timeline in
                        LockScreenLiquidGlassBackground(
                            variant: 11,
                            cornerRadius: Self.panelCornerRadius,
                            trigger: timeline.date.timeIntervalSinceReferenceDate,
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
                    }
                    .id(forceLiquidGlassCompatibilityFallback ? "compat" : "native")
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
            .overlay(shadowBalanceHighlights())
            .overlay(
                ZStack {
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
                .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(darkTintOpacity))
                    .allowsHitTesting(false)
            )
            .overlay(
                ZStack {
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
                .blendMode(contourStrokeBlendMode)
                .allowsHitTesting(false)
            )
            .overlay(specularHighlights())

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
                .shadow(color: Color.black.opacity(0.18), radius: 6.2, x: 0, y: 1.8)
                .shadow(color: Color.black.opacity(0.08), radius: 13.0, x: 0, y: 3.4)
                .environment(\.colorScheme, usesLightCompatibilityFallbackStyling ? .light : .dark)
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
    }

    private var mediaPanelContent: some View {
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
                .frame(width: albumArtSlotWidth, height: Self.compactAlbumArtSize, alignment: .leading)
                .clipped()
            }

            MusicControlsView(
                forceLightGrayUI: !usesLightCompatibilityFallbackStyling,
                forceDarkUI: usesLightCompatibilityFallbackStyling,
                iconButtonSize: 30,
                prefersCenteredInfoLayout: visualMorphProgress > 0.55
            )
                .environmentObject(lockVM)
                .compositingGroup()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, contentVerticalPadding)
        }
        .padding(.leading, contentLeadingPadding)
        .padding(.trailing, contentTrailingPadding)
        .padding(.vertical, 0)
    }

    @ViewBuilder
    private var stackContent: some View {
        let timers = visibleQuickTimersForStack
        ZStack(alignment: .bottomLeading) {
            if animator.showsMediaCard {
                panelCard(
                    size: mediaCardSize,
                    liquidRefreshRate: animator.isPresented ? (1.0 / 60.0) : 0.25,
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
                            )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .shadow(color: panelOuterShadowPrimaryColor, radius: 16, x: 0, y: 7)
        .shadow(color: panelOuterShadowSecondaryColor, radius: 22, x: 0, y: 2)
        .animation(Self.morphAnimation, value: morphProgress)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: animator.showsMediaCard)
        .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.52, dampingFraction: 0.8), value: animator.isPresented)
        .onAppear {
            guard !didConfigureVM else { return }
            lockVM.open()
            scheduleFinishedTimerRemovalsIfNeeded()
            didConfigureVM = true
        }
        .onChange(of: activeQuickTimersForLockScreen.map { "\($0.id.uuidString)-\($0.didFinish)-\($0.remainingSeconds <= 0)" }) { _ in
            scheduleFinishedTimerRemovalsIfNeeded()
        }
        .onDisappear {
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
        42 * (1 - clampedCompactProgress)
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
                    .clipped()
                    .padding(.bottom, 5)
                    .opacity(timerLabelOpacity)
                    .scaleEffect(timerLabelScale, anchor: .trailing)

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
  /// Slight blur on the lock icon only (appearance/disappearance).
    @Published var iconBlur: CGFloat = 0

    func setLocked(resetBlur: Bool = true) {
        mode = .locked
        opacity = 1
        widthScale = 1
        if resetBlur { iconBlur = 0 }
    }

    func setUnlocked(resetBlur: Bool = true) {
        mode = .unlocked
        opacity = 1
        widthScale = 1
        if resetBlur { iconBlur = 0 }
    }

  /// Collapse the overlay horizontally while keeping it pinned.
  /// We keep opacity at 1 so the disappearance reads as a width collapse (like music).
    func collapseForDismiss() {
        widthScale = 0.01
    }

    func hide() {
        mode = .hidden
        opacity = 0
        widthScale = 0.01
        iconBlur = 0
    }
}

struct LockScreenLiveActivityOverlay: View {
    @ObservedObject var model: LockScreenLiveActivityOverlayModel
    @ObservedObject private var musicManager = MusicManager.shared
    let notchSize: CGSize

    private let topCornerRadius: CGFloat = 7

    private var indicatorSide: CGFloat { max(0, notchSize.height - 12) }
    private var totalWidth: CGFloat {
        notchSize.width + indicatorSide * 2 + cornerRadiusInsets.closed.bottom * 2
    }
    private var shouldShowLockScreenMediaPanel: Bool {
        model.mode == .locked
    }

    var body: some View {
        HStack(spacing: 0) {
            indicator
                .frame(width: indicatorSide, height: indicatorSide)
                .padding(.leading, cornerRadiusInsets.closed.bottom)

            if shouldShowLockScreenMediaPanel {
                lockScreenMediaPanel
                    .frame(width: notchSize.width - topCornerRadius)
                    .padding(.leading, 6)
            } else {
                Rectangle()
                    .fill(.black)
                    .frame(width: notchSize.width - topCornerRadius)
            }

            Color.clear
                .frame(width: indicatorSide, height: indicatorSide)
                .padding(.trailing, cornerRadiusInsets.closed.bottom)
        }
        .frame(width: totalWidth, height: notchSize.height)
        .background(.black)
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: cornerRadiusInsets.closed.bottom
            )
        )
        .opacity(model.opacity)
        .scaleEffect(x: model.widthScale, y: 1.0, anchor: .top)
        .compositingGroup()
    }

    @ViewBuilder
    private var indicator: some View {
        LockIconAnimatedBlurView(
            isLocked: model.mode != .unlocked,
            size: 16,
            iconColor: .white,
            blurRadius: model.iconBlur
        )
    }

    @ViewBuilder
    private var lockScreenMediaPanel: some View {
        HStack(spacing: 7) {
            Group {
                if let albumImage = musicManager.albumArt.copy() as? NSImage {
                    Image(nsImage: albumImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.songTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.98))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(musicManager.artistName)
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

        if let lockWindow {
            SkyLightOperator.shared.delegateWindow(lockWindow)
            lockWindow.alphaValue = 1
            lockWindow.orderFront(nil)
        }

        lockModel.hide()

        Task { @MainActor in
            var tx0 = Transaction()
            tx0.disablesAnimations = true
            withTransaction(tx0) {
                lockModel.setLocked(resetBlur: false)
                lockModel.widthScale = 0.72
                lockModel.opacity = 1
                lockModel.iconBlur = 10
            }

            withAnimation(NotchMotion.lockReveal) {
                lockModel.widthScale = 1
                lockModel.iconBlur = 0
            }
        }
    }

    func showUnlockedAndHide(onFinished: (() -> Void)? = nil) {
        if isUnlockRunning { return }
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
                lockWindow.setFrame(rect, display: true)
                positionWindow(lockWindow, on: screen, width: totalWidth, height: notchSize.height)

                if let cv = lockWindow.contentView {
                    cv.layoutSubtreeIfNeeded()
                    cv.needsDisplay = true
                    cv.displayIfNeeded()
                }
                lockWindow.displayIfNeeded()
                CATransaction.flush()

                lockModel.setUnlocked(resetBlur: false)

                try? await Task.sleep(nanoseconds: 960_000_000)

                await hideDesktopWithAnimation(
                    desktopWindow: lockWindow,
                    model: lockModel,
                    notchSize: notchSize,
                    totalWidth: totalWidth
                )

                lockModel.hide()
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    lockWindow.animator().alphaValue = 0
                }
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

            ensureDesktopWindow(rect: rect, notchSize: notchSize, totalWidth: totalWidth)
            guard let desktopWindow else { return }

            positionWindow(desktopWindow, on: screen, width: totalWidth, height: notchSize.height)
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                desktopWindow.animator().alphaValue = 1
            }
            desktopWindow.orderFront(nil)
            desktopModel.setUnlocked(resetBlur: false)
            try? await Task.sleep(nanoseconds: 960_000_000)
            await hideDesktopWithAnimation(desktopWindow: desktopWindow, model: desktopModel, notchSize: notchSize, totalWidth: totalWidth)
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
        totalWidth: CGFloat
    ) async {
        let duration: TimeInterval = 0.34

        let safeTotalWidth = max(totalWidth, 1)
        let collapsedScale = max(0.001, min(1.0, notchSize.width / safeTotalWidth))

        await NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            desktopWindow.animator().alphaValue = 1
        }

        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            model.opacity = 1
        }

        withAnimation(NotchMotion.lockDismiss) {
            model.widthScale = collapsedScale
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        desktopWindow.alphaValue = 0
    }

    func hideImmediately() {
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

  // MARK: - Internals (Geometry)

    private func makeRect(for notchSize: CGSize) -> (CGFloat, NSRect) {
        let indicatorSide = max(0, notchSize.height - 12)
        let totalWidth = notchSize.width + indicatorSide * 2 + cornerRadiusInsets.closed.bottom * 2
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
            let w = BoringNotchWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

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
            let w = BoringNotchWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

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
        guard let window = coverWindow else { return }
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
        duration: TimeInterval,
        maxBlur: CGFloat
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

            let blurDrop = smoothstep(0.16, 0.97, t)
            let blur = maxBlur * pow(max(0, 1 - blurDrop), 1.35)

            model.widthScale = w
            model.opacity = o
            model.iconBlur = blur
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }

        model.widthScale = 1
        model.opacity = 1
        model.iconBlur = 0
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
