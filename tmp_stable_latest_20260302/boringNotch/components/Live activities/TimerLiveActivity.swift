//
// TimerLiveActivity.swift
// boringNotch
//
// Closed-notch "live activity" indicator for Quick Timers (page 3).
//

import SwiftUI
import AppKit

// MARK: - Native side hover detector (left/right only, center excluded)

private struct TimerSidesHoverTrackingView: NSViewRepresentable {
    let leftWidth: CGFloat
    let notchWidth: CGFloat
    let rightWidth: CGFloat
    let treatWholeAreaAsHoverTarget: Bool
    let onSidesHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = HoverDetectorView()
        v.leftWidth = leftWidth
        v.notchWidth = notchWidth
        v.rightWidth = rightWidth
        v.treatWholeAreaAsHoverTarget = treatWholeAreaAsHoverTarget
        v.onSidesHoverChanged = onSidesHoverChanged
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? HoverDetectorView else { return }
        v.leftWidth = leftWidth
        v.notchWidth = notchWidth
        v.rightWidth = rightWidth
        v.treatWholeAreaAsHoverTarget = treatWholeAreaAsHoverTarget
        v.onSidesHoverChanged = onSidesHoverChanged
    }

    final class HoverDetectorView: NSView {
        var leftWidth: CGFloat = 0
        var notchWidth: CGFloat = 0
        var rightWidth: CGFloat = 0
        var treatWholeAreaAsHoverTarget: Bool = false
        var onSidesHoverChanged: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let existing = trackingArea {
                removeTrackingArea(existing)
            }

            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect
            ]

            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            if let trackingArea {
                addTrackingArea(trackingArea)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            updateHoverState(with: event)
        }

        override func mouseMoved(with event: NSEvent) {
            updateHoverState(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            onSidesHoverChanged?(false)
        }

        // Let underlying SwiftUI buttons receive clicks while keeping tracking active.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func updateHoverState(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if treatWholeAreaAsHoverTarget {
                // Expanded mode: keep hover stable near edges to avoid accidental close
                // when the cursor grazes the top/border of the activity.
                let tolerantBounds = bounds.insetBy(dx: -10, dy: -10)
                onSidesHoverChanged?(tolerantBounds.contains(p))
                return
            }

            guard bounds.contains(p) else {
                onSidesHoverChanged?(false)
                return
            }

            let x = p.x
            let leftMax = leftWidth
            let rightMin = leftWidth + notchWidth
            let rightMax = rightMin + rightWidth

            let onLeft = x >= 0 && x <= leftMax
            let onRight = x >= rightMin && x <= rightMax
            onSidesHoverChanged?(onLeft || onRight)
        }
    }
}


/// Places the needle so that a pivot point along its length is exactly at the center of the ring,
/// then rotates around that pivot.
private struct TimerNeedlePivotModifier: ViewModifier {
    let length: CGFloat
  /// Distance of pivot point from the needle's leading edge as a fraction of `length`.
    let pivotFraction: CGFloat
    let angle: Double

    func body(content: Content) -> some View {
        let pivot = max(2, min(length - 2, length * pivotFraction))
        let anchor = UnitPoint(x: pivot / max(1, length), y: 0.5)

        return content
      // Place pivot at center: shift view so its pivot point sits on the ZStack center.
            .offset(x: length / 2 - pivot)
            .rotationEffect(.degrees(angle), anchor: anchor)
    }
}

/// Small closed-notch timer indicator (macOS) — not ActivityKit.
struct TimerLiveActivity: View {
    struct Layout {
        let sidePadding: CGFloat
        let leftWidth: CGFloat
        let rightWidth: CGFloat
        let fontSize: CGFloat
    }

    let text: String
    let extraCount: Int
  /// Remaining progress [0..1] (decreasing as time elapses).
    let progressRemaining: Double
    let timers: [QuickTimer]
    let layout: Layout
    let notchWidth: CGFloat
    let baseHeight: CGFloat
    let isCompactMode: Bool
    let expandedCenterGapWidth: CGFloat
    let expandedTimeWidth: CGFloat
    let expandedRowHeight: CGFloat
    let expandedRowsSpacing: CGFloat

  /// Expanded (hover on left/right segments only). The physical notch segment stays passive so classic notch hover works.
    let isExpanded: Bool
  /// Called when the pointer enters/leaves either visible side segment (left ring or right text).
    let onSidesHoverChanged: (Bool) -> Void
    let isTimerReadOnly: (QuickTimer) -> Bool
    let onToggleTimer: (QuickTimer) -> Void
    let onStopTimer: (QuickTimer) -> Void
    let animatedValue: Int

