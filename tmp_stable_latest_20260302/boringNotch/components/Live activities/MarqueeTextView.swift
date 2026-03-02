import SwiftUI
import AppKit

private struct MarqueeRenderedTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MarqueeText: View {
    @Binding var text: String

    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    let spacing: CGFloat
    let measuredPointSize: CGFloat?
    let measuredWeight: NSFont.Weight
    let isPaused: Bool

  // Pauses
    let startPause: Double       // Pause before the first scroll.
    let loopPause: Double        // Pause at each return to the start.
    let useEdgeFade: Bool

    @State private var cycleStart = Date()
    @State private var renderedTextWidth: CGFloat = 0
    @State private var accumulatedPausedDuration: TimeInterval = 0
    @State private var pauseBeganAt: Date?

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
        loopPause: Double = 1.0,
        useEdgeFade: Bool = false,
        measuredPointSize: CGFloat? = nil,
        measuredWeight: NSFont.Weight = .regular,
        isPaused: Bool = false
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
        self.useEdgeFade = useEdgeFade
        self.measuredPointSize = measuredPointSize
        self.measuredWeight = measuredWeight
        self.isPaused = isPaused
    }

  // MARK: - Text Measurement (AppKit, reliable)
    private var measuredTextWidth: CGFloat {
        let preferred = NSFont.preferredFont(forTextStyle: nsFont)
        let font = NSFont.systemFont(ofSize: measuredPointSize ?? preferred.pointSize, weight: measuredWeight)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width)
    }

    private var effectiveTextWidth: CGFloat {
        let rendered = renderedTextWidth > 0 ? ceil(renderedTextWidth) : 0
        return max(measuredTextWidth, rendered)
    }

    private var needsScrolling: Bool {
        effectiveTextWidth > frameWidth
    }

    private var animationDuration: Double {
    // Speed around 30 px/s, with a minimum duration.
        max(Double(effectiveTextWidth / 34.0), minDuration)
    }

    private var travelDistance: CGFloat {
        (effectiveTextWidth + spacing).rounded(.toNearestOrAwayFromZero)
    }

    private var leadingPauseDuration: Double {
        startPause + loopPause
    }

    private var cycleDuration: Double {
        leadingPauseDuration + animationDuration
    }

    private func currentOffset(at date: Date) -> CGFloat {
        guard needsScrolling else { return 0 }
        let activePause = pauseBeganAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        let elapsed = max(0, date.timeIntervalSince(cycleStart) - accumulatedPausedDuration - activePause)
        let cycleT = elapsed.truncatingRemainder(dividingBy: max(0.001, cycleDuration))

        if cycleT < leadingPauseDuration { return 0 }
        let t = (cycleT - leadingPauseDuration) / max(0.001, animationDuration)
        let clamped = CGFloat(max(0, min(1, t)))
        return -travelDistance * clamped
    }

  // MARK: - View
    var body: some View {
        TimelineView(.periodic(from: .now, by: needsScrolling ? (1.0 / 60.0) : 0.25)) { timeline in
            let marqueeOffset = currentOffset(at: timeline.date)
            // Disable left fade only when the first label is already out of view,
            // so the fade switch happens in the inter-text gap instead of on glyphs.
            let leftFadeCutoff = -(effectiveTextWidth - 4)
            let leftFadeWindow: CGFloat = 10
            let leftFadeRaw = (-marqueeOffset - 0.5) / leftFadeWindow
            let leftFadeRamp = max(0, min(1, leftFadeRaw))
            let leftFadeProgress = (marqueeOffset > leftFadeCutoff) ? leftFadeRamp : 0
            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    Text(text)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: MarqueeRenderedTextWidthKey.self,
                                    value: geo.size.width
                                )
                            }
                        )
                    if needsScrolling {
                        Text(text)
                    }
                }
                .font(font)
                .foregroundColor(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: marqueeOffset)
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
            .mask {
                if useEdgeFade && needsScrolling {
                    GeometryReader { geo in
                        let fadeWidth = max(6, min(12, geo.size.width * 0.08))
                        HStack(spacing: 0) {
                            ZStack {
                                Rectangle()
                                    .fill(Color.white)
                                    .opacity(1 - leftFadeProgress)

                                LinearGradient(
                                    colors: [.clear, .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .opacity(leftFadeProgress)
                            }
                            .frame(width: fadeWidth)

                            Rectangle().fill(Color.white)

                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: fadeWidth)
                        }
                    }
                } else {
                    Rectangle().fill(Color.white)
                }
            }
        }
        .background(backgroundColor)
        .frame(height: NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
        .onAppear {
            cycleStart = Date()
            accumulatedPausedDuration = 0
            pauseBeganAt = isPaused ? Date() : nil
        }
        .onChange(of: text) {
            cycleStart = Date()
            accumulatedPausedDuration = 0
            pauseBeganAt = isPaused ? Date() : nil
        }
        .onChange(of: frameWidth) {
            cycleStart = Date()
            accumulatedPausedDuration = 0
            pauseBeganAt = isPaused ? Date() : nil
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                if pauseBeganAt == nil {
                    pauseBeganAt = Date()
                }
            } else if let startedAt = pauseBeganAt {
                accumulatedPausedDuration += max(0, Date().timeIntervalSince(startedAt))
                pauseBeganAt = nil
            }
        }
        .onPreferenceChange(MarqueeRenderedTextWidthKey.self) { width in
            guard width > 0 else { return }
            if abs(width - renderedTextWidth) > 0.5 {
                renderedTextWidth = width
                cycleStart = Date()
                accumulatedPausedDuration = 0
                pauseBeganAt = isPaused ? Date() : nil
            }
        }
    }
}
