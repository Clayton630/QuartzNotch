
import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: QuartzViewModel
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @Binding var isPagerScrollEnabled: Bool
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var isLocalDropTargeting = false
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    private let spacing: CGFloat = 0
    private let interItemSpacing: CGFloat = 12

    private var isMirrorEnabled: Bool {
        Defaults[.showMirror]
    }

    private var isDropHighlighted: Bool {
        isLocalDropTargeting
    }

    private var shelfGap: CGFloat {
        -24.5 + (6 * openLayoutCompression)
    }

    private var fileShareWidth: CGFloat {
        170 - (12 * openLayoutCompression)
    }

    private var outerHorizontalPadding: CGFloat {
        22 - (3 * openLayoutCompression)
    }

    private var outerVerticalPadding: CGFloat {
        10 - (4 * openLayoutCompression)
    }

    private var panelContentVerticalPadding: CGFloat {
        16 - (6 * openLayoutCompression)
    }

    private var panelContentHorizontalPadding: CGFloat {
        8 - (1.5 * openLayoutCompression)
    }

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
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        HStack(spacing: shelfGap) {

            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: fileShareWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
                .environmentObject(vm)

            panel
                .frame(minWidth: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .zIndex(1)
                .onHover { hovering in
                    if hovering && !tvm.isEmpty {
                        isPagerScrollEnabled = false
                    } else {
                        isPagerScrollEnabled = true
                    }
                }

        }
        .padding(.horizontal, outerHorizontalPadding)
        .padding(.vertical, outerVerticalPadding)
        .onAppear { isPagerScrollEnabled = true }
        .onDisappear { isPagerScrollEnabled = true }
        .onDisappear {
            isLocalDropTargeting = false
            vm.dragDetectorTargeting = false
        }
        .onChange(of: isLocalDropTargeting) { _, targeted in
            vm.dragDetectorTargeting = targeted
        }
        .onChange(of: tvm.isEmpty) { isEmpty in
            if isEmpty { isPagerScrollEnabled = true }
        }

        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }

  // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }

    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen,
              !selection.selectedIDs.isEmpty else { return }

        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL { return fileURL }
            if case .link(let url) = item.kind { return url }
            return nil
        }

        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

  // MARK: - Panel

    var panel: some View {
        let hasItems = !tvm.items.isEmpty
        let idleFillOpacity: Double = hasItems ? (pageUseLiquidGlassBackground ? 0.66 : 0.97) : (pageUseLiquidGlassBackground ? 0.38 : 0.60)
        let idleOverlayOpacity: Double = hasItems ? (pageUseLiquidGlassBackground ? 0.14 : 0.36) : (pageUseLiquidGlassBackground ? 0.06 : 0.10)
        let strokeOpacity: Double = pageUseLiquidGlassBackground ? 0.15 : 0.12
        let shadowOpacity: Double = pageUseLiquidGlassBackground ? 0.30 : 0.40
        let strokeBaseColor: Color = isDropHighlighted ? .accentColor : .white
        let counterStrokeColor: Color = isDropHighlighted ? .accentColor.opacity(0.18) : .black.opacity(0.055)
        let strokeBlendMode: BlendMode = isDropHighlighted ? .normal : .screen
        let counterStrokeBlendMode: BlendMode = isDropHighlighted ? .normal : .multiply
        return ZStack {
            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(hasItems ? 0.33 : 0.27)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(hasItems ? 0.070 : 0.046))

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(hasItems ? 0.010 : 0.007))
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBaseFill.opacity(isDropHighlighted ? 1.0 : idleFillOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(cardBaseFill.opacity(isDropHighlighted ? 0.22 : idleOverlayOpacity))
                }
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 2)

            bottomAmbientShadow(cornerRadius: 16, opacity: 0.22, blur: 15, y: 7)

            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(counterStrokeColor, lineWidth: 1.0)
                    .blendMode(counterStrokeBlendMode)
            }

            Group {
                if pageUseLiquidGlassBackground {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isDropHighlighted ? Color.accentColor.opacity(0.62) : Color.white.opacity(strokeOpacity),
                            lineWidth: 1.3
                        )
                }
            }
            .animation(nil, value: isDropHighlighted)
        }
        .overlay {
            content
                .padding(.vertical, panelContentVerticalPadding)
                .padding(.horizontal, panelContentHorizontalPadding)
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.10 : 0.0), radius: 2.0, x: 0, y: 1)
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.035 : 0.0), radius: 4.6, x: 0, y: 2)
        }
        .overlay(alignment: .topTrailing) {
            if hasItems {
                Button {
                    selection.noteItemInteraction()
                    selection.clear()
                    tvm.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.46))
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection.clearIfAllowed() }
    }

    private var cardBaseFill: Color { Color(nsColor: .secondarySystemFill) }

  // MARK: - Content

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    ZStack {
                        let actionBlue = Color(nsColor: .systemBlue)
                        Circle()
                            .fill(actionBlue.opacity(isDropHighlighted ? 0.27 : 0.21))
                            .frame(width: 48, height: 48)

                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(actionBlue.opacity(isDropHighlighted ? 1.0 : 0.95))
                    }
                    .scaleEffect(isDropHighlighted ? 1.14 : 1.0)
                    .shadow(
                        color: Color(nsColor: .systemBlue).opacity(isDropHighlighted ? 0.32 : 0.0),
                        radius: isDropHighlighted ? 4.0 : 0.0
                    )
                    .animation(.spring(response: 0.30, dampingFraction: 0.62), value: isDropHighlighted)
                    .padding(.bottom, 4)

                    Text("File Tray")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        isTargeted: $isLocalDropTargeting) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        isTargeted: $isLocalDropTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