  // Match the in-app running timer pause/play tint.
    private let timerOrange = Color(nsColor: .systemOrange)

    @State private var isHoveringLeft: Bool = false
    @State private var isHoveringRight: Bool = false

    var body: some View {
        let extra = extraCount > 0 ? " +\(extraCount)" : ""

    // Slightly larger ring (the previous one looked too small).
    // Keep in sync with ContentView.timerActivityLayout.
        let ringSize: CGFloat = layout.fontSize + 5
        let ringLineWidth: CGFloat = 2.2
    // Needle is a tiny rounded rectangle whose *inner end* is fixed at the center.
    // Its outer end rotates along the ring, like the reference image.
        let needleThickness: CGFloat = 2.49

        let rowsCount = max(1, timers.count)
        let expandedHeaderHeight: CGFloat = 0
        let expandedTopPadding: CGFloat = 5
        let expandedBottomPadding: CGFloat = 16
        let footerHeight: CGFloat = isExpanded
            ? (expandedTopPadding
               + expandedHeaderHeight
               + CGFloat(rowsCount) * expandedRowHeight
               + CGFloat(max(0, rowsCount - 1)) * expandedRowsSpacing
               + expandedBottomPadding)
            : 0

        let totalHeight = baseHeight + footerHeight
        let leftHoverWidth = isCompactMode ? 0 : (layout.leftWidth + layout.sidePadding)
    // In compact mode, the right side carries the ring (former left content).
        let rightHoverWidth = isCompactMode
            ? max(layout.leftWidth + layout.sidePadding + 18, 48)
            : max(layout.rightWidth + layout.sidePadding + 22, 64)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
        // LEFT SECTION: Timer ring (with native hover area)
                if !isCompactMode {
                    ZStack(alignment: .top) {
                        ZStack {
              // Track
                            Circle()
                                .stroke(Color(red: 0x5A / 255.0, green: 0x41 / 255.0, blue: 0x22 / 255.0), lineWidth: ringLineWidth)

              // Remaining progress (decreasing)
                            Circle()
                                .trim(from: 0, to: max(0, min(1, progressRemaining)))
                                .stroke(
                                    timerOrange.opacity(0.95),
                                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: progressRemaining)

                            GeometryReader { geo in
                                let r = min(geo.size.width, geo.size.height) / 2
                                let clamped = max(0, min(1, progressRemaining))
                // Circle trim is rotated by -90° above, so 0 starts at 12 o'clock.
                                let angle = -90 + (360 * clamped)

                // Keep the needle fully inside the ring stroke.
                                let pathRadius = r - ringLineWidth / 2
                                let inset: CGFloat = 1.2
                                let needleLength = max(2, pathRadius - needleThickness / 2 - inset)

                                RoundedRectangle(cornerRadius: needleThickness / 2, style: .continuous)
                                    .fill(timerOrange)
                                    .frame(width: needleLength, height: needleThickness)
                  // Fix a pivot point slightly *inside* the needle (not right at the extremity)
                  // to avoid the visual "sliding" effect.
                                    .modifier(TimerNeedlePivotModifier(length: needleLength, pivotFraction: 0.18, angle: angle))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    .animation(.linear(duration: 1), value: progressRemaining)
                            }
                        }
                        .frame(width: ringSize, height: ringSize)
                        .frame(width: layout.leftWidth, alignment: .leading)
                        .padding(.leading, layout.sidePadding)
                        .frame(height: baseHeight)
                        .allowsHitTesting(false)
                    }
                }

        // CENTER SECTION: Physical notch area (without hover)
                Rectangle()
                    .fill(.black)
                    .frame(width: notchWidth, height: totalHeight)

        // RIGHT SECTION: Countdown text (with native hover area)
                ZStack(alignment: .topTrailing) {
                    if isCompactMode {
                        ZStack {
                            Circle()
                                .stroke(Color(red: 0x5A / 255.0, green: 0x41 / 255.0, blue: 0x22 / 255.0), lineWidth: ringLineWidth)

                            Circle()
                                .trim(from: 0, to: max(0, min(1, progressRemaining)))
                                .stroke(
                                    timerOrange.opacity(0.95),
                                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: progressRemaining)

                            GeometryReader { geo in
                                let r = min(geo.size.width, geo.size.height) / 2
                                let clamped = max(0, min(1, progressRemaining))
                                let angle = -90 + (360 * clamped)
                                let pathRadius = r - ringLineWidth / 2
                                let inset: CGFloat = 1.2
                                let needleLength = max(2, pathRadius - needleThickness / 2 - inset)

                                RoundedRectangle(cornerRadius: needleThickness / 2, style: .continuous)
                                    .fill(timerOrange)
                                    .frame(width: needleLength, height: needleThickness)
                                    .modifier(TimerNeedlePivotModifier(length: needleLength, pivotFraction: 0.18, angle: angle))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    .animation(.linear(duration: 1), value: progressRemaining)
                            }
                        }
                        .frame(width: ringSize, height: ringSize)
                        .frame(width: layout.leftWidth, alignment: .trailing)
                        .padding(.trailing, layout.sidePadding)
                        .frame(height: baseHeight)
                        .allowsHitTesting(false)
                    } else {
                        AnimatedTimerDigitsText(
                            text: text + extra,
                            value: animatedValue,
                            color: timerOrange,
                            font: .system(size: layout.fontSize, weight: .semibold),
                            reservedText: "00:00 +9"
                        )
                            .frame(width: layout.rightWidth, alignment: .trailing)
                            .padding(.trailing, layout.sidePadding)
                            .frame(height: baseHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: baseHeight, alignment: .top)
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(!isExpanded)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(timers.enumerated()), id: \.element.id) { index, timer in
                        let isReadOnly = isTimerReadOnly(timer)
                        HStack(spacing: 0) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(isReadOnly ? Color.white.opacity(0.04) : Color.white.opacity(0.20))
                                    if isReadOnly {
                                        Circle()
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    }
                                    Image(systemName: "xmark")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(isReadOnly ? Color.white.opacity(0.20) : Color.white.opacity(0.96))
                                }
                                .frame(width: 40, height: 40)

                                ZStack {
                                    let isFinished = timer.didFinish || timer.remainingSeconds <= 0
                                    Circle().fill(isReadOnly ? Color.white.opacity(0.04) : timerOrange.opacity(0.28))
                                    if isReadOnly {
                                        Circle()
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    }
                                    Image(systemName: isFinished ? "arrow.clockwise" : (timer.isRunning ? "pause.fill" : "play.fill"))
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(isReadOnly ? Color.white.opacity(0.20) : timerOrange)
                                        .offset(x: isFinished ? 0 : (timer.isRunning ? 0 : 1.2))
                                }
                                .frame(width: 40, height: 40)
                            }
                            .frame(width: 84, alignment: .leading)

                            Color.clear.frame(width: expandedCenterGapWidth)

                            AnimatedTimerDigitsText(
                                text: timer.displayTime,
                                value: timer.remainingSeconds,
                                color: timerOrange,
                                font: .system(size: 42, weight: .regular),
                                reservedText: "00:00:00"
                            )
                                .minimumScaleFactor(0.7)
                                .frame(width: expandedTimeWidth, alignment: .trailing)
                        }
                        .padding(.horizontal, 1)
                        .frame(height: expandedRowHeight)

