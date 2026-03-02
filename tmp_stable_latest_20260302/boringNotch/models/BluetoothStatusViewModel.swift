//
// BluetoothStatusViewModel.swift
// boringNotch
//
// Created by Clayton on 29/01/2026.
//

import Foundation
import SwiftUI
import Defaults
import Combine
import AppKit

@MainActor
final class BluetoothStatusViewModel: ObservableObject {

    static let shared = BluetoothStatusViewModel()

    @Published private(set) var lastConnectedDeviceName: String = ""
    @Published private(set) var lastConnectedDeviceKind: BluetoothActivityManager.BluetoothDeviceKind = .other
    @Published private(set) var lastConnectedBatteryPercent: Int? = nil
    @Published var lastConnectedAliasName: String?

  // Battery cache to make the UI feel instant when reconnecting the same device.
    private var batteryCache: [String: (percent: Int, ts: Date)] = [:]
    private let batteryCacheTTL: TimeInterval = 20 * 60

    private let coordinator = BoringViewCoordinator.shared
    private let manager = BluetoothActivityManager.shared
    private let xpc = XPCHelperClient.shared

    private init() {
        manager.onDeviceConnected = { [weak self] info in
            guard let self else { return }
            guard Defaults[.bluetoothLiveActivityEnabled] else { return }
            self.lastConnectedDeviceName = info.name
            self.lastConnectedDeviceKind = info.kind
            self.lastConnectedBatteryPercent = nil

      // Instant feel: show cached value (if fresh), then refresh.
            let cacheKey = self.cacheKey(address: info.address, name: info.name)
            if let entry = self.batteryCache[cacheKey], Date().timeIntervalSince(entry.ts) < self.batteryCacheTTL {
                self.lastConnectedBatteryPercent = entry.percent
            }

            self.xpc.warmUpBluetoothBatteryCache()
            self.resolveBatteryFast(address: info.address, name: info.name)
            self.coordinator.toggleExpandingView(status: true, type: .bluetooth)
        }
    }

