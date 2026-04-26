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
/// This matches Atoll's lock icon style: a solid color fill masked by the Lottie animation.
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

/// Blur-friendly lock icon version.
///
/// On macOS, applying SwiftUI `.blur()` to a Lottie view can be unreliable.
/// Forcing offscreen rendering via `.drawingGroup()` can, depending on configuration, rasterize
/// the view into an opaque square. This view applies blur using a rendered snapshot
/// it as an image with CoreImage Gaussian blur, shown only during the very
/// first and last moments (driven by `blurRadius`).
public struct LockIconAnimatedBlurView: View {
    public let isLocked: Bool
    public let size: CGFloat
    public var iconColor: Color = .white
    public var blurRadius: CGFloat

    public init(isLocked: Bool, size: CGFloat, iconColor: Color = .white, blurRadius: CGFloat) {
        self.isLocked = isLocked
        self.size = size
        self.iconColor = iconColor
        self.blurRadius = blurRadius
    }

    public var body: some View {
        ZStack {
            LockIconAnimatedView(isLocked: isLocked, size: size, iconColor: iconColor)
                .opacity(sharpOpacity)

            LockIconAnimatedView(isLocked: isLocked, size: size, iconColor: iconColor)
                .padding(blurPadding)
                .blur(radius: blurRadius)
                .frame(width: size, height: size)
                .clipped()
                .opacity(blurOpacity)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }

    private var blurPadding: CGFloat {
        max(4, blurRadius * 1.8)
    }

    private var blurOpacity: Double {
        let maxR: CGFloat = 18
        return Double(max(0, min(1, blurRadius / maxR)))
    }

    private var sharpOpacity: Double {
        max(0, min(1, 1.0 - blurOpacity))
    }
}

struct LockIconProgressView: View {
    var progress: CGFloat
    var iconColor: Color = .white

    var body: some View {
        let nearLocked = progress >= 0.999

        if LockIconLottieView.isAvailable, !nearLocked {
            Rectangle()
                .fill(iconColor)
                .mask {
                    LockIconLottieView(progress: 1 - progress)
                        .scaleEffect(1.12)
                }
        } else {
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                Image(systemName: "lock.fill")
                    .font(.system(size: max(10, s * 0.78), weight: .semibold, design: .rounded))
                    .foregroundStyle(iconColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct LockIconLottieView: View {
    var progress: CGFloat

    private static let animation: LottieAnimation? = {
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
                    .currentProgress(Double(max(0.02, min(0.98, progress))))
                    .configuration(.init(renderingEngine: .mainThread))
            } else {
                Color.clear
            }
        }
    }
}
