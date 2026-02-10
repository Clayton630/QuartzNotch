import SwiftUI

/// Shared motion presets for notch + live activities.
/// Keeps transitions coherent and "Apple-like" across the app.
enum NotchMotion {
 // Core notch open/close.
 // Open: Apple-like "push then settle" profile:
 // quick propulsion in the middle, then an extended buttery landing.
    static let notchOpen: Animation = .interpolatingSpring(mass: 1.02, stiffness: 238, damping: 25.8, initialVelocity: 0.0)
 // Close: short, clean, almost no rebound.
    static let notchClose: Animation = .smooth(duration: 0.32)

 // Width/layout adaptation while notch is open.
    static let notchLayout: Animation = .interpolatingSpring(mass: 0.96, stiffness: 235, damping: 24.8, initialVelocity: 0.04)
 // Pager-specific motion (swipe between pages).
    static let pagerDrag: Animation = .interactiveSpring(response: 1.50, dampingFraction: 0.998, blendDuration: 0.14)
    static let pagerSwipeSnap: Animation = .spring(duration: 0.46, bounce: 0.12, blendDuration: 0.08)
    static let pagerProgrammatic: Animation = .timingCurve(0.20, 0.90, 0.22, 1.00, duration: 0.56)

 // Generic live activity appear/disappear.
 // In: highly non-linear, fluid, with a subtle controlled landing.
    static let liveActivityIn: Animation = .spring(duration: 0.58, bounce: 0.10, blendDuration: 0.12)
 // Out: clean settle, minimal rebound.
    static let liveActivityOut: Animation = .spring(duration: 0.44, bounce: 0.01, blendDuration: 0.10)
 // Battery: reduce rebound vs generic live activity.
    static let liveActivityBatteryIn: Animation = .spring(duration: 0.56, bounce: 0.03, blendDuration: 0.12)
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
        .spring(duration: max(0.28, duration * 0.98), bounce: 0.05, blendDuration: 0.10)
    }

 // Lock/Unlock overlays: single-phase smooth animations (no stepped feel).
    static let lockReveal: Animation = .spring(duration: 0.42, bounce: 0.04, blendDuration: 0.10)
    static let lockDismiss: Animation = .spring(duration: 0.34, bounce: 0.00, blendDuration: 0.08)
    static let lockFadeOut: Animation = .timingCurve(0.36, 0.02, 0.24, 1.00, duration: 0.16)
}
