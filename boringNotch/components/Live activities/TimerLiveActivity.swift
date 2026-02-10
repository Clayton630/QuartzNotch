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
    let onSidesHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = HoverDetectorView()
        v.leftWidth = leftWidth
        v.notchWidth = notchWidth
        v.rightWidth = rightWidth
        v.onSidesHoverChanged = onSidesHoverChanged
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? HoverDetectorView else { return }
        v.leftWidth = leftWidth
        v.notchWidth = notchWidth
        v.rightWidth = rightWidth
        v.onSidesHoverChanged = onSidesHoverChanged
    }

    final class HoverDetectorView: NSView {
        var leftWidth: CGFloat = 0
        var notchWidth: CGFloat = 0
        var rightWidth: CGFloat = 0
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

        private func updateHoverState(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
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
    let layout: Layout
    let notchWidth: CGFloat
    let baseHeight: CGFloat
    let isCompactMode: Bool

  /// Expanded (hover on left/right segments only). The physical notch segment stays passive so classic notch hover works.
    let isExpanded: Bool
  /// Called when the pointer enters/leaves either visible side segment (left ring or right text).
    let onSidesHoverChanged: (Bool) -> Void

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

        let footerHeight: CGFloat = 40
        
    // Compute total height used by hover zones.
        let totalHeight = baseHeight + (isExpanded ? footerHeight : 0)
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
                        Text(text + extra)
                            .font(.system(size: layout.fontSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(timerOrange)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: layout.rightWidth, alignment: .trailing)
                            .padding(.trailing, layout.sidePadding)
                            .frame(height: baseHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: baseHeight, alignment: .top)
            .overlay {
                TimerSidesHoverTrackingView(
                    leftWidth: leftHoverWidth,
                    notchWidth: notchWidth,
                    rightWidth: rightHoverWidth
                ) { hoveringSides in
                    isHoveringLeft = hoveringSides
                    isHoveringRight = hoveringSides
                    onSidesHoverChanged(hoveringSides)
                }
                .frame(height: totalHeight)
            }

            if isExpanded {
                VStack(spacing: 2) {
                    Text("Timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.9))

                    Text(text + extra)
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(timerOrange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(height: totalHeight, alignment: .top)
        .animation(NotchMotion.popupHover, value: isExpanded)
    }
}