    private func cacheKey(address: String, name: String) -> String {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveBatteryFast(address: String, name: String) {
        let delays: [TimeInterval] = [0.0, 0.4, 0.9, 1.6, 2.6]
        let addr = address
        let nm = name
        let key = cacheKey(address: addr, name: nm)

        for delay in delays {
            Task.detached { [weak self] in
                guard let self else { return }
                guard Defaults[.bluetoothLiveActivityEnabled] else { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                if let p = await self.xpc.bluetoothBatteryPercent(forDeviceAddress: addr, deviceName: nm) {
                    await MainActor.run {
            // Don't bounce the UI if already set to the same value.
                        if self.lastConnectedBatteryPercent != p {
                            self.lastConnectedBatteryPercent = p
                        }
                        self.batteryCache[key] = (p, Date())
                    }
                }
            }
        }
    }
}

final class FocusModeLiveActivityManager: NSObject, ObservableObject {
    static let shared = FocusModeLiveActivityManager()

    @Published private(set) var isMonitoring = false
    @Published private(set) var isFocusModeActive = false
    @Published private(set) var isFocusToastVisible = false
    @Published private(set) var latestTransitionIsActive = false
    @Published private(set) var currentFocusModeName: String = ""
    @Published private(set) var currentFocusModeIdentifier: String = ""
    @Published private(set) var rawFocusSymbolName: String = ""
    @Published private(set) var rawFocusTintName: String = ""
    @Published private(set) var currentFocusSymbolName: String = ""
    @Published private(set) var currentFocusTintName: String = ""

    private let notificationCenter = DistributedNotificationCenter.default()
    private let metadataExtractionQueue = DispatchQueue(label: "quartznotch.focus.metadata", qos: .userInitiated)
    private let focusLogStream = FocusLogStream()
    private var enabledCancellable: AnyCancellable?
    private var hideToastTask: Task<Void, Never>?
    private var lastModeSignature: String = ""

    private override init() {
        super.init()
        focusLogStream.onMetadataUpdate = { [weak self] identifier, name in
            guard let self else { return }
            DispatchQueue.main.async {
                if let identifier, !identifier.isEmpty {
                    self.currentFocusModeIdentifier = identifier
                }
                if let name, !name.isEmpty {
                    self.currentFocusModeName = name
                }
                self.refreshModeSignatureIfNeeded()
                if let latest = self.focusLogStream.latestMetadata() {
                    if let symbol = latest.symbolName, !symbol.isEmpty {
                        self.rawFocusSymbolName = symbol
                    }
                    if let tint = latest.tintColorName, !tint.isEmpty {
                        self.rawFocusTintName = tint
                    }
                }
                self.applyDerivedVisualFallbackIfNeeded()
            }
        }

        enabledCancellable = Defaults.publisher(.focusLiveActivityEnabled, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.startMonitoring()
                } else {
                    self.stopMonitoring(resetState: true)
                }
            }

        if Defaults[.focusLiveActivityEnabled] {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring(resetState: false)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusEnabled(_:)),
            name: .focusModeEnabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusDisabled(_:)),
            name: .focusModeDisabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        focusLogStream.start()
        isMonitoring = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.applyDerivedVisualFallbackIfNeeded()
        }
    }

    func stopMonitoring(resetState: Bool) {
        notificationCenter.removeObserver(self, name: .focusModeEnabled, object: nil)
        notificationCenter.removeObserver(self, name: .focusModeDisabled, object: nil)
        focusLogStream.stop()
        hideToastTask?.cancel()
        hideToastTask = nil

        isMonitoring = false

        if resetState {
            isFocusModeActive = false
            isFocusToastVisible = false
            latestTransitionIsActive = false
            currentFocusModeName = ""
            currentFocusModeIdentifier = ""
            rawFocusSymbolName = ""
            rawFocusTintName = ""
            currentFocusSymbolName = ""
            currentFocusTintName = ""
        }
    }

    @objc private func handleFocusEnabled(_ notification: Notification) {
        handleFocusNotification(notification, isActive: true)
    }

    @objc private func handleFocusDisabled(_ notification: Notification) {
        handleFocusNotification(notification, isActive: false)
    }

    private func handleFocusNotification(_ notification: Notification, isActive: Bool) {
        metadataExtractionQueue.async { [weak self] in
            guard let self else { return }
            let metadata = self.extractMetadata(from: notification)
            let visual = self.extractVisualMetadata(from: notification)

            DispatchQueue.main.async {
                let fallbackMetadata = self.focusLogStream.latestMetadata()
                let resolvedIdentifier = metadata.identifier ?? fallbackMetadata?.identifier
                let resolvedName = metadata.name
                    ?? fallbackMetadata?.name
                    ?? self.inferName(from: resolvedIdentifier)

                if let id = resolvedIdentifier, !id.isEmpty {
                    self.currentFocusModeIdentifier = id
                }

                if let name = resolvedName, !name.isEmpty {
                    self.currentFocusModeName = name
                }
                self.refreshModeSignatureIfNeeded()
                if let symbol = visual.symbolName ?? fallbackMetadata?.symbolName, !symbol.isEmpty {
                    self.rawFocusSymbolName = symbol
                }
                if let tint = visual.tintColorName ?? fallbackMetadata?.tintColorName, !tint.isEmpty {
                    self.rawFocusTintName = tint
                }
                self.applyDerivedVisualFallbackIfNeeded()

                self.latestTransitionIsActive = isActive
                withAnimation(.smooth(duration: 0.3)) {
                    self.isFocusModeActive = isActive
                    self.isFocusToastVisible = true
                }
                self.scheduleFocusToastHide(isActive: isActive)
            }
        }
    }

    private func scheduleFocusToastHide(isActive: Bool) {
        hideToastTask?.cancel()
        let duration: TimeInterval = isActive ? 1.8 : 1.45
        hideToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.28)) {
                self.isFocusToastVisible = false
            }
        }
    }

    private func extractMetadata(from notification: Notification) -> (identifier: String?, name: String?) {
        let identifierKeys = [
            "FocusModeIdentifier", "focusModeIdentifier", "FocusModeUUID", "focusModeUUID", "UUID",
            "uuid", "identifier", "Identifier"
        ]

        let nameKeys = [
            "FocusModeName", "focusModeName", "FocusMode", "focusMode", "displayName", "display_name",
            "activityDisplayName", "modeName", "name", "Name"
        ]

        var candidates: [Any] = []
        if let userInfo = notification.userInfo { candidates.append(userInfo) }
        if let object = notification.object { candidates.append(object) }

        var identifier: String?
        var name: String?

        for candidate in candidates {
            if identifier == nil { identifier = firstMatch(for: identifierKeys, in: candidate) }
            if name == nil { name = firstMatch(for: nameKeys, in: candidate) }
            if identifier != nil && name != nil { break }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    if identifier == nil { identifier = firstMatch(for: identifierKeys, in: decoded) }
                    if name == nil { name = firstMatch(for: nameKeys, in: decoded) }
                    if identifier != nil && name != nil { break }
                }
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let object = candidate as? NSObject {
                    if identifier == nil, let i = extractIdentifier(fromFocusObject: object) { identifier = i }
                    if name == nil, let n = extractDisplayName(fromFocusObject: object) { name = n }
                    if identifier != nil && name != nil { break }
                }
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                let description = String(describing: candidate)
                if identifier == nil { identifier = extractIdentifier(from: description) }
                if name == nil { name = extractName(from: description) }
                if identifier != nil && name != nil { break }
            }
        }

        return (identifier, name)
    }

    private func extractVisualMetadata(from notification: Notification) -> (symbolName: String?, tintColorName: String?) {
        let symbolKeys = ["symbolImageName", "symbolName", "iconName", "icon", "sfSymbolName", "symbol"]
        let tintKeys = ["tintColorName", "tintColor", "accentColorName", "colorName", "color"]

        var candidates: [Any] = []
        if let userInfo = notification.userInfo { candidates.append(userInfo) }
        if let object = notification.object { candidates.append(object) }

        var symbolName: String?
        var tintColorName: String?

        for candidate in candidates {
            if symbolName == nil { symbolName = firstMatch(for: symbolKeys, in: candidate) }
            if tintColorName == nil { tintColorName = firstMatch(for: tintKeys, in: candidate) }
            if symbolName != nil && tintColorName != nil { break }
        }

        if symbolName == nil || tintColorName == nil {
            for candidate in candidates {
                guard let object = candidate as? NSObject else { continue }
                if symbolName == nil, let symbol = extractSymbolName(fromFocusObject: object) { symbolName = symbol }
                if tintColorName == nil, let tint = extractTintName(fromFocusObject: object) { tintColorName = tint }
                if symbolName != nil && tintColorName != nil { break }
            }
        }

        if symbolName == nil || tintColorName == nil {
            for candidate in candidates {
                let description = String(describing: candidate)
                if symbolName == nil { symbolName = FocusMetadataDecoder.extractSymbolName(from: description) }
                if tintColorName == nil { tintColorName = FocusMetadataDecoder.extractTintName(from: description) }
                if symbolName != nil && tintColorName != nil { break }
            }
        }

        return (symbolName, tintColorName)
    }

    private func firstMatch(for keys: [String], in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for key in keys {
                if let candidate = dictionary[key], let string = normalizedString(from: candidate) {
                    return string
                }
            }

            for nestedValue in dictionary.values {
                if let nestedMatch = firstMatch(for: keys, in: nestedValue) {
                    return nestedMatch
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let nestedMatch = firstMatch(for: keys, in: element) {
                    return nestedMatch
                }
            }
        }

        return nil
    }

    private func normalizedString(from value: Any) -> String? {
        switch value {
        case let string as String:
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        case let number as NSNumber:
            let cleaned = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        case let uuid as UUID:
            return uuid.uuidString
        case let uuid as NSUUID:
            return uuid.uuidString
        case let data as Data:
            if let decoded = decodeFocusPayload(from: data),
               let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID", "name", "Name", "displayName"], in: decoded) {
                return nested
            }
            if let string = String(data: data, encoding: .utf8) {
                let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
            return nil
        default:
            return nil
        }
    }

    private func decodeFocusPayloadIfNeeded(_ value: Any) -> Any? {
        switch value {
        case let data as Data:
            return decodeFocusPayload(from: data)
        case let data as NSData:
            return decodeFocusPayload(from: data as Data)
        default:
            return nil
        }
    }

    private func decodeFocusPayload(from data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return propertyList
        }
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return jsonObject
        }
        if let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func extractIdentifier(from raw: String) -> String? {
        FocusMetadataDecoder.extractIdentifier(from: raw)
    }

    private func extractName(from raw: String) -> String? {
        FocusMetadataDecoder.extractName(from: raw)
    }

    private func extractIdentifier(fromFocusObject object: NSObject) -> String? {
        if let identifier = focusString(object, selector: "modeIdentifier") { return identifier }
        if let identifier = focusString(object, selector: "identifier") { return identifier }
        if let metadata = focusObject(object, selector: "activeModeAssertionMetadata"),
           let identifier = extractIdentifier(fromFocusObject: metadata) { return identifier }
        if let configuration = focusObject(object, selector: "activeModeConfiguration"),
           let identifier = extractIdentifier(fromFocusObject: configuration) { return identifier }
        if let modeConfiguration = focusObject(object, selector: "modeConfiguration"),
           let identifier = extractIdentifier(fromFocusObject: modeConfiguration) { return identifier }
        if let details = focusObject(object, selector: "details"),
           let identifier = extractIdentifier(fromFocusObject: details) { return identifier }
        if let mode = focusObject(object, selector: "mode"),
           let identifier = extractIdentifier(fromFocusObject: mode) { return identifier }
        if let identifiers = focusObject(object, selector: "activeModeIdentifiers") {
            if let stringArray = identifiers as? [String],
               let first = stringArray
                .map(FocusMetadataDecoder.cleanedString)
                .first(where: { !$0.isEmpty }) {
                return first
            }
            if let array = identifiers as? NSArray {
                for case let string as String in array {
                    let cleaned = FocusMetadataDecoder.cleanedString(string)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        return nil
    }

    private func extractDisplayName(fromFocusObject object: NSObject) -> String? {
        if let name = focusString(object, selector: "name") { return name }
        if let name = focusString(object, selector: "displayName") { return name }
        if let name = focusString(object, selector: "activityDisplayName") { return name }
        if let descriptor = focusObject(object, selector: "symbolDescriptor"),
           let name = focusString(descriptor, selector: "name") { return name }
        if let mode = focusObject(object, selector: "mode"),
           let name = extractDisplayName(fromFocusObject: mode) { return name }
        if let details = focusObject(object, selector: "details"),
           let name = extractDisplayName(fromFocusObject: details) { return name }
        if let configuration = focusObject(object, selector: "modeConfiguration"),
           let name = extractDisplayName(fromFocusObject: configuration) { return name }
        return nil
    }

    private func extractSymbolName(fromFocusObject object: NSObject) -> String? {
        if let symbol = focusString(object, selector: "symbolImageName") { return symbol }
        if let symbol = focusString(object, selector: "symbolName") { return symbol }
        if let descriptor = focusObject(object, selector: "symbolDescriptor"),
           let symbol = focusString(descriptor, selector: "name") { return symbol }
        if let mode = focusObject(object, selector: "mode"),
           let symbol = extractSymbolName(fromFocusObject: mode) { return symbol }
        if let details = focusObject(object, selector: "details"),
           let symbol = extractSymbolName(fromFocusObject: details) { return symbol }
        if let configuration = focusObject(object, selector: "modeConfiguration"),
           let symbol = extractSymbolName(fromFocusObject: configuration) { return symbol }
        return nil
    }

    private func extractTintName(fromFocusObject object: NSObject) -> String? {
        if let tint = focusString(object, selector: "tintColorName") { return tint }
        if let tint = focusString(object, selector: "accentColorName") { return tint }
        if let tint = focusString(object, selector: "colorName") { return tint }
        if let mode = focusObject(object, selector: "mode"),
           let tint = extractTintName(fromFocusObject: mode) { return tint }
        if let details = focusObject(object, selector: "details"),
           let tint = extractTintName(fromFocusObject: details) { return tint }
        if let configuration = focusObject(object, selector: "modeConfiguration"),
           let tint = extractTintName(fromFocusObject: configuration) { return tint }
        return nil
    }

    private func focusObject(_ object: NSObject, selector selectorName: String) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        return value as? NSObject
    }

    private func focusString(_ object: NSObject, selector selectorName: String) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }

        switch value {
        case let string as String:
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        case let string as NSString:
            let cleaned = (string as String).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        case let number as NSNumber:
            let cleaned = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        default:
            return nil
        }
    }

    private func inferName(from identifier: String?) -> String? {
        guard let identifier else { return nil }
        let token = identifier
            .split(separator: ".")
            .last?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ") ?? ""
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func applyDerivedVisualFallbackIfNeeded() {
        let mode = FocusModeType.resolve(identifier: currentFocusModeIdentifier, name: currentFocusModeName)
        let dbRaw = FocusMetadataReader.shared.getRawMetadata(
            for: currentFocusModeName,
            identifier: currentFocusModeIdentifier
        )
        let dbSymbol = dbRaw.symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dbTint = dbRaw.tint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawSymbol = rawFocusSymbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTint = rawFocusTintName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !dbSymbol.isEmpty {
            currentFocusSymbolName = dbSymbol
        } else if !rawSymbol.isEmpty {
            currentFocusSymbolName = rawSymbol
        } else {
            currentFocusSymbolName = mode.sfSymbol
        }

        if !dbTint.isEmpty {
            currentFocusTintName = dbTint
        } else if !rawTint.isEmpty {
            currentFocusTintName = rawTint
        } else {
            currentFocusTintName = mode.accentColorName
        }
    }

    private func refreshModeSignatureIfNeeded() {
        let id = currentFocusModeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = currentFocusModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = "\(id)|\(name)"
        if signature == lastModeSignature { return }
        lastModeSignature = signature
        rawFocusSymbolName = ""
        rawFocusTintName = ""
        currentFocusSymbolName = ""
        currentFocusTintName = ""
    }

}

