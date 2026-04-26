import AppKit
import Combine
import SwiftUI
import Defaults
import ObjectiveC.runtime

@MainActor
final class AccentTintPulse: ObservableObject {
    static let shared = AccentTintPulse()
    @Published private(set) var generation: UInt64 = 0
    private init() {}
    func ping() {
        generation &+= 1
    }
}

private var _focusAccentOverride: NSColor? = nil

extension NSColor {
    static let quartzControlAccent = NSColor(
        srgbRed: 0.65,
        green: 0.54,
        blue: 0.89,
        alpha: 1.0
    )

    static let quartzDisplayAccent = NSColor(
        srgbRed: 0.71,
        green: 0.58,
        blue: 0.93,
        alpha: 1.0
    )

    private static func stableAccentColor(from color: NSColor) -> NSColor {
        var resolved = color.usingColorSpace(NSColorSpace.deviceRGB) ?? color
        if let appearance = NSApp?.effectiveAppearance {
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(NSColorSpace.deviceRGB) ?? color
            }
        }

        if let rgb = resolved.usingColorSpace(NSColorSpace.deviceRGB) {
            return NSColor(
                deviceRed: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: rgb.alphaComponent
            )
        }
        return resolved
    }

    private static func emphasizedAccentColor(from color: NSColor) -> NSColor {
        let rgb = stableAccentColor(from: color)
        let saturated = NSColor(
            deviceRed: min(1.0, rgb.redComponent * 1.09),
            green: max(0.0, rgb.greenComponent * 0.94),
            blue: min(1.0, rgb.blueComponent * 1.12),
            alpha: rgb.alphaComponent
        )
        return stableAccentColor(from: saturated.shadow(withLevel: 0.22) ?? saturated.blended(withFraction: 0.22, of: .black) ?? saturated)
    }

    static func enableControlAccentColorOverride() {
        swizzleFocusColor(named: "keyboardFocusIndicatorColor", alpha: 0.24)
    }

    static func applyEffectiveAccentOverride() {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            _focusAccentOverride = nsColor
        } else {
            _focusAccentOverride = stableAccentColor(from: quartzControlAccent)
        }
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    private static func swizzleFocusColor(named selectorName: String, alpha: CGFloat = 1.0) {
        let sel = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(NSColor.self, sel) else { return }

        let originalIMP = method_getImplementation(method)
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSColor
        let original = unsafeBitCast(originalIMP, to: Getter.self)

        let block: @convention(block) (AnyObject) -> NSColor = { cls in
            guard let override = _focusAccentOverride else { return original(cls, sel) }
            return alpha < 1.0 ? override.withAlphaComponent(alpha) : override
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    static var effectiveControlAccent: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return stableAccentColor(from: nsColor)
        }
        return stableAccentColor(from: quartzControlAccent)
    }

    static var effectiveAccent: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return emphasizedAccentColor(from: nsColor)
        }
        return emphasizedAccentColor(from: quartzDisplayAccent)
    }

    static var effectiveAccentBackground: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return emphasizedAccentColor(from: nsColor).withAlphaComponent(0.48)
        }
        return effectiveAccent.withAlphaComponent(0.48)
    }
}

extension Color {
    static var controlAccent: Color {
        Color(nsColor: NSColor.effectiveControlAccent)
    }

    static var effectiveAccent: Color {
        Color(nsColor: NSColor.effectiveAccent)
    }

    static var effectiveAccentBackground: Color {
        Color(nsColor: NSColor.effectiveAccentBackground)
    }
}
