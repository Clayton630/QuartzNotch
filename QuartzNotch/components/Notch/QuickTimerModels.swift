
import Foundation
import Combine
import AppKit
import AVFoundation
import ApplicationServices
import Defaults

// MARK: - Preset duration overrides

private enum QuickTimerPresetStorage {
    static let keyPrefix = "quickTimerPresetDuration_"

    static func key(for preset: TimerPreset) -> String {
        keyPrefix + preset.storageKey
    }
}

enum TimerPreset: CaseIterable, Hashable {
    case oneMin
    case threeMin
    case fiveMin

    fileprivate var storageKey: String {
        switch self {
        case .oneMin: return "oneMin"
        case .threeMin: return "threeMin"
        case .fiveMin: return "fiveMin"
        }
    }

    var duration: Int {
        switch self {
        case .oneMin: return 60
        case .threeMin: return 3 * 60
        case .fiveMin: return 5 * 60
        }
    }

    var displayName: String {
        switch self {
        case .oneMin: return "1:00"
        case .threeMin: return "3:00"
        case .fiveMin: return "5:00"
        }
    }

  /// Returns a user-customized duration (in seconds) if one exists.
    var customDurationSeconds: Int? {
        let value = UserDefaults.standard.integer(forKey: QuickTimerPresetStorage.key(for: self))
        return value > 0 ? value : nil
    }

  /// Effective duration used when starting the timer.
    var effectiveDurationSeconds: Int {
        customDurationSeconds ?? duration
    }

  /// Effective label shown in the UI.
    var effectiveDisplayName: String {
        Self.formatHMS(effectiveDurationSeconds)
    }

