
import Cocoa
import SkyLightWindow
import Defaults
import Combine

/// Call this ONCE, as early as possible in the app lifecycle — before any `SkyLightOperator.shared`
/// access. Registers the process's WindowServer connection as a loginwindow peer via
/// `SLSSetLoginwindowConnection`. Once registered, SkyLight spaces at level 400 created on this
/// connection are anchored inside the loginwindow rendering layer:
///   - On the lock screen  → they appear BELOW the native lock-screen UI (clock, password, widgets)
///                           but ABOVE the wallpaper. Exactly how Liqoria works.
///   - On the normal desktop → behaviour unchanged (no native lock-screen UI to be below).
///
/// Confirmed from Liqoria arm64 disassembly at 0x1001f3d44: this is the very first call after
/// `SLSMainConnectionID()`, performed before any `SLSSpaceCreate`. The call must happen before
/// `SkyLightOperator.shared` is initialised (which is lazy — first access triggers it).
func prepareSkyLightLoginwindowAnchor() {
    typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    typealias F_SLSSetLoginwindowConnection = @convention(c) (Int32) -> Int32
    let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
    guard
        let rawConn = dlsym(handler, "SLSMainConnectionID"),
        let rawLogin = dlsym(handler, "SLSSetLoginwindowConnection")
    else { return }
    let connFn = unsafeBitCast(rawConn, to: F_SLSMainConnectionID.self)
    let loginFn = unsafeBitCast(rawLogin, to: F_SLSSetLoginwindowConnection.self)
    _ = loginFn(connFn())
}

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
        
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

// Routes an NSWindow into a dedicated SkyLight space at absolute level 400
// (kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock), exactly matching the
// mechanism recovered from LiqoriaRecovered/SkyLightRecoveredBridge.swift.
//
// Key findings from the LiqoriaRecovered decompilation:
//
// 1. Liqoria does NOT go BELOW the native lock screen UI — it goes ABOVE it.
//    The backdrop covers the entire screen (incl. native clock/date), then Liqoria
//    reconstructs those elements using LoginUIKit.framework private controllers
//    (LUI2BigTimeViewController, LUI2DateViewController, LUI2StatusViewController).
//
// 2. The real mechanism is SLSAddWindowsToSpaces (not SLSSpaceAddWindowsAndRemoveFromSpaces).
//    Argument order: SLSAddWindowsToSpaces(conn, windowsCFArray, spacesCFArray).
//
// 3. SLSSetLoginwindowConnection is called EVERY time a window is delegated (not just once
//    at startup). The space is created lazily and cached.
//
// 4. Level = kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock (400) for the backdrop,
//    401 for the player, 405 for the login overlay (clock/date).
//
// 5. Before adding to the new space, the window is removed from its current spaces via
//    SLSCopySpacesForWindows + SLSRemoveWindowsFromSpaces.
final class LockScreenBackdropSkyLightOperator {
    static let shared = LockScreenBackdropSkyLightOperator()

    typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    typealias F_SLSSetLoginwindowConnection = @convention(c) (Int32) -> Int32
    typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    typealias F_SLSAddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
    typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
    typealias F_SLSCopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private let handle: UnsafeMutableRawPointer?
    private let fnConn: F_SLSMainConnectionID
    private let fnLogin: F_SLSSetLoginwindowConnection
    private let fnCreate: F_SLSSpaceCreate
    private let fnLevel: F_SLSSpaceSetAbsoluteLevel
    private let fnShow: F_SLSShowSpaces
    private let fnAdd: F_SLSAddWindowsToSpaces
    private let fnRemove: F_SLSRemoveWindowsFromSpaces
    private let fnCopySpaces: F_SLSCopySpacesForWindows?
    /// The absolute level for the lock-screen SkyLight space
    /// (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`, default 400).
    /// Exposed so callers can derive relative levels (e.g. +5 for the LoginUIKit overlay).
    let lockScreenLevel: Int32
    private var spacesByLevel: [Int32: UInt64] = [:]

