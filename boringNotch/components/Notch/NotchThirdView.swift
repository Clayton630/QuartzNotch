
import SwiftUI
import AppKit
import Defaults

// MARK: - Layout

private enum NotchThirdLayout {
    static func timerCardHeight(for compression: CGFloat) -> CGFloat {
        38 - (3 * compression)
    }

    static func timerStackSpacing(for compression: CGFloat) -> CGFloat {
        8 - (2 * compression)
    }

    /// Total height of the quick-timers column (all presets + spacing).
    static func quickTimersTotalHeight(for compression: CGFloat) -> CGFloat {
        let count = CGFloat(TimerPreset.allCases.count)
        guard count > 0 else { return 0 }
        return (count * timerCardHeight(for: compression)) + ((count - 1) * timerStackSpacing(for: compression))
    }

    /// Keep clipboard card perfectly aligned with the quick timers stack.
    static let clipboardVerticalOverhang: CGFloat = 0

    /// Fixed width for the duration label/editor so the timer row doesn't resize when entering edit mode.
    /// Must fit within the quick-timer card alongside the play button.
    static func durationEditorWidth(for compression: CGFloat) -> CGFloat {
        78 - (2 * compression)
    }

    /// Fixed card width for each quick timer to prevent expansion when switching states.
    static func quickTimerCardWidth(for compression: CGFloat) -> CGFloat {
        140 - (6 * compression)
    }

    static func sectionHorizontalPadding(for compression: CGFloat) -> CGFloat {
        17 - (2 * compression)
    }

    static func sectionTopPadding(for compression: CGFloat) -> CGFloat {
        4 - (2 * compression)
    }

    static func sectionBottomPadding(for compression: CGFloat) -> CGFloat {
        10 - (4 * compression)
    }

    static func rowHorizontalPadding(for compression: CGFloat) -> CGFloat {
        10 - (1.5 * compression)
    }

    static func rowVerticalPadding(for compression: CGFloat) -> CGFloat {
        5 - compression
    }

    static func controlSize(for compression: CGFloat) -> CGFloat {
        26 - (2 * compression)
    }

    static func readoutFontSize(for compression: CGFloat) -> CGFloat {
        12 - (0.6 * compression)
    }

    static func readoutHeight(for compression: CGFloat) -> CGFloat {
        16 - compression
    }
}

struct NotchThirdView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.showMirror) private var showMirror
    @StateObject private var timerManager = QuickTimerManager.shared
    @StateObject private var clipboardManager = ClipboardManager.shared

  /// In multi-page mode, the notch uses a swipeable pager that captures horizontal scroll gestures.
  /// While the user interacts with the clipboard list (two-finger scrolling), we disable pager scrolling
    /// to avoid accidental page switches/closures.
    @Binding var isPagerScrollEnabled: Bool

    init(isPagerScrollEnabled: Binding<Bool> = .constant(true)) {
        self._isPagerScrollEnabled = isPagerScrollEnabled
    }

    var body: some View {
        let timerStackHeight = NotchThirdLayout.quickTimersTotalHeight(for: openLayoutCompression)
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                QuickTimersSection()
                Spacer(minLength: 0)
            }
            .frame(width: 140)
            .frame(height: timerStackHeight, alignment: .top)
            
            ClipboardCard(isPagerScrollEnabled: $isPagerScrollEnabled)
                .frame(maxWidth: .infinity)
                .frame(
                    height: timerStackHeight + (2 * NotchThirdLayout.clipboardVerticalOverhang),
                    alignment: .top
                )
                .offset(y: -NotchThirdLayout.clipboardVerticalOverhang)

        }
        .padding(.horizontal, NotchThirdLayout.sectionHorizontalPadding(for: openLayoutCompression))
        .padding(.top, NotchThirdLayout.sectionTopPadding(for: openLayoutCompression))
        .padding(.bottom, NotchThirdLayout.sectionBottomPadding(for: openLayoutCompression))
    }
}

// MARK: - Quick Timers Section