                        if index < timers.count - 1 {
                            Color.clear
                                .frame(height: expandedRowsSpacing)
                                .overlay(alignment: .center) {
                                    Rectangle()
                                        .fill(.white.opacity(0.14))
                                        .frame(height: 1)
                                        .padding(.horizontal, 10)
                                }
                        }
                    }
                }
                .padding(.top, expandedTopPadding)
                .frame(height: footerHeight, alignment: .top)
                .allowsHitTesting(false)
            }
        }
        .frame(height: totalHeight, alignment: .top)
        .contentShape(Rectangle())
        .overlay {
            TimerSidesHoverTrackingView(
                leftWidth: leftHoverWidth,
                notchWidth: notchWidth,
                rightWidth: rightHoverWidth,
                treatWholeAreaAsHoverTarget: isExpanded
            ) { hoveringSides in
                isHoveringLeft = hoveringSides
                isHoveringRight = hoveringSides
                onSidesHoverChanged(hoveringSides)
            }
            .frame(height: totalHeight)
        }
        .animation(NotchMotion.popupHover, value: isExpanded)
    }
}

private struct TimerExpandedRow: View {
    @ObservedObject var timer: QuickTimer
    let onToggle: () -> Void
    let onStop: () -> Void

    private let timerOrange = Color(nsColor: .systemOrange)
    private let controlSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(timerOrange.opacity(0.28))
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(timerOrange)
                    .offset(x: timer.isRunning ? 0 : 1.2)
            }
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
            .onTapGesture { onToggle() }

            ZStack {
                Circle().fill(Color.white.opacity(0.20))
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
            .onTapGesture { onStop() }

            Text("Minuteur")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(timerOrange.opacity(0.95))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(timer.displayTime)
                .font(.system(size: 52, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(timerOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.98))
        )
    }
}

private struct AnimatedTimerDigitsText: View {
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
