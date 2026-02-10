import SwiftUI
import AppKit

struct MarqueeText: View {
    @Binding var text: String

    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    let spacing: CGFloat

  // Pauses
    let startPause: Double       // Pause before the first scroll.
    let loopPause: Double        // Pause at each return to the start.

    @State private var offset: CGFloat = 0
    @State private var runID = UUID()
  /// Changing this forces SwiftUI to drop the previous subtree, which effectively
  /// cancels any in-flight implicit animations on `offset`.
    @State private var contentID = UUID()

    init(
        _ text: Binding<String>,
        font: Font = .body,
        nsFont: NSFont.TextStyle = .body,
        textColor: Color = .primary,
        backgroundColor: Color = .clear,
        minDuration: Double = 1.2,
        frameWidth: CGFloat = 200,
        spacing: CGFloat = 24,
        startPause: Double = 0.7,
        loopPause: Double = 1.0
    ) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
        self.spacing = spacing
        self.startPause = startPause
        self.loopPause = loopPause
    }

  // MARK: - Text Measurement (AppKit, reliable)
    private var measuredTextWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: nsFont)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width)
    }

    private var needsScrolling: Bool {
        measuredTextWidth > frameWidth
    }

    private var animationDuration: Double {
    // Speed around 30 px/s, with a minimum duration.
        max(Double(measuredTextWidth / 34.0), minDuration)
    }

    private var travelDistance: CGFloat {
        measuredTextWidth + spacing
    }

    private func resetAndRestart() {
    // Instant reset to 0, then start a new loop via runID.
    // Also rebuild the subtree to prevent a previously-started animation from
    // continuing to drive `offset` after a track change.
        withAnimation(.none) {
            offset = 0
        }
        contentID = UUID()
        runID = UUID()
    }

    private func ns(_ seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

  // MARK: - View
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: spacing) {
                Text(text)
                if needsScrolling {
                    Text(text)
                }
            }
            .font(font)
            .foregroundColor(textColor)
            .fixedSize(horizontal: true, vertical: false)
      // When scrolling is not needed, hard-clamp to 0 so an old animation
      // cannot leave the text off-screen for a moment.
            .offset(x: needsScrolling ? offset : 0)
            .id(contentID)
        }
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .background(backgroundColor)
        .frame(height: NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
        .onAppear { resetAndRestart() }
        .onChange(of: text) {
            resetAndRestart()
        }
        .onChange(of: frameWidth) {
            resetAndRestart()
        }
        .task(id: runID) {
      // Controlled loop with pauses
            guard needsScrolling else {
                await MainActor.run {
                    withAnimation(.none) { offset = 0 }
                    contentID = UUID()
                }
                return
            }

      // Startup pause
            try? await Task.sleep(nanoseconds: ns(startPause))
            if Task.isCancelled { return }
      // The text or width may have changed during the pause.
            guard needsScrolling else {
                await MainActor.run {
                    withAnimation(.none) { offset = 0 }
                    contentID = UUID()
                }
                return
            }

            while !Task.isCancelled {
        // Re-check each loop iteration: a track change can make scrolling unnecessary.
                if !needsScrolling {
                    await MainActor.run {
                        withAnimation(.none) { offset = 0 }
                        contentID = UUID()
                    }
                    break
                }
        // 1) Scroll to the left.
                await MainActor.run {
                    withAnimation(.linear(duration: animationDuration)) {
                        offset = -travelDistance
                    }
                }

        // Wait for animation to complete.
                try? await Task.sleep(nanoseconds: ns(animationDuration))
                if Task.isCancelled { break }

        // 2) Pause en fin de cycle
                try? await Task.sleep(nanoseconds: ns(loopPause))
                if Task.isCancelled { break }

        // 3) Instant reset at the beginning (without animation)
                await MainActor.run {
                    withAnimation(.none) {
                        offset = 0
                    }
                }

        // petite respiration (optionnelle) avant de repartir
        // (keep it very short to avoid a flash)
                try? await Task.sleep(nanoseconds: ns(0.05))
            }
        }
    }
}