  /// Persist a custom duration (seconds). Pass `nil` to restore the default.
    func setCustomDurationSeconds(_ seconds: Int?) {
        let key = QuickTimerPresetStorage.key(for: self)
        if let seconds, seconds > 0 {
            UserDefaults.standard.set(seconds, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func formatMMSS(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let minutes = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", minutes, secs)
    }

  /// Formats as `h:mm:ss` when hours are present, otherwise `m:ss`.
    static func formatHMS(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

final class QuickTimer: ObservableObject, Identifiable, Equatable {
    static func == (lhs: QuickTimer, rhs: QuickTimer) -> Bool { lhs.id == rhs.id }

    let id = UUID()
    let preset: TimerPreset
    @Published var remainingSeconds: Int
    @Published var isRunning: Bool = false
    @Published var didFinish: Bool = false

    private var totalDuration: Int
    private var timer: Timer?
    var onFinish: (() -> Void)?

    init(preset: TimerPreset, duration: Int) {
        self.preset = preset
        self.totalDuration = max(1, duration)
        self.remainingSeconds = max(0, duration)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        let elapsed = totalDuration - remainingSeconds
        return min(1.0, max(0.0, Double(elapsed) / Double(totalDuration)))
    }

    var displayTime: String {
        TimerPreset.formatHMS(remainingSeconds)
    }

    func start() {
        guard !isRunning, remainingSeconds > 0 else { return }
        didFinish = false
        isRunning = true
        scheduleTimer()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        pause()
        didFinish = false
        remainingSeconds = 0
    }

    func reset() {
        pause()
        didFinish = false
        remainingSeconds = totalDuration
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            }
            if self.remainingSeconds <= 0 {
                self.pause()
                if !self.didFinish {
                    self.didFinish = true
                    self.onFinish?()
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

final class QuickTimerManager: ObservableObject {
    private enum SystemClockTimerState: Int {
        case stopped = 1
        case running = 2
        case paused = 3
        case fired = 4
        case unknown = 0

        var isVisibleInLiveActivity: Bool {
            switch self {
            case .running, .paused, .fired:
                return true
            default:
                return false
            }
        }
    }

    private struct SystemClockTimerSnapshot {
        let id: String
        let totalSeconds: Int
        let remainingSeconds: Int
        let isRunning: Bool
        let didFinish: Bool
    }

    static let shared = QuickTimerManager()
    @Published private(set) var timers: [QuickTimer] = []
    @Published private(set) var finishEventTick: Int = 0
    @Published private(set) var alertPulseToken: Int = 0
    @Published private(set) var alertPulseStrength: CGFloat = 0
    @Published private(set) var mirroredSystemQuickTimer: QuickTimer?
    @Published private(set) var systemClockMirrorDiagnostics: [String] = []

    private var timerChangeCancellables: [UUID: AnyCancellable] = [:]
    private var systemSyncCancellables: Set<AnyCancellable> = []
    private let systemClockTimerBridge = SystemClockTimerBridge.shared
    private var ringingTimerIDs: Set<UUID> = []
    private var alarmPlayer: AVAudioPlayer?
    private var alarmPlayerURL: URL?
    private var activeAlertToneID: String?
    private var alertPulseTask: Task<Void, Never>?
    private var systemTimerLogProcess: Process?
    private var systemTimerLogPipe: Pipe?
    private var systemTimerLogBuffer = Data()
    private var systemTimerLogLatestRemainingSeconds: Int?
    private var systemTimerLogLatestPaused: Bool = false
    private var systemTimerLogLastUpdateAt: Date?
    private var systemTimerLogIdentifier: String?
    private var systemTimerLogPreferredDurationSeconds: Int?
    private var systemTimerLogPreferredName: String?
    private let toneLibraryRingtonesRoot = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones"
    private let toneLibraryAlertTonesRoot = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones"
    private let mobileTimerDomain = "com.apple.mobiletimerd" as CFString

    private init() {
        setupBridgeSync()
    }

    private func setupBridgeSync() {
        systemClockTimerBridge.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            let total = max(1, Int(round(snapshot.totalDuration)))
            let remaining = max(0, Int(round(snapshot.remaining)))
            let isRunning = !snapshot.isPaused && !snapshot.isFinished
            let didFinish = snapshot.isFinished
            DispatchQueue.main.async {
                if let existing = self.mirroredSystemQuickTimer {
                    let oldRemaining = existing.remainingSeconds
                    let looksLikeNewRun = remaining > oldRemaining + 2

                    if looksLikeNewRun {
                        let timer = QuickTimer(preset: .oneMin, duration: total)
                        timer.remainingSeconds = remaining
                        timer.isRunning = isRunning
                        timer.didFinish = didFinish
                        self.mirroredSystemQuickTimer = timer
                    } else {
                        if existing.remainingSeconds != remaining {
                            existing.remainingSeconds = remaining
                        }
                        if existing.isRunning != isRunning {
                            existing.isRunning = isRunning
                        }
                        if existing.didFinish != didFinish {
                            existing.didFinish = didFinish
                        }
                    }
                } else {
                    let timer = QuickTimer(preset: .oneMin, duration: total)
                    timer.remainingSeconds = remaining
                    timer.isRunning = isRunning
                    timer.didFinish = didFinish
                    self.mirroredSystemQuickTimer = timer
                }
            }
        }

        systemClockTimerBridge.onClear = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.mirroredSystemQuickTimer != nil else { return }
                self.mirroredSystemQuickTimer = nil
            }
        }

        systemClockTimerBridge.onDiagnostics = { [weak self] diagnostics in
            DispatchQueue.main.async {
                guard let self, self.systemClockMirrorDiagnostics != diagnostics.renderedLines else { return }
                self.systemClockMirrorDiagnostics = diagnostics.renderedLines
            }
        }

        systemClockTimerBridge.requestImmediateProbe()
    }

    func refreshSystemClockMirrorDiagnostics() {
        systemClockTimerBridge.requestImmediateProbe()
    }

    private func setupSystemClockTimerSync() {
        Defaults.publisher(.mirrorSystemClockTimer)
            .sink { [weak self] change in
                guard let self else { return }
                if !change.newValue {
                    self.stopSystemTimerLogStream()
                    self.systemTimerLogLatestRemainingSeconds = nil
                    self.systemTimerLogLastUpdateAt = nil
                    DispatchQueue.main.async {
                        self.mirroredSystemQuickTimer = nil
                    }
                } else {
                    self.requestAccessibilityForSystemTimerIfNeeded()
                    self.startSystemTimerLogStreamIfNeeded()
                    self.pollSystemClockTimer()
                }
            }
            .store(in: &systemSyncCancellables)

        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollSystemClockTimer()
            }
            .store(in: &systemSyncCancellables)

        if Defaults[.mirrorSystemClockTimer] {
            requestAccessibilityForSystemTimerIfNeeded()
            startSystemTimerLogStreamIfNeeded()
        }
        pollSystemClockTimer()
    }

    private func requestAccessibilityForSystemTimerIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startSystemTimerLogStreamIfNeeded() {
        guard systemTimerLogProcess == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "ndjson",
            "--predicate", "subsystem == \"com.apple.mobiletimer.logging\"",
            "--level", "debug"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        systemTimerLogPipe = pipe
        systemTimerLogBuffer.removeAll(keepingCapacity: false)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consumeSystemTimerLogData(data)
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.systemTimerLogPipe?.fileHandleForReading.readabilityHandler = nil
            self.systemTimerLogPipe = nil
            self.systemTimerLogProcess = nil

            guard Defaults[.mirrorSystemClockTimer] else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startSystemTimerLogStreamIfNeeded()
            }
        }

        do {
            try process.run()
            systemTimerLogProcess = process
        } catch {
            systemTimerLogPipe?.fileHandleForReading.readabilityHandler = nil
            systemTimerLogPipe = nil
            systemTimerLogProcess = nil
        }
    }

    private func stopSystemTimerLogStream() {
        systemTimerLogPipe?.fileHandleForReading.readabilityHandler = nil
        systemTimerLogPipe = nil
        if let process = systemTimerLogProcess {
            if process.isRunning {
                process.terminate()
            }
            systemTimerLogProcess = nil
        }
        systemTimerLogBuffer.removeAll(keepingCapacity: false)
    }

    private func consumeSystemTimerLogData(_ data: Data) {
        systemTimerLogBuffer.append(data)

        while let newline = systemTimerLogBuffer.firstIndex(of: 0x0A) {
            let lineData = systemTimerLogBuffer.prefix(upTo: newline)
            systemTimerLogBuffer.removeSubrange(...newline)
            handleSystemTimerLogLine(lineData)
        }
    }

    private func handleSystemTimerLogLine(_ lineData: Data) {
        guard !lineData.isEmpty else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let message = obj["eventMessage"] as? String,
              !message.isEmpty
        else { return }

        if message.contains("scheduled timers:") {
            handleSystemScheduledTimersMessage(message)
        }

        if message.contains("started timer:"),
           let identifier = captureFirstMatch(pattern: "started timer:\\s*([A-Fa-f0-9\\-]+)", in: message) {
            systemTimerLogIdentifier = identifier.uppercased()
            systemTimerLogLatestPaused = false
            systemTimerLogLastUpdateAt = Date()
        }

        if message.contains("Timer will fire"),
           let minutesString = captureFirstMatch(pattern: "Timer will fire\\s+([0-9.]+)\\s+minutes?", in: message),
           let minutes = Double(minutesString) {
            let seconds = max(0, Int(round(minutes * 60.0)))
            systemTimerLogLatestRemainingSeconds = seconds
            if let existing = systemTimerLogPreferredDurationSeconds {
                systemTimerLogPreferredDurationSeconds = max(existing, seconds)
            } else {
                systemTimerLogPreferredDurationSeconds = seconds
            }
            systemTimerLogLatestPaused = false
            systemTimerLogLastUpdateAt = Date()
        }

        if message.contains("Timer stopped") {
            systemTimerLogLatestPaused = true
            systemTimerLogLastUpdateAt = Date()
            systemTimerLogIdentifier = nil
            return
        }

        if let remaining = extractRemainingSeconds(fromLogMessage: message) {
            systemTimerLogLatestRemainingSeconds = max(0, remaining)
            systemTimerLogLatestPaused = message.lowercased().contains("paused")
            systemTimerLogLastUpdateAt = Date()
        }
    }

    private func captureFirstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let swiftRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private func handleSystemScheduledTimersMessage(_ message: String) {
        guard let regex = try? NSRegularExpression(pattern: "<MT(?:Mutable)?Timer:[^>]+>") else { return }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = regex.matches(in: message, options: [], range: range)
        guard !matches.isEmpty else { return }

        for match in matches {
            guard let r = Range(match.range, in: message) else { continue }
            let entry = String(message[r])

            let state = captureFirstMatch(pattern: "state:([A-Za-z]+)", in: entry)?.lowercased()
            guard state == "running" || state == "paused" || state == "fired" else { continue }

            if let id = captureFirstMatch(pattern: "TimerID:\\s*([A-Fa-f0-9\\-]+)", in: entry) {
                systemTimerLogIdentifier = id.uppercased()
            }

            if let title = captureFirstMatch(pattern: "Title:\\s*([^,]+)", in: entry) {
                let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned != "(null)" {
                    systemTimerLogPreferredName = cleaned
                }
            }

            if let durationString = captureFirstMatch(pattern: "duration:([0-9]+(?:\\.[0-9]+)?)", in: entry),
               let duration = Double(durationString) {
                let d = max(1, Int(round(duration)))
                if let existing = systemTimerLogPreferredDurationSeconds {
                    systemTimerLogPreferredDurationSeconds = max(existing, d)
                } else {
                    systemTimerLogPreferredDurationSeconds = d
                }
            }

            if state == "paused" {
                systemTimerLogLatestPaused = true
            } else {
                systemTimerLogLatestPaused = false
            }
            systemTimerLogLastUpdateAt = Date()
            break
        }
    }

    private func extractRemainingSeconds(fromLogMessage message: String) -> Int? {
        let pattern = #"remainingTime:\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: message),
              let value = Double(message[valueRange])
        else {
            return nil
        }
        return Int(round(value))
    }

    private func pollSystemClockTimer() {
        guard Defaults[.mirrorSystemClockTimer] else { return }
        let plistSnapshot = fetchSystemClockTimerSnapshot()
        var snapshot = fetchSystemClockTimerSnapshotFromMenuBar(baseTotal: plistSnapshot?.totalSeconds) ?? plistSnapshot

        if snapshot == nil,
           let lastUpdate = systemTimerLogLastUpdateAt,
           Date().timeIntervalSince(lastUpdate) <= 4.0,
           let logRemaining = systemTimerLogLatestRemainingSeconds {
            let total = max(systemTimerLogPreferredDurationSeconds ?? logRemaining, logRemaining, 1)
            let didFinish = logRemaining <= 0
            snapshot = .init(
                id: systemTimerLogIdentifier ?? "system-clock-log",
                totalSeconds: total,
                remainingSeconds: logRemaining,
                isRunning: !systemTimerLogLatestPaused && !didFinish,
                didFinish: didFinish
            )
        }

        DispatchQueue.main.async {
            guard let snapshot else {
                self.mirroredSystemQuickTimer = nil
                return
            }

            var remaining = max(0, snapshot.remainingSeconds)
            var isRunning = snapshot.isRunning

            if let lastUpdate = self.systemTimerLogLastUpdateAt,
               Date().timeIntervalSince(lastUpdate) <= 2.2,
               let loggedRemaining = self.systemTimerLogLatestRemainingSeconds {
                remaining = loggedRemaining
                isRunning = !self.systemTimerLogLatestPaused
            }

            let timer = QuickTimer(preset: .oneMin, duration: max(1, snapshot.totalSeconds))
            timer.remainingSeconds = remaining
            timer.isRunning = isRunning
            timer.didFinish = snapshot.didFinish || remaining <= 0
            self.mirroredSystemQuickTimer = timer
        }
    }

    private func copyAXAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &raw)
        guard status == .success else { return nil }
        return raw as? T
    }

