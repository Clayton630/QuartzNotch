
import AppKit
import Foundation

@MainActor
final class LockScreenState: ObservableObject {
    static let shared = LockScreenState()

    @Published private(set) var isLocked: Bool = false
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var sessionResignObserver: NSObjectProtocol?
    private var sessionActiveObserver: NSObjectProtocol?

    private init() {
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setLocked(true)
            }
        }

        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setLocked(false)
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        sessionResignObserver = center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSystem()
            }
        }

        sessionActiveObserver = center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSystem()
            }
        }

        refreshFromSystem()
    }

    deinit {
        if let lockObserver {
            DistributedNotificationCenter.default().removeObserver(lockObserver)
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
        }
        if let sessionResignObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sessionResignObserver)
        }
        if let sessionActiveObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sessionActiveObserver)
        }
    }

    func setLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
    }

    private func refreshFromSystem() {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            setLocked(locked)
            return
        }
        if let lockedNumber = session["CGSSessionScreenIsLocked"] as? NSNumber {
            setLocked(lockedNumber.boolValue)
        }
    }
}

/// Central gate to temporarily suppress any "closed notch" live activities
/// (music, shelf/file tray, face, HUD, etc.) during lock/unlock transitions.
///
/// Why: the lock/unlock animation is rendered by a dedicated overlay window.
/// If the main notch keeps drawing its own closed live activity at the same time,
/// the lock/unlock animation gets visually polluted (overdraw) and the lock
/// animation can look broken when switching activity priority at the same moment.
@MainActor
final class LockTransitionState: ObservableObject {
    static let shared = LockTransitionState()

    @Published private(set) var suppressClosedActivities: Bool = false

    func begin() {
        suppressClosedActivities = true
    }

    func end() {
        suppressClosedActivities = false
    }
}
