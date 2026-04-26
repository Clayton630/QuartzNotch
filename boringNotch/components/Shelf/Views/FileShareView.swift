
import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FileShareView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @StateObject private var quickShare = QuickShareService.shared
    @Default(.quickShareProvider) var quickShareProvider: String
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    @State private var hostView: NSView?
    @State private var interactionNonce: UUID = .init()
    @State private var isProcessing = false
    @State private var isLocalDropTargeting = false

    @ViewBuilder
    private func bottomAmbientShadow(cornerRadius: CGFloat, opacity: Double, blur: CGFloat, y: CGFloat) -> some View {
        if pageUseLiquidGlassBackground {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(opacity))
                .scaleEffect(x: 0.99, y: 0.95)
                .blur(radius: blur)
                .offset(y: y)
                .mask {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.00),
                                    .init(color: .clear, location: 0.52),
                                    .init(color: .white.opacity(0.72), location: 0.82),
                                    .init(color: .white, location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .drawingGroup()
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }

    private var selectedProvider: QuickShareProvider {
        quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }

    var body: some View {
        dropArea
            .background(NSViewHost(view: $hostView))
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $isLocalDropTargeting) { providers in
                interactionNonce = .init()
                vm.dropEvent = true
                Task { await handleDrop(providers) }
                return true
            }
            .onChange(of: isLocalDropTargeting) { _, targeted in
                vm.dropZoneTargeting = targeted
            }
            .onDisappear {
                isLocalDropTargeting = false
                vm.dropZoneTargeting = false
            }
            .onTapGesture {
                Task {
                    await handleClick()
                }
            }
    }

    private var dropArea: some View {
        let cornerRadius: CGFloat = 16
        let hasLocalActivity = isProcessing || quickShare.isPickerOpen
        let isDropHighlighted = isLocalDropTargeting
        let idleFillOpacity: Double = hasLocalActivity ? (pageUseLiquidGlassBackground ? 0.62 : 0.82) : (pageUseLiquidGlassBackground ? 0.38 : 0.60)
        let idleOverlayOpacity: Double = hasLocalActivity ? (pageUseLiquidGlassBackground ? 0.11 : 0.22) : (pageUseLiquidGlassBackground ? 0.06 : 0.10)
        let strokeOpacity: Double = pageUseLiquidGlassBackground ? 0.15 : 0.12
        let shadowOpacity: Double = pageUseLiquidGlassBackground ? 0.30 : 0.40
        let strokeBaseColor: Color = isDropHighlighted ? .accentColor : .white
        let counterStrokeColor: Color = isDropHighlighted ? .accentColor.opacity(0.18) : .black.opacity(0.055)
        let strokeBlendMode: BlendMode = isDropHighlighted ? .normal : .screen
        let counterStrokeBlendMode: BlendMode = isDropHighlighted ? .normal : .multiply
        return ZStack {
            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(hasLocalActivity ? 0.31 : 0.27)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(hasLocalActivity ? 0.062 : 0.044))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(hasLocalActivity ? 0.009 : 0.007))
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardBaseFill.opacity(isDropHighlighted ? 1.0 : idleFillOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(cardBaseFill.opacity(isDropHighlighted ? 0.22 : idleOverlayOpacity))
                }
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 2)

            bottomAmbientShadow(cornerRadius: cornerRadius, opacity: 0.22, blur: 15, y: 7)

            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(counterStrokeColor, lineWidth: 1.0)
                    .blendMode(counterStrokeBlendMode)
            }

            Group {
                if pageUseLiquidGlassBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: strokeBaseColor.opacity(isDropHighlighted ? 0.28 : strokeOpacity), location: 0.00),
                                    .init(color: strokeBaseColor.opacity(isDropHighlighted ? 0.28 : strokeOpacity), location: 0.54),
                                    .init(color: strokeBaseColor.opacity(isDropHighlighted ? 0.38 : 0.17), location: 0.76),
                                    .init(color: strokeBaseColor.opacity(isDropHighlighted ? 0.58 : 0.34), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.3
                        )
                        .blendMode(strokeBlendMode)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isDropHighlighted ? Color.accentColor.opacity(0.62) : Color.white.opacity(strokeOpacity),
                            lineWidth: 1.3
                        )
                }
            }

            VStack(spacing: 8) {
                ZStack {
                    let actionBlue = Color(nsColor: .systemBlue)
                    Circle()
                        .fill(actionBlue.opacity(isDropHighlighted ? 0.27 : 0.21))
                        .frame(width: 48, height: 48)

                    Group {
                        if isAirDropProvider(selectedProvider.id) {
                            Image("AirDrop")
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 21, height: 21)
                                .foregroundStyle(actionBlue.opacity(isDropHighlighted ? 1.0 : 0.95))
                        } else if let symbol = systemSymbolName(for: selectedProvider.id) {
                            Image(systemName: symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(actionBlue.opacity(isDropHighlighted ? 1.0 : 0.95))
                        } else if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .saturation(0)
                                .brightness(0.04)
                                .colorMultiply(actionBlue)
                                .opacity(isDropHighlighted ? 1.0 : 0.95)
                        } else if let nsImg = ProviderAppIconResolver.icon(forProviderName: selectedProvider.id) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .saturation(0)
                                .brightness(0.04)
                                .colorMultiply(actionBlue)
                                .opacity(isDropHighlighted ? 1.0 : 0.95)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(actionBlue.opacity(isDropHighlighted ? 1.0 : 0.95))
                        }
                    }
                    .frame(width: 34, height: 34)
                        .font(.system(size: 17, weight: .medium))
                }
                .scaleEffect(isDropHighlighted ? 1.14 : 1.0)
                .shadow(
                    color: Color(nsColor: .systemBlue).opacity(isDropHighlighted ? 0.32 : 0.0),
                    radius: isDropHighlighted ? 4.0 : 0.0
                )
                .animation(.spring(response: 0.30, dampingFraction: 0.62), value: isDropHighlighted)
                .padding(.bottom, 4)

                Text(selectedProvider.id)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

            }
            .padding(18)
            .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.10 : 0.0), radius: 2.0, x: 0, y: 1)
            .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.035 : 0.0), radius: 4.6, x: 0, y: 2)
            
            if isProcessing || quickShare.isPickerOpen {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(pageUseLiquidGlassBackground ? Color.white.opacity(0.14) : .black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var cardBaseFill: Color { Color(nsColor: .secondarySystemFill) }

    private func isAirDropProvider(_ providerName: String) -> Bool {
        providerName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .contains("airdrop")
    }

    private func systemSymbolName(for providerName: String) -> String? {
        let name = providerName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if name.contains("message") || name.contains("imessage") { return "message.fill" }
        if name.contains("mail") { return "envelope.fill" }
        if name.contains("notes") || name.contains("note") { return "note.text" }
        if name.contains("reminder") || name.contains("rappel") { return "list.bullet" }
        if name.contains("system share menu") { return "square.and.arrow.up" }
        return nil
    }

  // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) async {
        isProcessing = true
        defer { isProcessing = false }
        await quickShare.shareDroppedFiles(providers, using: selectedProvider, from: hostView)
    }
    
    private func handleClick() async {
        await quickShare.showFilePicker(for: selectedProvider, from: hostView)
    }
}

// MARK: - Host NSView extractor for anchoring share sheet

private struct NSViewHost: NSViewRepresentable {
    @Binding var view: NSView?
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { self.view = v }
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}
