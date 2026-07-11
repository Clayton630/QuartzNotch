import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

@MainActor
final class MarketingPreviewWindowController {
    static let shared = MarketingPreviewWindowController()

    private var windowController: NSWindowController?
    private let viewModel = QuartzViewModel()

    private init() {}

    func showWindow() {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = MarketingPreviewRoot(viewModel: viewModel)
        let hostingView = MarketingPreviewHostingView(rootView: content)
        hostingView.safeAreaRegions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1640, height: 920),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "QuartzNotch Marketing Preview"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        prepareDefaultPreviewState()
    }

    private func prepareDefaultPreviewState() {
        viewModel.configureForMarketingPreview()
        QuartzViewCoordinator.shared.currentView = .home
        if viewModel.notchState != .open {
            viewModel.open()
        }
    }
}

private final class MarketingPreviewHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyHighResolutionRendering()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyHighResolutionRendering()
    }

    override func layout() {
        super.layout()
        applyHighResolutionRendering()
    }

    private func applyHighResolutionRendering() {
        wantsLayer = true

        let screenScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let targetScale = max(screenScale * cinemaModeScale, screenScale)
        applyContentsScale(targetScale, to: layer)
    }

    private func applyContentsScale(_ scale: CGFloat, to layer: CALayer?) {
        guard let layer else { return }
        layer.contentsScale = scale
        layer.rasterizationScale = scale
        layer.sublayers?.forEach { applyContentsScale(scale, to: $0) }
    }
}

@MainActor
private final class MarketingPreviewCaptureController: ObservableObject {
    @Published var isRecording = false
    @Published var statusText: String?

    private var recordingSession: AnyObject?
    private var stopRecordingAction: (() -> Void)?

    func captureScreenshot(of window: NSWindow?) {
        guard let contentView = window?.contentView else {
            statusText = "No preview window"
            return
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        let bounds = contentView.bounds
        let scale = max((window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) * cinemaModeScale, 2)
        let pixelsWide = max(1, Int((bounds.width * scale).rounded(.toNearestOrAwayFromZero)))
        let pixelsHigh = max(1, Int((bounds.height * scale).rounded(.toNearestOrAwayFromZero)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            statusText = "Capture failed"
            return
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            statusText = "PNG export failed"
            return
        }

        do {
            let url = try outputURL(extension: "png")
            try pngData.write(to: url, options: .atomic)
            statusText = "Saved \(url.lastPathComponent)"
        } catch {
            statusText = "Capture failed: \(error.localizedDescription)"
        }
    }

    func toggleRecording(of window: NSWindow?) {
        if isRecording {
            stopRecordingAction?()
            return
        }

        guard #available(macOS 13.0, *) else {
            statusText = "Screen recording requires macOS 13+"
            return
        }

        guard let window else {
            statusText = "No preview window"
            return
        }

        Task {
            await startRecording(window: window)
        }
    }

    private func outputURL(extension pathExtension: String) throws -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let filename = "QuartzNotch-Marketing-Preview-\(formatter.string(from: Date())).\(pathExtension)"
        return desktop.appendingPathComponent(filename, isDirectory: false)
    }

    @available(macOS 13.0, *)
    private func startRecording(window: NSWindow) async {
        do {
            let url = try outputURL(extension: "mp4")
            let backingScale = max(window.backingScaleFactor, 1)
            let captureWidth = max(1, Int(window.frame.width * backingScale))
            let captureHeight = max(1, Int(window.frame.height * backingScale))
            let session = try await MarketingPreviewRecordingSession.start(
                windowID: CGWindowID(window.windowNumber),
                captureWidth: captureWidth,
                captureHeight: captureHeight,
                outputURL: url,
                onStarted: { [weak self] in
                    self?.isRecording = true
                    self?.statusText = "Recording..."
                },
                onFinished: { [weak self] result in
                    self?.isRecording = false
                    self?.recordingSession = nil
                    self?.stopRecordingAction = nil

                    switch result {
                    case .success(let url):
                        self?.statusText = "Saved \(url.lastPathComponent)"
                    case .failure(let error):
                        self?.statusText = "Recording failed: \(error.localizedDescription)"
                    }
                }
            )

            recordingSession = session
            stopRecordingAction = { [weak session] in
                Task { @MainActor in
                    await session?.stop()
                }
            }
        } catch {
            isRecording = false
            recordingSession = nil
            stopRecordingAction = nil
            statusText = "Recording failed: \(error.localizedDescription)"
        }
    }
}