    private func extractSecondsFromTimerString(_ value: String) -> Int? {
        let pattern = #"\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else { return nil }
        guard let mRange = Range(match.range(at: 1), in: value),
              let sRange = Range(match.range(at: 2), in: value)
        else {
            return nil
        }

        let first = Int(value[mRange]) ?? 0
        let second = Int(value[sRange]) ?? 0
        if let hRange = Range(match.range(at: 3), in: value) {
            let third = Int(value[hRange]) ?? 0
            return max(0, first * 3600 + second * 60 + third)
        }
        return max(0, first * 60 + second)
    }

    private func parseTimerFromAXText(_ text: String) -> (seconds: Int, isPaused: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let seconds = extractSecondsFromTimerString(trimmed) else { return nil }
        let lower = trimmed.lowercased()
        let isPaused = lower.contains("pause") || lower.contains("paused") || lower.contains("stopped")
        return (seconds, isPaused)
    }

    private func matchesTimerTextForAX(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased().contains("timer") { return true }
        let pattern = "[0-9]+(?::[0-9]{2}){0,2}"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func isTimerMenuExtraAX(_ element: AXUIElement) -> Bool {
        if let identifier: String = copyAXAttribute(kAXIdentifierAttribute as CFString, from: element),
           identifier.lowercased().contains("timer") {
            return true
        }
        if let title: String = copyAXAttribute(kAXTitleAttribute as CFString, from: element),
           matchesTimerTextForAX(title) {
            return true
        }
        if let value: String = copyAXAttribute(kAXValueAttribute as CFString, from: element),
           matchesTimerTextForAX(value) {
            return true
        }
        if let children: [AXUIElement] = copyAXAttribute(kAXChildrenAttribute as CFString, from: element) {
            for child in children {
                if let value: String = copyAXAttribute(kAXValueAttribute as CFString, from: child),
                   matchesTimerTextForAX(value) {
                    return true
                }
                if let title: String = copyAXAttribute(kAXTitleAttribute as CFString, from: child),
                   matchesTimerTextForAX(title) {
                    return true
                }
            }
        }
        return false
    }

    private func locateTimerMenuExtraAX() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let menuBar: AXUIElement = copyAXAttribute(kAXMenuBarAttribute as CFString, from: systemWide),
              let items: [AXUIElement] = copyAXAttribute(kAXChildrenAttribute as CFString, from: menuBar)
        else {
            return nil
        }

        for item in items where isTimerMenuExtraAX(item) {
            return item
        }
        return nil
    }

    private func extractTimerStringFromAX(_ element: AXUIElement) -> (seconds: Int, isPaused: Bool)? {
        if let value: String = copyAXAttribute(kAXValueAttribute as CFString, from: element),
           let parsed = parseTimerFromAXText(value) {
            return parsed
        }
        if let title: String = copyAXAttribute(kAXTitleAttribute as CFString, from: element),
           let parsed = parseTimerFromAXText(title) {
            return parsed
        }
        if let children: [AXUIElement] = copyAXAttribute(kAXChildrenAttribute as CFString, from: element) {
            for child in children {
                if let value: String = copyAXAttribute(kAXValueAttribute as CFString, from: child),
                   let parsed = parseTimerFromAXText(value) {
                    return parsed
                }
                if let title: String = copyAXAttribute(kAXTitleAttribute as CFString, from: child),
                   let parsed = parseTimerFromAXText(title) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func fetchSystemClockTimerSnapshotFromMenuBar(baseTotal: Int?) -> SystemClockTimerSnapshot? {
        guard AXIsProcessTrusted() else { return nil }

        guard let timerExtra = locateTimerMenuExtraAX(),
              let parsed = extractTimerStringFromAX(timerExtra) else { return nil }

        let total = max(baseTotal ?? parsed.seconds, parsed.seconds, 1)
        let didFinish = parsed.seconds <= 0
        let running = !parsed.isPaused && !didFinish
        return .init(
            id: "system-clock-menubar",
            totalSeconds: total,
            remainingSeconds: parsed.seconds,
            isRunning: running,
            didFinish: didFinish
        )
    }

    private func fetchSystemClockTimerSnapshot() -> SystemClockTimerSnapshot? {
        CFPreferencesAppSynchronize(mobileTimerDomain)

        guard let timersContainer = CFPreferencesCopyAppValue("MTTimers" as CFString, mobileTimerDomain) as? [String: Any],
              let timers = timersContainer["MTTimers"] as? [[String: Any]]
        else {
            return nil
        }

        let now = Date()
        let lastTriggerDate = CFPreferencesCopyAppValue("MTTimerLastTriggerDate" as CFString, mobileTimerDomain) as? Date

        let preferred = timers.sorted { lhs, rhs in
            let l = ((lhs["$MTTimer"] as? [String: Any])?["MTTimerTitle"] as? String) == "CURRENT_TIMER"
            let r = ((rhs["$MTTimer"] as? [String: Any])?["MTTimerTitle"] as? String) == "CURRENT_TIMER"
            return l && !r
        }

        for entry in preferred {
            guard let timer = entry["$MTTimer"] as? [String: Any] else { continue }

            let stateRaw = timer["MTTimerState"] as? Int ?? 0
            let state = SystemClockTimerState(rawValue: stateRaw) ?? .unknown

            let id = timer["MTTimerID"] as? String ?? UUID().uuidString
            let total = max(1, Int((timer["MTTimerDuration"] as? Double) ?? 0))
            let title = (timer["MTTimerTitle"] as? String) ?? ""

            var remaining = total
            if let fireTime = timer["MTTimerFireTime"] as? [String: Any],
               let interval = fireTime["$MTTimerTimeInterval"] as? [String: Any],
               let value = interval["MTTimerTimeInterval"] as? Double {
                remaining = max(0, Int(round(value)))
            }

            if state == .fired {
                remaining = 0
            }

            var isRunning = (state == .running)
            var didFinish = (state == .fired) || remaining <= 0
            let hasProgressFromDuration = remaining > 0 && remaining < total

            if !state.isVisibleInLiveActivity, title == "CURRENT_TIMER", let start = lastTriggerDate {
                let elapsed = now.timeIntervalSince(start)
                let estimatedRemaining = max(0, Int(round(Double(total) - elapsed)))
                if elapsed >= 0, estimatedRemaining > 0 {
                    remaining = estimatedRemaining
                    isRunning = true
                    didFinish = false
                } else if elapsed >= 0, estimatedRemaining == 0 {
                    remaining = 0
                    isRunning = false
                    didFinish = true
                }
            }

            if !state.isVisibleInLiveActivity, !isRunning, !didFinish, hasProgressFromDuration {
                isRunning = true
            }

            let inferVisibleFromCurrentEntry = (title == "CURRENT_TIMER") && (hasProgressFromDuration || didFinish)
            guard state.isVisibleInLiveActivity || isRunning || didFinish || inferVisibleFromCurrentEntry else { continue }
            return .init(
                id: id,
                totalSeconds: total,
                remainingSeconds: remaining,
                isRunning: isRunning,
                didFinish: didFinish
            )
        }

        return nil
    }

    private func resolveConfiguredAlertSoundURL(from configured: String) -> URL? {
        let value = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let fm = FileManager.default

        if value.hasPrefix("/") {
            let url = URL(fileURLWithPath: value)
            if fm.fileExists(atPath: url.path) { return url }
        }

        let baseName = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: value).pathExtension
        let exts = ext.isEmpty ? ["aiff", "aif", "caf", "wav", "m4a"] : [ext]
        let roots = [
            "/System/Library/Sounds",
            "/Library/Sounds",
            (NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? "") + "/Sounds"
        ]

        for root in roots where !root.isEmpty {
            for e in exts {
                let path = "\(root)/\(baseName).\(e)"
                if fm.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        return nil
    }

    private func normalizedToneKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func resolveClockTimerToneID() -> String? {
        if let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.mobiletimerd"),
           let timersContainer = domain["MTTimers"] as? [String: Any],
           let timers = timersContainer["MTTimers"] as? [[String: Any]] {
            let orderedTimers = timers.sorted { lhs, rhs in
                let l = ((lhs["$MTTimer"] as? [String: Any])?["MTTimerTitle"] as? String) == "CURRENT_TIMER"
                let r = ((rhs["$MTTimer"] as? [String: Any])?["MTTimerTitle"] as? String) == "CURRENT_TIMER"
                return l && !r
            }

            for entry in orderedTimers {
                guard let timer = entry["$MTTimer"] as? [String: Any],
                      let timerSound = timer["MTTimerSound"] as? [String: Any],
                      let sound = timerSound["$MTSound"] as? [String: Any],
                      let candidate = sound["MTSoundToneID"] as? String,
                      !candidate.isEmpty
                else { continue }
                return candidate
            }
        }

        let plistURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.mobiletimerd.plist")

        guard let root = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            return nil
        }

        if let latestData = root["kMTTimerDurationLatest"] as? Data,
           let decoded = try? PropertyListSerialization.propertyList(from: latestData, options: [], format: nil) as? [String: Any],
           let objects = decoded["$objects"] as? [Any] {
            for obj in objects {
                if let dict = obj as? [String: Any],
                   let id = dict["MTSoundToneID"] as? String,
                   !id.isEmpty {
                    return id
                }
            }
        }

        if let timersContainer = root["MTTimers"] as? [String: Any],
           let timers = timersContainer["MTTimers"] as? [[String: Any]] {
            let orderedTimers = timers.sorted { lhs, rhs in
                let l = ((lhs["$MTTimer"] as? [String: Any])?["MTTimerTitle"] as? String) == "CURRENT_TIMER"
                let r = ((rhs["$MTTimer"] as? [String: Any])?["MTTimerTitle"] as? String) == "CURRENT_TIMER"
                return l && !r
            }

            for entry in orderedTimers {
                guard let timer = entry["$MTTimer"] as? [String: Any],
                      let timerSound = timer["MTTimerSound"] as? [String: Any],
                      let sound = timerSound["$MTSound"] as? [String: Any],
                      let candidate = sound["MTSoundToneID"] as? String,
                      !candidate.isEmpty
                else { continue }
                return candidate
            }
        }

        return nil
    }

    private func resolveToneURL(from toneID: String) -> URL? {
        let rawName = toneID.split(separator: ":").last.map(String.init) ?? toneID
        let target = normalizedToneKey(rawName)
        guard !target.isEmpty else { return nil }

        let fm = FileManager.default
        let roots = [toneLibraryRingtonesRoot, toneLibraryAlertTonesRoot]
        var candidates: [(url: URL, key: String)] = []

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for file in entries {
                let base = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                let key = normalizedToneKey(base)
                let url = URL(fileURLWithPath: root).appendingPathComponent(file)
                candidates.append((url: url, key: key))
            }
        }

        if let match = candidates.first(where: { $0.key == target }) {
            return match.url
        }

        if let match = candidates.first(where: { $0.key.hasPrefix(target) }) {
            return match.url
        }

        if let match = candidates.first(where: { $0.key.contains(target) }) {
            return match.url
        }

        return nil
    }

    private func resolveClockTimerToneURL() -> URL? {
        guard let toneID = resolveClockTimerToneID() else { return nil }
        return resolveToneURL(from: toneID)
    }

    private func resolvePreferredAlertAudioURL() -> URL? {
        let selectedTone = Defaults[.quickTimerAlertToneID]

        if selectedTone == "globalAlert",
           let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain),
           let configured = global["com.apple.sound.beep.sound"] as? String,
           !configured.isEmpty,
           let url = resolveConfiguredAlertSoundURL(from: configured) {
            return url
        }

        if selectedTone != "systemDefault",
           let selectedURL = resolveToneURL(from: selectedTone) {
            return selectedURL
        }

        if let timerToneURL = resolveClockTimerToneURL() {
            return timerToneURL
        }

        let alarmURL = URL(fileURLWithPath: toneLibraryRingtonesRoot).appendingPathComponent("Alarm.m4r")
        if FileManager.default.fileExists(atPath: alarmURL.path) {
            return alarmURL
        }

        if let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain),
           let configured = global["com.apple.sound.beep.sound"] as? String,
           !configured.isEmpty,
           let url = resolveConfiguredAlertSoundURL(from: configured) {
            return url
        }

        return nil
    }

