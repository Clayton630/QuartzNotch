//
// ShelfItemView.swift
// boringNotch
//
// Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var isPagerScrollEnabled: Bool
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var isLocalDropTargeting = false
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    private let spacing: CGFloat = 0
    private let interItemSpacing: CGFloat = 12
    private let cameraReservedWidth: CGFloat = 150

  // Fallback for mirror preference without relying on external Defaults package
    private var isMirrorEnabled: Bool {
        Defaults[.showMirror]
    }

    private var shouldShowCamera: Bool {
        isMirrorEnabled
            && webcamManager.cameraAvailable
            && vm.isCameraExpanded
            && !vm.suppressCameraLayoutInOpenContent
    }

    private var isDropHighlighted: Bool {
        isLocalDropTargeting
    }

    var body: some View {
    // Use negative HStack spacing (instead of negative padding/offset) to visually reduce the
    // gap between FileShareView and the tray while keeping a stable, predictable hit/drop region.
    // Negative padding/offset can make macOS drop hit-testing feel "shifted".
    // Camera open: keep a tighter and symmetric layout
    // (same spacing Share<->Tray and Tray<->Camera reserve).
        let shelfGap: CGFloat = shouldShowCamera ? -6 : -24.5

        HStack(spacing: shelfGap) {

      // AirDrop (FileShareView)
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: shouldShowCamera ? 150 : 170, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
                .environmentObject(vm)

      // File tray (expanded to the left)
      // NOTE: On macOS, attaching .onDrop to a view that is only a *stroke* can make the
      // effective drop region feel "broken" (the hit area may end up matching the stroke
      // outline instead of the full panel bounds). We add an invisible fill behind the
      // chrome so the drop area exactly matches the visible panel rectangle.
            panel
                .frame(minWidth: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        // Keep the tray above the share view in the overlap region so it reliably receives drops.
                .zIndex(1)
        // When the pointer is over the tray, allow the tray's horizontal ScrollView
        // to receive two-finger scrolling instead of the pager.
                .onHover { hovering in
          // If the tray is empty there is nothing to scroll inside the tray,
          // so keep the pager scroll enabled even while hovering the tray.
                    if hovering && !tvm.isEmpty {
                        isPagerScrollEnabled = false
                    } else {
                        isPagerScrollEnabled = true
                    }
                }

            if shouldShowCamera {
                Spacer(minLength: 0)
                    .frame(width: cameraReservedWidth, height: 0)
            }
        }
    // Consistent global margins
        .padding(.horizontal, 19)
        .padding(.vertical, 10)
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
      // If the tray becomes empty, re-enable pager scrolling immediately.
            if isEmpty { isPagerScrollEnabled = true }
        }

    // Quick Look
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
        let idleFillOpacity: Double = hasItems ? 0.97 : 0.60
        let idleOverlayOpacity: Double = hasItems ? 0.36 : 0.10
        return ZStack {
      // Invisible fill that defines a reliable hit/drop region.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBaseFill.opacity(isDropHighlighted ? 1.0 : idleFillOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(cardBaseFill.opacity(isDropHighlighted ? 0.22 : idleOverlayOpacity))
                }
                .shadow(color: Color.black.opacity(pageUseLiquidGlassBackground ? 0.25 : 0.40), radius: 6, x: 0, y: 2)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDropHighlighted ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.12),
                    lineWidth: 1.3
                )
                .animation(nil, value: isDropHighlighted)
        }
        .overlay {
            content
                .padding(.vertical)
                .padding(.horizontal, 8)
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
    // Avoid disabling the entire transaction tree here.
    // This view participates in the pager's horizontal translation animation.
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
        // Make the empty state itself a full-size drop target so you don't have to aim
        // for the stroke/margins.
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
        // On macOS, the NSScrollView subtree can block parent .onDrop hit-testing.
        // Attach the drop destination here so the whole tray area accepts drops.
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