@available(macOS 13.0, *)
private final class MarketingPreviewRecordingSession: NSObject, SCStreamOutput, SCStreamDelegate {
    private let stream: SCStream
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let outputURL: URL
    private let sampleQueue = DispatchQueue(label: "com.quartznotch.marketing-preview-recorder")
    private var didFinish = false
    private var didStartWriting = false
    private let onStarted: @MainActor () -> Void
    private let onFinished: @MainActor (Result<URL, Error>) -> Void

    private init(
        stream: SCStream,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        audioInput: AVAssetWriterInput,
        outputURL: URL,
        onStarted: @escaping @MainActor () -> Void,
        onFinished: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        self.stream = stream
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.outputURL = outputURL
        self.onStarted = onStarted
        self.onFinished = onFinished
        super.init()
    }

    static func start(
        windowID: CGWindowID,
        captureWidth: Int,
        captureHeight: Int,
        outputURL: URL,
        onStarted: @escaping @MainActor () -> Void,
        onFinished: @escaping @MainActor (Result<URL, Error>) -> Void
    ) async throws -> MarketingPreviewRecordingSession {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let shareableContent = try await SCShareableContent.current
        guard let targetWindow = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw NSError(
                domain: "QuartzNotchMarketingPreview",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Preview window is not available to ScreenCaptureKit"]
            )
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = captureWidth
        configuration.height = captureHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = false

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = false

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: captureWidth,
                AVVideoHeightKey: captureHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(45_000_000, captureWidth * captureHeight * 18),
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
                ],
            ]
        )
        videoInput.expectsMediaDataInRealTime = true

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 320_000,
            ]
        )
        audioInput.expectsMediaDataInRealTime = true

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "QuartzNotchMarketingPreview",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not start video writer"]
            )
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let session = MarketingPreviewRecordingSession(
            stream: stream,
            writer: writer,
            videoInput: videoInput,
            audioInput: audioInput,
            outputURL: outputURL,
            onStarted: onStarted,
            onFinished: onFinished
        )

        try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.sampleQueue)
        try stream.addStreamOutput(session, type: .audio, sampleHandlerQueue: session.sampleQueue)
        try await stream.startCapture()
        Task { @MainActor in onStarted() }
        return session
    }

    func stop() async {
        guard !didFinish else { return }
        do {
            try stream.removeStreamOutput(self, type: .screen)
            try stream.removeStreamOutput(self, type: .audio)
            try await stream.stopCapture()
            finishWriting()
        } catch {
            finish(.failure(error))
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !didFinish, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .screen:
            guard isCompleteScreenFrame(sampleBuffer) else { return }
            appendVideo(sampleBuffer)
        case .audio:
            appendAudio(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(.failure(error))
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !didFinish else { return }
        if !didStartWriting {
            didStartWriting = true
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        if !videoInput.append(sampleBuffer) {
            finish(.failure(writer.error ?? NSError(
                domain: "QuartzNotchMarketingPreview",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Video encoding failed"]
            )))
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard didStartWriting, !didFinish, audioInput.isReadyForMoreMediaData else { return }
        if !audioInput.append(sampleBuffer) {
            finish(.failure(writer.error ?? NSError(
                domain: "QuartzNotchMarketingPreview",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Audio encoding failed"]
            )))
        }
    }

    private func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return true
        }

        return status == .complete
    }

    private func finishWriting() {
        sampleQueue.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.didFinish = true
            self.videoInput.markAsFinished()
            self.audioInput.markAsFinished()
            self.writer.finishWriting { [weak self] in
                guard let self else { return }
                if let error = self.writer.error {
                    Task { @MainActor in self.onFinished(.failure(error)) }
                } else {
                    Task { @MainActor in self.onFinished(.success(self.outputURL)) }
                }
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !didFinish else { return }
        didFinish = true
        Task { @MainActor in onFinished(result) }
    }
}

private struct MarketingPreviewRoot: View {
    @ObservedObject var viewModel: QuartzViewModel
    @ObservedObject private var coordinator = QuartzViewCoordinator.shared
    @StateObject private var captureController = MarketingPreviewCaptureController()
    @State private var backgroundStyle = 3
    @State private var previewCursorPosition: CGPoint = .zero
    @State private var previewCursorVisible = false
    @State private var previewWindow: NSWindow?

    private let bezelImagePixelSize = CGSize(width: 3860, height: 2540)
    private let bezelVisiblePixelBounds = CGRect(x: 27, y: 233, width: 3806, height: 2296)
    private let bezelDisplayWidth: CGFloat = 3849
    private let bezelScreenTopY: CGFloat = 288
    private let verticalShiftUp: CGFloat = 230
    private let notchTopSeamBridgeHeight: CGFloat = 1
    private let previewCursorScale: CGFloat = 2.1

    private let baseWidth = OpenNotchLayoutMetrics.shellSize.width + openNotchHorizontalOverhang * 2
    private let baseHeight = OpenNotchLayoutMetrics.shellSize.height
        + OpenNotchLayoutMetrics.lyricsExtraHeight
        + OpenNotchLayoutMetrics.volumeExtraHeight
        + shadowPadding

    var body: some View {
        VStack(spacing: 22) {
            previewToolbar

            ZStack(alignment: .top) {
                previewBackground

                GeometryReader { proxy in
                    let contentWidth = baseWidth * cinemaModeScale
                    let contentHeight = baseHeight * cinemaModeScale
                    let bezelDisplayHeight = previewBezelDisplayHeight

                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: proxy.size.height / 2 - verticalShiftUp - 1)

                        HStack(spacing: 0) {
                            Spacer(minLength: 0)

                            ContentView()
                                .environmentObject(viewModel)
                                .environment(\.isMarketingPreview, true)
                                .environment(\.marketingPreviewScale, cinemaModeScale)
                                .environment(\.displayScale, previewDisplayScale)
                                .frame(width: baseWidth, height: baseHeight, alignment: .top)
                                .scaleEffect(cinemaModeScale, anchor: .top)
                                .frame(width: contentWidth, height: contentHeight, alignment: .top)

                            Spacer(minLength: 0)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .zIndex(1)

                    HoverTrackingOverlay { hovering in
                        if hovering {
                            if viewModel.notchState == .closed {
                                withAnimation(NotchMotion.notchOpen) {
                                    viewModel.open()
                                }
                            }
                        } else {
                            if viewModel.notchState == .open {
                                withAnimation(NotchMotion.notchClose) {
                                    viewModel.close()
                                }
                            }
                        }
                    }
                    .frame(width: viewModel.notchSize.width * cinemaModeScale, height: viewModel.notchSize.height * cinemaModeScale)
                    .position(
                        x: proxy.size.width / 2,
                        y: (proxy.size.height / 2 - verticalShiftUp - 1) + (viewModel.notchSize.height * cinemaModeScale / 2)
                    )
                    .zIndex(2)

                    Rectangle()
                        .fill(Color.black)
                        .frame(width: previewTopSeamBridgeWidth, height: notchTopSeamBridgeHeight)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height / 2 - verticalShiftUp - 1 - (notchTopSeamBridgeHeight / 2)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(3)

                    MarketingPreviewCursorTracker(
                        cursorPosition: $previewCursorPosition,
                        isVisible: $previewCursorVisible
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                    .zIndex(900)

                    if previewCursorVisible {
                        MarketingPreviewCursor(
                            position: previewCursorPosition,
                            scale: previewCursorScale
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(901)
                    }

                    Image("MarketingMacBookBezel")
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(
                            width: bezelDisplayWidth,
                            height: bezelDisplayHeight,
                            alignment: .top
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .offset(y: previewBezelOffsetY(in: proxy.size.height))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(1000)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
        }
        .padding(24)
        .frame(minWidth: 1200, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MarketingPreviewWindowAccessor { window in
            previewWindow = window
        })
        .onAppear {
            viewModel.configureForMarketingPreview()
            if viewModel.notchState != .open {
                viewModel.open()
            }
        }
    }

    private var previewDisplayScale: CGFloat {
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2
        return max(screenScale * cinemaModeScale, screenScale)
    }

    private var previewBezelDisplayHeight: CGFloat {
        bezelDisplayWidth * bezelImagePixelSize.height / bezelImagePixelSize.width
    }

    private var previewBezelImageScale: CGFloat {
        bezelDisplayWidth / bezelImagePixelSize.width
    }

    private var previewBezelVisibleDisplaySize: CGSize {
        CGSize(
            width: bezelVisiblePixelBounds.width * previewBezelImageScale,
            height: bezelVisiblePixelBounds.height * previewBezelImageScale
        )
    }

    private func previewBezelOffsetY(in containerHeight: CGFloat) -> CGFloat {
        containerHeight / 2 - verticalShiftUp - (bezelScreenTopY * bezelDisplayWidth / bezelImagePixelSize.width) - 1
    }

    private func previewBezelVisibleCenter(in containerSize: CGSize) -> CGPoint {
        let visibleSize = previewBezelVisibleDisplaySize
        let visibleMinX = (containerSize.width - bezelDisplayWidth) / 2 + bezelVisiblePixelBounds.minX * previewBezelImageScale
        let visibleMinY = previewBezelOffsetY(in: containerSize.height) + bezelVisiblePixelBounds.minY * previewBezelImageScale

        return CGPoint(
            x: visibleMinX + visibleSize.width / 2,
            y: visibleMinY + visibleSize.height / 2
        )
    }

    private var previewTopSeamBridgeWidth: CGFloat {
        guard viewModel.notchState == .closed else {
            return viewModel.notchSize.width * cinemaModeScale
        }

        let closedActivityExtension = 2 * max(48, viewModel.effectiveClosedNotchHeight + 22)
        let closedActivityWidth = viewModel.closedNotchSize.width + closedActivityExtension
        return max(viewModel.notchSize.width, closedActivityWidth) * cinemaModeScale
    }

    private var previewToolbar: some View {
        HStack(spacing: 10) {
            Text("Marketing Preview")
                .font(.system(size: 15, weight: .semibold))

            Divider().frame(height: 18)

            Button("Media") { setPage(.home) }
            Button("Calendar") { setPage(.third) }
            Button("Shelf") { setPage(.shelf) }

            Divider().frame(height: 18)

            Button(viewModel.notchState == .open ? "Close Notch" : "Open Notch") {
                if viewModel.notchState == .open {
                    viewModel.close()
                } else {
                    viewModel.open()
                }
            }

            Button("Background") {
                backgroundStyle = (backgroundStyle + 1) % 4
            }

            Divider().frame(height: 18)

            Button("Capture") {
                captureController.captureScreenshot(of: previewWindow)
            }

            Button(captureController.isRecording ? "Stop" : "Record") {
                captureController.toggleRecording(of: previewWindow)
            }
            .foregroundStyle(captureController.isRecording ? .red : .primary)

            Spacer()

            Text(captureController.statusText ?? "Capture this window for README images/videos")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch backgroundStyle {
        case 1:
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.14), Color(red: 0.35, green: 0.28, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2:
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.94, blue: 0.97), Color(red: 0.78, green: 0.83, blue: 0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 3:
            liquidGlassShowcaseBackground
        default:
            ZStack {
                Color(red: 0.035, green: 0.038, blue: 0.050)
                RadialGradient(
                    colors: [Color.purple.opacity(0.30), .clear],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 760
                )
                RadialGradient(
                    colors: [Color.orange.opacity(0.24), .clear],
                    center: .bottomTrailing,
                    startRadius: 80,
                    endRadius: 680
                )
            }
        }
    }

    private var liquidGlassShowcaseBackground: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white

                liquidGlassReferencePattern
                    .frame(width: previewBezelVisibleDisplaySize.width, height: previewBezelVisibleDisplaySize.height)
                    .clipped()
                    .position(previewBezelVisibleCenter(in: proxy.size))

                loremIpsumBackdrop
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .offset(y: proxy.size.height * 0.43)
            }
        }
    }

    private var liquidGlassReferencePattern: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var horizontal = Path()
                    stride(from: size.height * 0.18, through: size.height, by: 42).forEach { y in
                        horizontal.move(to: CGPoint(x: 0, y: y))
                        horizontal.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(horizontal, with: .color(.black.opacity(0.34)), lineWidth: 1.6)

                    var diagonals = Path()
                    stride(from: -size.height, through: size.width, by: 118).forEach { x in
                        diagonals.move(to: CGPoint(x: x, y: size.height))
                        diagonals.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    context.stroke(diagonals, with: .color(.black.opacity(0.26)), lineWidth: 2.4)

                    let circles: [(CGPoint, CGFloat)] = [
                        (CGPoint(x: size.width * 0.18, y: size.height * 0.34), 92),
                        (CGPoint(x: size.width * 0.78, y: size.height * 0.42), 124),
                        (CGPoint(x: size.width * 0.53, y: size.height * 0.72), 172)
                    ]

                    for (center, radius) in circles {
                        let rect = CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(.black.opacity(0.42)),
                            lineWidth: 3.0
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text("QuartzNotch")
                    Text("Liquid Glass")
                    Text("Refraction")
                }
                .font(.system(size: 84, weight: .black, design: .serif))
                .foregroundStyle(Color(red: 0.07, green: 0.22, blue: 0.42).opacity(0.24))
                .tracking(-2.2)
                .padding(.leading, 92)
                .padding(.top, max(34, proxy.size.height * 0.23))
            }
        }
        .allowsHitTesting(false)
    }

    private var loremIpsumBackdrop: some View {
        let text = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer non mi vitae arcu facilisis viverra. Sed posuere, neque at posuere feugiat, justo lorem posuere nunc, vitae dignissim ipsum augue et sem. Praesent posuere arcu sed magna consequat, a gravida sem egestas. Donec vulputate sapien id quam laoreet, sed faucibus lectus facilisis. Nulla facilisi.
        Integer varius risus vitae lorem dictum, curabitur at enim in nisl posuere luctus. Suspendisse potenti. Morbi euismod, erat vel feugiat dignissim, justo tellus placerat libero, vitae viverra nisl neque non massa. Aenean sagittis magna vel lacus cursus, id porttitor augue pulvinar.
        Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae. Pellentesque finibus, metus vel dignissim eleifend, massa ipsum porttitor ligula, non vestibulum sem lorem a arcu. Duis id risus ultricies, efficitur lorem nec, semper justo.
        Aliquam erat volutpat. Vivamus tristique tellus et sem convallis, ac luctus lorem hendrerit. Nunc faucibus sapien sit amet arcu pulvinar, vel fermentum risus aliquet. Cras gravida nulla a arcu ultricies, non interdum est posuere.
        """

        return Text(text)
            .font(.system(size: 39, weight: .bold, design: .serif))
            .foregroundStyle(Color(red: 0.07, green: 0.22, blue: 0.42))
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 72)
            .allowsHitTesting(false)
    }

    private func setPage(_ view: NotchViews) {
        if viewModel.notchState != .open {
            viewModel.open()
        }
        coordinator.currentView = view
    }
}

fileprivate struct HoverTrackingOverlay: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView(onHoverChanged: onHoverChanged)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? TrackingView {
            view.onHoverChanged = onHoverChanged
            view.ensureTracking()
        }
    }

    class TrackingView: NSView {
        var onHoverChanged: (Bool) -> Void
        private var trackingArea: NSTrackingArea?
        private var isHovering = false
        private var pendingExitWorkItem: DispatchWorkItem?

        init(onHoverChanged: @escaping (Bool) -> Void) {
            self.onHoverChanged = onHoverChanged
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            pendingExitWorkItem?.cancel()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Let all mouse clicks and drags pass through to SwiftUI views below us!
            return nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            updateTracking()
        }

        func ensureTracking() {
            if trackingArea == nil {
                updateTracking()
            }
        }

        func updateTracking() {
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect
            ]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            if let trackingArea {
                addTrackingArea(trackingArea)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            pendingExitWorkItem?.cancel()
            pendingExitWorkItem = nil

            guard !isHovering else { return }
            isHovering = true
            onHoverChanged(true)
        }

        override func mouseExited(with event: NSEvent) {
            pendingExitWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !self.containsCurrentMouse() else { return }

                self.isHovering = false
                self.onHoverChanged(false)
            }

            pendingExitWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        private func containsCurrentMouse() -> Bool {
            guard let window else { return false }

            let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return bounds.insetBy(dx: -2, dy: -2).contains(localPoint)
        }
    }
}

fileprivate struct MarketingPreviewWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

fileprivate struct MarketingPreviewCursor: View {
    let position: CGPoint
    let scale: CGFloat

    private let cursor = NSCursor.arrow

    var body: some View {
        let image = cursor.image
        let imageSize = image.size == .zero ? CGSize(width: 28, height: 40) : image.size
        let displaySize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let hotSpot = cursor.hotSpot == .zero ? CGPoint(x: 5, y: 5) : cursor.hotSpot

        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: displaySize.width, height: displaySize.height)
            .position(
                x: position.x + displaySize.width / 2 - hotSpot.x * scale,
                y: position.y + displaySize.height / 2 - hotSpot.y * scale
            )
    }
}

fileprivate struct MarketingPreviewCursorTracker: NSViewRepresentable {
    @Binding var cursorPosition: CGPoint
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onCursorChanged = { point, visible in
            cursorPosition = point
            isVisible = visible
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onCursorChanged = { point, visible in
            cursorPosition = point
            isVisible = visible
        }
        nsView.updateTracking()
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: ()) {
        nsView.restoreSystemCursor()
    }

    final class TrackingView: NSView {
        var onCursorChanged: ((CGPoint, Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var didHideCursor = false
        private var cursorWatchdogTimer: Timer?
        private var notificationObservers: [NSObjectProtocol] = []

        deinit {
            removeNotificationObservers()
            cursorWatchdogTimer?.invalidate()
            restoreSystemCursor()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeNotificationObservers()
            if window == nil {
                restoreSystemCursor()
                onCursorChanged?(.zero, false)
            } else {
                installNotificationObservers()
                updateTracking()
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            updateTracking()
        }

        func updateTracking() {
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect
            ]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            if let trackingArea {
                addTrackingArea(trackingArea)
            }
            restoreCursorIfPointerIsOutside()
        }

        override func mouseEntered(with event: NSEvent) {
            hideSystemCursorIfNeeded()
            publishCursorPosition(from: event, visible: true)
        }

        override func mouseMoved(with event: NSEvent) {
            hideSystemCursorIfNeeded()
            publishCursorPosition(from: event, visible: true)
        }

        override func mouseDragged(with event: NSEvent) {
            hideSystemCursorIfNeeded()
            publishCursorPosition(from: event, visible: true)
        }

        override func mouseExited(with event: NSEvent) {
            restoreSystemCursor()
            onCursorChanged?(.zero, false)
        }

        func restoreSystemCursor() {
            guard didHideCursor else { return }
            didHideCursor = false
            cursorWatchdogTimer?.invalidate()
            cursorWatchdogTimer = nil
            NSCursor.unhide()
        }

        private func hideSystemCursorIfNeeded() {
            guard !didHideCursor else { return }
            didHideCursor = true
            NSCursor.hide()
            startCursorWatchdog()
        }

        private func publishCursorPosition(from event: NSEvent, visible: Bool) {
            let localPoint = convert(event.locationInWindow, from: nil)
            let swiftUIPoint = CGPoint(
                x: localPoint.x,
                y: bounds.height - localPoint.y
            )
            onCursorChanged?(swiftUIPoint, visible)
        }

        private func startCursorWatchdog() {
            cursorWatchdogTimer?.invalidate()
            cursorWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.restoreCursorIfPointerIsOutside()
            }
        }

        private func restoreCursorIfPointerIsOutside() {
            guard didHideCursor else { return }
            guard let window, window.isVisible else {
                restoreAndHideCustomCursor()
                return
            }

            let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.insetBy(dx: -2, dy: -2).contains(localPoint) {
                restoreAndHideCustomCursor()
            }
        }

        private func restoreAndHideCustomCursor() {
            restoreSystemCursor()
            onCursorChanged?(.zero, false)
        }

        private func installNotificationObservers() {
            guard let window else { return }
            let center = NotificationCenter.default
            notificationObservers = [
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in self?.restoreAndHideCustomCursor() },
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in self?.restoreAndHideCustomCursor() },
                center.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in self?.restoreAndHideCustomCursor() },
            ]
        }

        private func removeNotificationObservers() {
            let center = NotificationCenter.default
            notificationObservers.forEach { center.removeObserver($0) }
            notificationObservers.removeAll()
        }
    }
}
