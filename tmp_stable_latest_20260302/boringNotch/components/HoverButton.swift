//
// HoverButton.swift
// boringNotch
//
// Created by Kraigo on 04.09.2024.
//

import SwiftUI

private enum SkipTriangleDirection {
    case forward
    case backward
}

private struct SkipTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct SkipDoubleTriangleGlyph: View {
    let color: Color
    let pointSize: CGFloat
    let direction: SkipTriangleDirection
    let progress: CGFloat
    let isAnimating: Bool

    private var triangleW: CGFloat { pointSize * 0.58 }
    private var triangleH: CGFloat { pointSize * 0.94 }
    private var triangleGap: CGFloat { 0 }

    var body: some View {
        let p = progress
        let pc = max(0, min(1, progress))
        let firstX = -(triangleW + triangleGap) * 0.5
        let secondX = (triangleW + triangleGap) * 0.5
        let spawnOffset = triangleW + triangleGap

        // Slower shrink curve (fade unchanged): starts gently, compresses later.
        let firstScale = max(0.0, 1.0 - (pow(pc, 1.55) * 0.55))
        // Make the disappearing glyph fade out much earlier so the fade itself is barely noticeable.
        let firstOpacity = max(0.0, 1.0 - (pc * 2.4))
        // Push the disappearing glyph much further so it exits cleanly without being overtaken.
        let disappearingFirstX = firstX - (spawnOffset * (1.85 * p))
        let secondToFirstX = secondX + (firstX - secondX) * p
        let newSecondX = secondX + spawnOffset * (1 - p)
        // No bounce: simple integrated scale evolution for the entering glyph.
        let newSecondScale: CGFloat = {
            let arriveT = max(0.0, min(1.0, pc / 0.82))
            return 0.90 + (0.10 * arriveT)
        }()
        let newSecondOpacity = min(1.0, pc * 1.35)

        Group {
            if direction == .forward {
                animatedGlyph(
                    firstX: firstX,
                    disappearingFirstX: disappearingFirstX,
                    secondX: secondX,
                    secondToFirstX: secondToFirstX,
                    newSecondX: newSecondX,
                    firstScale: firstScale,
                    firstOpacity: firstOpacity,
                    newSecondScale: newSecondScale,
                    newSecondOpacity: newSecondOpacity
                )
            } else {
                animatedGlyph(
                    firstX: firstX,
                    disappearingFirstX: disappearingFirstX,
                    secondX: secondX,
                    secondToFirstX: secondToFirstX,
                    newSecondX: newSecondX,
                    firstScale: firstScale,
                    firstOpacity: firstOpacity,
                    newSecondScale: newSecondScale,
                    newSecondOpacity: newSecondOpacity
                )
                .scaleEffect(x: -1, y: 1)
            }
        }
        .frame(width: pointSize * 1.18, height: pointSize)
        .compositingGroup()
    }

    @ViewBuilder
    private func animatedGlyph(
        firstX: CGFloat,
        disappearingFirstX: CGFloat,
        secondX: CGFloat,
        secondToFirstX: CGFloat,
        newSecondX: CGFloat,
        firstScale: CGFloat,
        firstOpacity: CGFloat,
        newSecondScale: CGFloat,
        newSecondOpacity: CGFloat
    ) -> some View {
        ZStack {
            if isAnimating {
                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: triangleW, height: triangleH)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: disappearingFirstX)
                    .scaleEffect(firstScale)
                    .opacity(firstOpacity)
                    .zIndex(3)

                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: triangleW, height: triangleH)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: secondToFirstX)
                    .zIndex(2)

                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: triangleW, height: triangleH)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: newSecondX)
                    .scaleEffect(newSecondScale)
                    .opacity(newSecondOpacity)
                    .zIndex(4)
            } else {
                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: triangleW, height: triangleH)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: firstX)

                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: triangleW, height: triangleH)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: secondX)
            }
        }
    }
}

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var customSize: CGFloat? = nil
    var customIconFontSize: CGFloat? = nil
    var animateOnTap: Bool = false
    var tapNudgeX: CGFloat = 0
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;
    
    @State private var isHovering = false
    @State private var tapTransitionProgress: CGFloat = 0
    @State private var isTapTransitionActive = false

    var body: some View {
        let size = customSize ?? CGFloat(scale == .large ? 40 : 30)
        let slideDuration: Double = 0.66
        let slideAnimation: Animation = .interpolatingSpring(stiffness: 235, damping: 20)
        let isSkipIcon = (icon == "forward.fill" || icon == "backward.fill")
        // Invert animation direction mapping to match requested behavior.
        let skipDirection: SkipTriangleDirection = (icon == "backward.fill") ? .forward : .backward
        let iconPointSize: CGFloat = customIconFontSize ?? (scale == .large ? 28 : 17)
        
        Button(action: {
            if animateOnTap {
                if tapNudgeX != 0 {
                    isTapTransitionActive = true
                    tapTransitionProgress = 0
                    withAnimation(slideAnimation) {
                        tapTransitionProgress = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + slideDuration) {
                        // Snap back to the idle single-icon state after the transition frame.
                        tapTransitionProgress = 0
                        isTapTransitionActive = false
                    }
                } else {
                    // Legacy tap animation for call sites that don't provide a slide direction.
                    isTapTransitionActive = true
                    tapTransitionProgress = 0
                    withAnimation(.easeOut(duration: 0.08)) {
                        tapTransitionProgress = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.interpolatingSpring(stiffness: 230, damping: 20)) {
                            tapTransitionProgress = 0
                        }
                        isTapTransitionActive = false
                    }
                }
            }
            action()
        }) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Group {
                                if isSkipIcon {
                                    SkipDoubleTriangleGlyph(
                                        color: iconColor,
                                        pointSize: iconPointSize,
                                        direction: skipDirection,
                                        progress: tapTransitionProgress,
                                        isAnimating: animateOnTap && tapNudgeX != 0 && isTapTransitionActive
                                    )
                                } else {
                                    Image(systemName: icon)
                                        .foregroundColor(iconColor)
                                        .contentTransition(contentTransition)
                                        .font(customIconFontSize != nil
                                              ? .system(size: customIconFontSize!)
                                              : (scale == .large ? .largeTitle : .body))
                                }
                            }
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