    private func resolvePreferredAlertToneID() -> String {
        let selectedTone = Defaults[.quickTimerAlertToneID]
        if selectedTone == "globalAlert" {
            return "globalAlert"
        }
        if selectedTone != "systemDefault" {
            return selectedTone
        }
        return resolveClockTimerToneID() ?? "system:Alarm"
    }

    private func normalizedPulseToneID(_ toneID: String) -> String {
        toneID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func pulsePattern(for toneID: String) -> [Double] {
        let t = normalizedPulseToneID(toneID)
        if t.contains("radial") {
            return [0.18, 0.22, 0.44]
        }
        if t.contains("radar") {
            return [0.26, 0.26, 0.26, 0.52]
        }
        if t.contains("alarm") {
            return [0.40, 0.40]
        }
        if t.contains("beacon") || t.contains("chimes") {
            return [0.30, 0.48]
        }
        return [0.42]
    }

    private func pulseStrength(step: Int, patternCount: Int) -> CGFloat {
        guard patternCount > 1 else { return 1.0 }
        return (step % patternCount == 0) ? 1.0 : 0.72
    }

    private func startAlertPulseLoopIfNeeded() {
        guard !ringingTimerIDs.isEmpty else { return }
        if alertPulseTask != nil { return }

        let toneID = activeAlertToneID ?? resolvePreferredAlertToneID()
        let pattern = pulsePattern(for: toneID)
        let count = max(1, pattern.count)

        alertPulseTask = Task { [weak self] in
            var step = 0
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self else { return }
                    self.alertPulseStrength = self.pulseStrength(step: step, patternCount: count)
                    self.alertPulseToken &+= 1
                }

                let interval = pattern[step % count]
                let nanos = UInt64(max(0.05, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                step += 1
            }
        }
    }

    private func stopAlertPulseLoopIfNeeded() {
        guard ringingTimerIDs.isEmpty else { return }
        alertPulseTask?.cancel()
        alertPulseTask = nil
        alertPulseStrength = 0
    }

    private func startAlertLoopIfNeeded() {
        guard !ringingTimerIDs.isEmpty else { return }
        guard let url = resolvePreferredAlertAudioURL() else { return }
        activeAlertToneID = resolvePreferredAlertToneID()

        if alarmPlayer?.isPlaying == true, alarmPlayerURL == url {
            startAlertPulseLoopIfNeeded()
            return
        }

        alarmPlayer?.stop()
        alarmPlayer = nil
        alarmPlayerURL = nil

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            alarmPlayer = player
            alarmPlayerURL = url
            startAlertPulseLoopIfNeeded()
        } catch {
            alarmPlayer = nil
            alarmPlayerURL = nil
        }
    }

    private func stopAlertLoopIfNeeded() {
        guard ringingTimerIDs.isEmpty else { return }
        alarmPlayer?.stop()
        alarmPlayer = nil
        alarmPlayerURL = nil
        activeAlertToneID = nil
        stopAlertPulseLoopIfNeeded()
    }

    private func markTimerFinished(_ timer: QuickTimer) {
        ringingTimerIDs.insert(timer.id)
        startAlertLoopIfNeeded()
    }

    private func clearTimerFinishedState(_ timer: QuickTimer) {
        ringingTimerIDs.remove(timer.id)
        stopAlertLoopIfNeeded()
    }

