import SwiftUI
import AppKit
import CoreVideo
import QuartzCore

private func marqueeClockNow() -> CFTimeInterval {
    Date().timeIntervalSinceReferenceDate
}

final class MarqueeDisplayLinkClock: ObservableObject {
    static let shared = MarqueeDisplayLinkClock()

    @Published private(set) var now: CFTimeInterval = marqueeClockNow()

    private var displayLink: CVDisplayLink?
    private var activeConsumerCount: Int = 0
    private var lastPublishedTimestamp: CFTimeInterval = 0
    private let minimumPublishInterval: CFTimeInterval = 1.0 / 60.0

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
            let timestamp = marqueeClockNow()
            guard timestamp - clock.lastPublishedTimestamp >= clock.minimumPublishInterval else {
                return kCVReturnSuccess
            }
            clock.lastPublishedTimestamp = timestamp
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

    @Published private(set) var cycleAnchor: CFTimeInterval = marqueeClockNow()
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
        cycleAnchor = marqueeClockNow()
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
    @ObservedObject private var marqueeClock = MarqueeDisplayLinkClock.shared

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

    @State private var cycleStart: CFTimeInterval = marqueeClockNow()
    @State private var accumulatedPausedDuration: TimeInterval = 0
    @State private var pauseBeganAt: CFTimeInterval?
    @State private var participantID = UUID()
    @State private var textImage: NSImage?
    @State private var cachedTextWidth: CGFloat = 1
    @State private var cachedLineHeight: CGFloat = 1
    @State private var hasAcquiredClock = false
    @State private var frozenNow: CFTimeInterval?

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
        cachedTextWidth
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

    private var shouldUseSharedClock: Bool {
        needsScrolling && !isPaused
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
        if shouldUseSharedClock {
            if !hasAcquiredClock {
                MarqueeDisplayLinkClock.shared.acquire()
                hasAcquiredClock = true
            }
        } else if hasAcquiredClock {
            MarqueeDisplayLinkClock.shared.release()
            hasAcquiredClock = false
        }
    }

    private func rebuildTextImage() {
        let scale = max(1, displayScale)
        let font = resolvedNSFont
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
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
        cachedTextWidth = logicalSize.width
        cachedLineHeight = max(1, font.pointSize * 1.3)
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
        let displayNow = frozenNow ?? (needsScrolling ? marqueeClock.now : cycleStart)
        marqueeContent(now: displayNow)
        .background(backgroundColor)
        .frame(height: cachedLineHeight)
        .onAppear {
            rebuildTextImage()
            cycleStart = marqueeClockNow()
            accumulatedPausedDuration = 0
            let now = marqueeClockNow()
            pauseBeganAt = isPaused ? now : nil
            frozenNow = isPaused ? now : nil
            refreshSyncRegistration(restartCycle: false)
            updateClockSubscription()
        }
        .onChange(of: text) {
            rebuildTextImage()
            cycleStart = marqueeClockNow()
            accumulatedPausedDuration = 0
            let now = marqueeClockNow()
            pauseBeganAt = isPaused ? now : nil
            frozenNow = isPaused ? now : nil
            refreshSyncRegistration(restartCycle: true)
            updateClockSubscription()
        }
        .onChange(of: colorScheme) {
            rebuildTextImage()
        }
        .onChange(of: displayScale) {
            rebuildTextImage()
        }
        .onChange(of: frameWidth) {
            cycleStart = marqueeClockNow()
            accumulatedPausedDuration = 0
            let now = marqueeClockNow()
            pauseBeganAt = isPaused ? now : nil
            frozenNow = isPaused ? now : nil
            refreshSyncRegistration(restartCycle: true)
            updateClockSubscription()
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                if pauseBeganAt == nil {
                    let now = marqueeClock.now
                    pauseBeganAt = now
                    frozenNow = now
                }
            } else if let startedAt = pauseBeganAt {
                accumulatedPausedDuration += max(0, marqueeClockNow() - startedAt)
                pauseBeganAt = nil
                frozenNow = nil
            }
            updateClockSubscription()
        }
        .onChange(of: needsScrolling) {
            refreshSyncRegistration(restartCycle: true)
            updateClockSubscription()
        }
        .onChange(of: cycleDuration) {
            refreshSyncRegistration(restartCycle: false)
        }
        .onDisappear {
            if hasAcquiredClock {
                MarqueeDisplayLinkClock.shared.release()
                hasAcquiredClock = false
            }
            syncCoordinator?.remove(id: participantID)
        }
    }

    private func marqueeContent(now currentNow: CFTimeInterval) -> some View {
        let marqueeOffset = currentOffset(at: currentNow)
        let leftFadeCutoff = -(effectiveTextWidth - 2)
        let leftFadeWindow: CGFloat = 10
        let leftFadeRaw = (-marqueeOffset - 0.5) / leftFadeWindow
        let leftFadeRamp = max(0, min(1, leftFadeRaw))
        let leftFadeProgress = (marqueeOffset > leftFadeCutoff) ? leftFadeRamp : 0
        let effectiveFrameAlignment: Alignment = needsScrolling ? .leading : frameAlignment

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
            .offset(x: marqueeOffset)
        }
        .frame(width: frameWidth, alignment: effectiveFrameAlignment)
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
}
