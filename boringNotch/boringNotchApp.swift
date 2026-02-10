//
// boringNotchApp.swift
// boringNotchApp
//
// Created by Harsh Vardhan Goswami on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI
import CoreGraphics
import SkyLightWindow
import QuartzCore

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
    // Ensure the Menu Bar icon is OFF by default on a clean install / after preferences reset.
    // If the user has already chosen a value, we preserve it.
        if UserDefaults.standard.object(forKey: "menubarIcon") == nil {
            Defaults[.menubarIcon] = false
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("QuartzNotch", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                SettingsWindowController.shared.showWindow()
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Boring Notch") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: BoringViewModel] = [:] // UUID -> BoringViewModel
    var window: NSWindow?
    let vm: BoringViewModel = .init()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector

  // Dedicated window for the lock activity on the lock screen
    private let lockScreenActivityWindow = LockScreenLiveActivityWindowManager.shared

    private func applyDockIconIfNeeded() {
        // Ensure Dock/app switcher always gets a concrete icon image even if system cache is stale.
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = icon
            return
        }
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true

    // During the lock transition, suppress any closed-notch live activity
    // in the main window to avoid visual conflicts with the lock overlay.
        LockTransitionState.shared.begin()

    // Feeds SwiftUI state (for in-notch rendering when needed)
        LockScreenState.shared.setLocked(true)

    // Dedicated lock-screen window (robust: works even if the main window
    // is not allowed or visible on the lock screen)
        if Defaults[.showOnLockScreen] && Defaults[.liveActivityLockScreen] {
            lockScreenActivityWindow.showLocked(
                preferredScreenUUID: coordinator.preferredScreenUUID
            )
        }

        if !Defaults[.showOnLockScreen] {
            hideNotchWindowsForLock()
        } else {
      // Important: do NOT SkyLight-delegate the main notch window(s) during lock.
      // Doing so can force a Space re-attachment on unlock and switch to an existing fullscreen Space.
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false

        LockScreenState.shared.setLocked(false)

    // Keep main-window activities suppressed until the unlock transition finishes.
        LockTransitionState.shared.begin()

        if Defaults[.showOnLockScreen] && Defaults[.liveActivityLockScreen] {
            lockScreenActivityWindow.showUnlockedAndHide {
                Task { @MainActor in
                    LockTransitionState.shared.end()
                }
            }
        } else {
      // No lock-screen live activity: end suppression immediately.
            lockScreenActivityWindow.hideImmediately()
            Task { @MainActor in
                LockTransitionState.shared.end()
            }
        }

    // IMPORTANT (Spaces): do not touch the main notch window(s) immediately on unlock.
    // Repositioning / ordering too early is a common trigger for "jump to an existing fullscreen Space".
    // The lock-screen overlay window handles visuals; we restore the notch windows after the transition.
        Task { @MainActor in
      // Small delay = let WindowServer settle the active Space after unlock.
            try? await Task.sleep(for: .milliseconds(450))
            self.adjustWindowPosition(changeAlpha: false)
            if !Defaults[.showOnLockScreen] { self.showNotchWindowsAfterUnlock() }}
    }

    
    @MainActor
    private func hideNotchWindowsForLock() {
    // We avoid closing/recreating windows during the lock/unlock transition because
    // attaching a window back into the private notch Space (CGSSpace) is a common trigger
    // for macOS "jumping" to an existing fullscreen Space on unlock.
        if Defaults[.showOnAllDisplays] {
            for w in windows.values {
                w.alphaValue = 0
                w.orderOut(nil)
            }
        } else if let w = window {
            w.alphaValue = 0
            w.orderOut(nil)
        }
    }

    @MainActor
    private func showNotchWindowsAfterUnlock() {
    // Restore visibility without tearing down / re-attaching to Spaces.
        if Defaults[.showOnAllDisplays] {
            for w in windows.values {
                w.alphaValue = 1
                w.orderFront(nil)
            }
        } else if let w = window {
            w.alphaValue = 1
            w.orderFront(nil)
        }
    }

private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
    // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

    // Avoid orderFrontRegardless(): it can cause Space jumps (especially around lock/unlock).
    // With a non-activating panel, orderFront(nil) is sufficient to show the window.
        window.orderFront(nil)
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

    // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIconIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: false)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: false)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

    // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createBoringNotchWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: false)
        } else {
            adjustWindowPosition(changeAlpha: false)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        }

        previousScreens = NSScreen.screens
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

      // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

      // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = BoringViewModel(screenUUID: uuid)
                    let window = createBoringNotchWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createBoringNotchWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFront(nil)
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//            NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//    NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}

// MARK: - Lock Screen Live Activity Window

// MARK: - Lock Screen Live Activity Window

@MainActor
final class LockScreenLiveActivityWindowManager {
    static let shared = LockScreenLiveActivityWindowManager()

  // Lock-screen window (SkyLight).
    private var lockWindow: NSWindow?
    private var lockHosting: NSHostingView<AnyView>?

  // Desktop window used during unlock transition.
    private var desktopWindow: NSWindow?
    private var desktopHosting: NSHostingView<AnyView>?

  // Two separate models prevent state contamination
    private let lockModel = LockScreenLiveActivityOverlayModel()
    private let desktopModel = LockScreenLiveActivityOverlayModel()

    private var hideTask: Task<Void, Never>?
    private var isUnlockRunning = false

  // Geometry cache (avoids mismatch)
    private var lastScreenUUID: String?
    private var lastNotchSize: CGSize?
    private var lastTotalWidth: CGFloat?
    
  // Cover window (anti-flicker)
    private var coverWindow: NSWindow?
    private var coverHosting: NSHostingView<AnyView>?

  // MARK: - Public

  /// Show the "locked" overlay on the requested screen.
  /// - Note: if `preferredScreenUUID` is nil or invalid, fallback to the main screen.
    func showLocked(preferredScreenUUID: String?) {
        hideTask?.cancel()
        hideTask = nil
        isUnlockRunning = false

    // Keep desktop window invisible during lock.
        desktopModel.hide()
        desktopWindow?.alphaValue = 0
        desktopWindow?.orderOut(nil)

        let screen: NSScreen = {
            if let uuid = preferredScreenUUID,
               let s = NSScreen.screen(withUUID: uuid) { return s }
            return NSScreen.main ?? NSScreen.screens.first!
        }()

        lastScreenUUID = screen.displayUUID

        let notchSize = getClosedNotchSize(screenUUID: screen.displayUUID)
        let (totalWidth, rect) = makeRect(for: notchSize)
        lastNotchSize = notchSize
        lastTotalWidth = totalWidth

        ensureLockWindow(rect: rect, notchSize: notchSize, totalWidth: totalWidth)
        positionWindow(lockWindow!, on: screen, width: totalWidth, height: notchSize.height)

        if let lockWindow {
            SkyLightOperator.shared.delegateWindow(lockWindow)
            lockWindow.alphaValue = 1
            lockWindow.orderFront(nil)
        }

    // Important: start from a hidden state (otherwise no animation can run).
        lockModel.hide()

    // Start a single animation immediately (without visible steps).
        Task { @MainActor in
            var tx0 = Transaction()
            tx0.disablesAnimations = true
            withTransaction(tx0) {
                lockModel.setLocked(resetBlur: false)
                lockModel.widthScale = 0.72
                lockModel.opacity = 1
                lockModel.iconBlur = 10
            }

            withAnimation(NotchMotion.lockReveal) {
                lockModel.widthScale = 1
                lockModel.iconBlur = 0
            }
        }
    }

    func showUnlockedAndHide(onFinished: (() -> Void)? = nil) {
        if isUnlockRunning { return }
        isUnlockRunning = true
        hideTask?.cancel()

        hideTask = Task { @MainActor in
            defer {
                self.isUnlockRunning = false
                onFinished?()
            }

      // Important:
      // The short black background flicker came from the lockWindow -> desktopWindow
      // handoff (two windows, two hosting passes, and one to two non-deterministic
      // composition frames depending on GPU / WindowServer).
      // To remove this robustly, do not swap windows: reuse lockWindow (SkyLight)
      // for unlock + collapse, then orderOut and remove delegate at the end.

            let screen: NSScreen = {
                if let uuid = lastScreenUUID, let s = NSScreen.screen(withUUID: uuid) { return s }
                return NSScreen.main ?? NSScreen.screens.first!
            }()

            let notchSize = lastNotchSize ?? getClosedNotchSize(screenUUID: screen.displayUUID)
            let (totalWidth, rect) = makeRect(for: notchSize)

      // Reuse lockWindow when available (nominal path).
            if let lockWindow {
        // Ensure exact geometry (no AppKit animation).
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    lockWindow.animator().alphaValue = 1
                }
                lockWindow.setFrame(rect, display: true)
                positionWindow(lockWindow, on: screen, width: totalWidth, height: notchSize.height)

                if let cv = lockWindow.contentView {
                    cv.layoutSubtreeIfNeeded()
                    cv.needsDisplay = true
                    cv.displayIfNeeded()
                }
                lockWindow.displayIfNeeded()
                CATransaction.flush()

        // Start the lock animation (without modifying the Lottie itself).
                lockModel.setUnlocked(resetBlur: false)

        // Wait for lock icon animation, then run collapse + fade.
        // Slightly longer guard to avoid any overlap where width collapse starts
        // before the unlock icon motion has visually completed.
                try? await Task.sleep(nanoseconds: 960_000_000)

                await hideDesktopWithAnimation(
                    desktopWindow: lockWindow,
                    model: lockModel,
                    notchSize: notchSize,
                    totalWidth: totalWidth
                )

                lockModel.hide()
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    lockWindow.animator().alphaValue = 0
                }
                lockWindow.orderOut(nil)
                SkyLightOperator.shared.undelegateWindow(lockWindow)
                self.lockWindow = nil
                self.lockHosting = nil
                return
            }

      // Rare fallback if lockWindow is unavailable: keep desktop path unchanged.
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                desktopModel.setLocked()
                desktopModel.opacity = 1
                desktopModel.widthScale = 1
            }

            ensureDesktopWindow(rect: rect, notchSize: notchSize, totalWidth: totalWidth)
            guard let desktopWindow else { return }

            positionWindow(desktopWindow, on: screen, width: totalWidth, height: notchSize.height)
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                desktopWindow.animator().alphaValue = 1
            }
            desktopWindow.orderFront(nil)
            desktopModel.setUnlocked(resetBlur: false)
            try? await Task.sleep(nanoseconds: 960_000_000)
            await hideDesktopWithAnimation(desktopWindow: desktopWindow, model: desktopModel, notchSize: notchSize, totalWidth: totalWidth)
            desktopModel.hide()
            desktopWindow.alphaValue = 0
            desktopWindow.orderOut(nil)
        }
    }

  // MARK: - Desktop dismiss animation (lock/unlock style)

    private func hideDesktopWithAnimation(
        desktopWindow: NSWindow,
        model: LockScreenLiveActivityOverlayModel,
        notchSize: CGSize,
        totalWidth: CGFloat
    ) async {
    // Unlock dismiss: single-phase (no multi-speed stepping).
        let duration: TimeInterval = 0.34

        let safeTotalWidth = max(totalWidth, 1)
        let collapsedScale = max(0.001, min(1.0, notchSize.width / safeTotalWidth))

    // 0) Cancel any residual AppKit alpha animation (common one-frame flash source).
        await NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            desktopWindow.animator().alphaValue = 1
        }

    // 1) Ensure overlay opacity is fully set, without animation.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            model.opacity = 1
        }

    // 2) Single visual phase: width collapse only (no mid-animation fade).
        withAnimation(NotchMotion.lockDismiss) {
            model.widthScale = collapsedScale
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        desktopWindow.alphaValue = 0
    }

    func hideImmediately() {
        hideTask?.cancel()
        hideTask = nil
        isUnlockRunning = false

        lockModel.hide()
        desktopModel.hide()

        lockWindow?.alphaValue = 0
        lockWindow?.orderOut(nil)

        desktopWindow?.alphaValue = 0
        desktopWindow?.orderOut(nil)
    }

  // MARK: - Internals (Geometry)

    private func makeRect(for notchSize: CGSize) -> (CGFloat, NSRect) {
        let indicatorSide = max(0, notchSize.height - 12)
        let totalWidth = notchSize.width + indicatorSide * 2 + cornerRadiusInsets.closed.bottom * 2
        let rect = NSRect(x: 0, y: 0, width: totalWidth, height: notchSize.height)
        return (totalWidth, rect)
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, width: CGFloat, height: CGFloat) {
        let screenFrame = screen.frame
        window.setFrameOrigin(NSPoint(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height))
    }

  // MARK: - Internals (Windows)

    private func ensureLockWindow(rect: NSRect, notchSize: CGSize, totalWidth: CGFloat) {
        if lockWindow == nil {
            let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
            let w = NSWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false

            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let root = LockScreenLiveActivityOverlay(model: lockModel, notchSize: notchSize)
                .frame(width: totalWidth, height: notchSize.height)
                .ignoresSafeArea()

            let hosting = NSHostingView(rootView: AnyView(root))
            w.contentView = hosting

            lockWindow = w
            lockHosting = hosting
        } else {
            lockWindow?.setFrame(rect, display: true)

            if let hosting = lockHosting {
                let root = LockScreenLiveActivityOverlay(model: lockModel, notchSize: notchSize)
                    .frame(width: totalWidth, height: notchSize.height)
                    .ignoresSafeArea()
                hosting.rootView = AnyView(root)
            }
        }
    }

    private func ensureDesktopWindow(rect: NSRect, notchSize: CGSize, totalWidth: CGFloat) {
        if desktopWindow == nil {
            let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
            let w = NSWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false

            w.level = .mainMenu + 3
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let root = LockScreenLiveActivityOverlay(model: desktopModel, notchSize: notchSize)
                .frame(width: totalWidth, height: notchSize.height)
                .ignoresSafeArea()

            let hosting = NSHostingView(rootView: AnyView(root))
            w.contentView = hosting

            desktopWindow = w
            desktopHosting = hosting
        } else {
            desktopWindow?.setFrame(rect, display: true)

            if let hosting = desktopHosting {
                let root = LockScreenLiveActivityOverlay(model: desktopModel, notchSize: notchSize)
                    .frame(width: totalWidth, height: notchSize.height)
                    .ignoresSafeArea()
                hosting.rootView = AnyView(root)
            }
        }
    }

  // MARK: - Manual animation (60fps, deterministic)

    private func animateWidthScaleEaseOut(model: LockScreenLiveActivityOverlayModel,
                                         from: CGFloat, to: CGFloat, duration: TimeInterval) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = easeOutCubic(t)
            model.widthScale = lerp(from, to, eased)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }
    }

  /// Three-speed curve without discontinuity (C1 continuous) to avoid
  /// perceived micro-stutter between phases 2 and 3.
  ///
  /// Implementation: three-segment Hermite spline.
  /// - t in [0..1] (time)
  /// - p in [0..1] (progress)
  /// Controls points (t, p) and dp/dt slopes at segment joints.
    private func animateWidthScaleOrganicSpline(model: LockScreenLiveActivityOverlayModel,
                                                from: CGFloat, to: CGFloat, duration: TimeInterval) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))

    // Split timing (3 phases)
        let t0: CGFloat = 0
        let t1: CGFloat = 0.40
        let t2: CGFloat = 0.93
        let t3: CGFloat = 1

    // Strong non-linearity without aggressive overshoot.
        let p0: CGFloat = 0
        let p1: CGFloat = 0.56
        let p2: CGFloat = 0.97
        let p3: CGFloat = 1

    // Start cushioned, stronger mid section, then long damped landing.
        let m0: CGFloat = 0.08
        let m1: CGFloat = 1.20
        let m2: CGFloat = 0.06
        let m3: CGFloat = 0.0

        func hermite(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat, _ ma: CGFloat, _ mb: CGFloat, _ h: CGFloat) -> CGFloat {
            let uu = max(0, min(1, u))
            let uu2 = uu * uu
            let uu3 = uu2 * uu
            let h00 = 2*uu3 - 3*uu2 + 1
            let h10 = uu3 - 2*uu2 + uu
            let h01 = -2*uu3 + 3*uu2
            let h11 = uu3 - uu2
            return h00*a + h10*(h*ma) + h01*b + h11*(h*mb)
        }

        func splineProgress(_ t: CGFloat) -> CGFloat {
            if t <= t1 {
                let h = (t1 - t0)
                let u = (t - t0) / h
                return hermite(u, p0, p1, m0, m1, h)
            } else if t <= t2 {
                let h = (t2 - t1)
                let u = (t - t1) / h
                return hermite(u, p1, p2, m1, m2, h)
            } else {
                let h = (t3 - t2)
                let u = (t - t2) / h
                return hermite(u, p2, p3, m2, m3, h)
            }
        }

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = max(0, min(1.0, splineProgress(t)))
            model.widthScale = lerp(from, to, p)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }

        model.widthScale = to
    }

    private func animateLockRevealOrganic(
        model: LockScreenLiveActivityOverlayModel,
        duration: TimeInterval,
        maxBlur: CGFloat
    ) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))

        func hermite(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat, _ ma: CGFloat, _ mb: CGFloat, _ h: CGFloat) -> CGFloat {
            let uu = max(0, min(1, u))
            let uu2 = uu * uu
            let uu3 = uu2 * uu
            let h00 = 2*uu3 - 3*uu2 + 1
            let h10 = uu3 - 2*uu2 + uu
            let h01 = -2*uu3 + 3*uu2
            let h11 = uu3 - uu2
            return h00*a + h10*(h*ma) + h01*b + h11*(h*mb)
        }

    // Horizontal reveal profile: non-linear and fluid, but no visible bounce spike.
        let t0: CGFloat = 0
        let t1: CGFloat = 0.16
        let t2: CGFloat = 0.84
        let t3: CGFloat = 1

        let p0: CGFloat = 0
        let p1: CGFloat = 0.24
        let p2: CGFloat = 0.94
        let p3: CGFloat = 1

        let m0: CGFloat = 0.44
        let m1: CGFloat = 1.02
        let m2: CGFloat = 0.20
        let m3: CGFloat = 0

        func widthProgress(_ t: CGFloat) -> CGFloat {
            if t <= t1 {
                let h = t1 - t0
                let u = (t - t0) / h
                return hermite(u, p0, p1, m0, m1, h)
            } else if t <= t2 {
                let h = t2 - t1
                let u = (t - t1) / h
                return hermite(u, p1, p2, m1, m2, h)
            } else {
                let h = t3 - t2
                let u = (t - t2) / h
                return hermite(u, p2, p3, m2, m3, h)
            }
        }

        func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
            if x <= a { return 0 }
            if x >= b { return 1 }
            let u = (x - a) / (b - a)
            return u * u * (3 - 2 * u)
        }

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let w = max(0.01, min(1.0, widthProgress(t)))

      // Fast visibility ramp, then stable.
            let o = smoothstep(0.00, 0.32, t)

      // Keep blur early, then sharpen aggressively in the second half.
            let blurDrop = smoothstep(0.16, 0.97, t)
            let blur = maxBlur * pow(max(0, 1 - blurDrop), 1.35)

            model.widthScale = w
            model.opacity = o
            model.iconBlur = blur
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }

        model.widthScale = 1
        model.opacity = 1
        model.iconBlur = 0
    }

    private func animateOpacityEaseOut(model: LockScreenLiveActivityOverlayModel,
                                       from: CGFloat, to: CGFloat, duration: TimeInterval) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = easeOutCubic(t)
            model.opacity = lerp(from, to, eased)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }
    }

    private func animateWidthScaleBackEase(model: LockScreenLiveActivityOverlayModel,
                                          from: CGFloat, to: CGFloat, duration: TimeInterval, overshoot: CGFloat) async {
        let dt: TimeInterval = 1.0 / 60.0
        let steps = max(1, Int(duration / dt))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = easeOutBack(t, s: overshoot)
            model.widthScale = lerp(from, to, eased)
            try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let p = 1 - t
        return 1 - (p * p * p)
    }

    private func easeOutBack(_ t: CGFloat, s: CGFloat) -> CGFloat {
        let c1 = s * 10.0
        let c3 = c1 + 1.0
        let x = t - 1.0
        return 1.0 + (c3 * x * x * x) + (c1 * x * x)
    }
}

