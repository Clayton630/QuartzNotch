
import SwiftUI
import Defaults

struct TabSelectionView: View {
    @EnvironmentObject var vm: QuartzViewModel
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    let availableWidth: CGFloat

    private var selectedIndex: Int {
        availableViews.firstIndex(of: coordinator.currentView) ?? 0
    }

    private func mix(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private var availableViews: [NotchViews] {
        presentableNotchViewsInConfiguredOrder(currentView: coordinator.currentView)
    }

    private var compression: CGFloat {
        let baseDotSize: CGFloat = 6
        let baseHitPadding: CGFloat = 4
        let baseSpacing: CGFloat = 1
        let baseHInset: CGFloat = 6

        let compactDotSize: CGFloat = 5.2
        let compactHitPadding: CGFloat = 3
        let compactSpacing: CGFloat = 0.5
        let compactHInset: CGFloat = 4

        let baseFootprint = baseDotSize + (baseHitPadding * 2)
        let compactFootprint = compactDotSize + (compactHitPadding * 2)

        let baseWidth =
            CGFloat(availableViews.count) * baseFootprint
            + CGFloat(max(0, availableViews.count - 1)) * baseSpacing
            + (baseHInset * 2)

        let compactWidth =
            CGFloat(availableViews.count) * compactFootprint
            + CGFloat(max(0, availableViews.count - 1)) * compactSpacing
            + (compactHInset * 2)
        let clampedWidth = max(52, availableWidth)

        guard baseWidth > clampedWidth else { return 0 }
        guard baseWidth > compactWidth else { return 1 }
        return min(1, max(0, (baseWidth - clampedWidth) / (baseWidth - compactWidth)))
    }

    private var dotSize: CGFloat {
        mix(6, 5.2, compression)
    }

    private var hitPadding: CGFloat {
        mix(4, 3, compression)
    }

    private var unifiedSpacing: CGFloat {
        mix(1, 0.5, compression)
    }

    private var pillHInset: CGFloat {
        mix(6, 4, compression)
    }

    private var pillVInset: CGFloat {
        mix(3, 2.5, compression)
    }

    private var fitScale: CGFloat {
        let dotFootprint = dotSize + (hitPadding * 2)
        let estimatedPillWidth =
            CGFloat(availableViews.count) * dotFootprint
            + CGFloat(max(0, availableViews.count - 1)) * unifiedSpacing
            + (pillHInset * 2)

        let clampedWidth = max(52, availableWidth)
        return min(1, max(0.8, clampedWidth / max(estimatedPillWidth, 1)))
    }

    var body: some View {
        let baseFill = Color(nsColor: .secondarySystemFill)
        let unifiedBaseOpacity: Double = 0.985
        let unifiedDoubleFillOpacity: Double = 0.24

        HStack(spacing: unifiedSpacing) {
            ForEach(Array(availableViews.enumerated()), id: \.offset) { idx, view in
                dot(
                    index: idx,
                    view: view,
                    accessibility: view.accessibilityTitle
                )
            }
        }
        .padding(.horizontal, pillHInset)
        .padding(.vertical, pillVInset)
        .background(
            Capsule()
                .fill(baseFill)
                .overlay {
                    Capsule()
                        .fill(baseFill)
                        .opacity(unifiedDoubleFillOpacity)
                }
                .opacity(unifiedBaseOpacity)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.025), lineWidth: 1)
                }
                .allowsHitTesting(false)
        )
        .fixedSize(horizontal: true, vertical: false)
        .scaleEffect(fitScale, anchor: .leading)
        .contentShape(Rectangle())
    }

  // MARK: - Components

    private func dot(index: Int, view: NotchViews, accessibility: String) -> some View {
        Button {
            withAnimation(.smooth) {
                coordinator.currentView = view
            }
        } label: {
            Circle()
                .fill(index == selectedIndex ? .white : .gray.opacity(0.45))
                .frame(width: dotSize, height: dotSize)
                .padding(hitPadding)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
    }
}

#Preview {
    TabSelectionView(availableWidth: 120)
        .environmentObject(QuartzViewModel())
}
