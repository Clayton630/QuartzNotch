//
// QuickTimerModels.swift
// boringNotch
//
// Created by AI Assistant on 2026-02-02.
//

import Foundation
import Combine

// MARK: - Preset duration overrides

private enum QuickTimerPresetStorage {
    static let keyPrefix = "quickTimerPresetDuration_"

    static func key(for preset: TimerPreset) -> String {
        keyPrefix + preset.storageKey
    }
}

// Presets for quick timers
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
    // `integer(forKey:)` returns 0 when missing; treat 0 as "no override".
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

// Model for a running quick timer
final class QuickTimer: ObservableObject, Identifiable, Equatable {
    static func == (lhs: QuickTimer, rhs: QuickTimer) -> Bool { lhs.id == rhs.id }

    let id = UUID()
    let preset: TimerPreset
    @Published var remainingSeconds: Int
    @Published var isRunning: Bool = false

    private var totalDuration: Int
    private var timer: Timer?

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
        remainingSeconds = 0
    }

    func reset() {
        pause()
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
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

// Manager for quick timers
final class QuickTimerManager: ObservableObject {
    static let shared = QuickTimerManager()
    @Published private(set) var timers: [QuickTimer] = []

    private var timerChangeCancellables: [UUID: AnyCancellable] = [:]

    private init() {}

    private func observeTimer(_ timer: QuickTimer) {
    // Forward child timer changes so views observing only the manager still refresh.
        timerChangeCancellables[timer.id] = timer.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func unobserveTimer(_ timer: QuickTimer) {
        timerChangeCancellables[timer.id]?.cancel()
        timerChangeCancellables[timer.id] = nil
    }

    func startTimer(duration: Int, preset: TimerPreset) {
        if let existing = timers.first(where: { $0.preset == preset }) {
            observeTimer(existing)
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
        timer.stop()
        unobserveTimer(timer)
        timers.removeAll { $0.id == timer.id }
    }

    func toggleTimer(_ timer: QuickTimer) {
        if timer.isRunning {
            timer.pause()
        } else {
            if timer.remainingSeconds == 0 { timer.reset() }
            timer.start()
        }
    }

    func resetTimer(_ timer: QuickTimer) {
        timer.reset()
    }
}