struct QuickTimersSection: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @StateObject private var timerManager = QuickTimerManager.shared
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    
    var body: some View {
        VStack(spacing: NotchThirdLayout.timerStackSpacing(for: openLayoutCompression)) {
            ForEach(Array(TimerPreset.allCases.enumerated()), id: \.element) { index, preset in
                QuickTimerButton(
                    preset: preset,
                    ambientShadowOpacity: timerShadowOpacity(for: index),
                    ambientShadowBlur: timerShadowBlur(for: index),
                    ambientShadowYOffset: timerShadowYOffset(for: index)
                )
            }
        }
        .overlay {
            if pageUseLiquidGlassBackground {
                VStack(spacing: NotchThirdLayout.timerStackSpacing(for: openLayoutCompression)) {
                    ForEach(Array(TimerPreset.allCases.enumerated()), id: \.offset) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.31), lineWidth: 1.0)
                            .frame(
                                width: NotchThirdLayout.quickTimerCardWidth(for: openLayoutCompression),
                                height: NotchThirdLayout.timerCardHeight(for: openLayoutCompression)
                            )
                    }
                }
                .blendMode(.screen)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.00), location: 0.00),
                            .init(color: .white.opacity(0.22), location: 0.40),
                            .init(color: .white.opacity(0.56), location: 0.72),
                            .init(color: .white.opacity(1.00), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func timerShadowOpacity(for index: Int) -> Double {
        guard pageUseLiquidGlassBackground else { return 0 }
        if index == 1 { return 0.14 }
        if index == TimerPreset.allCases.count - 1 { return 0.24 }
        return 0
    }

    private func timerShadowBlur(for index: Int) -> CGFloat {
        if index == 1 { return 12 }
        if index == TimerPreset.allCases.count - 1 { return 15 }
        return 0
    }

    private func timerShadowYOffset(for index: Int) -> CGFloat {
        if index == 1 { return 5 }
        if index == TimerPreset.allCases.count - 1 { return 7 }
        return 0
    }
}

struct QuickTimerButton: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    let preset: TimerPreset
    let ambientShadowOpacity: Double
    let ambientShadowBlur: CGFloat
    let ambientShadowYOffset: CGFloat
    @StateObject private var timerManager = QuickTimerManager.shared
    @State private var isHovering = false
    @State private var isEditingDuration = false
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    private var activeTimer: QuickTimer? {
        timerManager.timers.first(where: { $0.preset == preset })
    }

    private var durationSeconds: Binding<Int> {
        Binding(
            get: { preset.effectiveDurationSeconds },
            set: { preset.setCustomDurationSeconds($0) }
        )
    }

    var body: some View {
        ZStack {
            NotchCardBackground(
                cornerRadius: 10,
                isHovering: isHovering,
                ambientShadowOpacity: ambientShadowOpacity,
                ambientShadowBlur: ambientShadowBlur,
                ambientShadowYOffset: ambientShadowYOffset
            )

            if let timer = activeTimer {
                ActiveQuickTimerContent(
                    timer: timer,
                    onToggle: {
                        timerManager.toggleTimer(timer)
                    },
                    onStop: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            timerManager.stopTimer(timer)
                        }
                    }
                )
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.10 : 0.0), radius: 2.0, x: 0, y: 1)
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.035 : 0.0), radius: 4.6, x: 0, y: 2)
            } else {
                InactiveQuickTimerContent(
                    preset: preset,
                    durationSeconds: durationSeconds,
                    isEditingDuration: $isEditingDuration,
                    onStart: {
                        timerManager.startTimer(duration: preset.effectiveDurationSeconds, preset: preset)
                    }
                )
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.10 : 0.0), radius: 2.0, x: 0, y: 1)
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.035 : 0.0), radius: 4.6, x: 0, y: 2)
            }
        }
        .frame(
            width: NotchThirdLayout.quickTimerCardWidth(for: openLayoutCompression),
            height: NotchThirdLayout.timerCardHeight(for: openLayoutCompression)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .compositingGroup()
        .animation(.none, value: activeTimer != nil)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button(isEditingDuration ? "Done Editing" : "Edit Duration") {
                isEditingDuration.toggle()
            }

            Divider()

            Button("-10s") { preset.setCustomDurationSeconds(max(1, preset.effectiveDurationSeconds - 10)) }
            Button("+10s") { preset.setCustomDurationSeconds(preset.effectiveDurationSeconds + 10) }
            Button("-1m") { preset.setCustomDurationSeconds(max(1, preset.effectiveDurationSeconds - 60)) }
            Button("+1m") { preset.setCustomDurationSeconds(preset.effectiveDurationSeconds + 60) }

            if preset.customDurationSeconds != nil {
                Button("Reset Duration") { preset.setCustomDurationSeconds(nil) }
            }

            if let timer = activeTimer {
                Button("Reset") { timerManager.resetTimer(timer) }
                Button("Stop") { timerManager.stopTimer(timer) }
            }
        }
    }
}