private final class FocusLogStream {
    private let queue = DispatchQueue(label: "quartznotch.focus.logstream", qos: .utility)
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var isRunning = false

    private let metadataLock = NSLock()
    private var lastIdentifier: String?
    private var lastName: String?
    private var lastSymbolName: String?
    private var lastTintColorName: String?

    var onMetadataUpdate: ((String?, String?) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "stream",
                "--style", "compact",
                "--level", "info",
                "--predicate", "subsystem == \"com.apple.focus\""
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                if data.isEmpty {
                    self.queue.async { [weak self] in
                        self?.handleTermination()
                    }
                    return
                }
                self.queue.async { [weak self] in
                    self?.handleIncomingData(data)
                }
            }

            process.terminationHandler = { [weak self] _ in
                self?.queue.async {
                    self?.handleTermination()
                }
            }

            do {
                try process.run()
                self.process = process
                self.pipe = pipe
                self.isRunning = true
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.pipe = nil
                self.isRunning = false
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.handleTermination(terminateProcess: true)
        }
    }

    func latestMetadata() -> (identifier: String?, name: String?, symbolName: String?, tintColorName: String?)? {
        metadataLock.lock()
        let id = lastIdentifier
        let name = lastName
        let symbol = lastSymbolName
        let tint = lastTintColorName
        metadataLock.unlock()

        let cleanId = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTint = tint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleanId?.isEmpty ?? true) && (cleanName?.isEmpty ?? true)
            && (cleanSymbol?.isEmpty ?? true) && (cleanTint?.isEmpty ?? true) {
            return nil
        }
        return (cleanId, cleanName, cleanSymbol, cleanTint)
    }

    private func handleIncomingData(_ data: Data) {
        buffer.append(data)
        let newline: UInt8 = 0x0A

        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty else { continue }
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        if line.contains("active mode assertion: (null)") || line.contains("active activity: (null)") {
            clearMetadata()
            return
        }

        let identifier = extractIdentifier(from: line)
        let name = extractName(from: line)
        let symbol = extractSymbolName(from: line)
        let tint = extractTintName(from: line)

        guard identifier != nil || name != nil || symbol != nil || tint != nil else { return }

        metadataLock.lock()
        if let identifier, !identifier.isEmpty { lastIdentifier = identifier }
        if let name, !name.isEmpty { lastName = name }
        if let symbol, !symbol.isEmpty { lastSymbolName = symbol }
        if let tint, !tint.isEmpty { lastTintColorName = tint }
        let idToSend = lastIdentifier
        let nameToSend = lastName
        metadataLock.unlock()

        onMetadataUpdate?(idToSend, nameToSend)
    }

    private func clearMetadata() {
        metadataLock.lock()
        lastIdentifier = nil
        lastName = nil
        lastSymbolName = nil
        lastTintColorName = nil
        metadataLock.unlock()
    }

    private func handleTermination(terminateProcess: Bool = false) {
        if terminateProcess {
            process?.terminate()
        }

        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        process = nil
        pipe = nil
        buffer.removeAll(keepingCapacity: true)
        isRunning = false
    }

    private func extractIdentifier(from raw: String) -> String? {
        FocusMetadataDecoder.extractIdentifier(from: raw)
    }

    private func extractName(from raw: String) -> String? {
        FocusMetadataDecoder.extractName(from: raw)
    }

    private func extractSymbolName(from raw: String) -> String? {
        FocusMetadataDecoder.extractSymbolName(from: raw)
    }

    private func extractTintName(from raw: String) -> String? {
        FocusMetadataDecoder.extractTintName(from: raw)
    }
}

