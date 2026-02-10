//
// QuickTimerManager.swift
// boringNotch
//
// Created by AI Assistant on 2026-02-02.
//

import Foundation
import Combine
import UserNotifications

class QuickTimerManager: ObservableObject {
    static let shared = QuickTimerManager()
    
    @Published var timers: [QuickTimer] = []
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        requestNotificationPermission()
        startTimerUpdates()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func startTimerUpdates() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTimers()
            }
            .store(in: &cancellables)
    }
    
    private func updateTimers() {
        for i in timers.indices {
            if timers[i].isRunning {
                timers[i].remainingSeconds -= 1
                
                if timers[i].remainingSeconds <= 0 {
                    timers[i].isRunning = false
                    timers[i].remainingSeconds = 0
                    sendNotification(for: timers[i])
                }
                
        // Force UI update immediately for each running timer
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
        }
    }
    
    func startTimer(duration: TimeInterval, preset: TimerPreset) {
    // Check if a timer with this preset already exists
        if let index = timers.firstIndex(where: { $0.preset == preset }) {
      // Restart existing timer
            timers[index].remainingSeconds = Int(duration)
            timers[index].totalSeconds = Int(duration)
            timers[index].isRunning = true
        } else {
      // Create new timer
            let timer = QuickTimer(
                preset: preset,
                totalSeconds: Int(duration),
                remainingSeconds: Int(duration)
            )
            timers.append(timer)
        }
    }
    
    func toggleTimer(_ timer: QuickTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers[index].isRunning.toggle()
        }
    }
    
    func stopTimer(_ timer: QuickTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers.remove(at: index)
        }
    }
    
    func resetTimer(_ timer: QuickTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers[index].remainingSeconds = timers[index].totalSeconds
            timers[index].isRunning = false
        }
    }
    
    private func sendNotification(for timer: QuickTimer) {
        let content = UNMutableNotificationContent()
        content.title = "Timer Finished"
        content.body = "\(timer.preset.displayName) timer has completed"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: timer.id.uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

struct QuickTimer: Identifiable {
    let id = UUID()
    let preset: TimerPreset
    let totalSeconds: Int
    var remainingSeconds: Int
    var isRunning: Bool = true
    
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }
    
    var displayTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum TimerPreset: String, CaseIterable {
    case oneMinute = "1min"
    case fiveMinutes = "5min"
    case tenMinutes = "10min"
    
    var duration: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        }
    }
    
    var displayName: String {
        switch self {
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .tenMinutes: return "10 min"
        }
    }
    
    var icon: String {
        return "timer"
    }
}
