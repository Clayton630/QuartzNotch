import AppKit
import SwiftUI
import Lottie

/// Progress-driven animator (0 = unlocked, 1 = locked).
@MainActor
final class LockIconAnimator: ObservableObject {
    @Published private(set) var progress: CGFloat

    private var animationTask: Task<Void, Never>?
    private let animationDuration: TimeInterval = 0.35
    private let animationSteps: Int = 48

    init(initiallyLocked: Bool) {
        progress = initiallyLocked ? 1.0 : 0.0
    }

    deinit {
        animationTask?.cancel()
    }

    func update(isLocked: Bool, animated: Bool = true) {
        let target: CGFloat = isLocked ? 1.0 : 0.0
        let clampedTarget = max(0.0, min(1.0, target))

        if !animated {
            animationTask?.cancel()
            progress = clampedTarget
            return
        }

        guard abs(progress - clampedTarget) > 0.0005 else {
            progress = clampedTarget
            return
        }

        animationTask?.cancel()

        let startProgress = progress
        let delta = clampedTarget - startProgress
        let stepDuration = animationDuration / Double(animationSteps)
        let stepNanoseconds = UInt64(stepDuration * 1_000_000_000)

        animationTask = Task { [weak self] in
            guard let self else { return }

            for step in 0...animationSteps {
                if Task.isCancelled { return }

                if step > 0 {
                    try? await Task.sleep(nanoseconds: stepNanoseconds)
                }

                let fraction = Double(step) / Double(animationSteps)
                let eased = easeOutCubic(fraction)
                progress = startProgress + CGFloat(eased) * delta
            }

            progress = clampedTarget
        }
    }

    private func easeOutCubic(_ t: Double) -> Double {
        let clamped = max(0.0, min(1.0, t))
        return 1.0 - pow(1.0 - clamped, 3)
    }
}

/// Drop-in view used by the lock/unlock overlay.
public struct LockIconAnimatedView: View {
    public let isLocked: Bool
    public let size: CGFloat
    public var iconColor: Color = .white

    @StateObject private var animator: LockIconAnimator

    public init(isLocked: Bool, size: CGFloat, iconColor: Color = .white) {
        self.isLocked = isLocked
        self.size = size
        self.iconColor = iconColor
        _animator = StateObject(wrappedValue: LockIconAnimator(initiallyLocked: isLocked))
    }

    public var body: some View {
        LockIconProgressView(progress: animator.progress, iconColor: iconColor)
            .frame(width: size, height: size, alignment: .center)
            .accessibilityLabel(isLocked ? "Screen locked" : "Screen unlocked")
            .onChange(of: isLocked) { newValue in
                animator.update(isLocked: newValue, animated: true)
            }
    }

}
struct LockIconProgressView: View {
    var progress: CGFloat
    var iconColor: Color = .white

    var body: some View {
        GeometryReader { geo in
            if LockIconLottieView.isAvailable {
                let lottieProgress = 1 - progress
                LottieLockViewport(size: geo.size) {
                    LockIconLottieView(progress: lottieProgress)
                        .colorMultiply(iconColor)
                    }
                    .offset(x: LottieLockGeometry.contentXCorrection + unlockDriftX)
                    .transition(.identity)
            } else {
                let s = min(geo.size.width, geo.size.height)
                Image(systemName: "lock.fill")
                    .font(.system(size: max(10, s * 0.78), weight: .semibold, design: .rounded))
                    .foregroundStyle(iconColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.identity)
            }
        }
    }

    private var unlockDriftX: CGFloat {
        let unlockedAmount = 1 - max(0, min(1, progress))
        let eased = unlockedAmount * unlockedAmount * (3 - 2 * unlockedAmount)
        return -2.0 * eased
    }
}

private enum LottieLockGeometry {
    static let lockedProgress: CGFloat = 0.02
    static let unlockedProgress: CGFloat = 0.98
    static let viewportScale: CGFloat = 1.6
    static let contentXCorrection: CGFloat = -2
}

private extension View {
    func lottieLockViewport() -> some View {
        scaleEffect(LottieLockGeometry.viewportScale)
    }
}

private struct LottieLockViewport<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        let side = min(size.width, size.height)

        content
            .frame(width: side, height: side, alignment: .center)
            .frame(width: size.width, height: size.height, alignment: .center)
            .lottieLockViewport()
    }
}

struct LockIconLottieView: View {
    var progress: CGFloat

    fileprivate static let animation: LottieAnimation? = {
        if let animation = LottieAnimation.named("lock_icon_animation") {
            return animation
        }

        if let url = Bundle.main.url(forResource: "lock_icon_animation", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return try? LottieAnimation.from(data: data)
        }

        print("[WARN] [LockIconLottieView] Missing lock_icon_animation.json – falling back to SF Symbols")
        return nil
    }()

    static var isAvailable: Bool {
        animation != nil
    }

    var body: some View {
        Group {
            if let animation = Self.animation {
                Lottie.LottieView(animation: animation)
                    .resizable()
                    .currentProgress(Double(max(LottieLockGeometry.lockedProgress, min(LottieLockGeometry.unlockedProgress, progress))))
                    .configuration(.init(renderingEngine: .mainThread))
            } else {
                Color.clear
            }
        }
    }
}
