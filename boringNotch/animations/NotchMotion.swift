import SwiftUI

/// Shared motion presets for notch + live activities.
/// Keeps transitions coherent and "Apple-like" across the app.
enum NotchMotion {
 // Core notch open/close.
 // Open: Apple-like "push then settle" profile:
 // quick propulsion in the middle, then an extended buttery landing.
    // Fast body, slower settle at the very end, with a clearly visible landing rebound.
    static let notchOpen: Animation = .spring(duration: 0.38, bounce: 0.18, blendDuration: 0.10)
    // Horizontal-only open shaping (less linear width expansion).
    static let notchOpenHorizontal: Animation = .spring(duration: 0.40, bounce: 0.22, blendDuration: 0.10)
    // Content-only reveal: slightly more rebound than the notch container.
    static let openContentReveal: Animation = .spring(duration: 0.41, bounce: 0.24, blendDuration: 0.10)
 // Close: short, clean, almost no rebound.
    static let notchCloseDuration: Double = 0.33
    // Non-linear close with a natural easing profile (less linear than timing curves).
    static let notchClose: Animation = .spring(duration: notchCloseDuration, bounce: 0.015, blendDuration: 0.08)

 // Width/layout adaptation while notch is open.
    static let notchLayout: Animation = .interpolatingSpring(mass: 0.96, stiffness: 235, damping: 24.8, initialVelocity: 0.04)
 // Pager-specific motion (swipe between pages).
    static let pagerDrag: Animation = .interactiveSpring(response: 0.50, dampingFraction: 0.95, blendDuration: 0.08)
    static let pagerSwipeSnap: Animation = .spring(duration: 0.44, bounce: 0.22, blendDuration: 0.08)
    static let pagerProgrammatic: Animation = .timingCurve(0.22, 0.88, 0.24, 1.00, duration: 0.52)

 // Generic live activity appear/disappear.
 // In: highly non-linear, fluid, with a subtle controlled landing.
    static let liveActivityIn: Animation = .spring(duration: 0.58, bounce: 0.10, blendDuration: 0.12)
 // Out: clean settle, minimal rebound.
    static let liveActivityOut: Animation = .spring(duration: 0.44, bounce: 0.01, blendDuration: 0.10)
 // Battery: reduce rebound vs generic live activity.
    static let liveActivityBatteryIn: Animation = .spring(duration: 0.39, bounce: 0.03, blendDuration: 0.09)
 // Bluetooth: a bit faster on entry while keeping the same fluid signature.
    static let liveActivityBluetoothIn: Animation = .spring(duration: 0.50, bounce: 0.08, blendDuration: 0.10)

 // Now Playing: preserve the existing close "feel", while making open less linear.
    static let nowPlayingIn: Animation = .spring(duration: 0.56, bounce: 0.11, blendDuration: 0.10)
    static let nowPlayingOut: Animation = .spring(duration: 0.44, bounce: 0.01, blendDuration: 0.08)

 // Hover-driven popup expansion (Bluetooth/Timer sides).
    static let popupHover: Animation = .spring(duration: 0.34, bounce: 0.08, blendDuration: 0.08)

 // Used for global suppression/reveal and tiny state changes.
    static func visibility(duration: Double) -> Animation {
        .spring(duration: max(0.26, duration * 1.04), bounce: 0.02, blendDuration: 0.08)
    }

 // Width morphs for battery closed activity.
    static func widthMorph(duration: Double) -> Animation {
        .spring(duration: max(0.21, duration * 0.90), bounce: 0.05, blendDuration: 0.08)
    }

 // Lock/Unlock overlays: single-phase smooth animations (no stepped feel).
    static let lockReveal: Animation = .spring(duration: 0.42, bounce: 0.04, blendDuration: 0.10)
    static let lockDismiss: Animation = .spring(duration: 0.34, bounce: 0.00, blendDuration: 0.08)
    static let lockFadeOut: Animation = .timingCurve(0.36, 0.02, 0.24, 1.00, duration: 0.16)
}