private enum FocusNotificationParsing {
    static let identifierPattern: NSRegularExpression? = {
        let pattern = "com\\.apple\\.(?:focus|donotdisturb)[A-Za-z0-9_.-]*"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    static let identifierDetailPatterns: [NSRegularExpression] = {
        let patterns = [
            "modeIdentifier:\\s*'([^'\\s]+)'",
            "activityIdentifier:\\s*([A-Za-z0-9._-]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static let namePatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*\"([^\"]+)\"",
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*([^;\\n]+)",
            "activityDisplayName:\\s*([^;>\\n]+)",
            "modeIdentifier:\\s*'com\\.apple\\.focus\\.([A-Za-z0-9._-]+)'"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static let symbolPatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:symbolImageName|symbolName|iconName|sfSymbolName)\\s*=\\s*\"([^\"]+)\"",
            "(?i)(?:symbolImageName|symbolName|iconName|sfSymbolName)\\s*=\\s*([^;\\n]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static let tintPatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:tintColorName|accentColorName|colorName|tintColor)\\s*=\\s*\"([^\"]+)\"",
            "(?i)(?:tintColorName|accentColorName|colorName|tintColor)\\s*=\\s*([^;\\n]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()
}

private enum FocusMetadataDecoder {
    static func cleanedString(_ string: String) -> String {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return trimmed
    }

    static func extractIdentifier(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        if let regex = FocusNotificationParsing.identifierPattern,
           let match = regex.firstMatch(in: description, options: [], range: fullRange),
           match.numberOfRanges > 0,
           let identifierRange = Range(match.range(at: 0), in: description) {
            let candidate = cleanedString(String(description[identifierRange]))
            if !candidate.isEmpty { return candidate }
        }

        for regex in FocusNotificationParsing.identifierDetailPatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let identifierRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[identifierRange]))
                if !candidate.isEmpty { return candidate }
            }
        }

        return nil
    }

    static func extractName(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        for regex in FocusNotificationParsing.namePatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let nameRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[nameRange]))
                if !candidate.isEmpty { return candidate }
            }
        }

        return nil
    }

    static func extractSymbolName(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)
        for regex in FocusNotificationParsing.symbolPatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let symbolRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[symbolRange]))
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }

    static func extractTintName(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)
        for regex in FocusNotificationParsing.tintPatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let tintRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[tintRange]))
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }
}

