
import Cocoa
import UniformTypeIdentifiers
import QuartzCore

final class DragDetector {

 // MARK: - Callbacks

    typealias VoidCallback = () -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?


    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false
    private var lastProcessedDragTime: CFTimeInterval = 0
    private let dragProcessingInterval: CFTimeInterval = 1.0 / 30.0

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

 // MARK: - Private Helpers
    
 /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
    }

    func startMonitoring() {
        stopMonitoring()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }

            let newContent = self.dragPasteboard.changeCount != self.pasteboardChangeCount
            if newContent {
                self.pasteboardChangeCount = self.dragPasteboard.changeCount
            }

            if newContent && !self.isContentDragging && self.hasValidDragContent() {
                self.isContentDragging = true
            }

            guard self.isContentDragging else { return }

            let now = CACurrentMediaTime()
            guard (now - self.lastProcessedDragTime) >= self.dragProcessingInterval else { return }
            self.lastProcessedDragTime = now

            let mouseLocation = NSEvent.mouseLocation

            let containsMouse = self.notchRegion.contains(mouseLocation)
            if containsMouse && !self.hasEnteredNotchRegion {
                self.hasEnteredNotchRegion = true
                self.onDragEntersNotchRegion?()
            } else if !containsMouse && self.hasEnteredNotchRegion {
                self.hasEnteredNotchRegion = false
                self.onDragExitsNotchRegion?()
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }
            
            self.isDragging = false
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.pasteboardChangeCount = -1
            self.lastProcessedDragTime = 0
        }
    }

    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
        lastProcessedDragTime = 0
    }

    deinit {
        stopMonitoring()
    }
}