private struct ActiveQuickTimerContent: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @ObservedObject var timer: QuickTimer
    let onToggle: () -> Void
    let onStop: () -> Void

    private let runningTint = Color(nsColor: .systemOrange)
    private let neutralTint = Color.white.opacity(0.85)
    private let stopToRingOffset: CGFloat = 32

    var body: some View {
        let controlSize = NotchThirdLayout.controlSize(for: openLayoutCompression)
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                TimerReadout(
                    text: timer.displayTime,
                    value: timer.remainingSeconds,
                    opacity: 1.0
                )
            }
            .frame(width: NotchThirdLayout.durationEditorWidth(for: openLayoutCompression), alignment: .leading)

            Spacer(minLength: 0)

            ZStack {
                ProgressRingControl(
                    progress: timer.progress,
                    isRunning: timer.isRunning,
                    tint: runningTint,
                    size: controlSize,
                    action: onToggle
                )

                Button(action: onStop) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.10))
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(neutralTint)
                    }
                    .frame(width: controlSize, height: controlSize)
                }
                .buttonStyle(.plain)
                .offset(x: -stopToRingOffset)
            }
            .frame(width: controlSize, height: controlSize, alignment: .trailing)
        }
        .padding(.horizontal, NotchThirdLayout.rowHorizontalPadding(for: openLayoutCompression))
        .padding(.vertical, NotchThirdLayout.rowVerticalPadding(for: openLayoutCompression))
    }
}

private struct InactiveQuickTimerContent: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    let preset: TimerPreset
    @Binding var durationSeconds: Int
    @Binding var isEditingDuration: Bool
    let onStart: () -> Void

    private let readyTint = Color(nsColor: .systemGreen)
    var body: some View {
        let controlSize = NotchThirdLayout.controlSize(for: openLayoutCompression)
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if isEditingDuration {
                    InlineDurationEditor(durationSeconds: $durationSeconds) {
                        isEditingDuration = false
                    }
                } else {
                    TimerReadout(
                        text: TimerPreset.formatHMS(durationSeconds),
                        value: durationSeconds,
                        opacity: 0.85,
                        onTap: { isEditingDuration = true }
                    )
                }
            }
            .frame(width: NotchThirdLayout.durationEditorWidth(for: openLayoutCompression), alignment: .leading)

            Spacer(minLength: 0)

            Button(action: onStart) {
                ZStack {
                    Circle()
                        .fill(readyTint.opacity(0.22))
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(readyTint)
                }
                .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NotchThirdLayout.rowHorizontalPadding(for: openLayoutCompression))
        .padding(.vertical, NotchThirdLayout.rowVerticalPadding(for: openLayoutCompression))
    }
}

private struct TimerReadout: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    let text: String
    let value: Int
    let opacity: Double
    var onTap: (() -> Void)? = nil

    var body: some View {
        AnimatedCountdownText(
            text: text,
            value: value
        )
        .font(.system(size: NotchThirdLayout.readoutFontSize(for: openLayoutCompression), weight: .semibold))
        .opacity(opacity)
        .frame(width: NotchThirdLayout.durationEditorWidth(for: openLayoutCompression), alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - Inline duration editor (integrated, but not limiting)

/// Minimal UI, but allows *arbitrary* durations (including hours) via typing.
///
/// - Click duration to enter edit mode.
/// - Type formats like: `1:30`, `01:00:00`, `90m`, `1h`, `1h30m`, `45s`.
/// - Enter = apply. Esc = cancel.
/// - +/- buttons adjust quickly:
///  - default: ±1m
///  - Option: ±10s
///  - Shift: ±10m
private struct InlineDurationEditor: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @Binding var durationSeconds: Int
    let onDone: () -> Void

    @State private var originalSeconds: Int = 0
    @State private var hText: String = "0"
    @State private var mText: String = "00"
    @State private var sText: String = "00"

    @FocusState private var focused: Field?
    private enum Field: Hashable { case h, m, s }

    var body: some View {
        HStack(spacing: 2) {
            field($hText, field: .h, width: 28, maxDigits: 3)
            colon
            field($mText, field: .m, width: 20, maxDigits: 2)
            colon
            field($sText, field: .s, width: 20, maxDigits: 2)
        }
        .frame(width: NotchThirdLayout.durationEditorWidth(for: openLayoutCompression), alignment: .leading)
        .onAppear {
            originalSeconds = durationSeconds
            let (h, m, s) = splitHMS(durationSeconds)
            hText = String(h)
            mText = String(format: "%02d", m)
            sText = String(format: "%02d", s)
            NotificationCenter.default.post(name: .notchTextInputBegan, object: nil)
            DispatchQueue.main.async { focused = .h }
        }
        .onExitCommand {
            durationSeconds = originalSeconds
            NotificationCenter.default.post(name: .notchTextInputEnded, object: nil)
            onDone()
        }
    }

    private var colon: some View {
        Text(":")
            .foregroundStyle(.white.opacity(0.75))
            .monospacedDigit()
    }

    private func field(
        _ text: Binding<String>,
        field: Field,
        width: CGFloat,
        maxDigits: Int
    ) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(.white.opacity(0.92))
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .focused($focused, equals: field)
            .monospacedDigit()
            .onChange(of: text.wrappedValue) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                let trimmed = String(digits.prefix(maxDigits))
                if trimmed != newValue { text.wrappedValue = trimmed }
            }
            .onSubmit { applyAndExit() } // Enter: apply + exit
    }

    private func applyAndExit() {
        let h = max(0, Int(hText) ?? 0)
        let m = min(59, max(0, Int(mText) ?? 0))
        let s = min(59, max(0, Int(sText) ?? 0))

        let total = max(1, (h * 3600) + (m * 60) + s)
        durationSeconds = total

        NotificationCenter.default.post(name: .notchTextInputEnded, object: nil)
        onDone()
    }

    private func splitHMS(_ seconds: Int) -> (Int, Int, Int) {
        let v = max(0, seconds)
        let h = v / 3600
        let m = (v % 3600) / 60
        let s = v % 60
        return (h, m, s)
    }
}