enum FullDiskAccessAuthorization {
    private static let probeURLs: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
    ]

    static func hasPermission() -> Bool {
        for url in probeURLs {
            if canReadProtectedResource(at: url) {
                return true
            }
        }
        return false
    }

    private static func canReadProtectedResource(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return true
        } catch {
            return false
        }
    }
}

enum FocusModeType: String, CaseIterable {
    case doNotDisturb = "com.apple.donotdisturb.mode"
    case work = "com.apple.focus.work"
    case personal = "com.apple.focus.personal"
    case sleep = "com.apple.focus.sleep"
    case driving = "com.apple.focus.driving"
    case fitness = "com.apple.focus.fitness"
    case gaming = "com.apple.focus.gaming"
    case mindfulness = "com.apple.focus.mindfulness"
    case reading = "com.apple.focus.reading"
    case reduceInterruptions = "com.apple.focus.reduce-interruptions"
    case custom = "com.apple.focus.custom"
    case unknown = ""

    var displayName: String {
        switch self {
        case .doNotDisturb: return "Do Not Disturb"
        case .work: return "Work"
        case .personal: return "Personal"
        case .sleep: return "Sleep"
        case .driving: return "Driving"
        case .fitness: return "Fitness"
        case .gaming: return "Gaming"
        case .mindfulness: return "Mindfulness"
        case .reading: return "Reading"
        case .reduceInterruptions: return "Reduce Interr."
        case .custom: return "Focus"
        case .unknown: return "Focus Mode"
        }
    }

