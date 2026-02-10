//
// BoringNotchSkyLightWindow.swift
// boringNotch
//
// Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
    // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var allowsInlineTextInput: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
    // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
    // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
    // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)

    // Allow temporarily becoming key for inline text input (e.g. editing quick timer duration).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInlineTextInputBegan),
            name: .notchTextInputBegan,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInlineTextInputEnded),
            name: .notchTextInputEnded,
            object: nil
        )
    }

    @objc private func handleInlineTextInputBegan() {
        allowsInlineTextInput = true

    // The notch window is normally a non-activating panel. When the user explicitly
    // clicks into a text field, we temporarily allow key status so keyboard input works.
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
        orderFront(nil)
    }

    @objc private func handleInlineTextInputEnded() {
        allowsInlineTextInput = false
        resignKey()
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { allowsInlineTextInput }
    override var canBecomeMain: Bool { allowsInlineTextInput }
}