private struct ProgressRingControl: View {
    let progress: Double
    let isRunning: Bool
    let tint: Color
    let size: CGFloat
    let action: () -> Void
    private let ringLineWidth: CGFloat = 2

  /// Render the ring as *remaining* time: full at start → empty at the end.
    private var displayedProgress: Double {
        1.0 - progress
    }

    var body: some View {
        Button(action: action) {
            ZStack {

                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: ringLineWidth)
                    .padding(ringLineWidth / 2)

                Circle()
                    .trim(from: 0, to: displayedProgress)
                    .stroke(
                        tint.opacity(0.95),
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(ringLineWidth / 2)
                    .animation(.linear(duration: 1), value: displayedProgress)

                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared styling primitives

private struct NotchCardBackground: View {
    let cornerRadius: CGFloat
    let isHovering: Bool
    var usesBottomWeightedStroke: Bool = false
    var ambientShadowOpacity: Double = 0
    var ambientShadowBlur: CGFloat = 0
    var ambientShadowYOffset: CGFloat = 0
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    private var baseFill: Color { Color(nsColor: .secondarySystemFill) }

    private let unifiedBaseOpacity: Double = 0.985
    private let unifiedHoverOpacity: Double = 1.00
    private let unifiedDoubleFillOpacity: Double = 0.24

    var body: some View {
        ZStack {
            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(isHovering ? 0.31 : 0.27)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(isHovering ? 0.066 : 0.050))

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(isHovering ? 0.010 : 0.007))
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(baseFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(baseFill)
                        .opacity(pageUseLiquidGlassBackground ? 0.13 : unifiedDoubleFillOpacity)
                }
                .opacity(isHovering ? unifiedHoverOpacity : (pageUseLiquidGlassBackground ? 0.87 : unifiedBaseOpacity))
                .overlay {
                    if pageUseLiquidGlassBackground && ambientShadowOpacity > 0 {
                        BottomAmbientShadow(
                            cornerRadius: cornerRadius,
                            opacity: ambientShadowOpacity,
                            blur: ambientShadowBlur,
                            y: ambientShadowYOffset
                        )
                    }
                }
                .overlay {
                    if pageUseLiquidGlassBackground {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1.0)
                            .blendMode(.multiply)
                    }
                }
                .overlay {
                    if pageUseLiquidGlassBackground && usesBottomWeightedStroke {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.11), location: 0.00),
                                        .init(color: Color.white.opacity(0.11), location: 0.54),
                                        .init(color: Color.white.opacity(0.18), location: 0.76),
                                        .init(color: Color.white.opacity(0.34), location: 1.00),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .blendMode(.screen)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                Color.white.opacity(pageUseLiquidGlassBackground ? 0.11 : 0.025),
                                lineWidth: 1
                            )
                    }
                }
                .shadow(
                    color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.18 : 0.0),
                    radius: pageUseLiquidGlassBackground ? 8 : 0,
                    x: 0,
                    y: pageUseLiquidGlassBackground ? 2 : 0
                )
        }
    }
}

