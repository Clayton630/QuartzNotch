import AppKit
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
        let hostingView = NSHostingView(rootView: content)
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
        QuartzViewCoordinator.shared.currentView = .home
        if viewModel.notchState != .open {
            viewModel.open()
        }
    }
}

private struct MarketingPreviewRoot: View {
    @ObservedObject var viewModel: QuartzViewModel
    @ObservedObject private var coordinator = QuartzViewCoordinator.shared
    @State private var backgroundStyle = 0

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

                ContentView()
                    .environmentObject(viewModel)
                    .environment(\.isMarketingPreview, true)
                    .environment(\.marketingPreviewScale, cinemaModeScale)
                    .frame(width: baseWidth, height: baseHeight, alignment: .top)
                    .scaleEffect(cinemaModeScale, anchor: .top)
                    .frame(
                        width: baseWidth * cinemaModeScale,
                        height: baseHeight * cinemaModeScale,
                        alignment: .top
                    )
                    .padding(.top, 70)
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
        .onAppear {
                if viewModel.notchState != .open {
                viewModel.open()
            }
        }
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
                backgroundStyle = (backgroundStyle + 1) % 3
            }

            Spacer()

            Text("Capture this window for README images/videos")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
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

    private func setPage(_ view: NotchViews) {
        if viewModel.notchState != .open {
            viewModel.open()
        }
        coordinator.currentView = view
    }
}