    private func observeTimer(_ timer: QuickTimer) {
        timer.onFinish = { [weak self] in
            DispatchQueue.main.async {
                self?.markTimerFinished(timer)
                self?.finishEventTick += 1
                self?.objectWillChange.send()
            }
        }
        timerChangeCancellables[timer.id] = timer.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func unobserveTimer(_ timer: QuickTimer) {
        timerChangeCancellables[timer.id]?.cancel()
        timerChangeCancellables[timer.id] = nil
        timer.onFinish = nil
        clearTimerFinishedState(timer)
    }

    func startTimer(duration: Int, preset: TimerPreset) {
        if let existing = timers.first(where: { $0.preset == preset }) {
            observeTimer(existing)
            clearTimerFinishedState(existing)
            existing.reset()
            existing.start()
            return
        }
        let timer = QuickTimer(preset: preset, duration: duration)
        observeTimer(timer)
        timers.append(timer)
        timer.start()
    }

    func stopTimer(_ timer: QuickTimer) {
        if isMirroredSystemTimer(timer) { return }
        timer.stop()
        unobserveTimer(timer)
        timers.removeAll { $0.id == timer.id }
    }

    func toggleTimer(_ timer: QuickTimer) {
        if isMirroredSystemTimer(timer) { return }
        if timer.isRunning {
            timer.pause()
        } else {
            if timer.remainingSeconds == 0 {
                clearTimerFinishedState(timer)
                timer.reset()
            }
            timer.start()
        }
    }

    func resetTimer(_ timer: QuickTimer) {
        if isMirroredSystemTimer(timer) { return }
        clearTimerFinishedState(timer)
        timer.reset()
    }

    func isMirroredSystemTimer(_ timer: QuickTimer) -> Bool {
        mirroredSystemQuickTimer?.id == timer.id
    }
}

// MARK: - System Clock Timer Bridge (inlined for target compatibility)


final class SystemClockTimerBridge {
    struct Snapshot: Equatable {
        let remaining: TimeInterval
        let totalDuration: TimeInterval
        let isPaused: Bool
        let name: String
        let isFinished: Bool
    }

    static let shared = SystemClockTimerBridge()

    var onSnapshot: ((Snapshot) -> Void)?
    var onClear: ((Bool) -> Void)?
    var onDiagnostics: ((Diagnostics) -> Void)?

    struct Diagnostics: Equatable {
        let renderedLines: [String]
    }

    private enum SnapshotSource: String {
        case log = "LOG"
        case ax = "AX"
        case metadata = "PLIST"
        case inferred = "INFERRED"
        case unknown = "UNKNOWN"
    }

    private struct TimerMetadata: Equatable {
        enum State: Int {
            case stopped = 1
            case running = 2
            case paused = 3
            case fired = 4
            case unknown = 0

            var isActive: Bool {
                switch self {
                case .running, .paused:
                    return true
                default:
                    return false
                }
            }
        }

        let identifier: String
        let title: String
        let duration: TimeInterval
        let lastModified: Date?
        let firedDate: Date?
        let state: State
    }

    private struct ParsedTimerString {
        let remaining: TimeInterval
        let paused: Bool
    }

    private struct LogTimerEntry {
        let identifier: String
        let state: String?
        let title: String?
        let duration: Double?
    }

    private let domain = "com.apple.mobiletimerd" as CFString
    private let preferencesPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Preferences/com.apple.mobiletimerd.plist")
    private let queue = DispatchQueue(label: "com.quartznotch.systemtimer.bridge", qos: .userInitiated)

    private var metadata: TimerMetadata?
    private var initialTotalDuration: TimeInterval?
    private var latestRemaining: TimeInterval?
    private var latestPaused: Bool = false

    private var logProcess: Process?
    private var logPipe: Pipe?
    private var logBuffer = Data()
    private var logRestartWorkItem: DispatchWorkItem?
    private var logPreferredName: String?
    private var logPreferredDuration: TimeInterval?
    private var logIdentifier: String?
    private var logDidCompleteActiveTimer = false
    private var lastSnapshotSource: SnapshotSource = .unknown
    private var lastSnapshotAt: Date?
    private var lastSnapshotRemaining: TimeInterval?
    private var lastPublishedSnapshot: Snapshot?
    private var lastPublishedDiagnostics: Diagnostics?
    private var hasPublishedActiveSnapshot = false
    private var hasPublishedClear = true
    private var lastEvent: String = "idle"
    private var lastClearReason: String = "none"

    private var menuExtra: AXUIElement?
    private var fileDescriptor: CInt = -1
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var ticker: DispatchSourceTimer?
    private var metadataTicker: DispatchSourceTimer?
    private var defaultsCancellable: AnyCancellable?

    private init() {
        defaultsCancellable = Defaults.publisher(.mirrorSystemClockTimer, options: [])
            .sink { [weak self] change in
                if change.newValue {
                    self?.startIfNeeded()
                } else {
                    self?.stopMonitoring(clearTimer: true)
                }
            }

        if Defaults[.mirrorSystemClockTimer] {
            startIfNeeded()
        }
    }

    private var isMonitoring: Bool {
        logProcess != nil || ticker != nil || metadataTicker != nil || fileMonitor != nil
    }

    func requestImmediateProbe() {
        queue.async { [weak self] in
            guard let self else { return }
            if Defaults[.mirrorSystemClockTimer], !self.isMonitoring {
                self.startIfNeeded()
            }
            self.lastEvent = "manual_probe"
            self.refreshMetadata()
            self.pollMenuExtra()
            self.publishDiagnostics(force: true)
        }
    }

    private func markSnapshot(_ source: SnapshotSource, remaining: TimeInterval) {
        lastSnapshotSource = source
        lastSnapshotAt = Date()
        lastSnapshotRemaining = remaining
    }

    private func publishDiagnostics(force: Bool = false) {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let snapshotText = lastSnapshotAt.map { fmt.string(from: $0) } ?? "never"
        let mirrorEnabled = Defaults[.mirrorSystemClockTimer] ? "ON" : "OFF"
        let axTrusted = AXIsProcessTrusted() ? "YES" : "NO"
        let metadataState = metadata.map { "\($0.state.rawValue)" } ?? "none"
        let metadataTitle = metadata?.title ?? "none"
        let metadataDuration = metadata.map { Int($0.duration.rounded()) } ?? 0
        let logRunning = (logProcess?.isRunning == true) ? "YES" : "NO"
        let tickerRunning = (ticker != nil) ? "YES" : "NO"
        let metadataTickerRunning = (metadataTicker != nil) ? "YES" : "NO"
        let fileMonitorRunning = (fileMonitor != nil) ? "YES" : "NO"
        let remainingText = latestRemaining.map { String(Int($0.rounded())) } ?? "nil"
        let lastSnapshotRemainingText = lastSnapshotRemaining.map { String(Int($0.rounded())) } ?? "nil"
        let lines = [
            "Mirror toggle: \(mirrorEnabled)",
            "Monitoring: \(isMonitoring ? "YES" : "NO")",
            "AX trusted: \(axTrusted)",
            "Log stream: \(logRunning)",
            "AX ticker: \(tickerRunning)",
            "Metadata ticker: \(metadataTickerRunning)",
            "Plist monitor: \(fileMonitorRunning)",
            "Metadata state: \(metadataState)",
            "Metadata title: \(metadataTitle)",
            "Metadata duration(s): \(metadataDuration)",
            "Log identifier: \(logIdentifier ?? "none")",
            "Latest remaining(s): \(remainingText)",
            "Latest paused: \(latestPaused ? "YES" : "NO")",
            "Last snapshot source: \(lastSnapshotSource.rawValue)",
            "Last snapshot at: \(snapshotText)",
            "Last snapshot remaining(s): \(lastSnapshotRemainingText)",
            "Last event: \(lastEvent)",
            "Last clear reason: \(lastClearReason)"
        ]

        let diagnostics = Diagnostics(renderedLines: lines)
        guard force || diagnostics != lastPublishedDiagnostics else { return }
        lastPublishedDiagnostics = diagnostics

        DispatchQueue.main.async { [weak self] in
            self?.onDiagnostics?(diagnostics)
        }
    }

