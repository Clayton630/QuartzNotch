//
// ContentView.swift
// boringNotchApp
//
// Created by Harsh Vardhan Goswami on 02/08/24
// Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import AVKit
import AppKit
import Combine
import Foundation
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

private struct NotchLiquidGlassBackground<Content: View>: NSViewRepresentable {
    let variant: Int
    let cornerRadius: CGFloat
    let trigger: Double
    let content: Content

    init(variant: Int = 11, cornerRadius: CGFloat, trigger: Double = 0, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.trigger = trigger
        self.content = content()
    }

    func makeNSView(context: Context) -> NSView {
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: .zero)
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            setVariant(on: glass, value: variant)

            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(host, forKey: "contentView")
            return glass
        }

        let fallback = NSVisualEffectView()
        fallback.material = .underWindowBackground
        fallback.blendingMode = .withinWindow
        fallback.state = .active

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
        if let host = nsView.value(forKey: "contentView") as? NSHostingView<Content> {
            host.rootView = content
        }
        nsView.setValue(cornerRadius, forKey: "cornerRadius")
        setVariant(on: nsView, value: variant)

        // Atoll v11 behavior: force very subtle wallpaper re-sampling each frame.
        let jitter = sin(trigger * 100) * 0.000001
        nsView.alphaValue = 1.0 - CGFloat(abs(jitter))
        nsView.needsDisplay = true
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
                .symbolRenderingMode(.hierarchical)
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

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared

 // Live activity for the file tray
    @StateObject private var tvm = ShelfStateViewModel.shared

 // Live activity for the lock screen icon
    @ObservedObject private var lockScreenState = LockScreenState.shared

 // Gating: hide any closed live activities during lock/unlock transitions
    @ObservedObject private var lockTransition = LockTransitionState.shared

 // Live activity for Bluetooth device connection
    @ObservedObject var bluetoothModel = BluetoothStatusViewModel.shared
    @StateObject private var focusModeManager = FocusModeLiveActivityManager.shared

 // Closed-notch timer live activity (Quick Timers on page 3)
    @StateObject private var quickTimerManager = QuickTimerManager.shared

 // Animated suppression progress for lock/unlock transitions.
 // 0 = visible (normal), 1 = fully suppressed (during lock/unlock)
    @State private var lockSuppressionProgress: CGFloat = 0

    @State private var hoverTask: Task<Void, Never>?
    @State private var liquidCloseTransitionTask: Task<Void, Never>?
    @State private var liquidVisualBlend: CGFloat = 0
    @State private var liquidStrokeReveal: CGFloat = 0
    @State private var keepLiquidVisualDuringClose: Bool = false
    @State private var isHovering: Bool = false
    @State private var detachedSecondaryAppearToken: Int = 0

 // Hover expansion for the Bluetooth closed live activity (kept separate from notch hover)
    @State private var isBluetoothPopupHovering: Bool = false
    @State private var isBluetoothSidesHovering: Bool = false
    @State private var isBluetoothCenterHovering: Bool = false
    @State private var isBluetoothPopupTransitioning: Bool = false
    @State private var bluetoothCenterHoverTask: Task<Void, Never>?
    @State private var bluetoothSidesHoverTask: Task<Void, Never>?
    @State private var bluetoothTransitionTask: Task<Void, Never>?

 // Hover expansion for the Timer closed live activity (sides only; center keeps classic notch hover)
    @State private var isTimerPopupHovering: Bool = false
    @State private var isTimerExpandedHovering: Bool = false
    @State private var isTimerPopupTransitioning: Bool = false
    @State private var isTimerPopupHoverArmed: Bool = true
    @State private var suppressTimerPopupAutoOpenUntil: Date = .distantPast
    @State private var keepTimerPopupOpenForFinishedAlert: Bool = false

 // Raw hover state for timer side segments (left/right). Used to prevent notch auto-open race.
    @State private var isTimerSidesHovering: Bool = false
 // Debounce to avoid flicker when moving between left/right segments.
    @State private var timerSidesHoverTask: Task<Void, Never>?
    @State private var timerTransitionTask: Task<Void, Never>?
    @State private var timerPopupRearmTask: Task<Void, Never>?

 // Proximity hover for timer sides (keeps expansion when pointer slips to an external screen above).
    @State private var hostWindow: NSWindow?
    @State private var timerGlobalMouseMonitor: Any?
    @State private var isTimerProximityHovering: Bool = false
    @State private var closedPopupFailsafeTask: Task<Void, Never>?
    @State private var timerAlarmBackgroundImpulseX: CGFloat = 0
    @State private var timerAlarmBackgroundDirection: CGFloat = -1
    @State private var timerAlarmBackgroundSettleTask: Task<Void, Never>?
    @State private var lastTimerAlertHapticAt: Date = .distantPast

    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics: Bool = false
    @State private var suppressAutoCloseUntil: Date = .distantPast
    @State private var frozenHoverExitTask: Task<Void, Never>?
    @State private var frozenHoverZoneWidth: CGFloat = 0
    @State private var frozenHoverZoneActive: Bool = false
    @State private var frozenHoverStartPointer: CGPoint = .zero
    @State private var frozenHoverPointerMoved: Bool = false
    @State private var frozenHoverOutsideTicks: Int = 0

 // prevents hover exit flicker during open animation/layout churn
    @State private var ignoreHoverExitUntil: Date = .distantPast

    @State private var isSwitchingOverlay: Bool = false
    private let overlaySwitchDelayMs: UInt64 = 140
    @State private var overlayWidthHold: CGFloat = 0
    @State private var overlayHeightHold: CGFloat = 0
    @State private var calendarRestoreAfterCamera: Bool = false
    @State private var overlaySwitchDirection: OverlaySwitchDirection = .none

 // Controls whether the pager captures horizontal scroll events.
 // When the pointer is over the file tray, we disable this so the tray can scroll.
    @State private var isPagerScrollEnabled: Bool = true

 // Battery closed notification *organic* width animation (custom easing)
    @State private var batteryChinFrom: CGFloat = 0
    @State private var batteryChinTo: CGFloat = 0
    @State private var batteryChinPhase: CGFloat = 1

 // Slightly longer than the background-only tween so content blur/opacity has time to be perceived.
    private let batteryAppearDuration: Double = 0.28
    private let batteryDisappearDuration: Double = 0.46

 // MARK: - Battery closed live activity content reveal
    private var batteryClosedContentProgress: CGFloat {
        guard vm.notchState == .closed else { return isBatteryClosedNotificationShowing ? 1 : 0 }
        guard closedActivityVisibility > 0.001 else { return 0 }
        guard Defaults[.showPowerStatusNotifications] else { return 0 }
        guard coordinator.expandingView.type == .battery else { return isBatteryClosedNotificationShowing ? 1 : 0 }

        let mode: OrganicBatteryEasing.Mode = (batteryChinTo >= batteryChinFrom) ? .appear : .disappear
        let p = OrganicBatteryEasing.map(batteryChinPhase, mode: mode)

  // Content must finish with the background's slow tail.
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
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .none:
            return .opacity.combined(with: .scale(scale: 0.98))
        }
    }

    private var cameraOverlayTransition: AnyTransition {
        switch overlaySwitchDirection {
        case .toCamera:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
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
    private var batteryClosedStatusText: String { "Charging" }

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.showCalendar) var showCalendar
    @Default(.showMirror) var showMirror

    @Default(.pageHomeEnabled) private var pageHomeEnabled
    @Default(.pageShelfEnabled) private var pageShelfEnabled

    @Default(.pageThirdEnabled) private var pageThirdEnabled
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    private let animationSpring = NotchMotion.notchOpen

 // Alternate variants (prepared for later use).
 // Switch to `.compactMode` per activity when you want to enable them.
    private let bluetoothLiveActivityMode: ClosedLiveActivityMode = .standard
    private let timerLiveActivityMode: ClosedLiveActivityMode = .standard
    private let fileTrayLiveActivityMode: ClosedLiveActivityMode = .standard
    private let nowPlayingLiveActivityMode: ClosedLiveActivityMode = .standard

    private var isBluetoothCompactMode: Bool { bluetoothLiveActivityMode == .compactMode }
    private var isTimerCompactMode: Bool { timerLiveActivityMode == .compactMode }
    private var isFileTrayCompactMode: Bool { fileTrayLiveActivityMode == .compactMode }
    private var isNowPlayingCompactMode: Bool { nowPlayingLiveActivityMode == .compactMode }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private let closedActivityTopCornerRadius: CGFloat = 7

 // MARK: - Closed state helpers

    private var isBatteryClosedNotificationShowing: Bool {
        coordinator.expandingView.type == .battery
        && coordinator.expandingView.show
        && vm.notchState == .closed
        && closedActivityVisibility > 0.001
        && Defaults[.showPowerStatusNotifications]
    }

    private var isBluetoothClosedNotificationShowing: Bool {
        coordinator.expandingView.type == .bluetooth
        && coordinator.expandingView.show
        && vm.notchState == .closed
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && vm.effectiveClosedNotchHeight > 0
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
        focusModeManager.latestTransitionIsActive ? "On" : "Off"
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
        // Keep classic timer toggle for internal quick timers, but still allow mirrored Clock timer
        // when mirror mode is enabled.
        if quickTimerManager.mirroredSystemQuickTimer == nil {
            guard Defaults[.liveActivityTimerEnabled] else { return false }
        }
        guard vm.effectiveClosedNotchHeight > 0 else { return false }
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
  // Use the soonest-ending timer as the representative progress.
  // QuickTimer.progress is elapsed [0..1], so we invert for a decreasing ring.
        guard let t = activeQuickTimers.first else { return 0 }
        return max(0, min(1, 1 - t.progress))
    }

    private static func measureMonospacedWidth(_ text: String, fontSize: CGFloat, weight: NSFont.Weight) -> CGFloat {
  // The timer uses monospaced digits in SwiftUI. Using the monospaced-digit font here avoids
  // under-measuring and prevents the digits from sliding under the physical notch.
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func measureSystemWidth(_ text: String, fontSize: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private var timerActivityLayout: TimerLiveActivity.Layout {
  // Keep visually consistent with other closed activities.
        let fontSize: CGFloat = 12.4
  // Keep the left side compact; the right side can expand for digits.
        let sidePadding: CGFloat = 3

  // Left: progress ring (no text).
  // Keep this in sync with TimerLiveActivity.swift.
  // Slightly larger than before (the ring looked too small).
  // Keep this in sync with TimerLiveActivity.swift.
        let ringSize: CGFloat = fontSize + 5

  // Left: static width that only needs to fit the icon.
  // (Do NOT mirror the right side.)
        let leftWidth = max(16, ceil(ringSize) + 1)

  // Right: time string + optional "+N" (monospaced digits for the clock part)
        let extra = timerActivityExtraCount > 0 ? " +\(timerActivityExtraCount)" : ""
  // Right: give the text enough room to live entirely outside the physical notch.
  // Use monospaced measurement + a slightly larger safety margin (kerning / rendering differences).
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

    private var timerExpandedFooterHeight: CGFloat {
        let rowsCount = max(1, activeQuickTimers.count)
        let expandedRowHeight: CGFloat = 40
        let expandedRowsSpacing: CGFloat = 12
        let expandedTopPadding: CGFloat = 0
        let expandedBottomPadding: CGFloat = 16
        return expandedTopPadding
            + CGFloat(rowsCount) * expandedRowHeight
            + CGFloat(max(0, rowsCount - 1)) * expandedRowsSpacing
            + expandedBottomPadding
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
            VStack(spacing: 12) {
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
                    .padding(.horizontal, 1)
                    .frame(height: 40)
                }
            }
            .padding(.horizontal, 0)
            .padding(.top, 0)
            .padding(.bottom, 0)
            .frame(width: timerExpandedTargetWidth, height: timerExpandedFooterHeight, alignment: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                isTimerExpandedHovering = hovering
                if hovering {
                    isTimerSidesHovering = true
                } else {
                    timerSidesHoverTask?.cancel()
                    timerSidesHoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        if keepTimerPopupOpenForFinishedAlert { return }
                        if !isTimerSidesHovering && !isTimerExpandedHovering {
                            withAnimation(NotchMotion.popupHover) {
                                isTimerPopupHovering = false
                            }
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }


 /// When the timer activity is shown, shift the whole closed notch slightly left so the extra width
 /// appears on the right (digits) instead of being symmetric.
    private var closedChinOffsetX: CGFloat {
  // Compact mode: right-only extension for selected activities.
        if isBluetoothClosedNotificationShowing && isBluetoothCompactMode {
            let side = max(0, vm.effectiveClosedNotchHeight - 12)
            let ext = (side + 10 + (isBluetoothPopupHovering ? 110 : 0)) * closedActivityVisibility
            return -(ext / 2)
        }
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

  // Negative => shift left, so the larger "rightExtra" is visually allocated to the right.
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
        && Defaults[.showOnLockScreen]
        && Defaults[.liveActivityLockScreen]
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
            expandedRowHeight: 40,
            expandedRowsSpacing: 12,
            isExpanded: isTimerPopupHovering,
            onSidesHoverChanged: { hovering in
                // Direct hover only (no proximity hover with external displays)
                isTimerSidesHovering = hovering
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
                    // Re-arm only after a real hover exit, so the next timer appearance
                    // cannot auto-open from a stale/continuous pointer position.
                    isTimerPopupHoverArmed = Date() >= suppressTimerPopupAutoOpenUntil
                    // Leave hysteresis: avoid falling back to "center hover" when grazing the boundary.
                    timerSidesHoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(140))
                        guard !Task.isCancelled else { return }
                        if isTimerExpandedHovering { return }
                        if isHovering { return }
                        if !isTimerSidesHovering {
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
                    }
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
        && !isInlineHUDFloatingClosed
        && !shouldShowLockActivityClosed
    }

    private var shouldShowMusicActivityClosed: Bool {
        (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
        && vm.notchState == .closed
        && (musicManager.isPlaying || !musicManager.isPlayerIdle)
        && coordinator.musicLiveActivityEnabled
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
        && !shouldShowLockActivityClosed
        && !shouldShowFocusActivityClosed
        && !shouldShowFileTrayActivityClosed
    }

    private var shouldShowFaceClosed: Bool {
        !coordinator.expandingView.show
        && vm.notchState == .closed
        && (!musicManager.isPlaying && musicManager.isPlayerIdle)
        && Defaults[.showNotHumanFace]
        && closedActivityVisibility > 0.001
        && !vm.hideOnClosed
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
            || shouldShowLockActivityClosed
            || shouldShowFocusActivityClosed
            || isInlineHUDFloatingClosed
            || shouldShowFileTrayActivityClosed
            || shouldShowTimerActivityClosed
            || shouldShowMusicActivityClosed)
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
        && !isBluetoothClosedNotificationShowing
    }

    private var closedPrimaryActivityKind: ClosedActivityKind? {
        if isBluetoothClosedNotificationShowing { return .bluetooth }
        if shouldShowFocusActivityClosed { return .focus }
        if shouldShowTimerActivityClosed { return .timer }
        if shouldShowFileTrayActivityClosed { return .fileTray }
        if shouldShowMusicActivityClosed { return .music }
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
            // Bluetooth takes exclusive priority in closed mode:
            // do not render any detached secondary compact activity.
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

    private var closedSecondaryCompactWidth: CGFloat {
  // Keep detached compact width stable (independent from hover-expanded closed activity styling).
        guard closedSecondaryCompactActivityKind != nil else { return 0 }
        return max(0, vm.closedNotchSize.height - 12)
    }

    private var closedDetachedCompactSpacing: CGFloat {
        guard closedSecondaryCompactActivityKind != nil else { return 0 }
        return 0
    }

    private var closedDetachedCompactBubbleWidth: CGFloat {
        guard closedSecondaryCompactActivityKind != nil else { return 0 }
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
            if isBluetoothCompactMode { return nil }
            let hoverExtra: CGFloat = isBluetoothPopupHovering ? (110 / 2) : 0
            return side + 10 + hoverExtra
        case .focus:
            return focusActivityLayout.rightPadding + focusActivityLayout.rightWidth
        case .timer:
            if isTimerCompactMode { return nil }
            return timerActivityLayout.sidePadding + timerActivityLayout.rightWidth
        case .fileTray:
            if isFileTrayCompactMode { return nil }
            // Match FileTrayLiveActivity geometry:
            // total width = side + (notchWidth - topInset) + side
            // => right extra from notch center = side - (topInset / 2)
            return max(0, side - (cornerRadiusInsets.closed.top / 2))
        case .music:
            if isNowPlayingCompactMode { return nil }
            return side + 10
        }
    }

    private var closedPrimaryRightEdgeX: CGFloat {
  // Explicit per-activity right edge (same strategy as timer) to keep detached compact bubble
  // anchored correctly regardless of which closed activity is primary.
        if let rightExtra = closedPrimaryRightExtra {
            return (vm.closedNotchSize.width / 2) + (rightExtra * closedActivityVisibility)
        }

  // Fallback for compact / legacy modes.
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

  // Expanded Bluetooth popup: round corners more (top).
        if isBluetoothClosedNotificationShowing && isBluetoothPopupHovering {
            return 10
        }

  // Expanded Timer popup (sides-hover): round corners more (top).
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

  // Expanded Bluetooth popup: round corners more (bottom).
        if isBluetoothClosedNotificationShowing && isBluetoothPopupHovering {
            return 18
        }

  // Expanded Timer popup (sides-hover): round corners more (bottom).
        if shouldShowTimerActivityClosed && isTimerPopupHovering {
            return 18
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
            if isBluetoothCompactMode {
                chinWidth += (max(0, vm.effectiveClosedNotchHeight - 12) + 10)
            } else {
                chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
            }

   // Hover expansion: widen the closed Bluetooth live activity without opening the notch.
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
   // Adaptive width: ensure the full time string fits outside the physical notch.
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

    private var computedChinWidthRaw: CGFloat {
        computedPrimaryChinWidthRaw
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
        let base: CGFloat = 420

        let extraCameraWidth: CGFloat = isCameraVisibleComputed ? 160 : 0
        let extraCalendarWidth: CGFloat = isCalendarVisibleComputed ? 230 : 0
        let overlaySwitchWidthHold: CGFloat =
            (isSwitchingOverlay && overlaySwitchDirection == .toCalendar) ? 230 : 0
        // Keep the historical open width even if the visual top corners are forced to 0.
        let legacyOpenTopRadius = Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
        let exactBoundsWidthCompensation: CGFloat = 2 * legacyOpenTopRadius

        return max(
            vm.closedNotchSize.width,
            base + max(extraCameraWidth, extraCalendarWidth, overlayWidthHold, overlaySwitchWidthHold) - exactBoundsWidthCompensation
        )
    }

    private var openHeightValueComputed: CGFloat? {
        guard vm.notchState == .open else { return nil }
        return max(vm.notchSize.height, overlayHeightHold)
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
    private func liquidV11Layer(cornerRadius: CGFloat, tintOpacity: Double) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            NotchLiquidGlassBackground(
                variant: 11,
                cornerRadius: cornerRadius,
                trigger: context.date.timeIntervalSinceReferenceDate
            ) {
                Color.white.opacity(tintOpacity)
            }
        }
    }

    @ViewBuilder
    private func liquidCornerShadowLayer() -> some View {
        let topCornerSpan = max(30, topCornerRadius * 3.1)
        let bottomCornerSpan = max(42, bottomCornerRadius * 2.45)
        let edgeBand = max(12, topCornerRadius * 0.78)

        ZStack {
            // Single continuous inner shadow.
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
                .allowsHitTesting(false)
        }
        .compositingGroup()
        .clipShape(currentNotchShape)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func liquidEdgeCornerMask(topCornerSpan: CGFloat, bottomCornerSpan: CGFloat, edgeBand: CGFloat) -> some View {
        ZStack {
            // Edge bands so the corner shadow is extended and connected along the contour.
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

            // Corner boosts to preserve rounded continuity through turns.
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
            let topCut = min(0.72, max(0.16, (vm.effectiveClosedNotchHeight + 14) / h))
            let fadeStart = max(0.0, topCut - 0.22)
            let fadeMid1 = min(1.0, fadeStart + 0.08)
            let fadeMid2 = min(1.0, fadeStart + 0.15)
            let fadeMid3 = min(1.0, fadeStart + 0.22)
            let fadeEnd = min(1.0, topCut + 0.14)
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
        // Fixed "base notch" shoulder geometry: do not vary with expanded layouts/pages.
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
                // In Liquid Glass mode, avoid spring rebound so shoulders and notch stay perfectly synced.
                if pageUseLiquidGlassBackground {
                    return .smooth(duration: 0.30)
                }
                return NotchMotion.notchOpen
            }
            return NotchMotion.notchClose
        }()
        let notchLayoutAnimation: Animation = NotchMotion.notchLayout
        let openShoulderProgress: CGFloat = (vm.notchState == .open) ? 1 : 0
        let useLiquidPageBackground = pageUseLiquidGlassBackground && (vm.notchState == .open || keepLiquidVisualDuringClose)
        let resolvedLiquidBlend = min(max(liquidVisualBlend, 0), 1)
        let liquidGlassBlend: CGFloat = min(max((resolvedLiquidBlend - 0.08) / 0.92, 0), 1)
        let liquidVeilBlendRaw: CGFloat = min(max((resolvedLiquidBlend - 0.26) / 0.74, 0), 1)
        let liquidVeilBlend: CGFloat = liquidVeilBlendRaw * liquidVeilBlendRaw
        // Keep the black blur veil present from the very first opening frame in Liquid mode.
        let liquidVeilOpacity: CGFloat = (useLiquidPageBackground && vm.notchState == .open) ? 1 : liquidVeilBlend
        let liquidBaseFadeBlend: CGFloat = min(max((resolvedLiquidBlend - 0.18) / 0.82, 0), 1)
        let liquidStrokeOpacity: CGFloat = {
            guard useLiquidPageBackground else { return 0 }
            // Dedicated stroke fade: starts with notch opening instead of waiting for liquid layers.
            let t = min(max(liquidStrokeReveal, 0), 1)
            return t * t * (3 - 2 * t)
        }()
        let notchTopLineColor: Color = useLiquidPageBackground ? .clear : .black
        // Keep NSGlassEffectView corners neutral; the notch shape clipping drives real geometry.
        let liquidCornerRadius: CGFloat = 0

        let baseView = ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let timerBackgroundShakeX = timerExpandedBackgroundOffset.width
                let timerBackgroundShakeY = timerExpandedBackgroundOffset.height
                let openInnerHorizontalPadding: CGFloat = vm.notchState == .open
                    ? max(0, cornerRadiusInsets.opened.top - 15)
                    : cornerRadiusInsets.closed.bottom
                let openOuterHorizontalPadding: CGFloat = vm.notchState == .open ? 1 : 0
                let mainLayout = NotchLayout()
                    .offset(x: -timerBackgroundShakeX, y: -timerBackgroundShakeY)
                    .frame(alignment: .top)
                    .frame(maxWidth: vm.notchState == .open ? openWidthValueComputed : nil)
                    .padding(
                        .horizontal,
                        openInnerHorizontalPadding
                    )
                    .padding(.horizontal, openOuterHorizontalPadding)
                    .padding(.bottom, vm.notchState == .open ? 12 : 0)
                    .padding(.top, vm.notchState == .open ? -10 : 0)
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(notchLayoutAnimation, value: isLayoutExpandedComputed)
                    .animation(notchLayoutAnimation, value: showCalendar)

                mainLayout
                    .background {
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(.black)
                                .opacity(useLiquidPageBackground ? 1 - liquidBaseFadeBlend : 1)

                            if useLiquidPageBackground {
                                ZStack(alignment: .top) {
                                    liquidV11Layer(cornerRadius: liquidCornerRadius, tintOpacity: 0.04)
                                        .padding(0)
                                        .scaleEffect(1.0)
                                        .blur(radius: 1.15)
                                        .clipShape(currentNotchShape)
                                        .opacity(liquidGlassBlend)
                                        .allowsHitTesting(false)

                                    // True vertical veil: black at the top, fully transparent lower down.
                                    GeometryReader { geo in
                                        let h = max(1, geo.size.height)
                                        let barHeight = max(2, topCornerRadius + 15)
                                        let topOpaqueHeight = min(h, max(0, vm.effectiveClosedNotchHeight))
                                        let topOpaqueRatio = min(0.94, max(0.0, topOpaqueHeight / h))
                                        let seam = min(0.94, max(topOpaqueRatio - 0.01, (barHeight - 5) / h))
                                        let fade1 = min(1.0, seam + 0.02)
                                        let fade2 = min(1.0, seam + 0.07)
                                        let fade3 = min(1.0, seam + 0.17)
                                        let fade4 = min(1.0, seam + 0.36)
                                        let fade5 = min(1.0, seam + 0.58)
                                        let fade6 = min(1.0, seam + 0.78)
                                        let fade7 = min(1.0, seam + 0.91)
                                        let fade8 = min(1.0, seam + 0.985)
                                        let tail = max(fade8, 0.9997)

                                        ZStack(alignment: .top) {
                                            LinearGradient(
                                                stops: [
                                                    .init(color: Color.black.opacity(1.00), location: 0.00),
                                                    .init(color: Color.black.opacity(1.00), location: seam),
                                                    .init(color: Color.black.opacity(0.98), location: fade1),
                                                    .init(color: Color.black.opacity(0.94), location: fade2),
                                                    .init(color: Color.black.opacity(0.86), location: fade3),
                                                    .init(color: Color.black.opacity(0.72), location: fade4),
                                                    .init(color: Color.black.opacity(0.54), location: fade5),
                                                    .init(color: Color.black.opacity(0.36), location: fade6),
                                                    .init(color: Color.black.opacity(0.22), location: fade7),
                                                    .init(color: Color.black.opacity(0.11), location: fade8),
                                                    .init(color: Color.black.opacity(0.05), location: tail),
                                                    .init(color: .clear, location: 1.00),
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .padding(.horizontal, -28)
                                            .blur(radius: 8.2)

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
                                        }
                                    }
                                    .clipShape(currentNotchShape)
                                    .opacity(liquidVeilOpacity)
                                    .allowsHitTesting(false)
                                }
                            }

                            Rectangle()
                                .fill(notchTopLineColor)
                                .frame(height: 1)
                                .padding(.horizontal, topCornerRadius + 3)

                            if useLiquidPageBackground {
                                liquidCornerShadowLayer()
                                    .opacity(liquidGlassBlend)

                                // White contour all around, only in Liquid Glass mode.
                                currentNotchShape
                                    .strokeBorder(
                                        Color.white.opacity(0.24),
                                        style: StrokeStyle(
                                            lineWidth: 0.8,
                                            lineCap: .round,
                                            lineJoin: .round
                                        )
                                    )
                                    .mask(liquidStrokeMask())
                                    .opacity(liquidStrokeOpacity)
                                    .allowsHitTesting(false)
                            }

                        }
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
                            BoringHeader()
                                .frame(height: max(24, vm.effectiveClosedNotchHeight))
                                .padding(.top, 6)
                                .offset(y: -12)
                                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                                .zIndex(3000)
                                .allowsHitTesting(true)
                        }
                    }
     // Avoid the "late"/inconsistent-looking drop shadow under the expanded notch.
     // Keep shadow only for the *closed* notch hover affordance.
                    .shadow(
                        color: ((vm.notchState == .closed && isHovering) && Defaults[.enableShadow])
                        ? .black.opacity(0.55) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 5 : 3
                    )
     // Asymmetric closed timer activity: apply the offset only once on the outer container
     // (below). Applying it twice can compress the right side.
                    .padding(.bottom, (vm.notchState == .closed && vm.effectiveClosedNotchHeight == 0) ? 10 : 0)
                    .frame(
                        width: vm.notchState == .closed ? displayedChinWidthComputed : nil,
                        height: openHeightValueComputed
                    )
                    .frame(width: vm.notchState == .open ? openWidthValueComputed : nil)
     // Match the notch background offset so the content stays aligned.
                    .offset(
                        x: (vm.notchState == .closed ? closedChinOffsetX : 0) + timerBackgroundShakeX,
                        y: timerBackgroundShakeY
                    )
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(notchLayoutAnimation, value: isLayoutExpandedComputed)
                    .animation(notchLayoutAnimation, value: showCalendar)
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
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open
                                        && !self.isHovering
                                        && !self.vm.isBatteryPopoverActive
                                        && !SharingStateManager.shared.preventNotchClose
                                    {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
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
                            ignoreHoverExitUntil = Date().addingTimeInterval(0.25)
                        } else if newState == .closed {
                            // Never keep timer popup expanded when closing from open notch.
                            suppressTimerPopupAutoOpenUntil = Date().addingTimeInterval(0.35)
                            timerSidesHoverTask?.cancel()
                            timerTransitionTask?.cancel()
                            timerPopupRearmTask?.cancel()
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
                        keepLiquidVisualDuringClose = enabled && vm.notchState == .open
                        liquidVisualBlend = (enabled && vm.notchState == .open) ? 1 : 0
                        liquidStrokeReveal = (enabled && vm.notchState == .open) ? 1 : 0
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            SettingsWindowController.shared.showWindow()
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    }

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

            if vm.notchState == .closed,
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
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(x: gestureScale, y: gestureScale, anchor: .top)
        .animation(NotchMotion.notchLayout, value: gestureProgress)
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
                let w = computedChinWidth
                batteryChinFrom = w
                batteryChinTo = w
                batteryChinPhase = 1
            }
            .onDisappear {
                liquidCloseTransitionTask?.cancel()
                liquidCloseTransitionTask = nil
                timerPopupRearmTask?.cancel()
                timerPopupRearmTask = nil
                if let m = timerGlobalMouseMonitor {
                    NSEvent.removeMonitor(m)
                    timerGlobalMouseMonitor = nil
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
                if calendarOn { calendarRestoreAfterCamera = false }
                if oldCalendarOn && !calendarOn && !isCameraVisibleComputed {
                    activateFrozenHoverZone(widthHint: 230)
                }

                suppressAutoCloseUntil = Date().addingTimeInterval(0.45)
                guard !isSwitchingOverlay else { return }

                if calendarOn, vm.isCameraExpanded {
                    isSwitchingOverlay = true
                    overlaySwitchDirection = .toCalendar

                    overlayHeightHold = vm.notchSize.height
                    let currentExtra: CGFloat = 160
                    overlayWidthHold = currentExtra

                    withAnimation(animationSpring) { showCalendar = false }
                    withAnimation(animationSpring) { vm.toggleCameraPreview() }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: overlaySwitchDelayMs * 1_000_000)
                        withAnimation(animationSpring) { showCalendar = true }

                        try? await Task.sleep(nanoseconds: 180 * 1_000_000)
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
                if oldCameraOn && !cameraOn && !showCalendar {
                    activateFrozenHoverZone(widthHint: 160)
                }
                if cameraOn, showCalendar {
                    calendarRestoreAfterCamera = true
                    withAnimation(animationSpring) { showCalendar = false }
                }

                guard !isSwitchingOverlay else { return }

                if cameraOn, showCalendar {
                    isSwitchingOverlay = true
                    overlaySwitchDirection = .toCamera

                    let currentExtra: CGFloat = (isCalendarVisibleComputed ? 230 : 0)
                    overlayWidthHold = max(160, currentExtra)

                    // Step 1: hide calendar while keeping the wider notch width held.
                    withAnimation(animationSpring) { showCalendar = false }
                    // Step 2: then animate width down to camera width.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame
                        withAnimation(animationSpring) {
                            overlayWidthHold = 160
                        }
                    }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: overlaySwitchDelayMs * 1_000_000)

                        if !vm.isCameraExpanded {
                            withAnimation(animationSpring) { vm.toggleCameraPreview() }
                        }

                        try? await Task.sleep(nanoseconds: 180 * 1_000_000)
                        withAnimation(NotchMotion.notchLayout) {
                            overlayWidthHold = 0
                        }
                        isSwitchingOverlay = false
                        overlaySwitchDirection = .none
                    }
                }

                if !cameraOn, calendarRestoreAfterCamera {
                    calendarRestoreAfterCamera = false
                    isSwitchingOverlay = true
                    overlaySwitchDirection = .toCalendar

                    overlayWidthHold = 230
                    withAnimation(animationSpring) { showCalendar = true }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180 * 1_000_000)
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

                bluetoothCenterHoverTask?.cancel()
                bluetoothSidesHoverTask?.cancel()
                bluetoothTransitionTask?.cancel()
                isBluetoothPopupHovering = false
                isBluetoothSidesHovering = false
                isBluetoothCenterHovering = false
                isBluetoothPopupTransitioning = false
                coordinator.resumeExpandingViewAutoHide()
            }
            .onChange(of: isBluetoothPopupHovering) { _, isOpen in
                if isOpen {
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
                    ensureClosedPopupFailsafeRunning()
                } else if !isBluetoothPopupHovering {
                    closedPopupFailsafeTask?.cancel()
                    closedPopupFailsafeTask = nil

                    timerSidesHoverTask?.cancel()
                    timerTransitionTask?.cancel()
                    isTimerSidesHovering = false
                    isTimerExpandedHovering = false
                    isTimerProximityHovering = false
                    isTimerPopupTransitioning = false
                    isTimerPopupHoverArmed = Date() >= suppressTimerPopupAutoOpenUntil

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(10))
                        handleHover(isHovering)
                    }
                }
            }
            .onChange(of: activeQuickTimers.count) { _, count in
                guard count == 0 else { return }

                timerPopupRearmTask?.cancel()
                timerPopupRearmTask = nil
                timerSidesHoverTask?.cancel()
                timerTransitionTask?.cancel()
                isTimerPopupHovering = false
                isTimerSidesHovering = false
                isTimerExpandedHovering = false
                isTimerProximityHovering = false
                isTimerPopupTransitioning = false
                isTimerPopupHoverArmed = false
                keepTimerPopupOpenForFinishedAlert = false

                handleHover(isHovering)
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
                    HStack(spacing: 0) {
                        Group {
       // Priority 1: battery notification
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
                                            .foregroundStyle(.green)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                            .allowsTightening(true)

                                        NotificationBatteryIcon(levelBattery: batteryModel.levelBattery)
                                            .frame(width: 29, height: 12)
                                    }
                                    .opacity(opacity)
                                    .blur(radius: blurRadius)
                                    .scaleEffect(scale, anchor: .trailing)
                                    .compositingGroup()
                                    .frame(width: sideWidth, alignment: .trailing)
                                }
                                .padding(.horizontal, sidePadding)
        // Keep battery live activity strictly horizontal in closed state.
                                .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                                .clipped()
                            }
       // Priority 2: lock screen icon
                            else if shouldShowLockActivityClosed {
                                LockScreenLiveActivity(
                                    isLocked: lockScreenState.isLocked,
                                    contentWidth: vm.closedNotchSize.width - 20,
                                    height: vm.effectiveClosedNotchHeight
                                )
                            }
       // Priority 3: inline HUD
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
       // Priority 4: Bluetooth
                            else if isBluetoothClosedNotificationShowing {
                                BluetoothLiveActivity(
                                    deviceName: bluetoothModel.lastConnectedAliasName ?? bluetoothModel.lastConnectedDeviceName,
                                    kind: bluetoothModel.lastConnectedDeviceKind,
                                    batteryPercent: bluetoothModel.lastConnectedBatteryPercent,
                                    isCompactMode: isBluetoothCompactMode,
                                    isExpanded: isBluetoothPopupHovering,
                                    onHoverZonesChanged: { hoveringSides, hoveringCenter in
                                        if hoveringSides {
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
           // Keep expanded while cursor is still inside activity (center zone).
                                            bluetoothSidesHoverTask?.cancel()
                                            bluetoothCenterHoverTask?.cancel()
                                            isBluetoothCenterHovering = true

           // If Bluetooth popup is already open/transitioning, center should NOT
           // trigger notch open and should keep the popup alive.
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
           // Neither sides nor center => cursor really left the activity.
                                            isBluetoothCenterHovering = false
                                            bluetoothCenterHoverTask?.cancel()

                                            if isBluetoothSidesHovering || isBluetoothPopupHovering {
                                                bluetoothSidesHoverTask?.cancel()
                                                bluetoothSidesHoverTask = Task { @MainActor in
                                                    try? await Task.sleep(for: .milliseconds(120))
                                                    guard !Task.isCancelled else { return }
                                                    self.isBluetoothSidesHovering = false

                                                    if self.coordinator.expandingView.show && self.coordinator.expandingView.type == .bluetooth {
                                                        self.coordinator.resumeExpandingViewAutoHide()
                                                    }

                                                    self.isBluetoothPopupTransitioning = true
                                                    self.bluetoothTransitionTask?.cancel()
                                                    self.bluetoothTransitionTask = Task { @MainActor in
                                                        try? await Task.sleep(for: .milliseconds(240))
                                                        guard !Task.isCancelled else { return }
                                                        self.isBluetoothPopupTransitioning = false
                                                    }
                                                    withAnimation(NotchMotion.popupHover) {
                                                        self.isBluetoothPopupHovering = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                )
                            }
       // Priority 5: focus mode
                            else if shouldShowFocusActivityClosed {
                                closedFocusLiveActivityView()
                                    .transition(
                                        .asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                                        )
                                    )
                            }
       // Priority 6: timer
                            else if shouldShowTimerActivityClosed {
                                closedTimerLiveActivityView()
                            }
       // Priority 7: file tray
                            else if shouldShowFileTrayActivityClosed {
                                FileTrayLiveActivity(count: fileTrayCount, isCompactMode: isFileTrayCompactMode)
                            }
       // Priority 8: player
                            else if shouldShowMusicActivityClosed {
                                MusicLiveActivity(isCompactMode: isNowPlayingCompactMode)
                                    .frame(alignment: .center)
                                    .transition(
                                        .asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                                            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                                        )
                                    )
                            }
       // Face
                            else if shouldShowFaceClosed {
                                BoringFaceAnimation()
                            }
                            else if vm.notchState == .open {
                                Rectangle()
                                    .fill(.clear)
                                    .frame(height: max(24, vm.effectiveClosedNotchHeight))
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
                                && Defaults[.sneakPeekStyles] == .standard
                            {
                                HStack(alignment: .center) {
                                    Image(systemName: "music.note")
                                    GeometryReader { geo in
                                        MarqueeText(
                                            .constant(musicManager.songTitle + " - " + musicManager.artistName),
                                            textColor: Defaults[.playerColorTinting]
                                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                            : .gray,
                                            minDuration: 1,
                                            frameWidth: geo.size.width
                                        )
                                    }
                                }
                                .foregroundStyle(.gray)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
            .conditionalModifier(
                (coordinator.sneakPeek.show
                 && (coordinator.sneakPeek.type == .music)
                 && vm.notchState == .closed
                 && !vm.hideOnClosed
                 && Defaults[.sneakPeekStyles] == .standard)
                || (coordinator.sneakPeek.show
                    && (coordinator.sneakPeek.type != .music)
                    && vm.notchState == .closed)
            ) { view in
                view.fixedSize()
            }
            .zIndex(2)

            if vm.notchState == .open {
                ZStack(alignment: .topTrailing) {
                    let calendarContentWidth: CGFloat = 215
                    let calendarLeadingGutterWidth: CGFloat = 6
                    let calendarTotalWidth: CGFloat = calendarContentWidth + calendarLeadingGutterWidth
                    let isCameraOverlayVisible: Bool =
                        Defaults[.showMirror]
                        && webcamManager.cameraAvailable
                        && vm.isCameraExpanded
                    let reservedTrailing: CGFloat = {
                        if isSwitchingOverlay && overlaySwitchDirection == .toCalendar {
                            return calendarTotalWidth
                        }
                        return showCalendar ? calendarTotalWidth : 0
                    }()

                    GeometryReader { geo in
                        let contentWidth = max(0, geo.size.width - reservedTrailing)

      // Pages gating (Settings → Pages)
                        let homeEnabled = pageHomeEnabled
                        let shelfEnabled = pageShelfEnabled
                        let thirdEnabled = pageThirdEnabled
                        let enabledCount = (homeEnabled ? 1 : 0) + (shelfEnabled ? 1 : 0) + (thirdEnabled ? 1 : 0)

                        Group {
                            if enabledCount <= 1 {
        // Single-page mode: no pager, no horizontal scroll capture.
                                if shelfEnabled && !homeEnabled {
                                    ShelfView(isPagerScrollEnabled: .constant(false))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .onAppear { coordinator.currentView = .shelf }
                                } else if thirdEnabled && !homeEnabled && !shelfEnabled {
                                    NotchThirdView(isPagerScrollEnabled: .constant(false))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .onAppear { coordinator.currentView = .third }
                                } else {
                                    NotchHomeView(albumArtNamespace: albumArtNamespace)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .onAppear { coordinator.currentView = .home }
                                }
                            } else {
        // Multi-page mode: swipeable pager (2 or 3 pages depending on Settings).
                                let enabledViews: [NotchViews] = {
                                    var v: [NotchViews] = []
                                    if homeEnabled { v.append(.home) }
                                    if shelfEnabled { v.append(.shelf) }
                                    if thirdEnabled { v.append(.third) }
                                    return v.isEmpty ? [.home] : v
                                }()

                                NotchPagerDynamic(
                                    selection: $coordinator.currentView,
                                    isScrollEnabled: $isPagerScrollEnabled,
                                    enabledViews: enabledViews,
                                    page: { view in
                                        switch view {
                                        case .home:
                                            AnyView(
                                                NotchHomeView(albumArtNamespace: albumArtNamespace)
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
                        .frame(width: contentWidth, height: geo.size.height, alignment: .topLeading)
                        .offset(y: -8)
                        .clipped()
                        .compositingGroup() // Render the pager as an independent group before parent clipping.
                        .animation(NotchMotion.notchLayout, value: reservedTrailing)
                    }

                    if showCalendar {
                        CalendarOverlayView()
                            .environmentObject(vm)
                            .frame(width: calendarTotalWidth)
                            .padding(.top, 6)
                            .padding(.trailing, -10)
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
                .animation(animationSpring, value: showCalendar)
                .animation(animationSpring, value: vm.isCameraExpanded)
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
        isCompactMode: Bool,
        isExpanded: Bool,
        onHoverZonesChanged: @escaping (_ hoveringSides: Bool, _ hoveringCenter: Bool) -> Void
    ) -> some View {
        BluetoothLiveActivityView(
            vm: vm,
            deviceName: deviceName,
            kind: kind,
            batteryPercent: batteryPercent,
            isCompactMode: isCompactMode,
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

    // Closed: keep the classic look (thin ring).
    // Expanded: scale thickness, but slightly slimmer than before.
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

   // Three cubic segments:
   // - horizontal tangent at both ends
   // - tiny rounded plateau at the top to avoid a pointed crest
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
    func BoringFaceAnimation() -> some View {
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

    @ViewBuilder
    func MusicLiveActivity(isCompactMode: Bool) -> some View {
        HStack {
            if !isCompactMode {
                AlbumArtFlipView(
                    currentImage: musicManager.albumArt,
                    eventID: musicManager.albumArtFlipEventID,
                    incomingImage: musicManager.albumArtFlipImage,
                    direction: musicManager.albumArtFlipDirection,
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                    geometryID: "albumArt",
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
                            .opacity((coordinator.expandingView.show && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)

                            Spacer(minLength: vm.closedNotchSize.width)

                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor)
                                    : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                     && coordinator.expandingView.type == .music
                                     && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0
                                )
                        }
                    }
                )
                .frame(width: isCompactMode
                       ? (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top + max(0, vm.effectiveClosedNotchHeight - 12) + 10)
                       : (vm.closedNotchSize.width + -cornerRadiusInsets.closed.top))

            HStack {
                if isCompactMode {
                    AlbumArtFlipView(
                        currentImage: musicManager.albumArt,
                        eventID: musicManager.albumArtFlipEventID,
                        incomingImage: musicManager.albumArtFlipImage,
                        direction: musicManager.albumArtFlipDirection,
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                        geometryID: "albumArt",
                        namespace: albumArtNamespace
                    )
                } else if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                            ? Color(nsColor: musicManager.avgColor).gradient
                            : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12 + gestureProgress / 2),
                height: max(0, vm.effectiveClosedNotchHeight - 12),
                alignment: .center
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    var dragDetector: some View {
  // If the Shelf page (Page 2) is disabled, dragging files over the notch should not auto-open it.
        if Defaults[.boringShelf] && pageShelfEnabled && vm.notchState == .closed {
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

  // Allow a small region ABOVE the notch window so the timer can remain expanded
  // even if the pointer slips onto an external display positioned above.
        let yAboveTolerance: CGFloat = 12
        let yBelowTolerance: CGFloat = 4

  // Les zones correspondent exactement aux zones de hover dans TimerLiveActivity
        // No external extension; only the visible left and right zones.
        let leftZoneW  = timerActivityLayout.sidePadding + timerActivityLayout.leftWidth
        let rightZoneW = timerActivityLayout.sidePadding + timerActivityLayout.rightWidth

  // Use f.maxY instead of f.minY for better multi-display compatibility
  // (macOS uses a coordinate system where Y increases upward)
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

    private func doOpen() {
  // Battery closed live activity remains horizontal-only.
        if isBatteryClosedNotificationShowing { return }
  // Do not open notch while Bluetooth popup is open or transitioning.
        if isBluetoothClosedNotificationShowing
            && (isBluetoothSidesHovering || isBluetoothPopupHovering || isBluetoothPopupTransitioning) { return }
        if pageUseLiquidGlassBackground {
            // Prime Liquid layers before notch state flips to .open so they are visible on frame 1.
            keepLiquidVisualDuringClose = true
            liquidVisualBlend = max(liquidVisualBlend, 0.35)
            liquidStrokeReveal = max(liquidStrokeReveal, 0.05)
            withAnimation(.easeOut(duration: 0.26)) {
                liquidStrokeReveal = 1
            }
        }
        ignoreHoverExitUntil = Date().addingTimeInterval(0.25)
        vm.open()
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

 // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        if lockScreenState.isLocked { return }

  // Bluetooth closed activity handles its own hover routing
  // (sides expand, center opens notch) to avoid overlap/race conditions.
        if isBluetoothClosedNotificationShowing { return }
  // Battery closed live activity should stay horizontal-only (no vertical notch open).
        if isBatteryClosedNotificationShowing { return }

  // Avoid conflicts: hovering should expand the Timer popup (sides), not open the notch.
  // (Center hover remains the classic notch-open behavior.)
        if shouldShowTimerActivityClosed && (isTimerPopupHovering || isTimerSidesHovering || isTimerProximityHovering) { return }

        let timerHoverBlocksOpen = shouldShowTimerActivityClosed
            && (isTimerPopupHovering || isTimerSidesHovering || isTimerProximityHovering)

        hoverTask?.cancel()

        if hovering {
            deactivateFrozenHoverZone()
            withAnimation(animationSpring) { isHovering = true }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  !isBatteryClosedNotificationShowing,
                  !timerHoverBlocksOpen,
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
                          !timerStillBlocks else { return }
                    self.doOpen()
                }
            }
        } else {
            if Date() < ignoreHoverExitUntil { return }
            if Date() < suppressAutoCloseUntil { return }
            if frozenHoverZoneActive { return }

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
        // Cancel any already-scheduled hover close from the old (larger) zone.
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
                        // Require pointer to stay out for a few polls to avoid instant close on tiny jitter.
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

    private func isPointerInsideFrozenHoverZone() -> Bool {
        guard let window = hostWindow else { return true }
        guard let contentView = window.contentView else { return true }

        let width = max(vm.closedNotchSize.width, frozenHoverZoneWidth)
        let height = max(vm.notchSize.height, vm.effectiveClosedNotchHeight)
        let pointer = window.mouseLocationOutsideOfEventStream

        // Keep a generous top-band hit zone matching the previously opened overlay area.
        // This avoids instant close when the cursor remains visually "where it was".
        let centerX = contentView.bounds.midX
        let halfWidth = (width / 2) + 10
        let minY = contentView.bounds.height - max(height + 42, 220)

        let insideX = abs(pointer.x - centerX) <= halfWidth
        let insideY = pointer.y >= minY
        return insideX && insideY
    }

 // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
  // Don't trigger if pager scroll is disabled (user is interacting with scrollable content)
        guard vm.notchState == .closed && isPagerScrollEnabled else { return }

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
  // Don't trigger if pager scroll is disabled (user is interacting with scrollable content)
        guard vm.notchState == .open && !vm.isHoveringCalendar && isPagerScrollEnabled else { return }

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
}

// MARK: - Bluetooth expanded view

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
    let vm: BoringViewModel
    let deviceName: String
    let kind: BluetoothActivityManager.BluetoothDeviceKind
    let batteryPercent: Int?
    let isCompactMode: Bool
    let isExpanded: Bool
    let closedTopCornerInset: CGFloat
    let onHoverZonesChanged: (_ hoveringSides: Bool, _ hoveringCenter: Bool) -> Void

    var body: some View {
        let baseHeight = vm.effectiveClosedNotchHeight

  // Background sizing: keep footer tight to the physical notch.
        let barExtraHeight: CGFloat = isExpanded ? 12 : 0
        let barHeight = baseHeight + barExtraHeight

  // Footer (Connected + device name)
        let footerHeight: CGFloat = isExpanded ? 28 : 0
        let contentHeight = isExpanded ? (barHeight + footerHeight) : baseHeight

  // Wider center area on hover (matches chin width widening logic).
        let centerExtraWidth: CGFloat = isExpanded ? 110 : 24

  // Slot sizes (icon + battery)
        let sideBase = max(0, barHeight - 12)
        let side = sideBase
        let airPodsVideoSide = sideBase + (isExpanded ? 20 : 6)
  // DualSense video should be slightly smaller than AirPods Pro (only affects DualSense).
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

  // Horizontal insets:
  // - Closed: small + symmetric
  // - Expanded: more padding on the left, slightly less on the right
        let leftInset: CGFloat = isExpanded ? 32 : 4
        let rightInset: CGFloat = isExpanded ? 18 : 4

  // Center spacer width must account for insets (keep overall width stable).
        let centerWidth = max(
            0,
            (vm.closedNotchSize.width + -closedTopCornerInset + centerExtraWidth) - (leftInset + rightInset)
        )

  // Stable hover geometry (closed-state based), so boundaries do not move while expanding.
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
  // Cover both closed and expanded geometries so moving within the expanded center
  // does not look like a hover exit.
        let expandedTotalWidth = max(0, leftInset + side + centerWidth + side + rightInset)
        let hitTotalWidth = max(hitLeftWidth + hitCenterWidth + hitRightWidth, expandedTotalWidth)

        return VStack(spacing: 0) {
   // Top bar row: inset + icon + center spacer + battery + inset
            HStack(spacing: 0) {
                if !isCompactMode {
                    Color.clear.frame(width: leftInset)

     // LEFT
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
                }

    // CENTER (empty but preserves space)
                Rectangle()
                    .fill(.black)
                    .frame(width: isCompactMode ? (centerWidth + side + rightInset) : centerWidth)

    // RIGHT
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

                if !isCompactMode {
                    Color.clear.frame(width: rightInset)
                }
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
                leftEdgeWidth: isCompactMode ? 0 : hitLeftWidth,
                rightEdgeWidth: hitRightWidth,
                isExpanded: isExpanded,
                onHoverZonesChanged: onHoverZonesChanged
            )
            .frame(width: hitTotalWidth, height: contentHeight, alignment: .topLeading)
        }
        .onHover { hovering in
   // Hard reset when pointer leaves the whole Bluetooth activity area.
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
    let page: (NotchViews) -> AnyView

    @State private var dragOffset: CGFloat = 0
    @State private var filteredDeltaX: CGFloat = 0
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
                        .frame(width: width)
                        .clipped() // Clip each page individually.
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
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovering = hovering }
        .onChange(of: selection) { _, _ in
            dragOffset = 0
            filteredDeltaX = 0
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

        if !isDragging && abs(deltaX) > 0 { isDragging = true }

  // Low-pass filter + tiny dead zone to suppress hand tremor jitter while dragging.
        let jitterDeadZone: CGFloat = 0.20
        let input = abs(deltaX) < jitterDeadZone ? 0 : deltaX
        let alpha: CGFloat = 0.42
        filteredDeltaX += (input - filteredDeltaX) * alpha

  // Keep strong finger coupling, but on filtered input.
        let newOffset = dragOffset + (filteredDeltaX * 0.52)
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

        let threshold = width * 0.08
        var nextIndex = currentIndex

        if dragOffset < -threshold || velocity < -0.40 {
            nextIndex = min(currentIndex + 1, enabledViews.count - 1)
        } else if dragOffset > threshold || velocity > 0.40 {
            nextIndex = max(currentIndex - 1, 0)
        }

        isDragging = false
        filteredDeltaX = 0
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
                    .clipped() // Clip each page individually.
                    .compositingGroup() // Force independent rendering.
                    .allowsHitTesting(!isDragging)

                second
                    .frame(width: width)
                    .clipped() // Clip each page individually.
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
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in self.isHovering = hovering }
        .onChange(of: selection) { _, _ in
            dragOffset = 0
            filteredDeltaX = 0
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
        if !isDragging && abs(deltaX) > 0 { isDragging = true }

  // Low-pass filter + tiny dead zone to suppress hand tremor jitter while dragging.
        let jitterDeadZone: CGFloat = 0.20
        let input = abs(deltaX) < jitterDeadZone ? 0 : deltaX
        let alpha: CGFloat = 0.42
        filteredDeltaX += (input - filteredDeltaX) * alpha

  // Keep strong finger coupling, but on filtered input.
        let newOffset = dragOffset + (filteredDeltaX * 0.52)
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
        let threshold = width * 0.08
        var nextIndex = currentIndex

        if currentIndex == 0 {
            if dragOffset < -threshold || velocity < -0.40 { nextIndex = 1 }
        } else {
            if dragOffset > threshold || velocity > 0.40 { nextIndex = 0 }
        }

        isDragging = false
        filteredDeltaX = 0

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

    private let emptyAssetName = "battery_empty"
    private let fullAssetName  = "battery_full"

    private static let nativeAspectRatio: CGFloat = 109.394295 / 52.0

    private var fillFraction: CGFloat {
        let p = CGFloat(levelBattery)
        if p >= 100.0 { return 1.0 }

        let clamped = min(max(p, 0.0), 99.0)
        return clamped / 110.0
    }

    var body: some View {
        GeometryReader { geo in
            let renderedWidth = min(geo.size.width, geo.size.height * Self.nativeAspectRatio)
            let fillWidth = renderedWidth * fillFraction

            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Image(emptyAssetName)
                        .resizable()
                        .scaledToFit()

                    Image(fullAssetName)
                        .resizable()
                        .scaledToFit()
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
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