    private init() {
        let h = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_NOW
        )
        handle = h
        func sym<T>(_ name: String) -> T {
            unsafeBitCast(dlsym(h, name), to: T.self)
        }
        fnConn   = sym("SLSMainConnectionID")
        fnLogin  = sym("SLSSetLoginwindowConnection")
        fnCreate = sym("SLSSpaceCreate")
        fnLevel  = sym("SLSSpaceSetAbsoluteLevel")
        fnShow   = sym("SLSShowSpaces")
        fnAdd    = sym("SLSAddWindowsToSpaces")
        fnRemove = sym("SLSRemoveWindowsFromSpaces")
        fnCopySpaces = dlsym(h, "SLSCopySpacesForWindows")
            .map { unsafeBitCast($0, to: F_SLSCopySpacesForWindows.self) }
            ?? dlsym(h, "CGSCopySpacesForWindows")
                .map { unsafeBitCast($0, to: F_SLSCopySpacesForWindows.self) }

        // Read the exact level constant from the SkyLight binary itself,
        // same as LiqoriaRecovered does via loadMutablePointer.
        let levelPtr = dlsym(h, "kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock")
            .map { $0.assumingMemoryBound(to: Int32.self).pointee }
        lockScreenLevel = levelPtr ?? 400
    }

    /// Delegate `window` to a lock-screen SkyLight space at the given absolute level.
    /// SLSSetLoginwindowConnection is called each time (matches LiqoriaRecovered behaviour).
    @discardableResult
    func delegateWindow(_ window: NSWindow, level: Int32? = nil) -> Int32 {
        let targetLevel = level ?? lockScreenLevel
        let conn = fnConn()
        _ = fnLogin(conn)

        let space: UInt64
        if let existing = spacesByLevel[targetLevel] {
            space = existing
        } else {
            let created = fnCreate(conn, 1, 0)
            guard created != 0 else { return -2 }
            _ = fnLevel(conn, created, targetLevel)
            _ = fnShow(conn, [NSNumber(value: created)] as CFArray)
            spacesByLevel[targetLevel] = created
            space = created
        }

        let windowsCF = [NSNumber(value: window.windowNumber)] as CFArray
        // Remove from current spaces first (matches LiqoriaRecovered step-by-step)
        if let copySpaces = fnCopySpaces,
           let currentSpaces = copySpaces(conn, 7, windowsCF)?.takeRetainedValue(),
           CFArrayGetCount(currentSpaces) > 0 {
            _ = fnRemove(conn, windowsCF, currentSpaces)
        }
        let spacesCF = [NSNumber(value: space)] as CFArray
        return fnAdd(conn, windowsCF, spacesCF)
    }

    func undelegateWindow(_ window: NSWindow) {
        let conn = fnConn()
        let windowsCF = [NSNumber(value: window.windowNumber)] as CFArray
        for space in spacesByLevel.values {
            let spacesCF = [NSNumber(value: space)] as CFArray
            _ = fnRemove(conn, windowsCF, spacesCF)
        }
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var allowsInlineTextInput: Bool = false
    private var recordingContextIsClosed: Bool = true
    private var recordingContextIsInUse: Bool = false
    
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
        
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        updateSharingType()
    }
    
    private func setupObservers() {
        Defaults.publisher(.hideFromScreenRecordingMode)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)

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

        NSApp.activate(ignoringOtherApps: true)
        makeKey()
        orderFront(nil)
    }

    @objc private func handleInlineTextInputEnded() {
        allowsInlineTextInput = false
        resignKey()
    }
    
    private func updateSharingType() {
        let mode = Defaults[.hideFromScreenRecordingMode]
        let shouldHide: Bool
        switch mode {
        case .disabled:
            shouldHide = false
        case .fullyHidden:
            shouldHide = true
        case .onlyWhenClosed:
            shouldHide = recordingContextIsClosed
        case .onlyWhenNotInUse:
            shouldHide = recordingContextIsClosed && !recordingContextIsInUse
        }

        if shouldHide {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }

    func updateScreenRecordingContext(isClosed: Bool, isInUse: Bool) {
        recordingContextIsClosed = isClosed
        recordingContextIsInUse = isInUse
        updateSharingType()
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
