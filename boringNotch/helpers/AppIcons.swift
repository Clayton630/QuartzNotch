
import SwiftUI
import AppKit
import Defaults
import Foundation

struct AppIcons {
    
    func getIcon(file path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path)
        else { return nil }
        
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    func getIcon(bundleID: String) -> NSImage? {
        guard let path = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        )?.absoluteString
        else { return nil }
        
        return getIcon(file: path)
    }
    
  /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }
        
        return Bundle(url: url)
    }
    
}

extension Notification.Name {
    static let appIconPreviewSignatureDidChange = Notification.Name("AppIconPreviewSignatureDidChange")
}

@MainActor
final class AppIconPreviewMonitor: ObservableObject {
    @Published private(set) var signature: String = AppIconModeManager.previewStateSignature()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .appIconPreviewSignatureDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.signature = AppIconModeManager.previewStateSignature()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

func AppIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }
    
    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

enum ProviderAppIconResolver {
    static func icon(forProviderName providerName: String) -> NSImage? {
        let trimmed = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let workspace = NSWorkspace.shared
        let normalized = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalized.contains("raccourci") || normalized.contains("shortcut") {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                return workspace.icon(forFile: appURL.path)
            }
        }

        if let appPath = workspace.fullPath(forApplication: trimmed) {
            return workspace.icon(forFile: appPath)
        }

        if let appPath = workspace.fullPath(forApplication: "\(trimmed).app") {
            return workspace.icon(forFile: appPath)
        }

        return nil
    }
}

enum AppIconModeManager {
    struct IconAssetSet {
        let iconResourceName: String
        let defaultAssetName: String
        let darkAssetName: String
        let clearLightAssetName: String
        let clearDarkAssetName: String
        let tintedLightAssetName: String
    }

    static let classicAssetSet = IconAssetSet(
        iconResourceName: "AppIcon",
        defaultAssetName: "logo2default",
        darkAssetName: "logo2dark",
        clearLightAssetName: "logo2clearlight",
        clearDarkAssetName: "logo2cleardark",
        tintedLightAssetName: "logo2tintedlight"
    )

    static let quartzNewAssetSet = IconAssetSet(
        iconResourceName: "QuartzNewIcon",
        defaultAssetName: "logo3default",
        darkAssetName: "logo3dark",
        clearLightAssetName: "logo3clearlight",
        clearDarkAssetName: "logo3cleardark",
        tintedLightAssetName: "logo3tintedlight"
    )
    
    private static var monitoringTimer: Timer?
    private static var lastObservedStateSignature: String?
    private static var lastObservedPreviewSignature: String?
    private static var isSystemDarkAppearance: Bool {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let interfaceStyle = globalDomain?["AppleInterfaceStyle"] as? String
        return interfaceStyle?.lowercased() == "dark"
    }

    private static var systemThemeValue: String {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (globalDomain?["AppleIconAppearanceTheme"] as? String) ?? "RegularAutomatic"
    }

    private static var systemTintValue: String {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (globalDomain?["AppleIconAppearanceTintColor"] as? String) ?? "Blue"
    }

    private enum ResolvedMode {
        case regular(Bool)
        case clear(Bool)
        case tinted(Bool)
    }

    private static func resolvedSystemMode() -> ResolvedMode {
        let normalized = systemThemeValue.lowercased()
        let useDarkVariant = normalized.contains("automatic") ? isSystemDarkAppearance : normalized.contains("dark")

        if normalized.contains("tinted") {
            return .tinted(useDarkVariant)
        }
        if normalized.contains("clear") {
            return .clear(useDarkVariant)
        }
        return .regular(useDarkVariant)
    }

    private static func tintHueValue() -> Double? {
        let name = systemTintValue.lowercased()
        switch name {
        case "red": return 0.0
        case "orange": return 0.16
        case "yellow": return 0.33
        case "green": return 0.5
        case "blue": return 0.66
        case "purple": return 0.83
        case "pink": return 0.92
        case "graphite": return nil
        default: return 0.66
        }
    }

    static var selectedAssetSet: IconAssetSet {
        assetSet(for: Defaults[.appIconChoice])
    }

    static func assetSet(for choice: AppIconChoice) -> IconAssetSet {
        switch choice {
        case .classic:
            return classicAssetSet
        case .quartzNew:
            return quartzNewAssetSet
        }
    }

