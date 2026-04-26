import CoreGraphics
import CoreImage
import Defaults
import Darwin
import SwiftUI

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: UInt32) -> CFArray

final class LockScreenDesktopOverrideCoordinator {
    static let shared = LockScreenDesktopOverrideCoordinator()

    private struct DesktopImageState {
        let url: URL
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    private struct ManagedDisplayCurrentSpace {
        let displayUUID: String
        let spaceUUID: String
        let type: Int
    }

    private struct WallpaperStoreSnapshot {
        let data: Data
        let preferredDesktopImageURL: URL?
    }

    private struct WallpaperImagePrefsSnapshot {
        let data: Data
        let preferredDesktopImageURL: URL
    }

    private struct RestoreContext {
        let generatedImageURL: URL?
        let originalDesktopImageURL: URL?
        let originalDesktopImageOptions: [NSWorkspace.DesktopImageOptionKey: Any]
        let activeDisplayUUID: String?
        let originalWallpaperStoreData: Data?
        let originalWallpaperImageExtensionPrefsData: Data?
    }

    private let imageDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/QuartzNotch/LockScreenBackdrop", isDirectory: true)
    private let wallpaperStoreURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist", isDirectory: false)
    private let wallpaperImageExtensionPrefsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Preferences/com.apple.wallpaper.extension.image.plist", isDirectory: false)
    private let ciContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])

    private var generatedImageURL: URL?
    private var originalDesktopImageURL: URL?
    private var originalDesktopImageOptions: [NSWorkspace.DesktopImageOptionKey: Any]?
    private var activeDisplayUUID: String?
    private var cachedDesktopImages: [String: DesktopImageState] = [:]
    private var cachedRawWallpaperStoreData: Data?
    private var cachedWallpaperStoreData: Data?
    private var originalWallpaperStoreData: Data?
    private var cachedRawWallpaperImageExtensionPrefsData: Data?
    private var cachedWallpaperImageExtensionPrefsData: Data?
    private var originalWallpaperImageExtensionPrefsData: Data?
    private var isActive = false
    private var isRestoring = false
    private var didWarmUpAccess = false
    private var pendingImageCleanupTasks: [URL: Task<Void, Never>] = [:]
    private let wallpaperStateMonitorQueue = DispatchQueue(label: "quartznotch.wallpaper-state-monitor", qos: .utility)
    private let wallpaperOverrideOperationQueue = DispatchQueue(label: "quartznotch.wallpaper-override-operation", qos: .userInitiated)
    private var wallpaperStoreMonitorFD: CInt = -1
    private var wallpaperStoreMonitor: DispatchSourceFileSystemObject?
    private var wallpaperImagePrefsMonitorFD: CInt = -1
    private var wallpaperImagePrefsMonitor: DispatchSourceFileSystemObject?
    private var wallpaperStateRefreshTask: Task<Void, Never>?
    private let wallpaperRestoreSettleInterval: TimeInterval = 1.6
    private var wallpaperRestoreSettleDeadline: Date = .distantPast

    private init() {
        startWallpaperStateMonitoring()
    }

    var hasActiveOverride: Bool { isActive }
    var isBusyRestoring: Bool { isRestoring }

    func synchronizeCurrentFullscreenSpaceWallpapersIfNeeded(
        updateCachedSnapshots: Bool = true,
        reloadAgent: Bool = true
    ) {
        guard let wallpaperStoreData = try? Data(contentsOf: wallpaperStoreURL),
              var root = try? PropertyListSerialization.propertyList(from: wallpaperStoreData, options: [], format: nil) as? [String: Any],
              var spaces = root["Spaces"] as? [String: Any] else {
            return
        }

        var mutated = false

        for managedSpace in currentManagedDisplaySpaces() {
            guard managedSpace.type == 4,
                  let replacementDesktopNode = preferredNonSystemDesktopNode(
                    from: root,
                    displayUUID: managedSpace.displayUUID,
                    excludingSpaceUUID: managedSpace.spaceUUID
                  ),
                  spaceNeedsWallpaperSynchronization(
                    spaces: spaces,
                    displayUUID: managedSpace.displayUUID,
                    spaceUUID: managedSpace.spaceUUID,
                    replacementDesktopNode: replacementDesktopNode
                  ) else {
                continue
            }

            let templateSpace = (spaces[managedSpace.spaceUUID] as? [String: Any])
                ?? (spaces[""] as? [String: Any])

            upsertDesktopNode(
                in: &spaces,
                spaceUUID: managedSpace.spaceUUID,
                displayUUID: managedSpace.displayUUID,
                desktopNode: replacementDesktopNode,
                templateSpace: templateSpace
            )
            mutated = true
        }

        guard mutated else { return }

        root["Spaces"] = spaces

        do {
            let updatedStoreData = try PropertyListSerialization.data(
                fromPropertyList: root,
                format: .binary,
                options: 0
            )
            try updatedStoreData.write(to: wallpaperStoreURL, options: .atomic)
            if updateCachedSnapshots {
                cachedRawWallpaperStoreData = updatedStoreData
                cachedWallpaperStoreData = updatedStoreData
            }
            if reloadAgent {
                reloadWallpaperAgent()
            }
        } catch {
            print("Failed to synchronize fullscreen space wallpaper store for lock screen: \\(error)")
        }
    }

    func cacheCurrentDesktopImages(includeRawSnapshots: Bool = true) {
        var updated: [String: DesktopImageState] = [:]
        let workspace = NSWorkspace.shared

        for screen in NSScreen.screens {
            guard let displayUUID = displayUUID(for: screen),
                  let url = workspace.desktopImageURL(for: screen) else {
                continue
            }

            guard !isInvalidRestoreCandidateURL(url) || cachedDesktopImages[displayUUID] == nil else {
                continue
            }

            updated[displayUUID] = DesktopImageState(
                url: url,
                options: workspace.desktopImageOptions(for: screen) ?? [:]
            )
        }

        if !updated.isEmpty {
            cachedDesktopImages = updated
        }

        if let latestStoreData = try? Data(contentsOf: wallpaperStoreURL) {
            if includeRawSnapshots {
                cachedRawWallpaperStoreData = latestStoreData
            }
            if let sanitizedStoreData = sanitizedWallpaperStoreData(latestStoreData, preferredDisplayUUID: nil),
           let snapshot = wallpaperStoreSnapshot(from: sanitizedStoreData, preferredDisplayUUID: nil) {
                cachedWallpaperStoreData = snapshot.data
            }
        }

        if let latestImagePrefsData = try? Data(contentsOf: wallpaperImageExtensionPrefsURL) {
            if includeRawSnapshots {
                cachedRawWallpaperImageExtensionPrefsData = latestImagePrefsData
            }
            if let sanitizedImagePrefsData = sanitizedWallpaperImageExtensionPrefsData(latestImagePrefsData),
           let snapshot = wallpaperImagePrefsSnapshot(from: sanitizedImagePrefsData) {
                cachedWallpaperImageExtensionPrefsData = snapshot.data
            }
        }
    }

    func warmUpAccessIfNeeded() {
        guard !didWarmUpAccess else { return }
        didWarmUpAccess = true

        ensureImageDirectory()

        let warmupImageURL = imageDirectory.appendingPathComponent("warmup-\(UUID().uuidString).png", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: warmupImageURL) }

        guard let warmupImage = makeWarmupImage(),
              let tiff = warmupImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        try? pngData.write(to: warmupImageURL, options: .atomic)
        _ = try? Data(contentsOf: warmupImageURL)
    }

    @MainActor
    func activateIfPossible(screen: NSScreen, artwork: NSImage) -> Bool {
        guard !isRestoring else { return false }
        ensureImageDirectory()

        guard let imageURL = makeOverrideImage(screen: screen, artwork: artwork) else {
            return false
        }

        let workspace = NSWorkspace.shared
        let targetDisplayUUID = displayUUID(for: screen)
        let freshRawWallpaperStoreData = try? Data(contentsOf: wallpaperStoreURL)
        let freshWallpaperStoreData = freshRawWallpaperStoreData
            .flatMap { sanitizedWallpaperStoreData($0, preferredDisplayUUID: targetDisplayUUID) }
        let freshRawWallpaperImageExtensionPrefsData = try? Data(contentsOf: wallpaperImageExtensionPrefsURL)
        let freshWallpaperImageExtensionPrefsData = freshRawWallpaperImageExtensionPrefsData
            .flatMap { sanitizedWallpaperImageExtensionPrefsData($0) }
        let freshStoreSnapshot = wallpaperStoreSnapshot(
            from: freshWallpaperStoreData,
            preferredDisplayUUID: targetDisplayUUID
        )
        let freshImagePrefsSnapshot = wallpaperImagePrefsSnapshot(from: freshWallpaperImageExtensionPrefsData)
        let cachedStoreSnapshot = wallpaperStoreSnapshot(
            from: cachedWallpaperStoreData,
            preferredDisplayUUID: targetDisplayUUID
        )
        let cachedImagePrefsSnapshot = wallpaperImagePrefsSnapshot(from: cachedWallpaperImageExtensionPrefsData)
        let preferCachedSnapshots = LockScreenState.shared.isLocked || wallpaperStateIsSettlingAfterRestore()
        let preferredStoreSnapshot = preferCachedSnapshots
            ? (cachedStoreSnapshot ?? freshStoreSnapshot)
            : (freshStoreSnapshot ?? cachedStoreSnapshot)
        let preferredImagePrefsSnapshot = preferCachedSnapshots
            ? (cachedImagePrefsSnapshot ?? freshImagePrefsSnapshot)
            : (freshImagePrefsSnapshot ?? cachedImagePrefsSnapshot)
        let preferredStoreURL = preferredStoreSnapshot?.preferredDesktopImageURL
        let preferredImageProviderURL = preferredImagePrefsSnapshot?.preferredDesktopImageURL
        let selectedStoreIsNonImageBacked = preferredStoreSnapshot != nil && preferredStoreURL == nil
        let workspaceDesktopURL = workspace.desktopImageURL(for: screen)
        let preferredRawWallpaperStoreData = LockScreenState.shared.isLocked
            ? (cachedRawWallpaperStoreData ?? freshRawWallpaperStoreData)
            : (freshRawWallpaperStoreData ?? cachedRawWallpaperStoreData)
        let preferredRawWallpaperImageExtensionPrefsData = LockScreenState.shared.isLocked
            ? (cachedRawWallpaperImageExtensionPrefsData ?? freshRawWallpaperImageExtensionPrefsData)
            : (freshRawWallpaperImageExtensionPrefsData ?? cachedRawWallpaperImageExtensionPrefsData)

        if !LockScreenState.shared.isLocked,
           let freshStoreSnapshot {
            cachedWallpaperStoreData = freshStoreSnapshot.data
        }
        if !LockScreenState.shared.isLocked,
           let freshImagePrefsSnapshot {
            cachedWallpaperImageExtensionPrefsData = freshImagePrefsSnapshot.data
        }

        if !isActive || activeDisplayUUID != targetDisplayUUID {
            originalWallpaperStoreData = preferredRawWallpaperStoreData
                ?? preferredStoreSnapshot?.data
                ?? (preferCachedSnapshots
                    ? (cachedWallpaperStoreData ?? freshWallpaperStoreData)
                    : (freshWallpaperStoreData ?? cachedWallpaperStoreData))

            // Only preserve the image-extension prefs when the selected store snapshot
            // is image-backed, otherwise we can resurrect unrelated historical image state.
            if selectedStoreIsNonImageBacked {
                originalWallpaperImageExtensionPrefsData = nil
            } else {
                originalWallpaperImageExtensionPrefsData = preferredRawWallpaperImageExtensionPrefsData
                    ?? preferredImagePrefsSnapshot?.data
                    ?? (preferCachedSnapshots
                        ? (cachedWallpaperImageExtensionPrefsData ?? freshWallpaperImageExtensionPrefsData)
                        : (freshWallpaperImageExtensionPrefsData ?? cachedWallpaperImageExtensionPrefsData))
            }

            if let storeURL = preferredStoreURL,
                      !isInvalidRestoreCandidateURL(storeURL) {
                originalDesktopImageURL = storeURL
                originalDesktopImageOptions = workspace.desktopImageOptions(for: screen)
            } else if !selectedStoreIsNonImageBacked,
                      let imageProviderURL = preferredImageProviderURL,
                      !isInvalidRestoreCandidateURL(imageProviderURL) {
                originalDesktopImageURL = imageProviderURL
                originalDesktopImageOptions = workspace.desktopImageOptions(for: screen)
            } else if let targetDisplayUUID,
                      let cached = cachedDesktopImages[targetDisplayUUID],
                      !isInvalidRestoreCandidateURL(cached.url) {
                originalDesktopImageURL = cached.url
                originalDesktopImageOptions = cached.options
            } else if let workspaceDesktopURL,
                      !isInvalidRestoreCandidateURL(workspaceDesktopURL) {
                originalDesktopImageURL = workspaceDesktopURL
                originalDesktopImageOptions = workspace.desktopImageOptions(for: screen)
            } else {
                originalDesktopImageURL = preferredStoreURL
                    ?? (selectedStoreIsNonImageBacked ? nil : preferredImageProviderURL)
                    ?? workspaceDesktopURL
                originalDesktopImageOptions = workspace.desktopImageOptions(for: screen)
            }
            activeDisplayUUID = targetDisplayUUID
        }

        let applyOptions = originalDesktopImageOptions ?? [:]

        do {
            try workspace.setDesktopImageURL(imageURL, for: screen, options: applyOptions)
        } catch {
            print("Failed to set lock-screen desktop override image: \(error)")
            try? FileManager.default.removeItem(at: imageURL)
            return false
        }

        if let previousGeneratedImageURL = generatedImageURL,
           previousGeneratedImageURL != imageURL {
            scheduleCleanup(of: previousGeneratedImageURL, after: 8.0)
        }
        cancelCleanup(for: imageURL)
        generatedImageURL = imageURL
        isActive = true
        return true
    }

    func currentDesktopPreviewImage(for screen: NSScreen) -> NSImage? {
        let targetDisplayUUID = displayUUID(for: screen)
        let workspace = NSWorkspace.shared
        let liveWallpaperImageExtensionPrefsData = ((try? Data(contentsOf: wallpaperImageExtensionPrefsURL))
            .flatMap { sanitizedWallpaperImageExtensionPrefsData($0) })
            ?? cachedWallpaperImageExtensionPrefsData
        let liveWallpaperStoreData = ((try? Data(contentsOf: wallpaperStoreURL))
            .flatMap { sanitizedWallpaperStoreData($0, preferredDisplayUUID: targetDisplayUUID) })
            ?? cachedWallpaperStoreData
        let liveImageProviderURL = preferredImageProviderDesktopImageURL(from: liveWallpaperImageExtensionPrefsData)
        let liveStoreURL = preferredDesktopImageURL(from: liveWallpaperStoreData, preferredDisplayUUID: targetDisplayUUID)
        let cachedImageProviderURL = preferredImageProviderDesktopImageURL(from: cachedWallpaperImageExtensionPrefsData)
        let cachedStoreURL = preferredDesktopImageURL(from: cachedWallpaperStoreData, preferredDisplayUUID: targetDisplayUUID)
        let workspaceDesktopURL = workspace.desktopImageURL(for: screen)

        let resolvedURL: URL?
        let resolvedOptions: [NSWorkspace.DesktopImageOptionKey: Any]

        if let imageProviderURL = liveImageProviderURL,
           !isInvalidRestoreCandidateURL(imageProviderURL) {
            resolvedURL = imageProviderURL
            resolvedOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        } else if let storeURL = liveStoreURL,
                  !isInvalidRestoreCandidateURL(storeURL) {
            resolvedURL = storeURL
            resolvedOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        } else if let targetDisplayUUID,
                  let cached = cachedDesktopImages[targetDisplayUUID],
                  !isInvalidRestoreCandidateURL(cached.url) {
            resolvedURL = cached.url
            resolvedOptions = cached.options
        } else if let imageProviderURL = cachedImageProviderURL,
                  !isInvalidRestoreCandidateURL(imageProviderURL) {
            resolvedURL = imageProviderURL
            resolvedOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        } else if let storeURL = cachedStoreURL,
                  !isInvalidRestoreCandidateURL(storeURL) {
            resolvedURL = storeURL
            resolvedOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        } else if let workspaceDesktopURL,
                  !isInvalidRestoreCandidateURL(workspaceDesktopURL) {
            resolvedURL = workspaceDesktopURL
            resolvedOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        } else {
            resolvedURL = liveImageProviderURL
                ?? liveStoreURL
                ?? cachedImageProviderURL
                ?? cachedStoreURL
                ?? workspaceDesktopURL
            resolvedOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        }

        guard let resolvedURL else { return nil }
        return renderDesktopPreview(url: resolvedURL, options: resolvedOptions, size: screen.frame.size)
    }

    func restoredDesktopPreviewImage(for screen: NSScreen) -> NSImage? {
        guard let restoredState = restoredDesktopImageState(for: screen) else { return nil }
        return renderDesktopPreview(
            url: restoredState.url,
            options: restoredState.options,
            size: screen.frame.size
        )
    }

    func restoreIfNeededAndWaitForDesktopReady(on screen: NSScreen) async {
        guard let context = takeRestoreContext() else { return }
        let requiresWallpaperAgentReload = context.originalWallpaperStoreData != nil
            || context.originalWallpaperImageExtensionPrefsData != nil

        await performRestore(context)

        _ = screen
        let settleDelayMs = requiresWallpaperAgentReload ? 240 : 120
        try? await Task.sleep(for: .milliseconds(settleDelayMs))
    }

    @MainActor
    func restoreIfNeededForUnlock(on screen: NSScreen) {
        guard let context = takeRestoreContext() else { return }

        if let restoreState = desktopImageStateForUnlockRestore(on: screen, context: context) {
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    restoreState.url,
                    for: screen,
                    options: restoreState.options
                )
                isRestoring = false
                cacheCurrentDesktopImages()
                return
            } catch {
                print("Fast unlock wallpaper restore failed, falling back to full restore: \(error)")
            }
        }

        wallpaperOverrideOperationQueue.async { [weak self] in
            self?.performRestoreSynchronously(context)
        }
    }

    func restoreIfNeeded() {
        guard let context = takeRestoreContext() else { return }
        wallpaperOverrideOperationQueue.async { [weak self] in
            self?.performRestoreSynchronously(context)
        }
    }

    func currentGeneratedImage() -> NSImage? {
        guard let generatedImageURL else { return nil }
        return NSImage(contentsOf: generatedImageURL)
    }

    private func ensureImageDirectory() {
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    }

    private func reloadWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
        process.waitUntilExit()
    }

    private func takeRestoreContext() -> RestoreContext? {
        guard isActive, !isRestoring else { return nil }
        isRestoring = true

        let context = RestoreContext(
            generatedImageURL: generatedImageURL,
            originalDesktopImageURL: originalDesktopImageURL,
            originalDesktopImageOptions: originalDesktopImageOptions ?? [:],
            activeDisplayUUID: activeDisplayUUID,
            originalWallpaperStoreData: originalWallpaperStoreData,
            originalWallpaperImageExtensionPrefsData: originalWallpaperImageExtensionPrefsData
        )

        if let generatedImageURL {
            scheduleCleanup(of: generatedImageURL, after: 8.0)
        }
        self.generatedImageURL = nil
        self.originalDesktopImageURL = nil
        self.originalDesktopImageOptions = nil
        self.activeDisplayUUID = nil
        self.originalWallpaperStoreData = nil
        self.originalWallpaperImageExtensionPrefsData = nil
        isActive = false
        wallpaperRestoreSettleDeadline = Date().addingTimeInterval(wallpaperRestoreSettleInterval)

        return context
    }

    private func performRestore(_ context: RestoreContext) async {
        await withCheckedContinuation { continuation in
            wallpaperOverrideOperationQueue.async { [weak self] in
                self?.performRestoreSynchronously(context)
                continuation.resume()
            }
        }
    }

    private func performRestoreSynchronously(_ context: RestoreContext) {
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.isRestoring = false
            }
        }

        let currentWallpaperImageExtensionPrefsData = try? Data(contentsOf: wallpaperImageExtensionPrefsURL)
        let currentWallpaperStoreData = try? Data(contentsOf: wallpaperStoreURL)
        let shouldRestoreImagePrefs = context.originalWallpaperImageExtensionPrefsData != nil
            && currentWallpaperImageExtensionPrefsData != context.originalWallpaperImageExtensionPrefsData
        let shouldRestoreStore = context.originalWallpaperStoreData != nil
            && currentWallpaperStoreData != context.originalWallpaperStoreData

        if shouldRestoreImagePrefs,
           let originalWallpaperImageExtensionPrefsData = context.originalWallpaperImageExtensionPrefsData {
            do {
                try originalWallpaperImageExtensionPrefsData.write(
                    to: wallpaperImageExtensionPrefsURL,
                    options: .atomic
                )
            } catch {
                print("Failed to restore wallpaper image extension preferences: \(error)")
            }
        }

        if shouldRestoreStore,
           let originalWallpaperStoreData = context.originalWallpaperStoreData {
            do {
                try originalWallpaperStoreData.write(to: wallpaperStoreURL, options: .atomic)
            } catch {
                print("Failed to restore wallpaper store override: \(error)")
            }
        }

        if shouldRestoreStore || shouldRestoreImagePrefs {
            reloadWallpaperAgent()
            return
        }

        if let activeDisplayUUID = context.activeDisplayUUID,
           let screen = screen(for: activeDisplayUUID),
           let originalDesktopImageURL = context.originalDesktopImageURL {
            DispatchQueue.main.sync {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(
                        originalDesktopImageURL,
                        for: screen,
                        options: context.originalDesktopImageOptions
                    )
                } catch {
                    print("Failed to restore desktop wallpaper after lock-screen override: \(error)")
                }
            }
            return
        }
    }

    private func startWallpaperStateMonitoring() {
        wallpaperStoreMonitor = makeWallpaperStateMonitor(
            url: wallpaperStoreURL,
            fd: &wallpaperStoreMonitorFD
        )
        wallpaperImagePrefsMonitor = makeWallpaperStateMonitor(
            url: wallpaperImageExtensionPrefsURL,
            fd: &wallpaperImagePrefsMonitorFD
        )
    }

    private func makeWallpaperStateMonitor(
        url: URL,
        fd: inout CInt
    ) -> DispatchSourceFileSystemObject? {
        let path = url.path
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }
        fd = fileDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link, .revoke],
            queue: wallpaperStateMonitorQueue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleWallpaperStateRefresh()
            self?.restartWallpaperStateMonitoring()
        }
        source.setCancelHandler {
            Darwin.close(fileDescriptor)
        }
        source.resume()
        return source
    }

    private func restartWallpaperStateMonitoring() {
        wallpaperStoreMonitor?.cancel()
        wallpaperStoreMonitor = nil
        wallpaperStoreMonitorFD = -1
        wallpaperImagePrefsMonitor?.cancel()
        wallpaperImagePrefsMonitor = nil
        wallpaperImagePrefsMonitorFD = -1
        startWallpaperStateMonitoring()
    }

    private func scheduleWallpaperStateRefresh() {
        wallpaperStateRefreshTask?.cancel()
        let now = Date()
        let settleDelayMs = max(0, Int(ceil(wallpaperRestoreSettleDeadline.timeIntervalSince(now) * 1000)))
        let refreshDelayMs = max(140, settleDelayMs + 40)
        wallpaperStateRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(refreshDelayMs))
            guard let self else { return }
            if self.wallpaperStateIsSettlingAfterRestore() {
                self.scheduleWallpaperStateRefresh()
                return
            }
            guard !LockScreenState.shared.isLocked, !self.isActive else { return }
            self.cacheCurrentDesktopImages()
            self.synchronizeCurrentFullscreenSpaceWallpapersIfNeeded()
            self.wallpaperStateRefreshTask = nil
        }
    }

    private func cancelCleanup(for url: URL) {
        pendingImageCleanupTasks[url]?.cancel()
        pendingImageCleanupTasks[url] = nil
    }

    private func scheduleCleanup(of url: URL, after delay: TimeInterval) {
        cancelCleanup(for: url)
        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard !Task.isCancelled else { return }
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                self?.pendingImageCleanupTasks[url] = nil
            }
        }
        pendingImageCleanupTasks[url] = task
    }

    private func makeWarmupImage() -> NSImage? {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private func displayUUID(for screen: NSScreen) -> String? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }

        return CFUUIDCreateString(nil, cfUUID) as String
    }

    private func currentManagedDisplaySpaces() -> [ManagedDisplayCurrentSpace] {
        let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as NSArray

        return raw.compactMap { item in
            guard let entry = item as? [String: Any],
                  let displayUUID = entry["Display Identifier"] as? String,
                  let currentSpace = entry["Current Space"] as? [String: Any],
                  let spaceUUID = currentSpace["uuid"] as? String,
                  let type = currentSpace["type"] as? Int else {
                return nil
            }

            return ManagedDisplayCurrentSpace(
                displayUUID: displayUUID,
                spaceUUID: spaceUUID,
                type: type
            )
        }
    }

    private func wallpaperStoreSnapshot(from data: Data?, preferredDisplayUUID: String?) -> WallpaperStoreSnapshot? {
        guard let data,
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              preferredStableDesktopNode(from: root, preferredDisplayUUID: preferredDisplayUUID) != nil else {
            return nil
        }

        return WallpaperStoreSnapshot(
            data: data,
            preferredDesktopImageURL: preferredDesktopImageURL(from: data, preferredDisplayUUID: preferredDisplayUUID)
        )
    }

    private func wallpaperImagePrefsSnapshot(from data: Data?) -> WallpaperImagePrefsSnapshot? {
        guard let data,
              let preferredDesktopImageURL = preferredImageProviderDesktopImageURL(from: data),
              !isInvalidRestoreCandidateURL(preferredDesktopImageURL) else {
            return nil
        }

        return WallpaperImagePrefsSnapshot(
            data: data,
            preferredDesktopImageURL: preferredDesktopImageURL
        )
    }

    private func wallpaperStateIsSettlingAfterRestore(at now: Date = Date()) -> Bool {
        now < wallpaperRestoreSettleDeadline
    }

    private func restoredDesktopImageState(for screen: NSScreen) -> DesktopImageState? {
        let workspace = NSWorkspace.shared
        let targetDisplayUUID = displayUUID(for: screen) ?? activeDisplayUUID
        let originalStoreURL = preferredDesktopImageURL(
            from: originalWallpaperStoreData,
            preferredDisplayUUID: targetDisplayUUID
        )
        let originalStoreIsNonImageBacked = originalWallpaperStoreData != nil && originalStoreURL == nil

        func state(
            for url: URL?,
            options: [NSWorkspace.DesktopImageOptionKey: Any]
        ) -> DesktopImageState? {
            guard let url,
                  !isInvalidRestoreCandidateURL(url) else {
                return nil
            }
            return DesktopImageState(url: url, options: options)
        }

        let workspaceOptions = workspace.desktopImageOptions(for: screen) ?? [:]

        if let state = state(
            for: originalStoreIsNonImageBacked ? nil : originalDesktopImageURL,
            options: originalDesktopImageOptions ?? workspaceOptions
        ) {
            return state
        }

        if !originalStoreIsNonImageBacked,
           let state = state(
            for: preferredImageProviderDesktopImageURL(from: originalWallpaperImageExtensionPrefsData),
            options: workspaceOptions
        ) {
            return state
        }

        if let state = state(
            for: originalStoreURL,
            options: workspaceOptions
        ) {
            return state
        }

        if let targetDisplayUUID,
           let cached = cachedDesktopImages[targetDisplayUUID],
           !isInvalidRestoreCandidateURL(cached.url) {
            return cached
        }

        return nil
    }

    private func desktopImageStateForUnlockRestore(
        on screen: NSScreen,
        context: RestoreContext
    ) -> DesktopImageState? {
        let workspace = NSWorkspace.shared
        let targetDisplayUUID = displayUUID(for: screen) ?? context.activeDisplayUUID
        let originalStoreURL = preferredDesktopImageURL(
            from: context.originalWallpaperStoreData,
            preferredDisplayUUID: targetDisplayUUID
        )
        let originalStoreIsNonImageBacked = context.originalWallpaperStoreData != nil && originalStoreURL == nil
        let workspaceOptions = workspace.desktopImageOptions(for: screen) ?? [:]

        func state(
            for url: URL?,
            options: [NSWorkspace.DesktopImageOptionKey: Any]
        ) -> DesktopImageState? {
            guard let url,
                  !isInvalidRestoreCandidateURL(url) else {
                return nil
            }
            return DesktopImageState(url: url, options: options)
        }

        if !originalStoreIsNonImageBacked,
           let state = state(
            for: preferredImageProviderDesktopImageURL(from: context.originalWallpaperImageExtensionPrefsData),
            options: context.originalDesktopImageOptions
        ) {
            return state
        }

        if let state = state(
            for: originalStoreURL,
            options: context.originalDesktopImageOptions
        ) {
            return state
        }

        if let targetDisplayUUID,
           let cached = cachedDesktopImages[targetDisplayUUID],
           !isInvalidRestoreCandidateURL(cached.url) {
            return cached
        }

        if let state = state(
            for: originalStoreIsNonImageBacked ? nil : context.originalDesktopImageURL,
            options: context.originalDesktopImageOptions.isEmpty ? workspaceOptions : context.originalDesktopImageOptions
        ) {
            return state
        }

        return nil
    }

    private func desktopRestorationLooksReady(
        on screen: NSScreen,
        expectedState: DesktopImageState?,
        expectedPreview: NSImage?,
        generatedURL: URL?,
        requiresDisplayedWallpaperVerification: Bool
    ) -> Bool {
        let workspaceURL = NSWorkspace.shared.desktopImageURL(for: screen)

        if let workspaceURL, let generatedURL, urlsMatch(workspaceURL, generatedURL) {
            return false
        }

        if let workspaceURL,
           isQuartzGeneratedImageURL(workspaceURL) || isTransientWallpaperProviderURL(workspaceURL) {
            return false
        }

        if let expectedState,
           let workspaceURL,
           urlsMatch(workspaceURL, expectedState.url) {
            guard requiresDisplayedWallpaperVerification else {
                return true
            }
            guard let expectedPreview,
                  let displayedWallpaper = displayedWallpaperImage(for: screen) else {
                return false
            }
            return wallpaperImage(displayedWallpaper, visuallyMatches: expectedPreview)
        }

        if let expectedPreview,
           let displayedWallpaper = displayedWallpaperImage(for: screen),
           wallpaperImage(displayedWallpaper, visuallyMatches: expectedPreview) {
            return true
        }

        if requiresDisplayedWallpaperVerification {
            return false
        }

        return expectedState == nil && workspaceURL != nil
    }

    private func displayedWallpaperImage(for screen: NSScreen) -> NSImage? {
        let desktopBounds = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.union(frame)
            }
        let captureRect = quartzCaptureRect(for: screen.frame, in: desktopBounds)
        guard let wallpaperWindowID = desktopWallpaperWindowID(intersecting: captureRect),
              let cgImage = CGWindowListCreateImage(
                captureRect,
                .optionIncludingWindow,
                wallpaperWindowID,
                [.bestResolution]
              ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: screen.frame.size)
    }

    private func wallpaperImage(_ displayed: NSImage, visuallyMatches expected: NSImage) -> Bool {
        guard let displayedAverage = averageColor(for: displayed),
              let expectedAverage = averageColor(for: expected),
              let displayedRGBA = normalizedRGBA(for: displayedAverage),
              let expectedRGBA = normalizedRGBA(for: expectedAverage) else {
            return false
        }

        let displayedBrightness = brightness(for: displayedRGBA)
        let expectedBrightness = brightness(for: expectedRGBA)

        if expectedBrightness > 0.08, displayedBrightness < 0.025 {
            return false
        }

        return colorDistance(between: displayedRGBA, and: expectedRGBA) < 0.18
    }

    private func normalizedRGBA(for color: NSColor) -> SIMD4<Double>? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        return SIMD4(
            Double(rgb.redComponent),
            Double(rgb.greenComponent),
            Double(rgb.blueComponent),
            Double(rgb.alphaComponent)
        )
    }

    private func brightness(for color: SIMD4<Double>) -> Double {
        (0.2126 * color.x) + (0.7152 * color.y) + (0.0722 * color.z)
    }

    private func colorDistance(between lhs: SIMD4<Double>, and rhs: SIMD4<Double>) -> Double {
        let delta = lhs - rhs
        return sqrt((delta.x * delta.x) + (delta.y * delta.y) + (delta.z * delta.z))
    }

    private func urlsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL == rhs.standardizedFileURL
    }

    private func preferredNonSystemDesktopImageState(for screen: NSScreen) -> DesktopImageState? {
        let workspace = NSWorkspace.shared
        let targetDisplayUUID = displayUUID(for: screen)
        let freshWallpaperStoreData = (try? Data(contentsOf: wallpaperStoreURL))
            .flatMap { sanitizedWallpaperStoreData($0, preferredDisplayUUID: targetDisplayUUID) }
        let freshWallpaperImageExtensionPrefsData = (try? Data(contentsOf: wallpaperImageExtensionPrefsURL))
            .flatMap { sanitizedWallpaperImageExtensionPrefsData($0) }
        let freshImageProviderURL = preferredImageProviderDesktopImageURL(from: freshWallpaperImageExtensionPrefsData)
        let freshStoreURL = preferredDesktopImageURL(from: freshWallpaperStoreData, preferredDisplayUUID: targetDisplayUUID)
        let cachedImageProviderURL = preferredImageProviderDesktopImageURL(from: cachedWallpaperImageExtensionPrefsData)
        let cachedStoreURL = preferredDesktopImageURL(from: cachedWallpaperStoreData, preferredDisplayUUID: targetDisplayUUID)
        let workspaceDesktopURL = workspace.desktopImageURL(for: screen)
        let workspaceOptions = workspace.desktopImageOptions(for: screen) ?? [:]

        func state(for url: URL?) -> DesktopImageState? {
            guard let url,
                  !isInvalidRestoreCandidateURL(url) else {
                return nil
            }
            return DesktopImageState(url: url, options: workspaceOptions)
        }

        if let state = state(for: freshImageProviderURL) { return state }
        if let targetDisplayUUID,
          let cached = cachedDesktopImages[targetDisplayUUID],
           !isInvalidRestoreCandidateURL(cached.url) {
            return cached
        }
        if let state = state(for: freshStoreURL) { return state }
        if let state = state(for: cachedImageProviderURL) { return state }
        if let state = state(for: cachedStoreURL) { return state }
        if let state = state(for: workspaceDesktopURL) { return state }
        return nil
    }

    private func preferredNonSystemDesktopNode(
        from root: [String: Any],
        displayUUID: String,
        excludingSpaceUUID: String
    ) -> [String: Any]? {
        func nodeIsUsable(_ node: [String: Any]?) -> Bool {
            guard let node,
                  let content = node["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  !choices.isEmpty else {
                return false
            }

            for choice in choices {
                guard let provider = choice["Provider"] as? String else { continue }
                if provider != "com.apple.wallpaper.choice.image" {
                    return true
                }

                guard let configurationData = choice["Configuration"] as? Data,
                      let configuration = try? PropertyListSerialization.propertyList(from: configurationData, options: [], format: nil) as? [String: Any],
                      let urlDict = configuration["url"] as? [String: Any],
                      let relative = urlDict["relative"] as? String,
                      let url = URL(string: relative) else {
                    continue
                }

                if !isSystemDefaultDesktopURL(url)
                    && !isQuartzGeneratedImageURL(url)
                    && !isTransientWallpaperProviderURL(url) {
                    return true
                }
            }

            return false
        }

        func desktopNode(in container: [String: Any]?) -> [String: Any]? {
            guard let container else { return nil }
            if let desktop = container["Desktop"] as? [String: Any], nodeIsUsable(desktop) {
                return desktop
            }
            if let linked = container["Linked"] as? [String: Any], nodeIsUsable(linked) {
                return linked
            }
            if let defaultNode = container["Default"] as? [String: Any],
               let desktop = desktopNode(in: defaultNode) {
                return desktop
            }
            return nil
        }

        if let displays = root["Displays"] as? [String: Any],
           let display = displays[displayUUID] as? [String: Any],
           let node = desktopNode(in: display) {
            return node
        }

        if let spaces = root["Spaces"] as? [String: Any] {
            if let sharedSpace = spaces[""] as? [String: Any] {
                if let displays = sharedSpace["Displays"] as? [String: Any],
                   let display = displays[displayUUID] as? [String: Any],
                   let node = desktopNode(in: display) {
                    return node
                }
                if let defaultNode = sharedSpace["Default"] as? [String: Any],
                   let node = desktopNode(in: defaultNode) {
                    return node
                }
            }

            for (spaceUUID, value) in spaces where spaceUUID != excludingSpaceUUID {
                guard let space = value as? [String: Any] else { continue }
                if let displays = space["Displays"] as? [String: Any],
                   let display = displays[displayUUID] as? [String: Any],
                   let node = desktopNode(in: display) {
                    return node
                }
                if let defaultNode = space["Default"] as? [String: Any],
                   let node = desktopNode(in: defaultNode) {
                    return node
                }
            }
        }

        if let allSpacesAndDisplays = root["AllSpacesAndDisplays"] as? [String: Any],
           let node = desktopNode(in: allSpacesAndDisplays) {
            return node
        }

        if let systemDefault = root["SystemDefault"] as? [String: Any],
           let node = desktopNode(in: systemDefault) {
            return node
        }

        return nil
    }

    private func spaceNeedsWallpaperSynchronization(
        spaces: [String: Any],
        displayUUID: String,
        spaceUUID: String,
        replacementDesktopNode: [String: Any]
    ) -> Bool {
        guard let space = spaces[spaceUUID] as? [String: Any] else {
            return true
        }

        let replacementSignature = desktopNodeSignature(replacementDesktopNode)

        func nodeNeedsSync(_ node: [String: Any]?) -> Bool {
            guard let node,
                  let content = node["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  !choices.isEmpty else {
                return true
            }

            for choice in choices {
                guard let provider = choice["Provider"] as? String else { continue }
                if provider != "com.apple.wallpaper.choice.image" {
                    return desktopNodeSignature(node) != replacementSignature
                }
                guard let configurationData = choice["Configuration"] as? Data,
                      let configuration = try? PropertyListSerialization.propertyList(from: configurationData, options: [], format: nil) as? [String: Any],
                      let urlDict = configuration["url"] as? [String: Any],
                      let relative = urlDict["relative"] as? String,
                      let url = URL(string: relative) else {
                    return true
                }
                if isSystemDefaultDesktopURL(url)
                    || isQuartzGeneratedImageURL(url)
                    || isTransientWallpaperProviderURL(url) {
                    return true
                }
            }

            return desktopNodeSignature(node) != replacementSignature
        }

        if let displays = space["Displays"] as? [String: Any],
           let displayNode = displays[displayUUID] as? [String: Any],
           !nodeNeedsSync(displayNode["Desktop"] as? [String: Any]) {
            return false
        }

        if let defaultNode = space["Default"] as? [String: Any],
           !nodeNeedsSync(defaultNode["Desktop"] as? [String: Any]) {
            return false
        }

        return true
    }

    private func desktopNodeSignature(_ node: [String: Any]) -> String {
        guard let content = node["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]] else {
            return ""
        }

        let encodedOptionValues = (content["EncodedOptionValues"] as? Data)?.base64EncodedString() ?? ""

        let choiceSignature = choices.compactMap { choice -> String? in
            guard let provider = choice["Provider"] as? String else { return nil }
            if provider != "com.apple.wallpaper.choice.image" {
                return provider
            }
            let configuration = (choice["Configuration"] as? Data)?.base64EncodedString() ?? ""
            return provider + "|" + configuration
        }
        .joined(separator: "||")

        return encodedOptionValues + "::" + choiceSignature
    }

    private func upsertDesktopNode(
        in spaces: inout [String: Any],
        spaceUUID: String,
        displayUUID: String,
        desktopNode: [String: Any],
        templateSpace: [String: Any]?
    ) {
        var space = (spaces[spaceUUID] as? [String: Any]) ?? [:]

        var defaultNode = (space["Default"] as? [String: Any])
            ?? (templateSpace?["Default"] as? [String: Any])
            ?? ["Type": "individual"]
        defaultNode["Desktop"] = desktopNode
        space["Default"] = defaultNode

        var displays = (space["Displays"] as? [String: Any])
            ?? (templateSpace?["Displays"] as? [String: Any])
            ?? [:]
        var displayNode = (displays[displayUUID] as? [String: Any])
            ?? ((templateSpace?["Displays"] as? [String: Any])?[displayUUID] as? [String: Any])
            ?? ["Type": "individual"]
        displayNode["Desktop"] = desktopNode
        displays[displayUUID] = displayNode
        space["Displays"] = displays

        spaces[spaceUUID] = space
    }

    private func currentSpaceUsesSystemDefaultDesktop(
        from wallpaperStoreData: Data,
        displayUUID: String,
        spaceUUID: String
    ) -> Bool {
        guard let root = try? PropertyListSerialization.propertyList(from: wallpaperStoreData, options: [], format: nil) as? [String: Any],
              let spaces = root["Spaces"] as? [String: Any],
              let space = spaces[spaceUUID] as? [String: Any] else {
            return false
        }

        func desktopNodeStatus(_ node: [String: Any]?) -> Bool? {
            guard let node,
                  let content = node["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  !choices.isEmpty else {
                return nil
            }

            var sawSystemDefault = false

            for choice in choices {
                guard let provider = choice["Provider"] as? String else { continue }
                if provider != "com.apple.wallpaper.choice.image" {
                    return false
                }
                guard let configurationData = choice["Configuration"] as? Data,
                      let configuration = try? PropertyListSerialization.propertyList(from: configurationData, options: [], format: nil) as? [String: Any],
                      let urlDict = configuration["url"] as? [String: Any],
                      let relative = urlDict["relative"] as? String,
                      let url = URL(string: relative) else {
                    continue
                }

                if isQuartzGeneratedImageURL(url) || isSystemDefaultDesktopURL(url) {
                    sawSystemDefault = true
                } else {
                    return false
                }
            }

            return sawSystemDefault
        }

        if let displays = space["Displays"] as? [String: Any],
           let display = displays[displayUUID] as? [String: Any],
           let usesDefault = desktopNodeStatus(display["Desktop"] as? [String: Any]) {
            return usesDefault
        }

        if let defaultNode = space["Default"] as? [String: Any],
           let usesDefault = desktopNodeStatus(defaultNode["Desktop"] as? [String: Any]) {
            return usesDefault
        }

        return false
    }

    private func preferredDesktopImageURL(from wallpaperStoreData: Data?, preferredDisplayUUID: String?) -> URL? {
        guard let wallpaperStoreData,
              let root = try? PropertyListSerialization.propertyList(from: wallpaperStoreData, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        struct Candidate {
            let url: URL
            let score: TimeInterval
            let preferred: Bool
        }

        func decodeChoiceURL(from choice: [String: Any]) -> URL? {
            guard let provider = choice["Provider"] as? String,
                  provider == "com.apple.wallpaper.choice.image",
                  let configurationData = choice["Configuration"] as? Data,
                  let configuration = try? PropertyListSerialization.propertyList(from: configurationData, options: [], format: nil) as? [String: Any],
                  let urlDict = configuration["url"] as? [String: Any],
                  let relative = urlDict["relative"] as? String else {
                return nil
            }
            return URL(string: relative)
        }

        func nodeScore(_ node: [String: Any]) -> TimeInterval {
            let lastUse = (node["LastUse"] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            let lastSet = (node["LastSet"] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            return max(lastUse, lastSet)
        }

        func appendCandidate(from node: [String: Any], preferred: Bool, into list: inout [Candidate]) {
            guard let content = node["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]] else {
                return
            }

            for choice in choices {
                guard let url = decodeChoiceURL(from: choice),
                      !isQuartzGeneratedImageURL(url),
                      !isTransientWallpaperProviderURL(url) else { continue }
                list.append(Candidate(url: url, score: nodeScore(node), preferred: preferred))
            }
        }

        func appendDesktopCandidates(from container: [String: Any], preferred: Bool, into list: inout [Candidate]) {
            if let desktop = container["Desktop"] as? [String: Any] {
                appendCandidate(from: desktop, preferred: preferred, into: &list)
            }
            if let linked = container["Linked"] as? [String: Any] {
                appendCandidate(from: linked, preferred: preferred, into: &list)
            }
            if let defaultNode = container["Default"] as? [String: Any] {
                appendDesktopCandidates(from: defaultNode, preferred: preferred, into: &list)
            }
        }

        var candidates: [Candidate] = []

        if let allSpacesAndDisplays = root["AllSpacesAndDisplays"] as? [String: Any] {
            appendDesktopCandidates(from: allSpacesAndDisplays, preferred: true, into: &candidates)
        }

        if let systemDefault = root["SystemDefault"] as? [String: Any] {
            appendDesktopCandidates(from: systemDefault, preferred: true, into: &candidates)
        }

        if let displays = root["Displays"] as? [String: Any] {
            for (displayUUID, value) in displays {
                guard let display = value as? [String: Any] else { continue }
                let isPreferred = preferredDisplayUUID.map { $0.caseInsensitiveCompare(displayUUID) == .orderedSame } ?? false
                if let desktop = display["Desktop"] as? [String: Any] {
                    appendCandidate(from: desktop, preferred: isPreferred, into: &candidates)
                }
            }
        }

        if let spaces = root["Spaces"] as? [String: Any] {
            for (_, value) in spaces {
                guard let space = value as? [String: Any] else { continue }

                if let defaultNode = space["Default"] as? [String: Any],
                   let desktop = defaultNode["Desktop"] as? [String: Any] {
                    appendCandidate(from: desktop, preferred: true, into: &candidates)
                }

                if let displays = space["Displays"] as? [String: Any] {
                    for (displayUUID, displayValue) in displays {
                        guard let display = displayValue as? [String: Any],
                              let desktop = display["Desktop"] as? [String: Any] else { continue }
                        let isPreferred = preferredDisplayUUID.map { $0.caseInsensitiveCompare(displayUUID) == .orderedSame } ?? false
                        appendCandidate(from: desktop, preferred: isPreferred, into: &candidates)
                    }
                }
            }
        }

        let sorted = candidates.sorted {
            if $0.preferred != $1.preferred { return $0.preferred && !$1.preferred }
            if isSystemDefaultDesktopURL($0.url) != isSystemDefaultDesktopURL($1.url) { return !isSystemDefaultDesktopURL($0.url) && isSystemDefaultDesktopURL($1.url) }
            return $0.score > $1.score
        }

        return sorted.first?.url
    }

    private func screen(for displayUUIDValue: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let candidate = displayUUID(for: screen) else { return false }
            return candidate.caseInsensitiveCompare(displayUUIDValue) == .orderedSame
        }
    }

    private func preferredImageProviderDesktopImageURL(from prefsData: Data?) -> URL? {
        guard let prefsData,
              let root = try? PropertyListSerialization.propertyList(from: prefsData, options: [], format: nil) as? [String: Any],
              let imageFiles = root["ChoiceRequests.ImageFiles"] as? [Data] else {
            return nil
        }

        struct Candidate {
            let url: URL
            let dateAdded: Date
        }

        let quartzPathPrefix = imageDirectory.path

        let candidates = imageFiles.compactMap { entryData -> Candidate? in
            guard let entry = try? PropertyListSerialization.propertyList(from: entryData, options: [], format: nil) as? [String: Any],
                  let dateAdded = entry["dateAdded"] as? Date else {
                return nil
            }

            func decodeURL(from key: String) -> URL? {
                guard let container = entry[key] as? [String: Any],
                      let relative = container["relative"] as? String,
                      let url = URL(string: relative) else {
                    return nil
                }
                return url
            }

            let originalURL = decodeURL(from: "originalURL")
            let copyURL = decodeURL(from: "copyURL")

            guard let preferredURL = [originalURL, copyURL]
                .compactMap({ $0 })
                .first(where: { url in
                    let path = url.path
                    return !path.hasPrefix(quartzPathPrefix)
                        && !isTransientWallpaperProviderURL(url)
                        && !isSystemDefaultDesktopURL(url)
                }) else {
                return nil
            }

            return Candidate(url: preferredURL, dateAdded: dateAdded)
        }
        .sorted { $0.dateAdded > $1.dateAdded }

        return candidates.first?.url
    }

    private func sanitizedWallpaperImageExtensionPrefsData(_ prefsData: Data) -> Data? {
        guard var root = (try? PropertyListSerialization.propertyList(from: prefsData, options: [], format: nil)) as? [String: Any] else {
            return nil
        }

        guard let imageFiles = root["ChoiceRequests.ImageFiles"] as? [Data] else {
            return prefsData
        }

        let sanitizedImageFiles = imageFiles.filter { entryData in
            guard let entry = try? PropertyListSerialization.propertyList(from: entryData, options: [], format: nil) as? [String: Any] else {
                return true
            }

            func decodeURL(from key: String) -> URL? {
                guard let container = entry[key] as? [String: Any],
                      let relative = container["relative"] as? String else {
                    return nil
                }
                return URL(string: relative)
            }

            let candidateURLs = [decodeURL(from: "originalURL"), decodeURL(from: "copyURL")].compactMap { $0 }
            guard !candidateURLs.isEmpty else { return true }

            return candidateURLs.contains { !isUnsafeRestoredWallpaperURL($0) }
        }

        root["ChoiceRequests.ImageFiles"] = sanitizedImageFiles
        return try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func sanitizedWallpaperStoreData(_ wallpaperStoreData: Data, preferredDisplayUUID: String?) -> Data? {
        guard var root = (try? PropertyListSerialization.propertyList(from: wallpaperStoreData, options: [], format: nil)) as? [String: Any] else {
            return nil
        }

        guard let replacementDesktopNode = preferredStableDesktopNode(from: root, preferredDisplayUUID: preferredDisplayUUID) else {
            return wallpaperStoreData
        }

        var mutated = false

        func sanitizeDesktopNode(_ node: [String: Any]?) -> [String: Any]? {
            guard let node else { return nil }
            if desktopNodeUsesUnsafeRestoreWallpaper(node) {
                mutated = true
                return replacementDesktopNode
            }
            return node
        }

        func sanitizeContainer(_ container: inout [String: Any]) {
            if let desktop = container["Desktop"] as? [String: Any] {
                container["Desktop"] = sanitizeDesktopNode(desktop)
            }
            if let linked = container["Linked"] as? [String: Any] {
                container["Linked"] = sanitizeDesktopNode(linked)
            }
            if var defaultNode = container["Default"] as? [String: Any] {
                sanitizeContainer(&defaultNode)
                container["Default"] = defaultNode
            }
            if var displays = container["Displays"] as? [String: Any] {
                for (displayUUID, value) in displays {
                    guard var displayNode = value as? [String: Any] else { continue }
                    sanitizeContainer(&displayNode)
                    displays[displayUUID] = displayNode
                }
                container["Displays"] = displays
            }
        }

        if var allSpacesAndDisplays = root["AllSpacesAndDisplays"] as? [String: Any] {
            sanitizeContainer(&allSpacesAndDisplays)
            root["AllSpacesAndDisplays"] = allSpacesAndDisplays
        }

        if var systemDefault = root["SystemDefault"] as? [String: Any] {
            sanitizeContainer(&systemDefault)
            root["SystemDefault"] = systemDefault
        }

        if var displays = root["Displays"] as? [String: Any] {
            for (displayUUID, value) in displays {
                guard var displayNode = value as? [String: Any] else { continue }
                sanitizeContainer(&displayNode)
                displays[displayUUID] = displayNode
            }
            root["Displays"] = displays
        }

        if var spaces = root["Spaces"] as? [String: Any] {
            for (spaceUUID, value) in spaces {
                guard var spaceNode = value as? [String: Any] else { continue }
                sanitizeContainer(&spaceNode)
                spaces[spaceUUID] = spaceNode
            }
            root["Spaces"] = spaces
        }

        guard mutated else { return wallpaperStoreData }
        return try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func isSystemDefaultDesktopURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/System/Library/CoreServices/DefaultDesktop.heic"
            || path.hasPrefix("/System/Library/Desktop Pictures/")
    }

    private func isQuartzGeneratedImageURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(imageDirectory.path)
    }

    private func isTransientWallpaperProviderURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/com.apple.wallpaper.extension.image/")
            && path.hasPrefix("/private/var/folders/")
    }

    private func isInvalidRestoreCandidateURL(_ url: URL) -> Bool {
        isSystemDefaultDesktopURL(url)
            || isQuartzGeneratedImageURL(url)
            || isTransientWallpaperProviderURL(url)
    }

    private func isUnsafeRestoredWallpaperURL(_ url: URL) -> Bool {
        isQuartzGeneratedImageURL(url) || isTransientWallpaperProviderURL(url)
    }

    private func desktopNodeUsesUnsafeRestoreWallpaper(_ node: [String: Any]) -> Bool {
        guard let content = node["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]] else {
            return false
        }

        for choice in choices {
            guard let provider = choice["Provider"] as? String else { continue }
            guard provider == "com.apple.wallpaper.choice.image",
                  let configurationData = choice["Configuration"] as? Data,
                  let configuration = try? PropertyListSerialization.propertyList(from: configurationData, options: [], format: nil) as? [String: Any],
                  let urlDict = configuration["url"] as? [String: Any],
                  let relative = urlDict["relative"] as? String,
                  let url = URL(string: relative) else {
                continue
            }

            if isUnsafeRestoredWallpaperURL(url) {
                return true
            }
        }

        return false
    }

    private func preferredStableDesktopNode(from root: [String: Any], preferredDisplayUUID: String?) -> [String: Any]? {
        struct Candidate {
            let node: [String: Any]
            let score: TimeInterval
            let preferred: Bool
        }

        func nodeScore(_ node: [String: Any]) -> TimeInterval {
            let lastUse = (node["LastUse"] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            let lastSet = (node["LastSet"] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            return max(lastUse, lastSet)
        }

        func appendCandidate(from node: [String: Any]?, preferred: Bool, into list: inout [Candidate]) {
            guard let node,
                  !desktopNodeUsesUnsafeRestoreWallpaper(node) else {
                return
            }
            list.append(Candidate(node: node, score: nodeScore(node), preferred: preferred))
        }

        func appendCandidates(from container: [String: Any]?, preferred: Bool, into list: inout [Candidate]) {
            guard let container else { return }
            appendCandidate(from: container["Desktop"] as? [String: Any], preferred: preferred, into: &list)
            appendCandidate(from: container["Linked"] as? [String: Any], preferred: preferred, into: &list)
            if let defaultNode = container["Default"] as? [String: Any] {
                appendCandidates(from: defaultNode, preferred: preferred, into: &list)
            }
        }

        var candidates: [Candidate] = []

        if let allSpacesAndDisplays = root["AllSpacesAndDisplays"] as? [String: Any] {
            appendCandidates(from: allSpacesAndDisplays, preferred: true, into: &candidates)
        }

        if let systemDefault = root["SystemDefault"] as? [String: Any] {
            appendCandidates(from: systemDefault, preferred: true, into: &candidates)
        }

        if let displays = root["Displays"] as? [String: Any] {
            for (displayUUID, value) in displays {
                let isPreferred = preferredDisplayUUID.map { $0.caseInsensitiveCompare(displayUUID) == .orderedSame } ?? false
                appendCandidates(from: value as? [String: Any], preferred: isPreferred, into: &candidates)
            }
        }

        if let spaces = root["Spaces"] as? [String: Any] {
            for (_, value) in spaces {
                appendCandidates(from: value as? [String: Any], preferred: true, into: &candidates)
            }
        }

        return candidates.sorted {
            if $0.preferred != $1.preferred { return $0.preferred && !$1.preferred }
            return $0.score > $1.score
        }.first?.node
    }

    private func makeOverrideImage(screen: NSScreen, artwork: NSImage) -> URL? {
        let canvasSize = screen.frame.size
        guard canvasSize.width > 1, canvasSize.height > 1,
              let ciSource = ciImage(from: artwork) else {
            return nil
        }

        let renderRect = CGRect(origin: .zero, size: canvasSize)
        func scaledArtwork(scaleMultiplier: CGFloat, xOffsetRatio: CGFloat = 0, yOffsetRatio: CGFloat = 0) -> CIImage {
            let scale = max(canvasSize.width / ciSource.extent.width, canvasSize.height / ciSource.extent.height) * scaleMultiplier
            let scaled = ciSource.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = (canvasSize.width - scaled.extent.width) * 0.5 + canvasSize.width * xOffsetRatio
            let dy = (canvasSize.height - scaled.extent.height) * 0.5 + canvasSize.height * yOffsetRatio
            return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        }

        func colorAdjusted(_ image: CIImage, saturation: CGFloat, brightness: CGFloat, contrast: CGFloat) -> CIImage {
            guard let controls = CIFilter(name: "CIColorControls") else { return image }
            controls.setValue(image, forKey: kCIInputImageKey)
            controls.setValue(saturation, forKey: kCIInputSaturationKey)
            controls.setValue(brightness, forKey: kCIInputBrightnessKey)
            controls.setValue(contrast, forKey: kCIInputContrastKey)
            return controls.outputImage?.cropped(to: renderRect) ?? image
        }

        func withAlpha(_ image: CIImage, _ alpha: CGFloat) -> CIImage {
            image.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                ]
            )
            .cropped(to: renderRect)
        }

        func blurred(_ image: CIImage, radius: CGFloat) -> CIImage {
            guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
            blur.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(radius, forKey: kCIInputRadiusKey)
            return blur.outputImage?.cropped(to: renderRect) ?? image
        }

        func pixelated(_ image: CIImage, scale: CGFloat) -> CIImage {
            guard let pixellate = CIFilter(name: "CIPixellate") else { return image }
            pixellate.setValue(image, forKey: kCIInputImageKey)
            pixellate.setValue(scale, forKey: kCIInputScaleKey)
            pixellate.setValue(CIVector(x: renderRect.midX, y: renderRect.midY), forKey: kCIInputCenterKey)
            return pixellate.outputImage?.cropped(to: renderRect) ?? image
        }

        func layerImage(_ image: CIImage) -> NSImage? {
            guard let cgImage = ciContext.createCGImage(image, from: renderRect) else { return nil }
            let size = NSSize(width: renderRect.width, height: renderRect.height)
            return NSImage(cgImage: cgImage, size: size)
        }

        let average = averageColor(for: artwork) ?? NSColor(calibratedRed: 0.30, green: 0.33, blue: 0.44, alpha: 1)
        let topBase = MusicManager.shared.spectrogramTopColor.usingColorSpace(.deviceRGB) ?? average
        let bottomBase = MusicManager.shared.spectrogramBottomColor.usingColorSpace(.deviceRGB) ?? average
        let topColor = topBase.blended(withFraction: 0.14, of: .white)?.withAlphaComponent(1.0) ?? topBase
        let bottomColor = bottomBase.blended(withFraction: 0.30, of: .black)?.withAlphaComponent(1.0) ?? bottomBase
        let accentColor = average.blended(withFraction: 0.10, of: .white)?.withAlphaComponent(1.0) ?? average

        let ambientLayerImage = layerImage(withAlpha(
            blurred(
                pixelated(
                    colorAdjusted(
                        scaledArtwork(scaleMultiplier: 2.35, xOffsetRatio: 0.05, yOffsetRatio: 0.03),
                        saturation: 1.10,
                        brightness: 0.015,
                        contrast: 0.92
                    ),
                    scale: max(48, canvasSize.width * 0.045)
                ),
                radius: 180
            ),
            0.86
        ))

        let heroLayerImage = layerImage(withAlpha(
            blurred(
                pixelated(
                    scaledArtwork(scaleMultiplier: 2.10, xOffsetRatio: 0.04, yOffsetRatio: 0.02),
                    scale: max(28, canvasSize.width * 0.022)
                )
                .applyingFilter(
                    "CIColorControls",
                    parameters: [
                        kCIInputSaturationKey: 1.06,
                        kCIInputBrightnessKey: 0.0,
                        kCIInputContrastKey: 0.95
                    ]
                )
                .cropped(to: renderRect),
                radius: 110
            ),
            0.22
        ))

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(canvasSize.width.rounded())),
            pixelsHigh: max(1, Int(canvasSize.height.rounded())),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmapRep else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context

        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        let backgroundGradient = NSGradient(colors: [
            topColor,
            accentColor.blended(withFraction: 0.18, of: topColor) ?? accentColor,
            bottomColor
        ])
        backgroundGradient?.draw(in: canvasRect, angle: -90)

        ambientLayerImage?.draw(in: canvasRect, from: .zero, operation: .sourceOver, fraction: 1)
        heroLayerImage?.draw(in: canvasRect, from: .zero, operation: .sourceOver, fraction: 1)

        if let accentWash = NSGradient(colors: [
            accentColor.withAlphaComponent(0.10),
            accentColor.withAlphaComponent(0.035),
            NSColor.clear
        ]) {
            accentWash.draw(in: canvasRect, angle: -60)
        }

        if let bottomShade = NSGradient(colors: [
            NSColor.clear,
            NSColor.black.withAlphaComponent(0.10),
            NSColor.black.withAlphaComponent(0.22)
        ]) {
            bottomShade.draw(in: canvasRect, angle: -90)
        }

        if let sideVignette = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.14),
            NSColor.clear,
            NSColor.black.withAlphaComponent(0.14)
        ]) {
            sideVignette.draw(in: canvasRect, angle: 0)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        let fileURL = imageDirectory.appendingPathComponent("desktop-override-\(UUID().uuidString).png", isDirectory: false)
        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Failed to write lock-screen desktop override image: \(error)")
            return nil
        }
    }

    private func ciImage(from image: NSImage) -> CIImage? {
        if let tiffData = image.tiffRepresentation, let ciImage = CIImage(data: tiffData) {
            return ciImage
        }
        return nil
    }

    private func averageColor(for image: NSImage) -> NSColor? {
        guard let ciImage = ciImage(from: image) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
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
            alpha: CGFloat(bitmap[3]) / 255.0
        )
    }

    private func renderDesktopPreview(
        url: URL,
        options: [NSWorkspace.DesktopImageOptionKey: Any],
        size: NSSize
    ) -> NSImage? {
        guard size.width > 1,
              size.height > 1,
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        let result = NSImage(size: size)
        result.lockFocus()

        let canvasRect = NSRect(origin: .zero, size: size)
        let fillColor = (options[.fillColor] as? NSColor) ?? .black
        fillColor.setFill()
        canvasRect.fill()

        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            result.unlockFocus()
            return result
        }

        let scalingValue = (options[.imageScaling] as? NSNumber)?.intValue
            ?? Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
        let scaling = NSImageScaling(rawValue: UInt(scalingValue)) ?? .scaleProportionallyUpOrDown
        let allowClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true

        let widthScale = size.width / sourceSize.width
        let heightScale = size.height / sourceSize.height

        let drawRect: NSRect = {
            switch scaling {
            case .scaleAxesIndependently:
                return canvasRect
            case .scaleNone:
                return NSRect(
                    x: (size.width - sourceSize.width) * 0.5,
                    y: (size.height - sourceSize.height) * 0.5,
                    width: sourceSize.width,
                    height: sourceSize.height
                )
            case .scaleProportionallyDown:
                let scale = min(1, min(widthScale, heightScale))
                let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
                return NSRect(
                    x: (size.width - targetSize.width) * 0.5,
                    y: (size.height - targetSize.height) * 0.5,
                    width: targetSize.width,
                    height: targetSize.height
                )
            case .scaleProportionallyUpOrDown:
                let scale = allowClipping ? max(widthScale, heightScale) : min(widthScale, heightScale)
                let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
                return NSRect(
                    x: (size.width - targetSize.width) * 0.5,
                    y: (size.height - targetSize.height) * 0.5,
                    width: targetSize.width,
                    height: targetSize.height
                )
            @unknown default:
                let scale = max(widthScale, heightScale)
                let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
                return NSRect(
                    x: (size.width - targetSize.width) * 0.5,
                    y: (size.height - targetSize.height) * 0.5,
                    width: targetSize.width,
                    height: targetSize.height
                )
            }
        }()

        image.draw(in: drawRect)
        result.unlockFocus()
        return result
    }

    private func desktopWallpaperWindowID(intersecting targetRect: CGRect) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return windowList
            .compactMap { windowInfo -> (windowID: CGWindowID, bounds: CGRect, score: CGFloat)? in
                guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                      ownerName == "Dock",
                      let windowName = windowInfo[kCGWindowName as String] as? String,
                      windowName.hasPrefix("Wallpaper-"),
                      let windowNumber = windowInfo[kCGWindowNumber as String] as? NSNumber,
                      let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
                else {
                    return nil
                }

                let intersection = bounds.intersection(targetRect)
                guard !intersection.isNull, !intersection.isEmpty else {
                    return nil
                }

                return (CGWindowID(windowNumber.uint32Value), bounds, intersection.width * intersection.height)
            }
            .max(by: { $0.score < $1.score })?
            .windowID
    }

    private func quartzCaptureRect(for cocoaRect: NSRect, in desktopBounds: CGRect) -> CGRect {
        let captureX = cocoaRect.minX
        let captureY = desktopBounds.maxY - cocoaRect.maxY

        return CGRect(
            x: captureX,
            y: captureY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }
}
