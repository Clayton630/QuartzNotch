//
// ClipboardManager.swift
// boringNotch
//
// Created by AI Assistant on 2026-02-02.
//

import AppKit
import Combine
import SwiftUI
import Carbon.HIToolbox

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var items: [ClipboardItem] = []
    private var changeCount: Int = 0
    private var timer: Timer?
    
    private let maxItems = 10
    private var activeAppObserver: Any?
    private weak var lastExternalActiveApp: NSRunningApplication?
    
    private init() {
    // Initialize changeCount so we don't treat the current pasteboard as a "change" on first tick.
        changeCount = NSPasteboard.general.changeCount
        startTrackingLastExternalActiveApp()
        loadInitialClipboard()
        startMonitoring()
    }
    
    private func startMonitoring() {
    // Use .common run loop mode so the timer continues firing during event tracking (e.g. menu bar / hover).
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }
    
    private func loadInitialClipboard() {
    // Best-effort: capture the current pasteboard content once at startup.
        let pasteboard = NSPasteboard.general

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            addItem(content: string, type: .text)
            return
        }
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            addItem(content: image, type: .image)
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            if urls.count == 1, let url = urls.first {
                addItem(content: url, type: .file)
            } else {
                addItem(content: urls, type: .files)
            }
        }
    }
    
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        
    // Prefer plain text, then images, then URLs/files.
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            addItem(content: string, type: .text)
            return
        }

        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            addItem(content: image, type: .image)
            return
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
      // NOTE: This manager currently represents both file URLs and web URLs using the same cases.
      // UI can still display them (preview uses lastPathComponent for files), but functionality remains.
            if urls.count == 1, let url = urls.first {
                addItem(content: url, type: .file)
            } else {
                addItem(content: urls, type: .files)
            }
        }
    }
    
    private func addItem(content: Any, type: ClipboardItemType) {
    // Avoid duplicates
        if let lastItem = items.first, lastItem.matches(content: content, type: type) {
            return
        }
        
        let newItem = ClipboardItem(content: content, type: type)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.items.insert(newItem, at: 0)
            if self.items.count > self.maxItems {
                self.items.removeLast()
            }
        }
    }
    
    func copyItem(_ item: ClipboardItem) {
        writeItemToPasteboard(item)

        // Legacy behavior: single click on text tries immediate in-place insertion if a text field is focused.
        if item.type == .text, let string = item.content as? String {
            pasteIntoActiveTextField(string)
        }
    }

    /// Double-click behavior for Clipboard UI:
    /// put item on pasteboard, then paste into the previously active text zone.
    func pasteItemIntoLastTextZone(_ item: ClipboardItem) {
        Task { @MainActor in
            // Trigger macOS accessibility prompt automatically if needed.
            let allowed = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            guard allowed else { return }

            writeItemToPasteboard(item)

            // Maccy-like flow:
            // 1) release focus from this app
            // 2) reactivate the last external app that had focus
            // 3) wait a frame for focus + pasteboard sync
            // 4) send Cmd+V to session
            NSApp.deactivate()
            _ = lastExternalActiveApp?.activate(options: [])
            try? await Task.sleep(for: .milliseconds(55))

            if !sendCommandVPasteShortcut(),
               item.type == .text,
               let string = item.content as? String
            {
                // Fallback to local insertion when event posting is unavailable.
                pasteIntoActiveTextField(string)
            }
        }
    }

    private func writeItemToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let string = item.content as? String {
                pasteboard.setString(string, forType: .string)
            }
        case .image:
            if let image = item.content as? NSImage {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let url = item.content as? URL {
                pasteboard.writeObjects([url as NSURL])
            }
        case .files:
            if let urls = item.content as? [URL] {
                pasteboard.writeObjects(urls as [NSURL])
            }
        }
        
        changeCount = pasteboard.changeCount
    }

    private func sendCommandVPasteShortcut() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let keyCodeForV: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        else { return false }

        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }

    private func startTrackingLastExternalActiveApp() {
        activeAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let self = self
            else { return }

            let ownBundleID = Bundle.main.bundleIdentifier
            if app.bundleIdentifier != ownBundleID {
                self.lastExternalActiveApp = app
            }
        }
    }
    
  /// Attempts to paste text directly into the currently focused text field
    private func pasteIntoActiveTextField(_ text: String) {
    // Get the currently focused window and responder
        guard let window = NSApplication.shared.keyWindow,
              let firstResponder = window.firstResponder else {
            return
        }
        
    // Check if the first responder is a text view or text field
        if let textView = firstResponder as? NSTextView {
            textView.insertText(text, replacementRange: textView.selectedRange())
        } else if let textField = firstResponder as? NSTextField {
      // For NSTextField, we need to access its field editor
            if let fieldEditor = window.fieldEditor(false, for: textField) as? NSTextView {
                fieldEditor.insertText(text, replacementRange: fieldEditor.selectedRange())
            }
        }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        }
    }
    
    func clearAll() {
        items.removeAll()
    }
    
    deinit {
        timer?.invalidate()
        if let activeAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeAppObserver)
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let content: Any
    let type: ClipboardItemType
    let timestamp: Date = Date()
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func matches(content: Any, type: ClipboardItemType) -> Bool {
        guard self.type == type else { return false }
        
        switch type {
        case .text:
            return (self.content as? String) == (content as? String)
        case .file:
            return (self.content as? URL) == (content as? URL)
        case .files:
            let selfUrls = self.content as? [URL]
            let otherUrls = content as? [URL]
            return selfUrls == otherUrls
        case .image:
            return false // Images are harder to compare, always add
        }
    }
    
    var preview: String {
        switch type {
        case .text:
            if let string = content as? String {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .file:
            if let url = content as? URL {
                return url.lastPathComponent
            }
        case .files:
            if let urls = content as? [URL] {
                return "\(urls.count) files"
            }
        case .image:
            return "Image"
        }
        return ""
    }
    
    var icon: String {
        switch type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .files: return "folder"
        }
    }
}

enum ClipboardItemType {
    case text
    case image
    case file
    case files
}