private struct AnimatedCountdownText: View {
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    let text: String
    let value: Int

    var body: some View {
        ZStack(alignment: .leading) {
            Text("00:00")
                .monospacedDigit()
                .opacity(0)
                .accessibilityHidden(true)

            Text(text)
                .monospacedDigit()
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.22), value: value)
        }
        .drawingGroup() // Render to an offscreen texture to isolate from parent transforms.
        .frame(height: NotchThirdLayout.readoutHeight(for: openLayoutCompression), alignment: .center)
    }
}

private struct BottomAmbientShadow: View {
    let cornerRadius: CGFloat
    let opacity: Double
    let blur: CGFloat
    let y: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(opacity))
            .scaleEffect(x: 0.99, y: 0.95)
            .blur(radius: blur)
            .offset(y: y)
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .clear, location: 0.52),
                                .init(color: .white.opacity(0.72), location: 0.82),
                                .init(color: .white, location: 1.00),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }
}

// MARK: - Clipboard Section


// MARK: - Clipboard Card (visual parity with timer cards)

private struct ClipboardCard: View {
    @Binding var isPagerScrollEnabled: Bool
    @State private var isHovering = false
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    var body: some View {
        ZStack {
            NotchCardBackground(
                cornerRadius: 10,
                isHovering: isHovering,
                usesBottomWeightedStroke: true,
                ambientShadowOpacity: pageUseLiquidGlassBackground ? 0.22 : 0,
                ambientShadowBlur: pageUseLiquidGlassBackground ? 15 : 0,
                ambientShadowYOffset: pageUseLiquidGlassBackground ? 7 : 0
            )
            ClipboardSection(isPagerScrollEnabled: $isPagerScrollEnabled)
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.10 : 0.0), radius: 2.0, x: 0, y: 1)
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.035 : 0.0), radius: 4.6, x: 0, y: 2)
        }
        .onHover { isHovering = $0 }
    }
}

struct ClipboardSection: View {
    @StateObject private var clipboardManager = ClipboardManager.shared
    @Binding var isPagerScrollEnabled: Bool
    @State private var isHoveringList = false
    @State private var wheelMonitor: Any?
    @State private var pagerReenableTask: Task<Void, Never>?

    init(isPagerScrollEnabled: Binding<Bool>) {
        self._isPagerScrollEnabled = isPagerScrollEnabled
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                
                
                Spacer()
                
                if !clipboardManager.items.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            clipboardManager.clearAll()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if clipboardManager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Text("Empty")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(clipboardManager.items) { item in
                            ClipboardItemRow(item: item)
                        }
                    }
                    .padding(4)
                }
                .onHover { hovering in
                    isHoveringList = hovering
                    if !hovering {
                        pagerReenableTask?.cancel()
                        isPagerScrollEnabled = true
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            isPagerScrollEnabled = true
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard isHoveringList, !clipboardManager.items.isEmpty else { return event }

                let dx = abs(event.scrollingDeltaX)
                let dy = abs(event.scrollingDeltaY)
                let threshold: CGFloat = 0.8

                if dy > (dx + threshold) {
                    isPagerScrollEnabled = false
                    pagerReenableTask?.cancel()
                    pagerReenableTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(140))
                        guard !Task.isCancelled else { return }
                        if isHoveringList { isPagerScrollEnabled = true }
                    }
                } else if dx > (dy + threshold) {
                    isPagerScrollEnabled = true
                }

                return event
            }
        }
        .onDisappear {
            isPagerScrollEnabled = true
            pagerReenableTask?.cancel()
            if let wheelMonitor {
                NSEvent.removeMonitor(wheelMonitor)
                self.wheelMonitor = nil
            }
        }
        .onChange(of: clipboardManager.items.isEmpty) { isEmpty in
            if isEmpty { isPagerScrollEnabled = true }
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @StateObject private var clipboardManager = ClipboardManager.shared
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 16)
                
            if item.type == .image, let image = item.content as? NSImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(item.preview)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                
            Spacer(minLength: 0)
                
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    clipboardManager.deleteItem(item)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
        )
        .onTapGesture {
            clipboardManager.pasteItemIntoLastTextZone(item)
        }
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    NotchThirdView()
        .frame(width: 420, height: 200)
        .background(.black)
}
