import SwiftUI
import AppKit
import CoreVideo
import QuartzCore

final class MarqueeDisplayLinkClock: ObservableObject {
    static let shared = MarqueeDisplayLinkClock()

    @Published private(set) var now: CFTimeInterval = CACurrentMediaTime()

    private var displayLink: CVDisplayLink?
    private var activeConsumerCount: Int = 0

    private init() {
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let link else {
            return
        }

        displayLink = link

        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnSuccess }
            let unmanaged = Unmanaged<MarqueeDisplayLinkClock>.fromOpaque(userInfo)
            let clock = unmanaged.takeUnretainedValue()
            let timestamp = CACurrentMediaTime()
            DispatchQueue.main.async {
                guard clock.activeConsumerCount > 0 else { return }
                clock.now = timestamp
            }
            return kCVReturnSuccess
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    func acquire() {
        activeConsumerCount += 1
        if activeConsumerCount == 1, let displayLink {
            CVDisplayLinkStart(displayLink)
        }
    }

    func release() {
        activeConsumerCount = max(0, activeConsumerCount - 1)
        if activeConsumerCount == 0, let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }

    deinit {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}

final class MarqueeSyncCoordinator: ObservableObject {
    struct Entry {
        var needsScrolling: Bool
        var cycleDuration: Double
    }

    @Published private(set) var cycleAnchor: CFTimeInterval = CACurrentMediaTime()
    @Published private(set) var sharedCycleDuration: Double = 0

    private var entries: [UUID: Entry] = [:]

    var isSyncActive: Bool {
        entries.values.filter(\.needsScrolling).count >= 2
    }

    func update(id: UUID, needsScrolling: Bool, cycleDuration: Double) {
        entries[id] = Entry(needsScrolling: needsScrolling, cycleDuration: cycleDuration)
        recalculateSharedCycleDuration()
    }

    func remove(id: UUID) {
        entries.removeValue(forKey: id)
        recalculateSharedCycleDuration()
    }

    func restartCycle() {
        cycleAnchor = CACurrentMediaTime()
    }

    private func recalculateSharedCycleDuration() {
        let scrollingEntries = entries.values.filter(\.needsScrolling)
        sharedCycleDuration = scrollingEntries.count >= 2
            ? scrollingEntries.map(\.cycleDuration).max() ?? 0
            : 0
    }
}

struct MarqueeText: View {
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var displayLinkClock = MarqueeDisplayLinkClock.shared

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

    let startPause: Double       // Pause before the first scroll.
    let loopPause: Double        // Pause at each return to the start.
    let useEdgeFade: Bool
    let syncCoordinator: MarqueeSyncCoordinator?
    let frameAlignment: Alignment

    @State private var cycleStart: CFTimeInterval = CACurrentMediaTime()
    @State private var accumulatedPausedDuration: TimeInterval = 0
    @State private var pauseBeganAt: CFTimeInterval?
    @State private var participantID = UUID()
    @State private var textImage: NSImage?
    @State private var isClockAcquired = false

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
        syncCoordinator: MarqueeSyncCoordinator? = nil,
        frameAlignment: Alignment = .leading,
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
        self.syncCoordinator = syncCoordinator
        self.frameAlignment = frameAlignment
        self.measuredPointSize = measuredPointSize
        self.measuredWeight = measuredWeight
        self.isPaused = isPaused
    }

