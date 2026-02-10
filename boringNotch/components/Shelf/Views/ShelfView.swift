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
    @ObservedObject var webcamManager = WebcamManager.shared

    private let spacing: CGFloat = 8
    private let interItemSpacing: CGFloat = 12
    private let cameraReservedWidth: CGFloat = 150

  // Fallback for mirror preference without relying on external Defaults package
    private var isMirrorEnabled: Bool {
        Defaults[.showMirror]
    }

    private var shouldShowCamera: Bool {
        isMirrorEnabled && webcamManager.cameraAvailable && vm.isCameraExpanded
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { isPagerScrollEnabled = true }
        .onDisappear { isPagerScrollEnabled = true }
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
        ZStack {
      // Invisible fill that defines a reliable hit/drop region.
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.clear)

            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    vm.dragDetectorTargeting
                        ? Color.accentColor.opacity(0.9)
                        : Color.white.opacity(0.1),
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        dash: [10]
                    )
                )
                .animation(nil, value: vm.dragDetectorTargeting)
        }
        .overlay {
            content
                .padding(.vertical)
                .padding(.horizontal, 8)
        }
    // Avoid disabling the entire transaction tree here.
    // This view participates in the pager's horizontal translation animation.
        .contentShape(Rectangle())
        .onTapGesture { selection.clear() }
    }

  // MARK: - Content

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
        // Make the empty state itself a full-size drop target so you don't have to aim
        // for the stroke/margins.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        isTargeted: $vm.dragDetectorTargeting) { providers in
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
                        isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
