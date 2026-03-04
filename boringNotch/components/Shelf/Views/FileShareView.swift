//
// FileShareView.swift
// boringNotch
//
// Created by Alexander on 2025-09-24.
//

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
        let idleFillOpacity: Double = hasLocalActivity ? 0.82 : 0.60
        let idleOverlayOpacity: Double = hasLocalActivity ? 0.22 : 0.10
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardBaseFill.opacity(isDropHighlighted ? 1.0 : idleFillOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(cardBaseFill.opacity(isDropHighlighted ? 0.22 : idleOverlayOpacity))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isDropHighlighted ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.12),
                            lineWidth: 1.3
                        )
                )
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.25 : 0.40), radius: 6, x: 0, y: 2)

      // Content
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
            
      // Loading overlay
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
