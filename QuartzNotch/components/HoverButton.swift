
import SwiftUI

private enum SkipTriangleDirection {
    case forward
    case backward
}

enum HoverButtonAnimationEvent {
    case previousTrackSkip
    case nextTrackSkip
}

enum HoverButtonSymbolRotateDirection {
    case clockwise
    case counterClockwise
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

        let firstScale = max(0.0, 1.0 - (pow(pc, 1.55) * 0.55))
        let firstOpacity = max(0.0, 1.0 - (pc * 2.4))
        let disappearingFirstX = firstX - (spawnOffset * (1.85 * p))
        let secondToFirstX = secondX + (firstX - secondX) * p
        let newSecondX = secondX + spawnOffset * (1 - p)
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
    var tapRotationDegrees: Double = 0
    var tapSymbolRotateDirection: HoverButtonSymbolRotateDirection? = nil
    var externalAnimationTrigger: UUID? = nil
    var externalAnimationEvent: HoverButtonAnimationEvent? = nil
    var tapNudgeX: CGFloat = 0
    var contentTransitionID: AnyHashable? = nil
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;

    @State private var isHovering = false
    @State private var tapTransitionProgress: CGFloat = 0
    @State private var isTapTransitionActive = false
    @State private var symbolRotateTrigger = 0
    @State private var isPressPrimed = false

    var body: some View {
        let size = customSize ?? CGFloat(scale == .large ? 40 : 30)
        let slideDuration: Double = 0.66
        let slideAnimation: Animation = .interpolatingSpring(stiffness: 235, damping: 20)
        let isSkipIcon = (icon == "forward.fill" || icon == "backward.fill")
        let skipDirection: SkipTriangleDirection = (icon == "backward.fill") ? .forward : .backward
        let iconPointSize: CGFloat = customIconFontSize ?? (scale == .large ? 28 : 17)

        Button(action: {
            if animateOnTap {
                runTapAnimation(slideAnimation: slideAnimation, slideDuration: slideDuration)
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
                                        isAnimating: tapNudgeX != 0 && isTapTransitionActive
                                    )
                                    .rotationEffect(.degrees(tapTransitionProgress * tapRotationDegrees))
                                } else {
                                    symbolImage(pointSize: customIconFontSize != nil
                                                ? .system(size: customIconFontSize!)
                                                : (scale == .large ? .largeTitle : .body))
                                }
                            }
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard tapSymbolRotateDirection != nil else { return }
                    guard !isPressPrimed else { return }
                    isPressPrimed = true
                    symbolRotateTrigger += 1
                }
                .onEnded { _ in
                    isPressPrimed = false
                }
        )
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalAnimationTrigger) { _, newValue in
            guard newValue != nil else { return }
            runTapAnimation(slideAnimation: slideAnimation, slideDuration: slideDuration)
        }
        .onReceive(animationEventPublisher) { _ in
            guard externalAnimationEvent != nil else { return }
            runTapAnimation(slideAnimation: slideAnimation, slideDuration: slideDuration)
        }
    }

    private func runTapAnimation(slideAnimation: Animation, slideDuration: Double) {
        guard !isTapTransitionActive else { return }

        if tapNudgeX != 0 {
            isTapTransitionActive = true
            tapTransitionProgress = 0
            withAnimation(slideAnimation) {
                tapTransitionProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + slideDuration) {
                tapTransitionProgress = 0
                isTapTransitionActive = false
            }
        } else {
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

    private var animationEventPublisher: NotificationCenter.Publisher {
        switch externalAnimationEvent {
        case .previousTrackSkip:
            return NotificationCenter.default.publisher(for: .musicPreviousButtonAnimationTriggered)
        case .nextTrackSkip:
            return NotificationCenter.default.publisher(for: .musicNextButtonAnimationTriggered)
        case .none:
            return NotificationCenter.default.publisher(for: .hoverButtonAnimationNoop)
        }
    }

    @ViewBuilder
    private func symbolImage(pointSize: Font) -> some View {
        let base = Image(systemName: icon)
            .id(contentTransitionID)
            .foregroundColor(iconColor)
            .contentTransition(contentTransition)
            .rotationEffect(.degrees(tapTransitionProgress * tapRotationDegrees))
            .font(pointSize)

        if let direction = tapSymbolRotateDirection {
            if #available(macOS 15.0, *) {
                let rotateOptions = SymbolEffectOptions.nonRepeating.speed(3.2)
                switch direction {
                case .clockwise:
                    base.symbolEffect(.rotate.clockwise, options: rotateOptions, value: symbolRotateTrigger)
                case .counterClockwise:
                    base.symbolEffect(.rotate.counterClockwise, options: rotateOptions, value: symbolRotateTrigger)
                }
            } else {
                base
            }
        } else {
            base
        }
    }
}
