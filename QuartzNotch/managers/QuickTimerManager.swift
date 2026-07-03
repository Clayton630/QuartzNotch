
import Foundation
import Combine
import UserNotifications

class QuickTimerManager: ObservableObject {
    static let shared = QuickTimerManager()
    
    @Published var timers: [QuickTimer] = [] {
        didSet { updateTickerIfNeeded() }
    }
    private var cancellables = Set<AnyCancellable>()
    private var tickerCancellable: AnyCancellable?
    
    private init() {
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private var hasRunningTimers: Bool {
        timers.contains(where: \.isRunning)
    }

    private func updateTickerIfNeeded() {
        if hasRunningTimers {
            guard tickerCancellable == nil else { return }
            tickerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.updateTimers()
                }
        } else {
            tickerCancellable?.cancel()
            tickerCancellable = nil
        }
    }
    
    private func updateTimers() {
        guard hasRunningTimers else {
            updateTickerIfNeeded()
            return
        }

        var didChange = false
        for i in timers.indices {
            guard timers[i].isRunning else { continue }
            timers[i].remainingSeconds -= 1
            didChange = true

            if timers[i].remainingSeconds <= 0 {
                timers[i].isRunning = false
                timers[i].remainingSeconds = 0
                sendNotification(for: timers[i])
            }
        }

        if didChange {
            objectWillChange.send()
        }
        updateTickerIfNeeded()
    }
    
    func startTimer(duration: TimeInterval, preset: TimerPreset) {
        if let index = timers.firstIndex(where: { $0.preset == preset }) {
            timers[index].remainingSeconds = Int(duration)
            timers[index].totalSeconds = Int(duration)
            timers[index].isRunning = true
        } else {
            let timer = QuickTimer(
                preset: preset,
                totalSeconds: Int(duration),
                remainingSeconds: Int(duration)
            )
            timers.append(timer)
        }
        updateTickerIfNeeded()
    }
    
    func toggleTimer(_ timer: QuickTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers[index].isRunning.toggle()
        }
        updateTickerIfNeeded()
    }
    
    func stopTimer(_ timer: QuickTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers.remove(at: index)
        }
        updateTickerIfNeeded()
    }
    
    func resetTimer(_ timer: QuickTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers[index].remainingSeconds = timers[index].totalSeconds
            timers[index].isRunning = false
        }
        updateTickerIfNeeded()
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
    var totalSeconds: Int
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