@MainActor
final class LockScreenLiveActivityOverlayModel: ObservableObject {
    enum Mode { case hidden, locked, unlocked }

    @Published private(set) var mode: Mode = .hidden
    @Published var opacity: CGFloat = 0
  /// Horizontal expand/collapse only. This avoids the "drop from the top" feel.
    @Published var widthScale: CGFloat = 0.01
  /// Slight blur on the lock icon only (appearance/disappearance).
    @Published var iconBlur: CGFloat = 0

    func setLocked(resetBlur: Bool = true) {
        mode = .locked
        opacity = 1
        widthScale = 1
        if resetBlur { iconBlur = 0 }
    }

    func setUnlocked(resetBlur: Bool = true) {
        mode = .unlocked
        opacity = 1
        widthScale = 1
        if resetBlur { iconBlur = 0 }
    }

  /// Collapse the overlay horizontally while keeping it pinned.
  /// We keep opacity at 1 so the disappearance reads as a width collapse (like music).
    func collapseForDismiss() {
        widthScale = 0.01
    }

    func hide() {
        mode = .hidden
        opacity = 0
        widthScale = 0.01
        iconBlur = 0
    }
}

struct LockScreenLiveActivityOverlay: View {
    @ObservedObject var model: LockScreenLiveActivityOverlayModel
    let notchSize: CGSize