    private func emitSnapshot(_ snapshot: Snapshot, source: SnapshotSource) {
        let roundedSnapshot = Snapshot(
            remaining: snapshot.remaining.rounded(),
            totalDuration: snapshot.totalDuration.rounded(),
            isPaused: snapshot.isPaused,
            name: snapshot.name,
            isFinished: snapshot.isFinished
        )
        guard roundedSnapshot != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = roundedSnapshot
        hasPublishedActiveSnapshot = true
        hasPublishedClear = false
        markSnapshot(source, remaining: snapshot.remaining)
        publishDiagnostics()
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(roundedSnapshot)
        }
    }

    private func emitClear(_ animated: Bool) {
        guard hasPublishedActiveSnapshot || !hasPublishedClear else { return }
        lastPublishedSnapshot = nil
        hasPublishedActiveSnapshot = false
        hasPublishedClear = true
        DispatchQueue.main.async { [weak self] in
            self?.onClear?(animated)
        }
    }

    private func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isMonitoring else { return }
            self.lastEvent = "start_monitoring"

            let hasAccessibility = AXIsProcessTrusted()

            self.refreshMetadata()
            self.startFileMonitor()
            self.setupMetadataTicker()

            let logStarted = self.startLogStream()
            if hasAccessibility, self.ticker == nil {
                self.setupTicker()
            } else if !logStarted {
                self.lastClearReason = "no_log_and_no_ax"
                self.publishDiagnostics()
            }
            self.publishDiagnostics()
        }
    }

    private func stopMonitoring(clearTimer: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastEvent = "stop_monitoring"

            self.stopLogStream()
            self.ticker?.cancel()
            self.ticker = nil
            self.metadataTicker?.cancel()
            self.metadataTicker = nil
            self.fileMonitor?.cancel()
            self.fileMonitor = nil

            if self.fileDescriptor != -1 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }

            self.menuExtra = nil
            self.initialTotalDuration = nil
            self.metadata = nil
            self.latestRemaining = nil
            self.latestPaused = false
            self.logPreferredName = nil
            self.logPreferredDuration = nil
            self.logIdentifier = nil
            self.logDidCompleteActiveTimer = false
            self.lastSnapshotAt = nil
            self.lastSnapshotRemaining = nil
            self.lastSnapshotSource = .unknown
            self.logRestartWorkItem?.cancel()
            self.logRestartWorkItem = nil
            self.publishDiagnostics()

            if clearTimer {
                self.lastClearReason = "mirror_toggle_off"
                self.publishDiagnostics()
                self.emitClear(false)
            }
        }
    }

    private func setupTicker() {
        lastEvent = "start_ax_ticker"
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            self?.pollMenuExtra()
        }
        timer.resume()
        ticker = timer
        publishDiagnostics()
    }

    private func setupMetadataTicker() {
        guard metadataTicker == nil else { return }
        lastEvent = "start_metadata_ticker"
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(5), leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.refreshMetadata()
        }
        timer.resume()
        metadataTicker = timer
        publishDiagnostics()
    }

    @discardableResult
    private func startLogStream() -> Bool {
        if let process = logProcess, process.isRunning {
            return true
        }
        lastEvent = "start_log_stream"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "ndjson",
            "--predicate", "subsystem == \"com.apple.mobiletimer.logging\"",
            "--level", "debug"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        logBuffer.removeAll(keepingCapacity: false)
        logPipe = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                self?.consumeLogData(data)
            }
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                self?.handleLogStreamTermination()
            }
        }

        do {
            try process.run()
            logProcess = process
            publishDiagnostics()
            return true
        } catch {
            lastEvent = "start_log_stream_failed"
            outputPipe.fileHandleForReading.readabilityHandler = nil
            outputPipe.fileHandleForReading.closeFile()
            logPipe = nil
            publishDiagnostics()
            return false
        }
    }

    private func stopLogStream() {
        lastEvent = "stop_log_stream"
        logRestartWorkItem?.cancel()
        logRestartWorkItem = nil

        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe?.fileHandleForReading.closeFile()
        logPipe = nil

        if let process = logProcess {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        logProcess = nil
        logBuffer.removeAll(keepingCapacity: false)
        publishDiagnostics()
    }

    private func handleLogStreamTermination() {
        lastEvent = "log_stream_terminated"
        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe?.fileHandleForReading.closeFile()
        logPipe = nil
        logProcess = nil
        logBuffer.removeAll(keepingCapacity: false)

        guard Defaults[.mirrorSystemClockTimer] else { return }

        if AXIsProcessTrusted(), ticker == nil {
            setupTicker()
        }

        scheduleLogStreamRestart()
        publishDiagnostics()
    }

    private func scheduleLogStreamRestart() {
        logRestartWorkItem?.cancel()
        lastEvent = "schedule_log_restart"
        publishDiagnostics()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.logRestartWorkItem = nil
            let started = self.startLogStream()
            if !started, AXIsProcessTrusted(), self.ticker == nil {
                self.setupTicker()
            }
        }

        logRestartWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func consumeLogData(_ data: Data) {
        logBuffer.append(data)

        while let newlineIndex = logBuffer.firstIndex(of: UInt8(10)) {
            let lineData = Data(logBuffer[..<newlineIndex])
            let removalIndex = logBuffer.index(after: newlineIndex)
            logBuffer.removeSubrange(..<removalIndex)
            guard !lineData.isEmpty else { continue }
            processLogLine(lineData)
        }
    }

    private func processLogLine(_ data: Data) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let payload = jsonObject as? [String: Any]
        else {
            return
        }
        handleLogEvent(payload)
    }

    private func startFileMonitor() {
        let fd = open(preferencesPath, O_EVTONLY)
        guard fd != -1 else {
            lastEvent = "plist_monitor_open_failed"
            publishDiagnostics()
            return
        }

        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.lastEvent = "plist_changed"
            self?.refreshMetadata()
        }

        source.setCancelHandler { [weak self] in
            guard let fd = self?.fileDescriptor, fd != -1 else { return }
            close(fd)
            self?.fileDescriptor = -1
        }

        source.resume()
        fileMonitor = source
        lastEvent = "start_plist_monitor"
        publishDiagnostics()
    }

    private func pollMenuExtra() {
        guard Defaults[.mirrorSystemClockTimer] else { return }

        if logProcess != nil, logIdentifier != nil {
            return
        }

        if menuExtra == nil {
            menuExtra = locateTimerMenuExtra()
            if menuExtra == nil {
                handleMissingMenuExtra()
                return
            }
        }

        guard let element = menuExtra else { return }
        guard let parsed = extractTimerString(from: element) else {
            menuExtra = nil
            handleMissingMenuExtra()
            return
        }

        lastEvent = "ax_poll_update"
        latestRemaining = parsed.remaining
        latestPaused = parsed.paused
        applyTimerUpdate(remaining: parsed.remaining, paused: parsed.paused, source: .ax)
    }

    private func applyTimerUpdate(remaining: TimeInterval, paused: Bool, source: SnapshotSource) {
        guard Defaults[.mirrorSystemClockTimer] else { return }
        guard remaining.isFinite else { return }

        let durationFromMetadata = logPreferredDuration ?? metadata?.duration ?? 0
        if let metadata, metadata.state == .running || metadata.state == .paused {
            if durationFromMetadata > 0, (initialTotalDuration ?? 0) < durationFromMetadata {
                initialTotalDuration = durationFromMetadata
            }
        }

        if initialTotalDuration == nil {
            initialTotalDuration = max(durationFromMetadata, remaining)
        } else if remaining > (initialTotalDuration ?? 0) {
            initialTotalDuration = remaining
        }

        let baseTotal = max(durationFromMetadata, remaining > 0 ? remaining : 0)
        let total = initialTotalDuration ?? baseTotal

        let trimmedLogName = logPreferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMetadataName = metadata?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName: String

        if let name = trimmedLogName, !name.isEmpty {
            displayName = name
        } else if let name = trimmedMetadataName, !name.isEmpty {
            displayName = name
        } else {
            displayName = "Clock Timer"
        }

        let snapshot = Snapshot(
            remaining: remaining,
            totalDuration: total,
            isPaused: paused,
            name: displayName,
            isFinished: remaining <= 0
        )
        emitSnapshot(snapshot, source: source)
    }

    private func handleMissingMenuExtra() {
        guard AXIsProcessTrusted() else { return }
        guard logIdentifier == nil else { return }
        lastEvent = "ax_menu_extra_missing"
        lastClearReason = "ax_menu_extra_missing"
        publishDiagnostics()
        emitClear(true)
    }

    private func handleLogEvent(_ payload: [String: Any]) {
        guard Defaults[.mirrorSystemClockTimer] else { return }
        guard let message = payload["eventMessage"] as? String, !message.isEmpty else { return }
        lastEvent = "log_event"

        if message.contains("scheduled timers:") {
            handleScheduledTimersMessage(message)
        }
        if message.contains("Timer will fire") {
            handleTimerWillFireMessage(message)
        }
        if message.contains("remainingTime:") {
            handleRemainingTimeMessage(message)
        }
        if message.contains("next timer changed:") {
            handleNextTimerChangedMessage(message)
        }
        if message.contains("started timer:") {
            handleTimerStartedMessage(message)
        }
        if message.contains("Timer stopped") {
            handleTimerStoppedMessage(message)
        }
    }

    private func handleScheduledTimersMessage(_ message: String) {
        let entries = parseLogTimerEntries(from: message)
        guard !entries.isEmpty else { return }

        let normalizedCurrentId = logIdentifier?.uppercased()
        let selectedEntry: LogTimerEntry?

        if let currentId = normalizedCurrentId,
           let current = entries.first(where: { $0.identifier == currentId }) {
            selectedEntry = current
        } else if let active = entries.first(where: { ($0.state == "running" || $0.state == "paused") }) {
            selectedEntry = active
        } else if normalizedCurrentId == nil,
                  let fired = entries.first(where: { $0.state == "fired" }) {
            selectedEntry = fired
        } else {
            selectedEntry = nil
        }

        guard let entry = selectedEntry else { return }

        if normalizedCurrentId == nil {
            if let state = entry.state, state == "running" || state == "paused" || state == "fired" {
                setLogIdentifier(entry.identifier)
            }
        } else if let currentId = normalizedCurrentId, currentId != entry.identifier {
            if let state = entry.state, state == "running" || state == "paused" {
                setLogIdentifier(entry.identifier)
            }
        }

        if let title = entry.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "(null)" {
                logPreferredName = trimmed
            }
        }

        if let duration = entry.duration {
            if let existing = logPreferredDuration {
                logPreferredDuration = max(existing, duration)
            } else {
                logPreferredDuration = duration
            }
            if (initialTotalDuration ?? 0) < duration {
                initialTotalDuration = duration
            }
        }

        guard let state = entry.state else { return }
        switch state {
        case "paused":
            if let remaining = latestRemaining {
                applyLogDrivenUpdate(remaining: remaining, isPaused: true)
            } else {
                latestPaused = true
            }
        case "running":
            if let remaining = latestRemaining {
                applyLogDrivenUpdate(remaining: remaining, isPaused: false)
            } else {
                latestPaused = false
            }
        case "fired":
            latestPaused = false
            applyLogDrivenUpdate(remaining: 0, isPaused: false)
        case "stopped":
            if entry.identifier == normalizedCurrentId {
                clearLogState(triggerSmoothClose: true)
            }
        default:
            break
        }
    }

    private func handleTimerWillFireMessage(_ message: String) {
        guard logIdentifier != nil else { return }
        guard let minutesString = captureFirstMatch(pattern: "Timer will fire\\s+([0-9.]+)\\s+minutes?", in: message),
              let minutes = Double(minutesString)
        else { return }
        applyLogDrivenUpdate(remaining: minutes * 60, isPaused: latestPaused)
    }

    private func handleRemainingTimeMessage(_ message: String) {
        guard let valueString = captureFirstMatch(pattern: "remainingTime:\\s*([-0-9.]+)", in: message),
              let remaining = Double(valueString)
        else { return }
        applyLogDrivenUpdate(remaining: remaining, isPaused: latestPaused)
    }

    private func handleNextTimerChangedMessage(_ message: String) {
        guard let token = captureFirstMatch(pattern: "next timer changed:\\s*([^\\n]+)", in: message) else { return }
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
        if trimmed.isEmpty || trimmed.lowercased().contains("null") { return }
        setLogIdentifier(trimmed)
    }

    private func handleTimerStartedMessage(_ message: String) {
        lastEvent = "log_timer_started"
        guard let identifier = captureFirstMatch(pattern: "started timer:\\s*([A-Fa-f0-9\\-]+)", in: message) else { return }
        setLogIdentifier(identifier)
    }

    private func handleTimerStoppedMessage(_ message: String) {
        lastEvent = "log_timer_stopped"
        guard logIdentifier != nil else { return }
        clearLogState(triggerSmoothClose: true)
    }

    private func applyLogDrivenUpdate(remaining: TimeInterval, isPaused: Bool, nameOverride: String? = nil, durationOverride: TimeInterval? = nil) {
        guard Defaults[.mirrorSystemClockTimer] else { return }
        guard logIdentifier != nil else { return }

        if let nameOverride, !nameOverride.isEmpty {
            logPreferredName = nameOverride
        }
        if let durationOverride {
            if let existing = logPreferredDuration {
                logPreferredDuration = max(existing, durationOverride)
            } else {
                logPreferredDuration = durationOverride
            }
        }

        latestPaused = isPaused
        latestRemaining = remaining

        if let duration = logPreferredDuration, (initialTotalDuration ?? 0) < duration {
            initialTotalDuration = duration
        }
        if remaining > (initialTotalDuration ?? 0) {
            initialTotalDuration = remaining
        }

        applyTimerUpdate(remaining: remaining, paused: isPaused, source: .log)
    }

    private func setLogIdentifier(_ identifier: String) {
        let cleaned = identifier.trimmingCharacters(in: CharacterSet(charactersIn: " <>")).uppercased()
        guard !cleaned.isEmpty else { return }
        if logIdentifier != cleaned {
            lastEvent = "set_log_identifier"
            logIdentifier = cleaned
            logDidCompleteActiveTimer = false
            initialTotalDuration = nil
            latestRemaining = nil
            logPreferredDuration = nil
            logPreferredName = nil
            publishDiagnostics()
        }
    }

    private func clearLogState(triggerSmoothClose: Bool) {
        let didComplete = logDidCompleteActiveTimer

        logIdentifier = nil
        logPreferredName = nil
        logPreferredDuration = nil
        initialTotalDuration = nil
        latestRemaining = nil
        latestPaused = false
        logDidCompleteActiveTimer = false
        lastEvent = "clear_log_state"

        guard triggerSmoothClose else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if didComplete {
                self.lastClearReason = "log_complete_smooth_close"
                self.publishDiagnostics()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    self.emitClear(false)
                }
            } else {
                self.lastClearReason = "log_stop_clear"
                self.publishDiagnostics()
                self.emitClear(true)
            }
        }
    }

    private func captureFirstMatch(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let swiftRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private func parseLogTimerEntries(from message: String) -> [LogTimerEntry] {
        guard let regex = try? NSRegularExpression(pattern: "<MT(?:Mutable)?Timer:[^>]+>", options: []) else {
            return []
        }

        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = regex.matches(in: message, options: [], range: range)
        var entries: [LogTimerEntry] = []

        for match in matches {
            guard let swiftRange = Range(match.range, in: message) else { continue }
            let entryString = String(message[swiftRange])
            guard let rawIdentifier = captureFirstMatch(pattern: "TimerID:\\s*([A-Fa-f0-9\\-]+)", in: entryString) else { continue }

            let identifier = rawIdentifier.uppercased()
            let state = captureFirstMatch(pattern: "state:([A-Za-z]+)", in: entryString)?.lowercased()
            let title = captureFirstMatch(pattern: "Title:\\s*([^,]+)", in: entryString)
            let durationString = captureFirstMatch(pattern: "duration:([0-9]+(?:\\.[0-9]+)?)", in: entryString)
            let duration = durationString.flatMap(Double.init)

            entries.append(.init(identifier: identifier, state: state, title: title, duration: duration))
        }

        return entries
    }

    private func refreshMetadata() {
        lastEvent = "refresh_metadata"
        let previous = metadata
        metadata = fetchMetadata()

        if metadata == nil {
            initialTotalDuration = nil
            if let inferred = inferSnapshotFromPreferences() {
                emitSnapshot(inferred, source: .inferred)
            } else {
                lastClearReason = "metadata_empty"
                publishDiagnostics()
                emitClear(true)
            }
            return
        }

        guard let metadata else { return }

        if metadata.duration > 0, (initialTotalDuration ?? 0) < metadata.duration {
            initialTotalDuration = metadata.duration
        }

        if !metadata.state.isActive {
            if let inferred = inferSnapshotFromPreferences() {
                emitSnapshot(inferred, source: .inferred)
            } else {
                lastClearReason = "metadata_inactive"
                publishDiagnostics()
                emitClear(true)
            }
            return
        }

        guard metadata != previous || latestRemaining != nil else { return }

        let remaining = latestRemaining ?? metadata.duration
        applyTimerUpdate(remaining: remaining, paused: latestPaused, source: .metadata)
    }

    private func loadTimersFromPreferences() -> (timers: [[String: Any]], lastTriggerDate: Date?)? {
        CFPreferencesAppSynchronize(domain)

        if let container = CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any],
           let rawTimers = container["MTTimers"] as? [[String: Any]] {
            let lastTriggerDate = CFPreferencesCopyAppValue("MTTimerLastTriggerDate" as CFString, domain) as? Date
            return (rawTimers, lastTriggerDate)
        }

        guard let root = NSDictionary(contentsOfFile: preferencesPath) as? [String: Any],
              let container = root["MTTimers"] as? [String: Any],
              let rawTimers = container["MTTimers"] as? [[String: Any]]
        else {
            return nil
        }

        let lastTriggerDate = root["MTTimerLastTriggerDate"] as? Date
        return (rawTimers, lastTriggerDate)
    }

    private func inferSnapshotFromPreferences() -> Snapshot? {
        guard let pref = loadTimersFromPreferences() else {
            return nil
        }

        let rawTimers = pref.timers
        let lastTriggerDate = pref.lastTriggerDate
        let now = Date()

        for entry in rawTimers {
            guard let timer = entry["$MTTimer"] as? [String: Any] else { continue }
            let title = (timer["MTTimerTitle"] as? String) ?? ""
            guard title == "CURRENT_TIMER" else { continue }
            let stateRaw = timer["MTTimerState"] as? Int ?? 0
            let state = TimerMetadata.State(rawValue: stateRaw) ?? .unknown
            guard state == .running || state == .paused else { continue }

            let total = max(1, timer["MTTimerDuration"] as? TimeInterval ?? 0)
            var remaining = total

            if let fireTime = timer["MTTimerFireTime"] as? [String: Any],
               let interval = fireTime["$MTTimerTimeInterval"] as? [String: Any],
               let value = interval["MTTimerTimeInterval"] as? TimeInterval {
                remaining = max(0, value)
            }

            if let trigger = lastTriggerDate {
                let elapsed = max(0, now.timeIntervalSince(trigger))
                let estimated = max(0, total - elapsed)
                if estimated < remaining || remaining >= total {
                    remaining = estimated
                }
            }

            guard remaining > 0 else { continue }

            return Snapshot(
                remaining: remaining,
                totalDuration: total,
                isPaused: state == .paused,
                name: "Clock Timer",
                isFinished: false
            )
        }

        return nil
    }

    private func fetchMetadata() -> TimerMetadata? {
        guard let pref = loadTimersFromPreferences() else {
            return nil
        }

        let rawTimers = pref.timers

        let records: [TimerMetadata] = rawTimers.compactMap { entry in
            guard let timer = entry["$MTTimer"] as? [String: Any] else { return nil }
            let identifier = timer["MTTimerID"] as? String ?? UUID().uuidString
            let rawTitle = (timer["MTTimerTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty == false) ? rawTitle! : "Clock Timer"
            let duration = timer["MTTimerDuration"] as? TimeInterval ?? 0
            let lastModified = timer["MTTimerLastModifiedDate"] as? Date
            let firedDate = timer["MTTimerFiredDate"] as? Date
            let stateRaw = timer["MTTimerState"] as? Int ?? 0
            let state = TimerMetadata.State(rawValue: stateRaw) ?? .unknown
            return .init(identifier: identifier, title: title, duration: duration, lastModified: lastModified, firedDate: firedDate, state: state)
        }

        if let active = records.first(where: { $0.state.isActive }) {
            return active
        }

        return nil
    }

    private func locateTimerMenuExtra() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let menuBar: AXUIElement = copyAttribute(kAXMenuBarAttribute as CFString, from: systemWide),
              let items: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: menuBar)
        else {
            return nil
        }

        for item in items where isTimerMenuExtra(item) {
            return item
        }

        return nil
    }

    private func isTimerMenuExtra(_ element: AXUIElement) -> Bool {
        if let identifier: String = copyAttribute(kAXIdentifierAttribute as CFString, from: element),
           identifier.lowercased().contains("timer") {
            return true
        }
        if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: element),
           matchesTimerText(title) {
            return true
        }
        if let value: String = copyAttribute(kAXValueAttribute as CFString, from: element),
           matchesTimerText(value) {
            return true
        }
        if let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: element) {
            for child in children {
                if let value: String = copyAttribute(kAXValueAttribute as CFString, from: child), matchesTimerText(value) {
                    return true
                }
                if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: child), matchesTimerText(title) {
                    return true
                }
            }
        }
        return false
    }

    private func extractTimerString(from element: AXUIElement) -> ParsedTimerString? {
        if let value: String = copyAttribute(kAXValueAttribute as CFString, from: element),
           let parsed = parseTimerString(value) {
            return parsed
        }
        if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: element),
           let parsed = parseTimerString(title) {
            return parsed
        }
        if let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: element) {
            for child in children {
                if let value: String = copyAttribute(kAXValueAttribute as CFString, from: child),
                   let parsed = parseTimerString(value) {
                    return parsed
                }
                if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: child),
                   let parsed = parseTimerString(title) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func parseTimerString(_ raw: String) -> ParsedTimerString? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let paused = lower.contains("pause") || lower.contains("stopped")

        if let seconds = extractSeconds(from: trimmed) {
            return .init(remaining: seconds, paused: paused)
        }
        return nil
    }

    private func extractSeconds(from text: String) -> TimeInterval? {
        let numericPattern = "[0-9]+(?::[0-9]{2}){0,2}"
        if let match = text.range(of: numericPattern, options: .regularExpression) {
            let token = String(text[match])
            let parts = token.split(separator: ":").compactMap { Double($0) }
            switch parts.count {
            case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
            case 2: return parts[0] * 60 + parts[1]
            case 1: return parts[0]
            default: break
            }
        }

        let suffixPattern = "([0-9]+)([hms])"
        let regex = try? NSRegularExpression(pattern: suffixPattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, options: [], range: range) ?? []
        guard !matches.isEmpty else { return nil }

        var total: TimeInterval = 0
        for match in matches {
            guard match.numberOfRanges == 3,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }

            switch text[unitRange] {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
        }
        return total > 0 ? total : nil
    }

    private func matchesTimerText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.lowercased().contains("timer") {
            return true
        }

        let pattern = "[0-9]+(?::[0-9]{2}){0,2}"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let typed = value as? T else {
            return nil
        }
        return typed
    }
}