    var sfSymbol: String {
        switch self {
        case .doNotDisturb: return "moon.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .sleep: return "bed.double.fill"
        case .driving: return "car.fill"
        case .fitness: return "figure.run"
        case .gaming: return "gamecontroller.fill"
        case .mindfulness: return "circle.hexagongrid"
        case .reading: return "book.closed.fill"
        case .reduceInterruptions: return "apple.intelligence"
        case .custom: return "moon.fill"
        case .unknown: return "moon.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .doNotDisturb:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work:
            return Color(red: 0.414, green: 0.769, blue: 0.863, opacity: 1.0)
        case .personal:
            return Color(red: 0.748, green: 0.354, blue: 0.948, opacity: 1.0)
        case .sleep:
            return Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving:
            return Color(red: 0.988, green: 0.561, blue: 0.153)
        case .fitness:
            return Color(red: 0.176, green: 0.804, blue: 0.459)
        case .gaming:
            return Color(red: 0.043, green: 0.518, blue: 1.000, opacity: 1.0)
        case .mindfulness:
            return Color(red: 0.361, green: 0.898, blue: 0.883, opacity: 1.0)
        case .reading:
            return Color(red: 1.000, green: 0.622, blue: 0.044, opacity: 1.0)
        case .reduceInterruptions:
            return Color(red: 0.686, green: 0.322, blue: 0.871, opacity: 1.0)
        case .custom:
            return self.getCustomAccentColorFromFile()
        case .unknown:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        }
    }

