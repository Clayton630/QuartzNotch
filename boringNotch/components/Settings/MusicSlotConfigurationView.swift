
import Defaults
import SwiftUI

// MARK: - Preference key to collect slot frames

private struct SlotFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Main view

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @ObservedObject private var musicManager = MusicManager.shared

    // Slot reorder drag
    @State private var draggingSlotIndex: Int? = nil
    @State private var slotDragTranslationX: CGFloat = 0
    @State private var slotDragStartIndex: Int? = nil
    @State private var slotDragTargetIndex: Int? = nil

    // Palette drag
    @State private var draggingPaletteControl: MusicControlButton? = nil
    @State private var paletteDragPosition: CGPoint = .zero
    @State private var paletteDragTargetSlot: Int? = nil
    @State private var slotFrames: [Int: CGRect] = [:]

    private let fixedSlotCount = 5
    private let slotSize: CGFloat = 48
    private let slotSpacing: CGFloat = 8
    private var slotStride: CGFloat { slotSize + slotSpacing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            slotsSection
            paletteSection
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation(.spring(response: 0.3)) {
                        musicControlSlots = MusicControlButton.defaultLayout
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
        }
        .coordinateSpace(name: "musicConfig")
        .overlay(alignment: .topLeading) {
            if let control = draggingPaletteControl {
                SlotView(slot: control, iconColor: .primary.opacity(0.7), isHighlighted: false, useFillVariant: paletteDragTargetSlot == 1 || paletteDragTargetSlot == 3)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .position(paletteDragPosition)
                    .allowsHitTesting(false)
                    .animation(nil, value: paletteDragPosition)
            }
        }
        .onPreferenceChange(SlotFrameKey.self) { slotFrames = $0 }
        .onAppear {
            ensureSlotCapacity(fixedSlotCount)
            // Enforce playPause at center
            if musicControlSlots.indices.contains(2), musicControlSlots[2] != .playPause {
                var slots = musicControlSlots
                if let existing = slots.firstIndex(of: .playPause) { slots[existing] = .none }
                slots[2] = .playPause
                musicControlSlots = slots
            }
        }
    }

    // MARK: - Slots

    private var slotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Player layout")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack {
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    HStack(spacing: slotSpacing) {
                        ForEach(0..<fixedSlotCount, id: \.self) { index in
                            if index == 2 {
                                // Fixed center slot — always playPause, not interactive
                                SlotView(
                                    slot: .playPause,
                                    iconColor: .primary.opacity(0.7),
                                    isHighlighted: false,
                                    useFillVariant: false,
                                    isFixed: true
                                )
                            } else {
                                SlotView(
                                    slot: slotValue(at: index),
                                    iconColor: slotIconColor(for: slotValue(at: index)),
                                    isHighlighted: paletteDragTargetSlot == index,
                                    useFillVariant: index == 1 || index == 3
                                )
                                .background(GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SlotFrameKey.self,
                                        value: [index: geo.frame(in: .named("musicConfig"))]
                                    )
                                })
                                .opacity(draggingSlotIndex == index ? 0 : 1)
                                .offset(x: slotShiftOffset(for: index))
                                .onTapGesture {
                                    guard slotValue(at: index) != .none else { return }
                                    withAnimation(.spring(response: 0.25)) { updateSlot(.none, at: index) }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 6, coordinateSpace: .local)
                                        .onChanged { value in handleSlotDragChanged(index: index, translation: value.translation) }
                                        .onEnded { _ in handleSlotDragEnded() }
                                )
                            }
                        }
                    }

                    if let dragIdx = draggingSlotIndex, dragIdx != 2, let startIndex = slotDragStartIndex {
                        SlotView(
                            slot: slotValue(at: dragIdx),
                            iconColor: slotIconColor(for: slotValue(at: dragIdx)),
                            isHighlighted: false,
                            useFillVariant: dragIdx == 1 || dragIdx == 3
                        )
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .offset(x: CGFloat(startIndex) * slotStride + slotDragTranslationX)
                        .zIndex(10)
                        .allowsHitTesting(false)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
        }
    }

    // MARK: - Palette

    private var paletteSection: some View {
        let available = MusicControlButton.pickerOptions.filter { $0 != .none && $0 != .playPause }
        let rows = available.chunked(into: fixedSlotCount)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Add a control")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { control in
                            PaletteItem(
                                control: control,
                                isInUse: musicControlSlots.contains(control)
                            )
                            .opacity(draggingPaletteControl == control ? 0.3 : 1)
                            .gesture(
                                DragGesture(minimumDistance: 6, coordinateSpace: .named("musicConfig"))
                                    .onChanged { value in
                                        guard !musicControlSlots.contains(control) else { return }
                                        draggingPaletteControl = control
                                        paletteDragPosition = value.location
                                        let hit = slotFrames.first(where: { $0.value.contains(value.location) })?.key
                                        paletteDragTargetSlot = hit == 2 ? nil : hit  // center is not droppable
                                    }
                                    .onEnded { _ in
                                        if let target = paletteDragTargetSlot {
                                            withAnimation(.spring(response: 0.25)) { updateSlot(control, at: target) }
                                        }
                                        draggingPaletteControl = nil
                                        paletteDragTargetSlot = nil
                                    }
                            )
                            .onTapGesture {
                                guard !musicControlSlots.contains(control),
                                      let idx = musicControlSlots.indices.first(where: { $0 != 2 && musicControlSlots[$0] == .none }) else { return }
                                withAnimation(.spring(response: 0.25)) { updateSlot(control, at: idx) }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
        }
    }

    // MARK: - Slot drag logic

    // The four draggable positions (center index 2 is always fixed)
    private let movablePositions = [0, 1, 3, 4]

    private func handleSlotDragChanged(index: Int, translation: CGSize) {
        guard index != 2 else { return }  // center is fixed
        if draggingSlotIndex == nil {
            draggingSlotIndex = index
            slotDragStartIndex = index
            slotDragTargetIndex = index
            slotDragTranslationX = 0
        }
        guard let startIndex = slotDragStartIndex else { return }
        slotDragTranslationX = translation.width
        // Project from start index, snap to nearest real index, but skip center (2)
        let projected = CGFloat(startIndex) + translation.width / slotStride
        let rawTarget = min(max(Int(projected.rounded()), 0), fixedSlotCount - 1)
        let target = rawTarget == 2 ? (translation.width >= 0 ? 3 : 1) : rawTarget
        if slotDragTargetIndex != target {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                slotDragTargetIndex = target
            }
        }
    }

    private func handleSlotDragEnded() {
        defer { withAnimation(nil) { resetSlotDragState() } }
        guard let draggingSlotIndex,
              let startIndex = slotDragStartIndex,
              let targetIndex = slotDragTargetIndex,
              startIndex != targetIndex else { return }
        guard let fromMovable = movablePositions.firstIndex(of: startIndex),
              let toMovable = movablePositions.firstIndex(of: targetIndex) else { return }
        withAnimation(.spring(response: 0.25)) {
            // Operate only on the 4 movable slots, keeping center fixed
            var movableSlots = movablePositions.map { slotValue(at: $0) }
            let item = movableSlots[fromMovable]
            movableSlots.remove(at: fromMovable)
            movableSlots.insert(item, at: toMovable)
            var slots = musicControlSlots
            while slots.count < fixedSlotCount { slots.append(.none) }
            for (i, pos) in movablePositions.enumerated() {
                slots[pos] = movableSlots[i]
            }
            slots[2] = .playPause
            musicControlSlots = Array(slots.prefix(fixedSlotCount))
        }
    }

    private func resetSlotDragState() {
        draggingSlotIndex = nil
        slotDragTranslationX = 0
        slotDragStartIndex = nil
        slotDragTargetIndex = nil
    }

    private func slotShiftOffset(for index: Int) -> CGFloat {
        guard index != 2,
              let draggingSlotIndex,
              let startIndex = slotDragStartIndex,
              let targetIndex = slotDragTargetIndex,
              index != draggingSlotIndex else { return 0 }

        guard let indexMovable = movablePositions.firstIndex(of: index),
              let startMovable = movablePositions.firstIndex(of: startIndex),
              let targetMovable = movablePositions.firstIndex(of: targetIndex) else { return 0 }

        let newMovableIndex: Int
        if startMovable < targetMovable, indexMovable > startMovable, indexMovable <= targetMovable {
            newMovableIndex = indexMovable - 1
        } else if startMovable > targetMovable, indexMovable >= targetMovable, indexMovable < startMovable {
            newMovableIndex = indexMovable + 1
        } else {
            return 0
        }

        // Convert back to real indices to get the true visual offset (handles cross-center 2× stride)
        let currentRealIndex = movablePositions[indexMovable]
        let newRealIndex = movablePositions[newMovableIndex]
        return CGFloat(newRealIndex - currentRealIndex) * slotStride
    }

    // MARK: - Helpers

    private func slotIconColor(for slot: MusicControlButton) -> Color {
        switch slot {
        case .shuffle:    return musicManager.isShuffled ? .red : .primary.opacity(0.7)
        case .repeatMode: return musicManager.repeatMode != .off ? .red : .primary.opacity(0.7)
        case .favorite:   return .primary.opacity(0.7)
        case .none:       return .clear
        default:          return .primary.opacity(0.7)
        }
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: target - musicControlSlots.count))
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        musicControlSlots.indices.contains(index) ? musicControlSlots[index] : .none
    }

    private func updateSlot(_ value: MusicControlButton, at index: Int) {
        guard index != 2 else { return }  // center slot is fixed
        var slots = musicControlSlots
        if index >= slots.count {
            slots.append(contentsOf: Array(repeating: .none, count: index - slots.count + 1))
        }
        if let existing = slots.firstIndex(of: value), existing != index {
            slots[existing] = .none
        }
        slots[index] = value
        slots[2] = .playPause  // enforce center
        musicControlSlots = slots
    }
}