  // Match the same feel as closed live activities.
    private let topCornerRadius: CGFloat = 7

    private var indicatorSide: CGFloat { max(0, notchSize.height - 12) }
    private var totalWidth: CGFloat {
        notchSize.width + indicatorSide * 2 + cornerRadiusInsets.closed.bottom * 2
    }

    var body: some View {
        HStack(spacing: 0) {
            indicator
                .frame(width: indicatorSide, height: indicatorSide)
                .padding(.leading, cornerRadiusInsets.closed.bottom)

            Rectangle()
                .fill(.black)
                .frame(width: notchSize.width - topCornerRadius)

      // "Fake" right indicator for visual symmetry.
            Color.clear
                .frame(width: indicatorSide, height: indicatorSide)
                .padding(.trailing, cornerRadiusInsets.closed.bottom)
        }
        .frame(width: totalWidth, height: notchSize.height)
        .background(.black)
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: cornerRadiusInsets.closed.bottom
            )
        )
        .opacity(model.opacity)
    // Expand/collapse horizontally only: avoids the "drop from top" feel.
        .scaleEffect(x: model.widthScale, y: 1.0, anchor: .top)
        .compositingGroup()
    }

    @ViewBuilder
    private var indicator: some View {
    // A single animated icon that transitions between locked/unlocked.
    // (Uses lock_icon_animation.json)
    // NOTE:
    // Applying SwiftUI .blur() directly to a Lottie view can be unreliable on macOS.
    // With drawingGroup, the icon can rasterize as a gray square. Use a robust blur by
    // generating an icon snapshot, applying CoreImage Gaussian blur, and crossfading
    // only during the first and last moments.
        LockIconAnimatedBlurView(
            isLocked: model.mode != .unlocked,
            size: 16,
            iconColor: .white,
            blurRadius: model.iconBlur
        )
    }
}
