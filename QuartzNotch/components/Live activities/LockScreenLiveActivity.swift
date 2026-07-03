
import SwiftUI
import AppKit

struct LockScreenLiveActivity: View {
  /// true = screen locked ; false = unlocked
    let isLocked: Bool
    let contentWidth: CGFloat
    let height: CGFloat

    private var iconSize: CGFloat { max(0, height - 12) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: contentWidth, height: height)

            LockIconAnimatedView(
                isLocked: isLocked,
                size: iconSize,
                iconColor: .white
            )
        }
        .frame(width: contentWidth, height: height)
    }
}
