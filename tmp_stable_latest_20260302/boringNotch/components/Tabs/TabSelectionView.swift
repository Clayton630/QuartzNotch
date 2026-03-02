//
// TabSelectionView.swift
// boringNotch
//

import SwiftUI
import Defaults

struct TabSelectionView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.pageHomeEnabled) private var pageHomeEnabled
    @Default(.pageShelfEnabled) private var pageShelfEnabled

@Default(.pageThirdEnabled) private var pageThirdEnabled
    private var selectedIndex: Int {
        availableViews.firstIndex(of: coordinator.currentView) ?? 0
    }

    private var availableViews: [NotchViews] {
        var v: [NotchViews] = []
        if pageHomeEnabled { v.append(.home) }
        if pageShelfEnabled { v.append(.shelf) }
        if pageThirdEnabled { v.append(.third) }
    // Safety: never return empty.
        return v.isEmpty ? [.home] : v
    }

  // MARK: - Unified metrics (IMPORTANT)
    private let dotSize: CGFloat = 6

  // Tighten spacing inside the pill
    private let hitPadding: CGFloat = 4
    private let unifiedSpacing: CGFloat = 1

  // Tighten the pill around its content
    private let pillHInset: CGFloat = 6
    private let pillVInset: CGFloat = 3

    var body: some View {
        let baseFill = Color(nsColor: .secondarySystemFill)
        let unifiedBaseOpacity: Double = 0.985
        let unifiedDoubleFillOpacity: Double = 0.24

        HStack(spacing: unifiedSpacing) {
            ForEach(Array(availableViews.enumerated()), id: \.offset) { idx, view in
                dot(
                    index: idx,
                    view: view,
                    accessibility: {
                        switch view {
                        case .home: return "Home"
                        case .shelf: return "Shelf"
                        case .third: return "Third"
                        }
                    }()
                )
            }
        }
        .padding(.horizontal, pillHInset)
        .padding(.vertical, pillVInset)
        .background(
            Capsule()
                .fill(baseFill)
        // Unified background opacity (match NotchCardBackground).
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
        .contentShape(Rectangle())
    }

  // MARK: - Components

    private func dot(index: Int, view: NotchViews, accessibility: String) -> some View {
        Circle()
            .fill(index == selectedIndex ? .white : .gray.opacity(0.45))
            .frame(width: dotSize, height: dotSize)
            .padding(hitPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth) {
                    coordinator.currentView = view
                }
            }
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
    }
}

#Preview {
    TabSelectionView()
        .environmentObject(BoringViewModel())
}
