import SwiftUI

/// Shared motion presets for notch + live activities.
/// Keeps transitions coherent and "Apple-like" across the app.
enum NotchMotion {
    static let notchOpen: Animation = .spring(duration: 0.38, bounce: 0.18, blendDuration: 0.10)
    static let notchOpenHorizontal: Animation = .spring(duration: 0.40, bounce: 0.10, blendDuration: 0.10)
    static let openHeaderWidth: Animation = .spring(duration: 0.34, bounce: 0.08, blendDuration: 0.08)
    static let openContentReveal: Animation = .spring(duration: 0.34, bounce: 0.24, blendDuration: 0.08)
    static let notchCloseDuration: Double = 0.33
    static let notchClose: Animation = .spring(duration: notchCloseDuration, bounce: 0.015, blendDuration: 0.08)

    static let notchLayout: Animation = .interpolatingSpring(mass: 0.96, stiffness: 235, damping: 24.8, initialVelocity: 0.04)
    static let pagerDrag: Animation = .interactiveSpring(response: 0.50, dampingFraction: 0.95, blendDuration: 0.08)
    static let pagerSwipeSnap: Animation = .spring(duration: 0.44, bounce: 0.22, blendDuration: 0.08)
    static let pagerProgrammatic: Animation = .timingCurve(0.22, 0.88, 0.24, 1.00, duration: 0.52)

    static let liveActivityIn: Animation = .spring(duration: 0.58, bounce: 0.10, blendDuration: 0.12)
    static let liveActivityOut: Animation = .spring(duration: 0.44, bounce: 0.01, blendDuration: 0.10)
    static let liveActivityBatteryIn: Animation = .spring(duration: 0.39, bounce: 0.03, blendDuration: 0.09)
    static let liveActivityBluetoothIn: Animation = .spring(duration: 0.50, bounce: 0.08, blendDuration: 0.10)

    static let nowPlayingIn: Animation = .spring(duration: 0.56, bounce: 0.11, blendDuration: 0.10)
    static let nowPlayingOut: Animation = .spring(duration: 0.44, bounce: 0.01, blendDuration: 0.08)

    static let popupHover: Animation = .spring(duration: 0.34, bounce: 0.08, blendDuration: 0.08)

    static func visibility(duration: Double) -> Animation {
        .spring(duration: max(0.26, duration * 1.04), bounce: 0.02, blendDuration: 0.08)
    }

    static func widthMorph(duration: Double) -> Animation {
        .spring(duration: max(0.21, duration * 0.90), bounce: 0.05, blendDuration: 0.08)
    }

    static let lockReveal: Animation = .interpolatingSpring(mass: 1.02, stiffness: 108, damping: 19.0, initialVelocity: 0.82)
    static let lockDismiss: Animation = .timingCurve(0.06, 0.86, 0.30, 1.00, duration: 0.54)
    static let lockIconBlurReveal: Animation = .timingCurve(0.10, 0.88, 0.12, 1.00, duration: 0.70)
    static let lockIconBlurDismiss: Animation = .timingCurve(0.10, 0.74, 0.34, 1.00, duration: 0.50)
    static let lockFadeOut: Animation = .timingCurve(0.36, 0.02, 0.24, 1.00, duration: 0.16)
}
