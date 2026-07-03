import SwiftUI
import Defaults
import AppKit

struct CalendarOverlayView: View {
    @EnvironmentObject var vm: QuartzViewModel
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    @State private var selectedDate = Date()
    @StateObject private var wheelScrollTarget = CalendarWheelScrollTarget()

    var monthLeadingSafetyInset: CGFloat = 0
    private let leadingGutterWidth: CGFloat = 6

    private var selectedMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: selectedDate)
        return month.prefix(1).uppercased() + month.dropFirst()
    }

    private var moduleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 22,
            bottomLeadingRadius: 8,
            bottomTrailingRadius: cornerRadiusInsets.opened.bottom,
            topTrailingRadius: 22,
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Color.clear

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1)
                    .padding(.leading, 0)
                    .padding(.vertical, 12)
            }
            .frame(width: leadingGutterWidth)

            CalendarView(selectedDate: $selectedDate, wheelScrollTarget: wheelScrollTarget)
        }
        .background {
            moduleShape
                .fill(pageUseLiquidGlassBackground ? Color.clear : Color.black)
        }
        .contentShape(moduleShape)
        .overlay(alignment: .topLeading) {
            Text(selectedMonthTitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.red)
                .padding(.top, -31)
                .padding(.leading, CGFloat(leadingGutterWidth) + 4 + monthLeadingSafetyInset)
                .allowsHitTesting(false)
        }
        .overlay {
            CalendarModuleHorizontalScrollBridge(
                wheelScrollTarget: wheelScrollTarget
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onHover { isHovering in
            vm.isHoveringCalendar = isHovering
        }
    }
}

private struct CalendarModuleHorizontalScrollBridge: NSViewRepresentable {
    let wheelScrollTarget: CalendarWheelScrollTarget

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.coordinator = context.coordinator
        context.coordinator.bridgeView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.wheelScrollTarget = wheelScrollTarget
        nsView.coordinator = context.coordinator
        context.coordinator.bridgeView = nsView
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(wheelScrollTarget: wheelScrollTarget)
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?
        private var trackingAreaRef: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func scrollWheel(with event: NSEvent) {
            guard coordinator?.handleScrollWheel(event) == true else {
                nextResponder?.scrollWheel(with: event)
                return
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            trackingAreaRef = area
            addTrackingArea(area)
        }

        override func mouseEntered(with event: NSEvent) {
        }

        override func mouseExited(with event: NSEvent) {
        }
    }

    final class Coordinator {
        var wheelScrollTarget: CalendarWheelScrollTarget
        weak var bridgeView: NSView?
        private var monitor: Any?

        init(wheelScrollTarget: CalendarWheelScrollTarget) {
            self.wheelScrollTarget = wheelScrollTarget
        }

        deinit {
            removeMonitor()
        }

        var hasWheelHandler: Bool {
            wheelScrollTarget.handleScrollEvent != nil
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                return self.handleScrollWheel(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func handleScrollWheel(_ event: NSEvent) -> Bool {
            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY

            guard abs(horizontal) >= abs(vertical), abs(horizontal) > 0.2 else {
                return false
            }

            return wheelScrollTarget.handle(event)
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard
                let bridgeView,
                hasWheelHandler,
                event.window === bridgeView.window
            else { return false }

            let point = bridgeView.convert(event.locationInWindow, from: nil)
            guard bridgeView.bounds.contains(point) else { return false }

            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            return abs(horizontal) > abs(vertical) * 1.6
        }
    }
}