    var accentColorName: String {
        switch self {
        case .doNotDisturb, .sleep, .unknown: return "systemIndigoColor"
        case .work: return "systemCyanColor"
        case .personal: return "systemPurpleColor"
        case .driving: return "systemOrangeColor"
        case .fitness: return "systemGreenColor"
        case .gaming: return "systemBlueColor"
        case .mindfulness: return "systemTealColor"
        case .reading: return "systemYellowColor"
        case .reduceInterruptions: return "systemPurpleColor"
        case .custom: return "systemIndigoColor"
        }
    }

    init(identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLowercased = normalized.lowercased()

        guard !normalized.isEmpty else {
            self = .doNotDisturb
            return
        }

        if let direct = FocusModeType(rawValue: normalized) ?? FocusModeType(rawValue: normalizedLowercased) {
            self = direct
            return
        }

        if let resolved = FocusModeType.allCases.first(where: {
            guard !$0.rawValue.isEmpty else { return false }
            return normalized.hasPrefix($0.rawValue) || normalizedLowercased.hasPrefix($0.rawValue)
        }) {
            self = resolved
            return
        }

        if normalizedLowercased.hasPrefix("com.apple.focus") {
            self = .custom
            return
        }

        self = .doNotDisturb
    }

    static func resolve(identifier: String?, name: String?) -> FocusModeType {
        if let name, !name.isEmpty {
            let normalizedName = name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if normalizedName.contains("ne pas deranger")
                || normalizedName.contains("do not disturb")
                || normalizedName.contains("not disturb") {
                return .doNotDisturb
            }

            if normalizedName.contains("reduire les interruptions")
                || normalizedName.contains("reduce interruptions")
                || normalizedName.contains("reduce-interruptions")
                || normalizedName.contains("apple intelligence")
                || normalizedName.contains("intelligence") {
                return .reduceInterruptions
            }
        }

        if let identifier, !identifier.isEmpty {
            return FocusModeType(identifier: identifier)
        }

        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .custom
        }

        return .unknown
    }

    func getCustomIconFromFile() -> String {
        FocusMetadataReader.shared.getIcon(for: FocusModeLiveActivityManager.shared.currentFocusModeName)
    }

    func getCustomAccentColorFromFile() -> Color {
        FocusMetadataReader.shared.getAccentColor(for: FocusModeLiveActivityManager.shared.currentFocusModeName)
    }
}

private final class FocusMetadataReader {
    private let pathToDatabase: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")

    struct DNDConfigRoot: Codable {
        let data: [DNDDataEntry]
    }

    struct DNDDataEntry: Codable {
        let modeConfigurations: [String: DNDModeWrapper]
    }

    struct DNDModeWrapper: Codable {
        let mode: DNDMode
    }

