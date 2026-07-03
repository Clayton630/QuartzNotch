
import AppKit
import SwiftUI
import Defaults
import Sparkle

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?
    private var hostingView: NSHostingView<SettingsView>?
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        self.updaterController = controller
        setupWindow()
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "Quartz Notch Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("QuartzNotchSettingsWindow")
        
        let settingsView = SettingsView(updaterController: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        self.hostingView = hostingView
        window.contentView = hostingView
        
        window.delegate = self
    }
    
    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        AppIconModeManager.applyCurrentAppIconOverride()
        
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    func refreshWindowForAccentChange() {
        guard let window, window.isVisible == true else { return }
        hostingView?.needsLayout = true
        hostingView?.layoutSubtreeIfNeeded()
        hostingView?.display()
        window.invalidateShadow()
        window.displayIfNeeded()
    }

    override func close() {
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        window?.orderOut(nil)
        
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppIconModeManager.applyCurrentAppIconOverride()
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}