// MARK: - SlotView

private struct SlotView: View {
    let slot: MusicControlButton
    let iconColor: Color
    let isHighlighted: Bool
    var useFillVariant: Bool = false
    var isFixed: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFixed ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )

            if slot != .none {
                Image(systemName: useFillVariant ? slot.filledIconName : slot.iconName)
                    .font(.system(size: slot.prefersLargeScale ? 20 : (useFillVariant ? 18 : 14), weight: .semibold))
                    .foregroundStyle(iconColor)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(isHighlighted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2))
                    .frame(width: 26, height: 26)
            }

            if isFixed {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .frame(width: 48, height: 48)
        .scaleEffect(isHighlighted ? 1.06 : 1)
        .animation(.spring(response: 0.2), value: isHighlighted)
        .contentShape(Rectangle())
    }
}

// MARK: - PaletteItem

private struct PaletteItem: View {
    let control: MusicControlButton
    let isInUse: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered && !isInUse
                          ? Color.accentColor.opacity(0.18)
                          : Color.primary.opacity(0.06))
                    .frame(width: 44, height: 44)

                Image(systemName: control.iconName)
                    .font(.system(size: control.prefersLargeScale ? 16 : 13, weight: .medium))
                    .foregroundStyle(isInUse ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.65))
            }
            .animation(.easeInOut(duration: 0.1), value: isHovered)

            Text(control.label)
                .font(.caption2)
                .foregroundStyle(isInUse ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.6))
                .frame(width: 56, height: 28, alignment: .top)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .opacity(isInUse ? 0.45 : 1)
        .onHover { isHovered = !isInUse && $0 }
    }
}

// MARK: - Array helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
