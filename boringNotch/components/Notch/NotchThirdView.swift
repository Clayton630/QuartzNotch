//
// NotchThirdView.swift
// boringNotch
//
// Modified by AI Assistant on 2026-02-02.
//

import SwiftUI
import AppKit
import Defaults

// MARK: - Layout

private enum NotchThirdLayout {
  // Tuned to visually match the Clipboard card height.
    static let timerCardHeight: CGFloat = 38
    static let timerStackSpacing: CGFloat = 8

  /// Total height of the quick-timers column (all presets + spacing).
    static var quickTimersTotalHeight: CGFloat {
        let count = CGFloat(TimerPreset.allCases.count)
        guard count > 0 else { return 0 }
        return (count * timerCardHeight) + ((count - 1) * timerStackSpacing)
    }

  /// Keep clipboard card perfectly aligned with the quick timers stack.
    static let clipboardVerticalOverhang: CGFloat = 0

  /// Fixed width for the duration label/editor so the timer row doesn't resize when entering edit mode.
  /// Must fit within the quick-timer card alongside the play button.
    static let durationEditorWidth: CGFloat = 78

  /// Fixed card width for each quick timer to prevent expansion when switching states.
    static let quickTimerCardWidth: CGFloat = 140

}

struct NotchThirdView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.showMirror) private var showMirror
    @StateObject private var timerManager = QuickTimerManager.shared
    @StateObject private var clipboardManager = ClipboardManager.shared

  /// In multi-page mode, the notch uses a swipeable pager that captures horizontal scroll gestures.
  /// While the user interacts with the clipboard list (two-finger scrolling), we disable pager scrolling
  /// to avoid accidental page switches/closures.
    @Binding var isPagerScrollEnabled: Bool
    private let cameraReservedWidth: CGFloat = 132

    init(isPagerScrollEnabled: Binding<Bool> = .constant(true)) {
        self._isPagerScrollEnabled = isPagerScrollEnabled
    }

    private var shouldShowCamera: Bool {
        showMirror && webcamManager.cameraAvailable && vm.isCameraExpanded
    }
    
    var body: some View {
    // Top-align columns so visual height differences are immediately visible (and avoid center-align drift).
        HStack(alignment: .top, spacing: 10) {
      // Left side: Quick Timers (3 vertical presets)
            VStack(spacing: 0) {
                QuickTimersSection()
                Spacer(minLength: 0)
            }
            .frame(width: 140)
            .frame(height: NotchThirdLayout.quickTimersTotalHeight, alignment: .top)
            
      // Right side: Clipboard Manager
            ClipboardCard(isPagerScrollEnabled: $isPagerScrollEnabled)
                .frame(maxWidth: .infinity)
                .frame(
                    height: NotchThirdLayout.quickTimersTotalHeight + (2 * NotchThirdLayout.clipboardVerticalOverhang),
                    alignment: .top
                )
        // Keep exact top/bottom alignment with the timers column.
                .offset(y: -NotchThirdLayout.clipboardVerticalOverhang)

            if shouldShowCamera {
                Spacer(minLength: 0)
                    .frame(width: cameraReservedWidth, height: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

// MARK: - Quick Timers Section

struct QuickTimersSection: View {
    @StateObject private var timerManager = QuickTimerManager.shared
    
    var body: some View {
    // Give the presets more breathing room vertically.
        VStack(spacing: NotchThirdLayout.timerStackSpacing) {
            ForEach(TimerPreset.allCases, id: \.self) { preset in
                QuickTimerButton(preset: preset)
            }
        }
    }
}

struct QuickTimerButton: View {
    let preset: TimerPreset
    @StateObject private var timerManager = QuickTimerManager.shared
    @State private var isHovering = false
    @State private var isEditingDuration = false

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
            NotchCardBackground(cornerRadius: 10, isHovering: isHovering)

      // IMPORTANT:
      // We must observe an active timer directly; otherwise SwiftUI will not refresh
      // when `remainingSeconds` changes (because only the manager is a StateObject here).
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
            } else {
                InactiveQuickTimerContent(
                    preset: preset,
                    durationSeconds: durationSeconds,
                    isEditingDuration: $isEditingDuration,
                    onStart: {
                        timerManager.startTimer(duration: preset.effectiveDurationSeconds, preset: preset)
                    }
                )
            }
        }
        .frame(width: NotchThirdLayout.quickTimerCardWidth, height: NotchThirdLayout.timerCardHeight)
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
    @ObservedObject var timer: QuickTimer
    let onToggle: () -> Void
    let onStop: () -> Void

    private let runningTint = Color(nsColor: .systemOrange)
    private let neutralTint = Color.white.opacity(0.85)
    private let controlSize: CGFloat = 26
    private let stopToRingOffset: CGFloat = 32

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                TimerReadout(
                    text: timer.displayTime,
                    value: timer.remainingSeconds,
                    opacity: 1.0
                )
            }
            .frame(width: NotchThirdLayout.durationEditorWidth, alignment: .leading)

            Spacer(minLength: 0)

      // Keep the ring anchored like the inactive play button.
      // Render stop in overlay, shifted left into spacer space.
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private struct InactiveQuickTimerContent: View {
    let preset: TimerPreset
    @Binding var durationSeconds: Int
    @Binding var isEditingDuration: Bool
    let onStart: () -> Void

    private let readyTint = Color(nsColor: .systemGreen)
    private let controlSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if isEditingDuration {
                    InlineDurationEditor(durationSeconds: $durationSeconds) {
                        isEditingDuration = false
                    }
                } else {
          // Click the time label to toggle inline editing.
                    TimerReadout(
                        text: TimerPreset.formatHMS(durationSeconds),
                        value: durationSeconds,
                        opacity: 0.85,
                        onTap: { isEditingDuration = true }
                    )
                }
            }
      // Keep layout + typography stable when switching between display and edit mode.
            .frame(width: NotchThirdLayout.durationEditorWidth, alignment: .leading)

            Spacer(minLength: 0)

      // Play button on the right, green, like Apple's Timer.
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private struct TimerReadout: View {
    let text: String
    let value: Int
    let opacity: Double
    var onTap: (() -> Void)? = nil

    var body: some View {
        AnimatedCountdownText(
            text: text,
            value: value
        )
        .font(.system(size: 12, weight: .semibold))
        .opacity(opacity)
        .frame(width: NotchThirdLayout.durationEditorWidth, alignment: .leading)
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
        .frame(width: NotchThirdLayout.durationEditorWidth, alignment: .leading)
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

    // Keep a minimum of 1 second to avoid zero-length timers.
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
    // `progress` is elapsed/total in [0, 1]. Remaining is (1 - progress).
        1.0 - progress
    }

    var body: some View {
        Button(action: action) {
            ZStack {
        // No tinted background fill: keep the control clean and consistent.
        // Hit-testing is ensured by the explicit frame + contentShape.

        // Track
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: ringLineWidth)
                    .padding(ringLineWidth / 2)

        // Progress
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

    private var baseFill: Color { Color(nsColor: .secondarySystemFill) }

  // Keep this value in sync with header pills (dots + toolbar) for a unified UI.
    private let unifiedBaseOpacity: Double = 0.985
    private let unifiedHoverOpacity: Double = 1.00
    private let unifiedDoubleFillOpacity: Double = 0.24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
      // Match the pill/dots system fill style.
            .fill(baseFill)
      // Add a very subtle "double fill" to make the material feel slightly more opaque
      // without changing the overall color language.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(baseFill)
                    .opacity(unifiedDoubleFillOpacity)
            }
      // Slight hover lift, without making the card feel heavy.
            .opacity(isHovering ? unifiedHoverOpacity : unifiedBaseOpacity)
      // Uniform background (no gradient). Keep a very subtle stroke for definition.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
          // Keep the border strictly inside the bounds so it doesn't change perceived sizing.
                    .strokeBorder(Color.white.opacity(0.025), lineWidth: 1)
            }
    }
}

private struct AnimatedCountdownText: View {
    let text: String
    let value: Int

    var body: some View {
    // The core issue: .contentTransition(.numericText()) uses internal transforms
    // that combine badly with the parent HStack's .offset() during page swipes.
    // 
    // Solution: Render the text into an offscreen buffer BEFORE the page transform
    // is applied. This isolates the numeric animation from parent transformations.
        ZStack(alignment: .leading) {
      // Hidden placeholder to reserve stable layout space
            Text("00:00")
                .monospacedDigit()
                .opacity(0)
                .accessibilityHidden(true)

      // Actual animated text rendered to an independent layer
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
        .frame(height: 16, alignment: .center)
    }
}

// MARK: - Clipboard Section


// MARK: - Clipboard Card (visual parity with timer cards)

private struct ClipboardCard: View {
    @Binding var isPagerScrollEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        ZStack {
            NotchCardBackground(cornerRadius: 10, isHovering: isHovering)
            ClipboardSection(isPagerScrollEnabled: $isPagerScrollEnabled)
        }
        .onHover { isHovering = $0 }
    }
}

struct ClipboardSection: View {
    @StateObject private var clipboardManager = ClipboardManager.shared
    @Binding var isPagerScrollEnabled: Bool

    init(isPagerScrollEnabled: Binding<Bool>) {
        self._isPagerScrollEnabled = isPagerScrollEnabled
    }
    
    var body: some View {
        VStack(spacing: 0) {
      // Header
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
            
      // Clipboard items
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
        // When the pointer is over the clipboard list, allow two-finger scrolling
        // to scroll the list instead of triggering the notch pager.
                .onHover { hovering in
                    if hovering && !clipboardManager.items.isEmpty {
                        isPagerScrollEnabled = false
                    } else {
                        isPagerScrollEnabled = true
                    }
                }
            }
        }
    // Fill the height imposed by the parent. The card background is applied by the parent
    // *after* the explicit height, so it truly matches the timers column.
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { isPagerScrollEnabled = true }
        .onDisappear { isPagerScrollEnabled = true }
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
        Button {
            clipboardManager.copyItem(item)
        } label: {
            HStack(spacing: 8) {
        // Icon
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16)
                
        // Preview
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
                
        // Delete button
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
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