    private static func normalized(_ image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        let canvasSize = NSSize(width: 1024, height: 1024)
        let contentScale: CGFloat = 0.814
        let contentSize = NSSize(
            width: canvasSize.width * contentScale,
            height: canvasSize.height * contentScale
        )
        let origin = NSPoint(
            x: (canvasSize.width - contentSize.width) / 2,
            y: ((canvasSize.height - contentSize.height) / 2) + 2
        )

        let output = NSImage(size: canvasSize)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: origin, size: contentSize))
        output.unlockFocus()
        output.size = canvasSize
        return output
    }

    private static func currentStateSignature() -> String {
        [
            Defaults[.appIconChoice].rawValue,
            systemThemeValue,
            systemTintValue,
            isSystemDarkAppearance ? "dark" : "light",
            NSApp.activationPolicy() == .regular ? "regular" : "accessory"
        ].joined(separator: "|")
    }

    static func previewStateSignature() -> String {
        [
            systemThemeValue,
            systemTintValue,
            isSystemDarkAppearance ? "dark" : "light"
        ].joined(separator: "|")
    }

    @MainActor
    static func startMonitoringSystemAppearance() {
        guard monitoringTimer == nil else { return }
        lastObservedStateSignature = nil
        lastObservedPreviewSignature = nil
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { _ in
            Task { @MainActor in
                applyCurrentAppIconOverride()
            }
        }
        RunLoop.main.add(monitoringTimer!, forMode: .common)
    }

    @MainActor
    static func stopMonitoringSystemAppearance() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        lastObservedStateSignature = nil
        lastObservedPreviewSignature = nil
    }

    private static func renderedTintedIcon(for assets: IconAssetSet, normalize: Bool = true) -> NSImage? {
        guard let bundlePath = Bundle.main.path(forResource: assets.iconResourceName, ofType: "icon") else {
            let fallback = NSImage(named: assets.tintedLightAssetName)
            return normalize ? normalized(fallback) : fallback
        }

        guard let hue = tintHueValue() else {
            let fallback = NSImage(named: isSystemDarkAppearance ? assets.clearDarkAssetName : assets.clearLightAssetName)
            return normalize ? normalized(fallback) : fallback
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuartzNotch-\(assets.iconResourceName)-Tinted-\(Int(hue * 1000)).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/Applications/Icon Composer.app/Contents/Executables/ictool")
        task.arguments = [
            bundlePath,
            "--export-image",
            "--output-file", outputURL.path,
            "--platform", "macOS",
            "--rendition", "TintedLight",
            "--width", "1024",
            "--height", "1024",
            "--scale", "1",
            "--tint-color", String(hue),
            "--tint-strength", "1"
        ]

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                let fallback = NSImage(named: assets.tintedLightAssetName)
                return normalize ? normalized(fallback) : fallback
            }
            let image = NSImage(contentsOf: outputURL) ?? NSImage(named: assets.tintedLightAssetName)
            return normalize ? normalized(image) : image
        } catch {
            let fallback = NSImage(named: assets.tintedLightAssetName)
            return normalize ? normalized(fallback) : fallback
        }
    }

    static func previewImage(for choice: AppIconChoice) -> NSImage? {
        let assets = assetSet(for: choice)
        switch resolvedSystemMode() {
        case let .regular(useDarkVariant):
            return NSImage(named: useDarkVariant ? assets.darkAssetName : assets.defaultAssetName)
        case let .clear(useDarkVariant):
            return NSImage(named: useDarkVariant ? assets.clearDarkAssetName : assets.clearLightAssetName)
        case .tinted:
            return renderedTintedIcon(for: assets, normalize: false) ?? NSImage(named: assets.tintedLightAssetName)
        }
    }

    @MainActor
    static func applyCurrentAppIconOverride() {
        let previewSignature = previewStateSignature()
        if previewSignature != lastObservedPreviewSignature {
            lastObservedPreviewSignature = previewSignature
            NotificationCenter.default.post(name: .appIconPreviewSignatureDidChange, object: nil)
        }

        let newSignature = currentStateSignature()
        guard newSignature != lastObservedStateSignature else { return }
        lastObservedStateSignature = newSignature

        let assets = selectedAssetSet
        switch resolvedSystemMode() {
        case let .regular(useDarkVariant):
            NSApp.applicationIconImage = normalized(NSImage(named: useDarkVariant ? assets.darkAssetName : assets.defaultAssetName))
        case let .clear(useDarkVariant):
            NSApp.applicationIconImage = normalized(NSImage(named: useDarkVariant ? assets.clearDarkAssetName : assets.clearLightAssetName))
        case .tinted:
            NSApp.applicationIconImage = renderedTintedIcon(for: assets) ?? normalized(NSImage(named: assets.tintedLightAssetName))
        }
    }
}