  // MARK: - Text Measurement (AppKit, reliable)
    private var resolvedNSFont: NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: nsFont)
        return NSFont.systemFont(ofSize: measuredPointSize ?? preferred.pointSize, weight: measuredWeight)
    }

    private var measuredTextWidth: CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: resolvedNSFont]).width
        return ceil(width)
    }

    private var effectiveTextWidth: CGFloat {
        measuredTextWidth
    }

    private var needsScrolling: Bool {
        effectiveTextWidth > frameWidth
    }

    private var animationDuration: Double {
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

    private var activeCycleStart: CFTimeInterval {
        if let syncCoordinator, syncCoordinator.isSyncActive {
            return syncCoordinator.cycleAnchor
        }
        return cycleStart
    }

    private var activeCycleDuration: Double {
        if let syncCoordinator,
           syncCoordinator.isSyncActive,
           syncCoordinator.sharedCycleDuration > 0 {
            return syncCoordinator.sharedCycleDuration
        }
        return cycleDuration
    }

    private func currentOffset(at now: CFTimeInterval) -> CGFloat {
        guard needsScrolling else { return 0 }
        let activePause = pauseBeganAt.map { max(0, now - $0) } ?? 0
        let elapsed = max(0, now - activeCycleStart - accumulatedPausedDuration - activePause)
        let cycleT = elapsed.truncatingRemainder(dividingBy: max(0.001, activeCycleDuration))

        if cycleT < leadingPauseDuration { return 0 }
        let t = (cycleT - leadingPauseDuration) / max(0.001, animationDuration)
        let clamped = CGFloat(max(0, min(1, t)))
        return -travelDistance * clamped
    }

    private func refreshSyncRegistration(restartCycle: Bool) {
        syncCoordinator?.update(
            id: participantID,
            needsScrolling: needsScrolling,
            cycleDuration: cycleDuration
        )
        if restartCycle {
            syncCoordinator?.restartCycle()
        }
    }

    private func updateClockSubscription() {
        if needsScrolling {
            if !isClockAcquired {
                displayLinkClock.acquire()
                isClockAcquired = true
            }
        } else if isClockAcquired {
            displayLinkClock.release()
            isClockAcquired = false
        }
    }

    private func rebuildTextImage() {
        let scale = max(1, displayScale)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: resolvedNSFont,
                .foregroundColor: NSColor(textColor)
            ]
        )
        var bounds = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral
        bounds.origin = .zero

        let logicalSize = NSSize(
            width: max(1, ceil(bounds.width)),
            height: max(1, ceil(bounds.height))
        )
        let pixelWidth = max(1, Int(ceil(logicalSize.width * scale)))
        let pixelHeight = max(1, Int(ceil(logicalSize.height * scale)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            textImage = nil
            return
        }

        bitmap.size = logicalSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            textImage = nil
            return
        }

        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(true)
        context.cgContext.setAllowsAntialiasing(true)
        context.cgContext.setShouldSmoothFonts(true)

        attributed.draw(at: NSPoint.zero)

        let image = NSImage(size: logicalSize)
        image.addRepresentation(bitmap)
        textImage = image
    }

  // MARK: - View
    var body: some View {
        let currentNow = needsScrolling ? displayLinkClock.now : cycleStart
        let marqueeOffset = currentOffset(at: currentNow)
        let leftFadeCutoff = -(effectiveTextWidth - 2)
        let leftFadeWindow: CGFloat = 10
        let leftFadeRaw = (-marqueeOffset - 0.5) / leftFadeWindow
        let leftFadeRamp = max(0, min(1, leftFadeRaw))
        let leftFadeProgress = (marqueeOffset > leftFadeCutoff) ? leftFadeRamp : 0
        return ZStack(alignment: .leading) {
            HStack(spacing: spacing) {
                if let textImage {
                    Image(nsImage: textImage)
                        .interpolation(.high)
                        .antialiased(true)
                } else {
                    Text(text)
                }

                if needsScrolling {
                    if let textImage {
                        Image(nsImage: textImage)
                            .interpolation(.high)
                            .antialiased(true)
                    } else {
                        Text(text)
                    }
                }
            }
            .font(font)
            .foregroundColor(textColor)
            .fixedSize(horizontal: true, vertical: false)
            .compositingGroup()
            .offset(x: marqueeOffset)
        }
        .frame(width: frameWidth, alignment: frameAlignment)
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
        .background(backgroundColor)
        .frame(height: NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
        .onAppear {
            rebuildTextImage()
            cycleStart = CACurrentMediaTime()
            accumulatedPausedDuration = 0
            pauseBeganAt = isPaused ? CACurrentMediaTime() : nil
            refreshSyncRegistration(restartCycle: false)
            updateClockSubscription()
        }
        .onChange(of: text) {
            rebuildTextImage()
            cycleStart = CACurrentMediaTime()
            accumulatedPausedDuration = 0
            pauseBeganAt = isPaused ? CACurrentMediaTime() : nil
            refreshSyncRegistration(restartCycle: true)
        }
        .onChange(of: colorScheme) {
            rebuildTextImage()
        }
        .onChange(of: displayScale) {
            rebuildTextImage()
        }
        .onChange(of: frameWidth) {
            cycleStart = CACurrentMediaTime()
            accumulatedPausedDuration = 0
            pauseBeganAt = isPaused ? CACurrentMediaTime() : nil
            refreshSyncRegistration(restartCycle: true)
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                if pauseBeganAt == nil {
                    pauseBeganAt = CACurrentMediaTime()
                }
            } else if let startedAt = pauseBeganAt {
                accumulatedPausedDuration += max(0, CACurrentMediaTime() - startedAt)
                pauseBeganAt = nil
            }
        }
        .onChange(of: needsScrolling) {
            refreshSyncRegistration(restartCycle: true)
            updateClockSubscription()
        }
        .onChange(of: cycleDuration) {
            refreshSyncRegistration(restartCycle: false)
        }
        .onDisappear {
            syncCoordinator?.remove(id: participantID)
            if isClockAcquired {
                displayLinkClock.release()
                isClockAcquired = false
            }
        }
    }
}
