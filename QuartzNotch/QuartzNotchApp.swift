
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI
import CoreGraphics
import CoreImage
import SkyLightWindow
import QuartzCore
import Darwin

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: UInt32) -> CFArray

final class LockScreenBackdropSharedStore {
    static let shared = LockScreenBackdropSharedStore()

    private let fileQueue = DispatchQueue(label: "quartznotch.lockscreen-backdrop.shared-store", qos: .utility)
    private let colorContext = CIContext(options: [.cacheIntermediates: false])
    private var lastExportFingerprint: String?
    private var didAttemptInstall = false

    private init() {}

    private let backdropDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuartzNotch/LockScreenBackdrop", isDirectory: true)
    }()

    private let artworkURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuartzNotch/LockScreenBackdrop/current-artwork.png", isDirectory: false)
    }()

    private let metadataURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuartzNotch/LockScreenBackdrop/metadata.plist", isDirectory: false)
    }()

    private let installedSaverURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/QuartzNotchBackdrop.saver", isDirectory: true)
    }()

    func prepare() {
        ensureBackdropDirectory()
        installEmbeddedSaverIfNeeded()
    }

    func exportCurrentMediaState() {
        prepare()

        let musicManager = MusicManager.shared
        guard !musicManager.isUsingIdleMetadata else { return }

        let artwork = musicManager.albumArt
        let title = musicManager.songTitle
        let artist = musicManager.artistName
        let album = musicManager.album
        let bundleIdentifier = musicManager.bundleIdentifier

        fileQueue.async { [weak self] in
            guard let self else { return }
            guard let pngData = self.pngData(from: artwork) else { return }

            let fingerprint = self.makeFingerprint(
                title: title,
                artist: artist,
                album: album,
                bundleIdentifier: bundleIdentifier,
                artworkData: pngData
            )
            guard fingerprint != self.lastExportFingerprint else { return }

            let accentColor = self.averageColor(fromPNGData: pngData) ?? NSColor.white.withAlphaComponent(0.12)

            do {
                try pngData.write(to: self.artworkURL, options: .atomic)
                try self.writeMetadata(
                    title: title,
                    artist: artist,
                    album: album,
                    bundleIdentifier: bundleIdentifier,
                    accentColor: accentColor
                )
                self.lastExportFingerprint = fingerprint
            } catch {
                print("Failed to export lock-screen backdrop shared state: \(error)")
            }
        }
    }

    func installedSaverLocation() -> URL {
        installedSaverURL
    }

    private func ensureBackdropDirectory() {
        do {
            try FileManager.default.createDirectory(at: backdropDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create shared backdrop directory: \(error)")
        }
    }

    private func installEmbeddedSaverIfNeeded() {
        guard !didAttemptInstall else { return }
        didAttemptInstall = true

        guard let embeddedSaverURL = Bundle.main.resourceURL?
            .appendingPathComponent("Screen Savers", isDirectory: true)
            .appendingPathComponent("QuartzNotchBackdrop.saver", isDirectory: true),
              FileManager.default.fileExists(atPath: embeddedSaverURL.path) else {
            return
        }

        let installedSaverDirectory = installedSaverURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: installedSaverDirectory, withIntermediateDirectories: true)
            if shouldReplaceInstalledSaver(source: embeddedSaverURL, destination: installedSaverURL) {
                if FileManager.default.fileExists(atPath: installedSaverURL.path) {
                    try FileManager.default.removeItem(at: installedSaverURL)
                }
                try FileManager.default.copyItem(at: embeddedSaverURL, to: installedSaverURL)
            }
        } catch {
            print("Failed to install QuartzNotchBackdrop.saver: \(error)")
        }
    }

    private func shouldReplaceInstalledSaver(source: URL, destination: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return true }
        let sourceValues = try? source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let destinationValues = try? destination.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        if sourceValues?.fileSize != destinationValues?.fileSize {
            return true
        }

        switch (sourceValues?.contentModificationDate, destinationValues?.contentModificationDate) {
        case let (sourceDate?, destinationDate?):
            return sourceDate > destinationDate
        default:
            return false
        }
    }

    private func writeMetadata(
        title: String,
        artist: String,
        album: String,
        bundleIdentifier: String?,
        accentColor: NSColor
    ) throws {
        let calibrated = accentColor.usingColorSpace(.deviceRGB) ?? accentColor
        let metadata: [String: Any] = [
            "title": title,
            "artist": artist,
            "album": album,
            "bundleIdentifier": bundleIdentifier ?? "",
            "accentColorRGBA": [
                NSNumber(value: Double(calibrated.redComponent)),
                NSNumber(value: Double(calibrated.greenComponent)),
                NSNumber(value: Double(calibrated.blueComponent)),
                NSNumber(value: Double(calibrated.alphaComponent))
            ],
            "generatedAt": Date().timeIntervalSince1970
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func averageColor(fromPNGData pngData: Data) -> NSColor? {
        guard let ciImage = CIImage(data: pngData) else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent

        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        colorContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return NSColor(
            calibratedRed: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: 0.12
        )
    }

    private func makeFingerprint(
        title: String,
        artist: String,
        album: String,
        bundleIdentifier: String?,
        artworkData: Data
    ) -> String {
        let prefix = artworkData.prefix(128).base64EncodedString()
        return [title, artist, album, bundleIdentifier ?? "", prefix, String(artworkData.count)].joined(separator: "|")
    }
}

import AppKit
import Foundation

final class LockScreenIdleBackdropCoordinator {
    static let shared = LockScreenIdleBackdropCoordinator()

    private let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist", isDirectory: false)
    private let screenSaverDomain = "com.apple.screensaver" as CFString

    private var originalStoreData: Data?
    private var originalScreenSaverValues: [String: Any?] = [:]
    private var isActive = false

    private init() {}

    func activateIfPossible(saverURL: URL) -> Bool {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return false }
        guard FileManager.default.fileExists(atPath: saverURL.path) else { return false }

        do {
            let currentData = try Data(contentsOf: storeURL)
            if originalStoreData == nil {
                originalStoreData = currentData
            }
            if originalScreenSaverValues.isEmpty {
                originalScreenSaverValues = [
                    "moduleDict": copyScreenSaverPreference(named: "moduleDict"),
                    "moduleName": copyScreenSaverPreference(named: "moduleName"),
                    "path": copyScreenSaverPreference(named: "path"),
                    "override-picture-path": copyScreenSaverPreference(named: "override-picture-path")
                ]
            }

            guard let mutatedData = try makeMutatedStoreData(from: currentData) else {
                return false
            }

            applyScreenSaverOverride(saverURL: saverURL)

            if mutatedData != currentData {
                try mutatedData.write(to: storeURL, options: .atomic)
            }

            reloadWallpaperAgent()
            isActive = true
            return true
        } catch {
            print("Failed to activate lock-screen Idle backdrop: \(error)")
            return false
        }
    }

    func restoreIfNeeded() {
        guard isActive, let originalStoreData else { return }

        defer {
            isActive = false
            self.originalStoreData = nil
            self.originalScreenSaverValues = [:]
        }

        do {
            try originalStoreData.write(to: storeURL, options: .atomic)
            restoreScreenSaverPreferences()
            reloadWallpaperAgent()
        } catch {
            print("Failed to restore lock-screen Idle backdrop store: \(error)")
        }
    }

    private func makeMutatedStoreData(from data: Data) throws -> Data? {
        let plistObject = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: nil
        )
        guard let root = plistObject as? NSMutableDictionary else { return nil }

        var mutatedAnyIdle = false
        mutateIdleEntries(in: root, mutatedAnyIdle: &mutatedAnyIdle)
        guard mutatedAnyIdle else { return nil }

        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func mutateIdleEntries(in object: Any, mutatedAnyIdle: inout Bool) {
        if let dict = object as? NSMutableDictionary {
            if let idle = dict["Idle"] as? NSMutableDictionary {
                dict["Idle"] = configuredIdleEntry()
                mutatedAnyIdle = true
            }

            for value in dict.allValues {
                mutateIdleEntries(in: value, mutatedAnyIdle: &mutatedAnyIdle)
            }
            return
        }

        if let array = object as? NSMutableArray {
            for value in array {
                mutateIdleEntries(in: value, mutatedAnyIdle: &mutatedAnyIdle)
            }
        }
    }

    private func configuredIdleEntry() -> NSMutableDictionary {
        let choice = NSMutableDictionary()
        choice["Provider"] = "default"
        choice["Files"] = NSMutableArray()
        choice["Configuration"] = Data()

        let content = NSMutableDictionary()
        content["Choices"] = NSMutableArray(array: [choice])
        content["EncodedOptionValues"] = "$null"
        content["Shuffle"] = "$null"

        let linked = NSMutableDictionary()
        linked["Content"] = content
        linked["LastSet"] = Date()
        linked["LastUse"] = Date()

        let idleEntry = NSMutableDictionary()
        idleEntry["Type"] = "linked"
        idleEntry["Linked"] = linked
        return idleEntry
    }

    private func applyScreenSaverOverride(saverURL: URL) {
        let moduleDict: [String: Any] = [
            "moduleName": "QuartzNotchBackdrop",
            "path": saverURL.path,
            "type": "0"
        ]

        setScreenSaverPreference(moduleDict, named: "moduleDict")
        setScreenSaverPreference(nil, named: "moduleName")
        setScreenSaverPreference(nil, named: "path")
        setScreenSaverPreference(saverURL.path, named: "override-picture-path")
        synchronizeScreenSaverPreferences()
    }

    private func restoreScreenSaverPreferences() {
        for key in ["moduleDict", "moduleName", "path", "override-picture-path"] {
            setScreenSaverPreference(originalScreenSaverValues[key] ?? nil, named: key)
        }
        synchronizeScreenSaverPreferences()
    }

    private func copyScreenSaverPreference(named key: String) -> Any? {
        CFPreferencesCopyValue(
            key as CFString,
            screenSaverDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private func setScreenSaverPreference(_ value: Any?, named key: String) {
        CFPreferencesSetValue(
            key as CFString,
            value as CFPropertyList?,
            screenSaverDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private func synchronizeScreenSaverPreferences() {
        CFPreferencesSynchronize(
            screenSaverDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private func reloadWallpaperAgent() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["WallpaperAgent"]
        try? killall.run()
        killall.waitUntilExit()
    }
}

private struct CinemaModeRoot: View {
    @Default(.cinemaMode) private var cinemaMode
    @EnvironmentObject var vm: QuartzViewModel

    private let baseW = OpenNotchLayoutMetrics.shellSize.width + openNotchHorizontalOverhang * 2
    private var baseH: CGFloat {
        OpenNotchLayoutMetrics.shellSize.height + OpenNotchLayoutMetrics.lyricsExtraHeight + OpenNotchLayoutMetrics.volumeExtraHeight + shadowPadding
    }

    var body: some View {
        if cinemaMode {
            ContentView()
                .environmentObject(vm)
                .frame(width: baseW, height: baseH)
                .scaleEffect(cinemaModeScale, anchor: .top)
                .frame(
                    width: baseW * cinemaModeScale,
                    height: baseH * cinemaModeScale,
                    alignment: .top
                )
        } else {
            ContentView()
                .environmentObject(vm)
        }
    }
}

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        // Register as loginwindow peer BEFORE SkyLightOperator.shared is ever accessed.
        // Must be the very first SkyLight-related call in the process — see prepareSkyLightLoginwindowAnchor().
        prepareSkyLightLoginwindowAnchor()

        // Eagerly create the level-200 underlay space so it exists before the first lock screen.
        // SLSSetLoginwindowConnection (above) must precede SLSSpaceCreate for the
        // loginwindow peer registration to apply to the newly created space.
        _ = LockScreenBackdropSkyLightOperator.shared

        if UserDefaults.standard.object(forKey: "menubarIcon") == nil {
            Defaults[.menubarIcon] = false
        }
        if UserDefaults.standard.object(forKey: "hideFromScreenRecordingMode") == nil {
            Defaults[.hideFromScreenRecordingMode] = Defaults[.hideFromScreenRecordingLegacy]
                ? .fullyHidden
                : .onlyWhenNotInUse
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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
            Button("Restart Quartz Notch") {
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
    var viewModels: [String: QuartzViewModel] = [:] // UUID -> QuartzViewModel
    var window: NSWindow?
    let vm: QuartzViewModel = .init()
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var pendingScreenConfigurationTask: Task<Void, Never>?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var appCancellables = Set<AnyCancellable>()
    private var lockStateSyncCancellable: AnyCancellable?
    private var lockScreenMediaPanelSyncCancellable: AnyCancellable?
    private var lockScreenMediaHideTask: Task<Void, Never>?
    private var desktopWallpaperRecacheTask: Task<Void, Never>?
    private var unlockWallpaperRestoreTask: Task<Void, Never>?
    private var lastLockScreenMediaActivityAt: Date = .distantPast
    private var windowScreenDidChangeObservers: [ObjectIdentifier: Any] = [:]
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var iconAppearanceObserver: NSObjectProtocol?
    private var dockPreferenceObserver: NSObjectProtocol?

    private let lockScreenActivityWindow = LockScreenLiveActivityWindowManager.shared
    private let lockScreenPanelManager = LockScreenPanelManager.shared

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingScreenConfigurationTask?.cancel()
        AppIconModeManager.stopMonitoringSystemAppearance()
        NotificationCenter.default.removeObserver(self)
        lockStateSyncCancellable?.cancel()
        lockStateSyncCancellable = nil
        lockScreenMediaPanelSyncCancellable?.cancel()
        lockScreenMediaPanelSyncCancellable = nil
        if let observer = iconAppearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            iconAppearanceObserver = nil
        }
        if let observer = dockPreferenceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dockPreferenceObserver = nil
        }
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        lockScreenPanelManager.hidePanel()
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        desktopWallpaperRecacheTask?.cancel()
        desktopWallpaperRecacheTask = nil
        unlockWallpaperRestoreTask?.cancel()
        unlockWallpaperRestoreTask = nil

        LockScreenDesktopOverrideCoordinator.shared.cacheCurrentDesktopImages(includeRawSnapshots: false)

        LockTransitionState.shared.begin()

        LockScreenState.shared.setLocked(true)

        if Defaults[.showOnLockScreen] {
            if Defaults[.liveActivityLockScreen] {
                // Force main-screen lock overlay to avoid rendering on an off-target display.
                lockScreenActivityWindow.showLocked(preferredScreenUUID: nil)
            } else {
                lockScreenActivityWindow.hideImmediately()
            }
            syncLockScreenActivityPanelVisibility()
        }

        if !Defaults[.showOnLockScreen] {
            lockScreenPanelManager.hidePanel()
            hideNotchWindowsForLock()
        } else {
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        desktopWallpaperRecacheTask?.cancel()
        desktopWallpaperRecacheTask = nil
        unlockWallpaperRestoreTask?.cancel()
        unlockWallpaperRestoreTask = nil

        if Defaults[.showOnLockScreen] {
            let unlockScreen = NSScreen.screens.first(where: { $0.localizedName == "Built-in Retina Display" }) ?? NSScreen.main
            let unlockRestoreImage = LockScreenDesktopOverrideCoordinator.shared.currentGeneratedImage()
            if Defaults[.liveActivityLockScreen] {
                if let unlockScreen, let unlockRestoreImage {
                    if lockScreenActivityWindow.hasPreparedDesktopRestoreCover {
                        lockScreenActivityWindow.presentPreparedDesktopRestoreCover(on: unlockScreen)
                    } else {
                        lockScreenActivityWindow.showDesktopRestoreCover(image: unlockRestoreImage, on: unlockScreen)
                    }
                } else {
                    lockScreenActivityWindow.hideDesktopRestoreCoverImmediately()
                }
            } else {
                lockScreenActivityWindow.hideImmediately()
            }

            LockScreenState.shared.setLocked(false)
            LockTransitionState.shared.begin()

            lockScreenPanelManager.hidePanelForUnlock(rememberExpandedStateForNextShow: true)

            if Defaults[.liveActivityLockScreen] {
                lockScreenActivityWindow.showUnlockedAndHide { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        if let unlockScreen, let unlockRestoreImage {
                            self.unlockWallpaperRestoreTask?.cancel()
                            self.unlockWallpaperRestoreTask = Task { [weak self] in
                                await LockScreenDesktopOverrideCoordinator.shared.restoreIfNeededAndWaitForDesktopReady(on: unlockScreen)
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    self?.lockScreenActivityWindow.hideDesktopRestoreCover(after: 0.06, duration: 0.22)
                                    self?.unlockWallpaperRestoreTask = nil
                                    LockTransitionState.shared.end()
                                }
                            }
                        } else if let unlockScreen {
                            LockScreenDesktopOverrideCoordinator.shared.restoreIfNeededForUnlock(on: unlockScreen)
                            self.unlockWallpaperRestoreTask = nil
                            LockTransitionState.shared.end()
                        } else {
                            LockScreenDesktopOverrideCoordinator.shared.restoreIfNeeded()
                            self.unlockWallpaperRestoreTask = nil
                            LockTransitionState.shared.end()
                        }
                    }
                }
            } else {
                LockTransitionState.shared.end()
            }

        } else {
            LockScreenState.shared.setLocked(false)
            LockTransitionState.shared.begin()
            lockScreenPanelManager.hidePanel()
            lockScreenActivityWindow.hideImmediately()
            Task { @MainActor in
                LockTransitionState.shared.end()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.adjustWindowPosition(changeAlpha: false)
            if !Defaults[.showOnLockScreen] { self.showNotchWindowsAfterUnlock() }}

        desktopWallpaperRecacheTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !self.isScreenLocked else { return }
            LockScreenDesktopOverrideCoordinator.shared.cacheCurrentDesktopImages()
            self.desktopWallpaperRecacheTask = nil
        }
    }

    @MainActor
    private var activeQuickTimersForLockScreen: [QuickTimer] {
        var timers = QuickTimerManager.shared.timers
            .filter { $0.remainingSeconds > 0 || $0.didFinish }

        if let mirrored = QuickTimerManager.shared.mirroredSystemQuickTimer {
            timers.append(mirrored)
        }

        return timers
    }

    private var shouldShowLockScreenTimerPanel: Bool {
        guard Defaults[.showOnLockScreen] else { return false }
        guard Defaults[.enableLockScreenTimerWidget] else { return false }
        if QuickTimerManager.shared.mirroredSystemQuickTimer == nil {
            guard Defaults[.liveActivityTimerEnabled] else { return false }
        }
        return !activeQuickTimersForLockScreen.isEmpty
    }

    @MainActor
    private func syncLockScreenActivityPanelVisibility() {
        guard isScreenLocked else {
            lockScreenMediaHideTask?.cancel()
            lockScreenMediaHideTask = nil
            lockScreenPanelManager.hidePanel(preserveExpandedStateForNextShow: true)
            return
        }

        let hasUsableMedia = !MusicManager.shared.isUsingIdleMetadata
        if !hasUsableMedia {
            lastLockScreenMediaActivityAt = .distantPast
        }

        let hasRealArtwork = hasUsableMedia && !MusicManager.shared.albumArt.isEqual(defaultImage)
        let hasRealText =
            hasUsableMedia
            &&
            !MusicManager.shared.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isMediaStillWarm = hasUsableMedia && Date().timeIntervalSince(lastLockScreenMediaActivityAt) < 2.0

        let shouldShowMediaPanel =
            Defaults[.showOnLockScreen]
            && Defaults[.enableLockScreenMediaWidget]
            && (hasRealText || hasRealArtwork || isMediaStillWarm)

        if shouldShowMediaPanel || shouldShowLockScreenTimerPanel {
            lockScreenMediaHideTask?.cancel()
            lockScreenMediaHideTask = nil
            lockScreenPanelManager.showPanel(showMediaCard: shouldShowMediaPanel)
        } else {
            lockScreenMediaHideTask?.cancel()
            lockScreenMediaHideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard let self else { return }
                guard self.isScreenLocked else { return }
                let hasUsableMedia = !MusicManager.shared.isUsingIdleMetadata
                if !hasUsableMedia {
                    self.lastLockScreenMediaActivityAt = .distantPast
                }

                let hasRealArtwork = hasUsableMedia && !MusicManager.shared.albumArt.isEqual(defaultImage)
                let hasRealText =
                    hasUsableMedia
                    &&
                    !MusicManager.shared.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isMediaStillWarm = hasUsableMedia && Date().timeIntervalSince(self.lastLockScreenMediaActivityAt) < 2.0
                let shouldStillShowMedia =
                    Defaults[.showOnLockScreen]
                    && Defaults[.enableLockScreenMediaWidget]
                    && (hasRealText || hasRealArtwork || isMediaStillWarm)
                let shouldStillHide = !shouldStillShowMedia && !self.shouldShowLockScreenTimerPanel
                if shouldStillHide {
                    self.lockScreenPanelManager.hidePanel()
                }
            }
        }
    }

    
    @MainActor
    private func hideNotchWindowsForLock() {
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
                tearDownNotchWindow(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            tearDownNotchWindow(window)
            self.window = nil
        }
    }

    private func removeWindowScreenDidChangeObserver(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let observer = windowScreenDidChangeObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @MainActor
    private func tearDownNotchWindow(_ window: NSWindow) {
        removeWindowScreenDidChangeObserver(for: window)
        if let skyLightWindow = window as? QuartzNotchSkyLightWindow {
            skyLightWindow.disableSkyLight()
        }
        window.contentView = nil
        window.orderOut(nil)
        window.close()
        NotchSpaceManager.shared.notchSpace.windows.remove(window)
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
        let openSize = getOpenNotchSize(screenUUID: uuid)
        let notchHeight = openSize.height
        let notchWidth = openSize.width
        
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
        guard Defaults[.boringShelf] else { return }
        guard Defaults[.pageShelfEnabled] || Defaults[.allowShelfRevealWhenPageHidden] else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createQuartzNotchWindow(for screen: NSScreen, with viewModel: QuartzViewModel) -> NSWindow {
        let windowSize = getWindowSize(screenUUID: screen.displayUUID)
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = QuartzNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        let hostingView = NSHostingView(
            rootView: CinemaModeRoot()
                .environmentObject(viewModel)
        )
        // The notch window already reserves the physical notch area in its own
        // layout. On integrated MacBook displays, letting SwiftUI keep the
        // system safe area adds that top inset a second time and pushes open
        // content down. External displays do not expose the same inset, which
        // is why the bug only showed up on larger built-in notched panels.
        hostingView.safeAreaRegions = []
        window.contentView = hostingView

        window.orderFront(nil)
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        windowScreenDidChangeObservers[ObjectIdentifier(window)] = observer
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        let targetSize = getWindowSize(screenUUID: screen.displayUUID)
        let targetOrigin = NSPoint(
            x: screenFrame.origin.x + (screenFrame.width / 2) - targetSize.width / 2,
            y: screenFrame.origin.y + screenFrame.height - targetSize.height
        )
        window.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSColor.enableControlAccentColorOverride()
        NSColor.applyEffectiveAccentOverride()
        AppIconModeManager.applyCurrentAppIconOverride()
        AppIconModeManager.startMonitoringSystemAppearance()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            LockScreenDesktopOverrideCoordinator.shared.warmUpAccessIfNeeded()
            LockScreenDesktopOverrideCoordinator.shared.cacheCurrentDesktopImages()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReopenOnboardingSetup),
            name: .reopenOnboardingSetup,
            object: nil
        )

        iconAppearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            AppIconModeManager.applyCurrentAppIconOverride()
        }

        dockPreferenceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            queue: .main
        ) { _ in
            AppIconModeManager.applyCurrentAppIconOverride()
        }

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

        Defaults.publisher(.cinemaMode)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.adjustWindowPosition()
                }
            }
            .store(in: &appCancellables)

        Defaults.publisher(.debugLargeScreenLayoutPreviewMode)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.adjustWindowPosition()
                }
            }
            .store(in: &appCancellables)

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

        lockStateSyncCancellable = LockScreenState.shared.$isLocked
            .removeDuplicates()
            .sink { [weak self] locked in
                guard let self else { return }
                guard locked != self.isScreenLocked else { return }
                Task { @MainActor in
                    if locked {
                        self.onScreenLocked(Notification(name: NSNotification.Name("LockScreenStateFallbackLocked")))
                    } else {
                        self.onScreenUnlocked(Notification(name: NSNotification.Name("LockScreenStateFallbackUnlocked")))
                    }
                }
            }

        lockScreenMediaPanelSyncCancellable = Publishers.CombineLatest(
            MusicManager.shared.$songTitle.removeDuplicates(),
            MusicManager.shared.$artistName.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            Task { @MainActor [weak self] in
                if !MusicManager.shared.isUsingIdleMetadata {
                    self?.lastLockScreenMediaActivityAt = Date()
                } else {
                    self?.lastLockScreenMediaActivityAt = .distantPast
                }
                self?.syncLockScreenActivityPanelVisibility()
            }
        }

        MusicManager.shared.$albumArtFlipEventID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard !MusicManager.shared.isUsingIdleMetadata else {
                    self?.lastLockScreenMediaActivityAt = .distantPast
                    return
                }
                self?.lastLockScreenMediaActivityAt = Date()
            }
            .store(in: &appCancellables)

        Publishers.CombineLatest(
            QuickTimerManager.shared.$timers
                .map { $0.map(\.id) }
                .removeDuplicates(),
            QuickTimerManager.shared.$mirroredSystemQuickTimer
                .map { $0?.id }
                .removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncLockScreenActivityPanelVisibility()
            }
        }
        .store(in: &appCancellables)

        Publishers.Merge3(
            Defaults.publisher(.showOnLockScreen).map { _ in () },
            Defaults.publisher(.enableLockScreenMediaWidget).map { _ in () },
            Defaults.publisher(.enableLockScreenTimerWidget).map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncLockScreenActivityPanelVisibility()
            }
        }
        .store(in: &appCancellables)

        Defaults.publisher(.liveActivityLockScreen)
            .map(\.newValue)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !Defaults[.showOnLockScreen] || !enabled {
                        self.lockScreenActivityWindow.hideImmediately()
                    } else if self.isScreenLocked {
                        self.lockScreenActivityWindow.showLocked(preferredScreenUUID: nil)
                    }
                }
            }
            .store(in: &appCancellables)

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            self.coordinator.toggleSneakPeek(
                status: !self.coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
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
                        viewModel.manualOpenUntil = Date().addingTimeInterval(3.15)
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
            let window = createQuartzNotchWindow(
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

        guard screensChanged else { return }

        pendingScreenConfigurationTask?.cancel()
        pendingScreenConfigurationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.applyStabilizedScreenConfigurationChange()
        }
    }

    @MainActor
    private func applyStabilizedScreenConfigurationChange() {
        cleanupWindows()

        if Defaults[.showOnAllDisplays] {
            viewModels.values.forEach { $0.closeForLockTransition() }
        } else {
            vm.closeForLockTransition()
        }

        adjustWindowPosition()
        setupDragDetectors()

        pendingScreenConfigurationTask?.cancel()
        pendingScreenConfigurationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            self?.adjustWindowPosition(changeAlpha: false)
            self?.setupDragDetectors()
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    tearDownNotchWindow(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = QuartzViewModel(screenUUID: uuid)
                    let window = createQuartzNotchWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    viewModel.screenUUID = uuid
                    viewModel.closeForLockTransition()
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
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
                if let window {
                    tearDownNotchWindow(window)
                    self.window = nil
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.closeForLockTransition()

            if window == nil {
                window = createQuartzNotchWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
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

    @objc private func handleReopenOnboardingSetup() {
        reopenOnboardingSetup()
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    func reopenOnboardingSetup() {
        showOnboardingWindow(step: .welcome)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil || onboardingWindowController?.window == nil {
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
                        window.close()
                        self.onboardingWindowController = nil
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        self.onboardingWindowController = nil
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

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
    static let reopenOnboardingSetup = Notification.Name("reopenOnboardingSetup")
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

// MARK: - Lock Screen Display Context

struct LockScreenDisplayContext {
    let screen: NSScreen
    let frame: NSRect
    let identifier: String
}

@MainActor
final class LockScreenDisplayContextProvider {
    static let shared = LockScreenDisplayContextProvider()

    private(set) var context: LockScreenDisplayContext?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        refresh(reason: "init")
        registerObservers()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    @discardableResult
    func refresh(reason: String) -> LockScreenDisplayContext? {
        guard let screen = preferredLockScreen() else {
            context = nil
            return nil
        }

        let snapshot = LockScreenDisplayContext(
            screen: screen,
            frame: screen.frame,
            identifier: screen.localizedName
        )
        context = snapshot
        return snapshot
    }

    func contextSnapshot() -> LockScreenDisplayContext? {
        if let context {
            return context
        }
        return refresh(reason: "snapshot-miss")
    }

    private func preferredLockScreen() -> NSScreen? {
        if let builtin = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtin
        }

        let mainDisplayID = CGMainDisplayID()
        if let mainScreen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == mainDisplayID
        }) {
            return mainScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func registerObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = self?.refresh(reason: "screen-parameters")
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = self?.refresh(reason: "screens-did-wake")
            }
        }

        let spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = self?.refresh(reason: "space-changed")
            }
        }

        workspaceObservers = [wakeObserver, spaceObserver]
    }
}
