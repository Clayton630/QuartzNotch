//
// LockScreenLiveActivity.swift
// boringNotch
//
// Created by Clayton on 22/01/2026.
//

import SwiftUI

struct LockScreenLiveActivity: View {
  /// true = screen locked ; false = unlocked
    let isLocked: Bool
    let contentWidth: CGFloat
    let height: CGFloat

    private var iconSize: CGFloat { max(0, height - 12) }

  // "Blur to focus" effect on appearance (lock) only.
    @State private var iconBlur: CGFloat = 0
    @State private var blurTask: Task<Void, Never>?
    private let blurMax: CGFloat = 18

    var body: some View {
        ZStack {
      // Keep exactly the same footprint as other closed activities
            Rectangle()
                .fill(Color.clear)
                .frame(width: contentWidth, height: height)

            LockIconAnimatedBlurView(
                isLocked: isLocked,
                size: iconSize,
                iconColor: .white,
                blurRadius: iconBlur
            )
        }
        .frame(width: contentWidth, height: height)
        .onAppear { applyBlurTransition(isLocked: isLocked, initial: true) }
        .onChange(of: isLocked) { locked in
            applyBlurTransition(isLocked: locked, initial: false)
        }
    }

    private func applyBlurTransition(isLocked: Bool, initial: Bool) {
        blurTask?.cancel()
        if isLocked {
      // Apparition (verrouillage) : flou -> net.
      // Important: the notch expands horizontally; during the first ~200 ms,
      // the icon is compressed and blur is almost invisible, so sharpening is delayed.
            iconBlur = blurMax
            let startDelayMs = initial ? 360 : 300

      // Progressive focus in multiple stages for better readability on a small icon.
            blurTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(startDelayMs))
                guard !Task.isCancelled else { return }

                withAnimation(NotchMotion.liveActivityIn) { iconBlur = 12 }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }

                withAnimation(NotchMotion.liveActivityIn) { iconBlur = 6 }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }

                withAnimation(NotchMotion.liveActivityOut) { iconBlur = 0 }
            }
        } else {
      // No blur on dismissal.
            iconBlur = 0
        }
    }
}
