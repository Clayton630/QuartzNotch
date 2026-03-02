//
// LockScreenState.swift
// boringNotch
//
// Created by Clayton on 22/01/2026.
//

import Foundation

@MainActor
final class LockScreenState: ObservableObject {
    static let shared = LockScreenState()

    @Published private(set) var isLocked: Bool = false

    func setLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
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
