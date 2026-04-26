import AppKit
import SwiftUI

private enum AccentMenuStyle {
    static let cornerRadius: CGFloat = 7
    static let itemHeight: CGFloat = 28
}

private final class AccentMenuHoverState: ObservableObject {
    @Published var isHovered = false
}

private struct AccentMenuItemWrapper: View {
    let content: AnyView
    @ObservedObject var hoverState: AccentMenuHoverState

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AccentMenuStyle.cornerRadius, style: .continuous)
                    .fill(hoverState.isHovered ? Color.effectiveAccentBackground : Color.clear)
            )
    }
}

private final class AccentMenuAnchorView: NSView {}

private struct AccentMenuAnchorReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AccentMenuAnchorView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}

private struct AccentMenuEntry: Identifiable {
    let id: AnyHashable
    let content: AnyView
    let action: () -> Void
}

private final class AccentMenuActionTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: Any?) {
        action()
    }
}

private final class AccentMenuItemView: NSView {
    private let hostingView: NSHostingView<AccentMenuItemWrapper>
    private let hoverState: AccentMenuHoverState
    private let action: () -> Void
    private var trackingAreaRef: NSTrackingArea?

    private var isHovered = false {
        didSet { hoverState.isHovered = isHovered }
    }

    init(content: AnyView, width: CGFloat, action: @escaping () -> Void) {
        let hoverState = AccentMenuHoverState()
        self.hoverState = hoverState
        self.hostingView = NSHostingView(rootView: AccentMenuItemWrapper(content: content, hoverState: hoverState))
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: AccentMenuStyle.itemHeight))

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        action()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

private enum AccentMenuPresenter {
    @MainActor
    static func present(entries: [AccentMenuEntry], from anchorView: NSView, preferredWidth: CGFloat? = nil, selectedIndex: Int? = nil) {
        let width = max(preferredWidth ?? anchorView.bounds.width, 160)
        let menu = makeMenu(entries: entries, width: width)
        let positioningItem = selectedIndex.flatMap { menu.items.indices.contains($0) ? menu.items[$0] : nil }
        menu.popUp(positioning: positioningItem, at: NSPoint(x: 0, y: anchorView.bounds.height + 4), in: anchorView)
    }

    @MainActor
    static func present(entries: [AccentMenuEntry], at point: NSPoint, in anchorView: NSView, preferredWidth: CGFloat? = nil) {
        let width = max(preferredWidth ?? 160, 160)
        let menu = makeMenu(entries: entries, width: width)
        menu.popUp(positioning: nil, at: point, in: anchorView)
    }

    private static func makeMenu(entries: [AccentMenuEntry], width: CGFloat) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let targets = NSMutableArray()

        for entry in entries {
            let item = NSMenuItem()
            item.isEnabled = true
            let target = AccentMenuActionTarget(action: entry.action)
            targets.add(target)
            item.representedObject = targets
            item.target = target
            item.action = #selector(AccentMenuActionTarget.performAction(_:))
            item.view = AccentMenuItemView(content: entry.content, width: width) {
                target.performAction(nil)
            }
            menu.addItem(item)
        }

        return menu
    }
}

struct AccentMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var menuWidth: CGFloat? = nil
    var controlSize: ControlSize = .regular
    var leadingView: ((Value) -> AnyView?)? = nil
    var onSelect: ((Value) -> Void)? = nil

    @State private var anchorView: NSView?

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini: 8
        case .small: 9
        case .regular: 10
        case .large: 11
        @unknown default: 10
        }
    }

    private var verticalPadding: CGFloat {
        switch controlSize {
        case .mini: 3.5
        case .small: 4.5
        case .regular: 5.5
        case .large: 6.5
        @unknown default: 5.5
        }
    }

    private var font: Font {
        switch controlSize {
        case .mini: .system(size: 11)
        case .small: .system(size: 12)
        case .regular: .system(size: 13)
        case .large: .system(size: 13)
        @unknown default: .system(size: 13)
        }
    }

    var body: some View {
        Button {
            guard let anchorView else { return }
            let entries = options.map { value in
                AccentMenuEntry(
                    id: AnyHashable(value),
                    content: AnyView(menuRow(for: value, isSelected: value == selection)),
                    action: {
                        selection = value
                        onSelect?(value)
                    }
                )
            }
            let selectedIndex = options.firstIndex(where: { $0 == selection })
            AccentMenuPresenter.present(entries: entries, from: anchorView, preferredWidth: menuWidth, selectedIndex: selectedIndex)
        } label: {
            HStack(spacing: 7) {
                Text(title(selection))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(font)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .background(AccentMenuAnchorReader { anchorView = $0 })
    }

    @ViewBuilder
    private func menuRow(for value: Value, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            if let leading = leadingView?(value) {
                leading
            }

            Text(title(value))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemPurple))
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccentContextMenuCapture: NSViewRepresentable {
    let onRightClick: (NSView, NSPoint) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CaptureView: NSView {
        var onRightClick: ((NSView, NSPoint) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onRightClick?(self, point)
        }
    }
}

struct AccentContextMenuAction: Identifiable {
    let id = UUID()
    let title: String
    let keyboardShortcut: String?
    let action: () -> Void
}

struct AccentContextMenuModifier: ViewModifier {
    let actions: [AccentContextMenuAction]
    var menuWidth: CGFloat = 180

    func body(content: Content) -> some View {
        content.overlay {
            AccentContextMenuCapture { anchorView, point in
                let entries = actions.map { action in
                    AccentMenuEntry(
                        id: action.id,
                        content: AnyView(
                            HStack(spacing: 8) {
                                Text(action.title)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if let keyboardShortcut = action.keyboardShortcut {
                                    Text(keyboardShortcut)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ),
                        action: action.action
                    )
                }
                AccentMenuPresenter.present(entries: entries, at: point, in: anchorView, preferredWidth: menuWidth)
            }
            .allowsHitTesting(true)
        }
    }
}

extension View {
    func accentContextMenu(actions: [AccentContextMenuAction], menuWidth: CGFloat = 180) -> some View {
        modifier(AccentContextMenuModifier(actions: actions, menuWidth: menuWidth))
    }
}
