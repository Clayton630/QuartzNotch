import AppKit
import SwiftUI

// MARK: - Shared internals

private enum AccentMenuStyle {
    static let cornerRadius: CGFloat = 7
    static let itemHeight:   CGFloat = 28
}

private struct AccentMenuEntry: Identifiable {
    let id: AnyHashable
    let content: AnyView
    let action: () -> Void
}

// MARK: - Popup SwiftUI view (hosted inside the NSPanel)

private struct AccentMenuPopupView: View {
    let entries: [AccentMenuEntry]
    let width:   CGFloat
    let onSelect: (AccentMenuEntry) -> Void

    @State private var hoveredID: AnyHashable? = nil

    var body: some View {
        VStack(spacing: 1) {
            ForEach(entries) { entry in
                entry.content
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .frame(height: AccentMenuStyle.itemHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AccentMenuStyle.cornerRadius, style: .continuous)
                            .fill(hoveredID == entry.id
                                  ? Color.effectiveAccentBackground
                                  : Color.clear)
                    )
                    .gesture(DragGesture(minimumDistance: 0).onEnded { _ in onSelect(entry) })
                    .onHover { hoveredID = $0 ? entry.id : nil }
            }
        }
        .padding(4)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Popup manager (NSPanel, non-activating)

@MainActor
private final class AccentMenuPopupManager {
    static let shared = AccentMenuPopupManager()
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private init() {}

    func present(entries: [AccentMenuEntry],
                 from anchorView: NSView,
                 preferredWidth: CGFloat,
                 selectedIndex: Int?) {
        dismiss()

        let width      = max(preferredWidth, 160)
        let rowH       = AccentMenuStyle.itemHeight
        let vertPad: CGFloat = 4
        let totalH     = CGFloat(entries.count) * (rowH + 1) + vertPad * 2

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: totalH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque        = false
        p.backgroundColor = .clear
        p.level           = .popUpMenu
        p.hasShadow       = true
        p.isMovable       = false

        // Position below the anchor view
        if let win = anchorView.window {
            let boundsInWin  = anchorView.convert(anchorView.bounds, to: nil)
            let originScreen = win.convertPoint(toScreen: NSPoint(x: boundsInWin.minX,
                                                                   y: boundsInWin.minY))
            p.setFrameOrigin(NSPoint(x: originScreen.x, y: originScreen.y - totalH - 4))
        }

        p.contentView = NSHostingView(rootView: AccentMenuPopupView(
            entries: entries,
            width: width,
            onSelect: { [weak self] entry in
                entry.action()
                self?.dismiss()
            }
        ))
        p.orderFront(nil)
        panel = p

        // Dismiss when clicking outside
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel { self.dismiss() }
            return event
        }
    }

    func dismiss() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Anchor view helper

private final class AccentMenuAnchorView: NSView {}

private struct AccentMenuAnchorReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = AccentMenuAnchorView(frame: .zero)
        DispatchQueue.main.async { onResolve(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView) }
    }
}

// MARK: - AccentMenuPicker (public)

struct AccentMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var menuWidth:   CGFloat?    = nil
    var controlSize: ControlSize = .regular
    var leadingView: ((Value) -> AnyView?)? = nil
    var onSelect: ((Value) -> Void)? = nil

    @State private var anchorView: NSView?

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini: 8; case .small: 9; case .regular: 10; case .large: 11
        @unknown default: 10
        }
    }
    private var verticalPadding: CGFloat {
        switch controlSize {
        case .mini: 3.5; case .small: 4.5; case .regular: 5.5; case .large: 6.5
        @unknown default: 5.5
        }
    }
    private var font: Font {
        switch controlSize {
        case .mini: .system(size: 11); case .small: .system(size: 12)
        case .regular: .system(size: 13); case .large: .system(size: 13)
        @unknown default: .system(size: 13)
        }
    }

    private func localizedTitle(for value: Value) -> String {
        NSLocalizedString(title(value), comment: "")
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
            AccentMenuPopupManager.shared.present(
                entries: entries,
                from: anchorView,
                preferredWidth: menuWidth ?? anchorView.bounds.width,
                selectedIndex: selectedIndex
            )
        } label: {
            HStack(spacing: 7) {
                Text(localizedTitle(for: selection))
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
            if let leading = leadingView?(value) { leading }
            Text(localizedTitle(for: value))
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

// MARK: - Context menu (right-click) — keeps NSMenu, behaviour unchanged

private final class AccentContextMenuCapture: NSViewRepresentable {
    let onRightClick: (NSView, NSPoint) -> Void
    func makeNSView(context: Context) -> CaptureView {
        let v = CaptureView(); v.onRightClick = onRightClick; return v
    }
    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onRightClick = onRightClick
    }
    final class CaptureView: NSView {
        var onRightClick: ((NSView, NSPoint) -> Void)?
        override init(frame: NSRect) {
            super.init(frame: frame)
            translatesAutoresizingMaskIntoConstraints = false
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(self, convert(event.locationInWindow, from: nil))
        }
    }
}

private final class AccentMenuActionTarget: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func performAction(_ sender: Any?) { action() }
}

private enum AccentMenuPresenter {
    @MainActor
    static func present(entries: [AccentMenuEntry], at point: NSPoint, in anchorView: NSView, preferredWidth: CGFloat? = nil) {
        let width  = max(preferredWidth ?? 160, 160)
        let menu   = NSMenu()
        menu.autoenablesItems = false
        let targets = NSMutableArray()
        for entry in entries {
            let item   = NSMenuItem()
            item.isEnabled = true
            let target = AccentMenuActionTarget(action: entry.action)
            targets.add(target)
            item.representedObject = targets
            item.target = target
            item.action = #selector(AccentMenuActionTarget.performAction(_:))
            item.view   = AccentContextItemView(content: entry.content, width: width) {
                target.performAction(nil)
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: anchorView)
    }

    // Simple NSView for context menu items (mouseDown is fine for right-click menus)
    private final class AccentContextItemView: NSView {
        private let hostingView: NSHostingView<AnyView>
        private let action: () -> Void
        private var hoverState = false
        private var trackingAreaRef: NSTrackingArea?

        init(content: AnyView, width: CGFloat, action: @escaping () -> Void) {
            self.action = action
            self.hostingView = NSHostingView(rootView: content
                .padding(.horizontal, 8).padding(.vertical, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: AccentMenuStyle.itemHeight))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let t = trackingAreaRef { removeTrackingArea(t) }
            let t = NSTrackingArea(rect: bounds,
                                   options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                   owner: self, userInfo: nil)
            addTrackingArea(t); trackingAreaRef = t
        }
        override func mouseDown(with event: NSEvent) {
            action()
            enclosingMenuItem?.menu?.cancelTracking()
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
                let entries = actions.map { a in
                    AccentMenuEntry(
                        id: a.id,
                        content: AnyView(
                            HStack(spacing: 8) {
                                Text(a.title).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if let k = a.keyboardShortcut {
                                    Text(k).foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ),
                        action: a.action
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