    struct DNDMode: Codable {
        let name: String
        let symbolImageName: String?
        let tintColorName: String?
    }

    private struct ModeMatch {
        let modeId: String
        let mode: DNDMode
    }

    private var cachedRoot: DNDConfigRoot?
    private var cachedAt: Date = .distantPast
    private let cacheTTL: TimeInterval = 0.9
    private let queue = DispatchQueue(label: "quartznotch.focus.metadata.reader", qos: .userInitiated)

    private init() {}

    static let shared = FocusMetadataReader()

    private func getModeMatch(for focusName: String, identifier: String? = nil) -> ModeMatch? {
        guard FullDiskAccessAuthorization.hasPermission() else { return nil }
        let normalizedFocus = focusName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFocusForMatch = normalizeForMatching(normalizedFocus)
        let normalizedId = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let shouldUseIdentifier = !normalizedId.isEmpty && !isGenericFocusIdentifier(normalizedId)
        guard !normalizedFocus.isEmpty || shouldUseIdentifier else { return nil }

        return queue.sync {
            guard let root = loadRoot() else { return nil }

            // 1) Name match first: more reliable than generic identifiers like "com.apple.focus".
            if !normalizedFocus.isEmpty {
                for entry in root.data {
                    for (modeId, wrapper) in entry.modeConfigurations {
                        if normalizeForMatching(wrapper.mode.name) == normalizedFocusForMatch {
                            return ModeMatch(modeId: modeId, mode: wrapper.mode)
                        }
                    }
                }
            }

            guard shouldUseIdentifier else { return nil }

            // 2) Identifier match (exact / canonicalized), only for specific identifiers.
            for entry in root.data {
                for (modeId, wrapper) in entry.modeConfigurations {
                    let modeIdLower = modeId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if modeIdLower == normalizedId {
                        return ModeMatch(modeId: modeId, mode: wrapper.mode)
                    }
                    if canonicalizeFocusIdentifier(modeIdLower) == canonicalizeFocusIdentifier(normalizedId) {
                        return ModeMatch(modeId: modeId, mode: wrapper.mode)
                    }
                }
            }
            return nil
        }
    }

    private func loadRoot() -> DNDConfigRoot? {
        let now = Date()
        if let cachedRoot, now.timeIntervalSince(cachedAt) <= cacheTTL {
            return cachedRoot
        }

        do {
            let data = try Data(contentsOf: pathToDatabase)
            let root = try JSONDecoder().decode(DNDConfigRoot.self, from: data)
            cachedRoot = root
            cachedAt = now
            return root
        } catch {
            return cachedRoot
        }
    }

    func getIcon(for focus: String) -> String {
        guard let mode = getModeMatch(for: focus)?.mode else { return "app.badge" }
        return mode.symbolImageName ?? "app.badge"
    }

    func getRawMetadata(for focus: String, identifier: String? = nil) -> (symbol: String?, tint: String?) {
        guard let mode = getModeMatch(for: focus, identifier: identifier)?.mode else { return (nil, nil) }
        return (mode.symbolImageName, mode.tintColorName)
    }

    func getAccentColor(for focus: String) -> Color {
        guard let mode = getModeMatch(for: focus)?.mode,
              let colorName = mode.tintColorName else { return .indigo }
        return Color.stringToColor(for: colorName)
    }

    func getTintName(for focus: String) -> String {
        guard let mode = getModeMatch(for: focus)?.mode,
              let colorName = mode.tintColorName else { return "systemIndigoColor" }
        return colorName
    }

    private func normalizeForMatching(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isGenericFocusIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "com.apple.focus"
            || normalized == "com.apple.focus.mode"
            || normalized == "com.apple.donotdisturb"
            || normalized == "com.apple.donotdisturb.mode"
    }

    private func canonicalizeFocusIdentifier(_ identifier: String) -> String {
        var normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("com.apple.focus.mode.") {
            normalized = normalized.replacingOccurrences(of: "com.apple.focus.mode.", with: "com.apple.focus.")
        }
        return normalized
    }
}

private extension Color {
    static func stringToColor(for string: String) -> Color {
        let cleanName = string.lowercased()
            .replacingOccurrences(of: "system", with: "")
            .replacingOccurrences(of: "color", with: "")

        switch cleanName {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default: return .indigo
        }
    }
}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
}
