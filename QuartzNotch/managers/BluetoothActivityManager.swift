import Foundation
import IOBluetooth
import CoreBluetooth
import Defaults
import Combine

final class BluetoothActivityManager {
    
    enum BluetoothDeviceKind: Equatable {
        case airpodsLegacy   // AirPods 1 & 2 (all variants)
        case airpodsBasic    // AirPods 3 & 4 (includes AirPods 4 ANC)
        case airpodsPro      // AirPods Pro 1/2/3
        case airpodsMax      // AirPods Max (Lightning + USB-C)

        case audio
        case keyboard
        case mouse
        case keyboardMouseCombo
        case computer
        case phone
        case gamepad
        case dualsense
        case other
    }

    static let shared = BluetoothActivityManager()

    struct DeviceInfo: Equatable {
        let name: String
        let address: String
        let kind: BluetoothDeviceKind
    }

  /// Called when a device has just connected
    var onDeviceConnected: ((DeviceInfo) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var bluetoothEnabledCancellable: AnyCancellable?

    private var lastEvent: (DeviceInfo, Date)?
    private let minInterval: TimeInterval = 1.0

    private init() {
        if Defaults[.bluetoothLiveActivityEnabled], Self.isBluetoothAuthorizedForBackgroundMonitoring() {
            start()
        }

        bluetoothEnabledCancellable = Defaults.publisher(.bluetoothLiveActivityEnabled, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.start()
                } else {
                    self.stop()
                }
            }
    }

    private static func isBluetoothAuthorizedForBackgroundMonitoring() -> Bool {
        if #available(macOS 10.15, *) {
            return CBManager.authorization == .allowedAlways
        }
        return true
    }

  // MARK: - Name normalization / filtering (anti "ghost" popups)

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

  /// Returns true for devices we should ignore (Apple ecosystem / continuity / noisy names).
  /// Goal: avoid "phantom" popups for devices that are not really user-facing peripherals.
    private func shouldIgnoreDeviceName(_ name: String) -> Bool {
        let n = normalize(name)
        if n.isEmpty { return true }

        let ignoreContains: [String] = [
            "continuity",
            "handoff",
            "nearby",
            "instant hotspot",
            "apple tv",
            "homepod",
            "airtag",
            "watch",
            "iphone",
            "ipad",
            "macbook",
            "imac",
            "mac mini",
            "mac studio"
        ]

        let ignoreExact: Set<String> = [
            "unknown",
            "n/a",
            "null",
            "device",
            "bluetooth",
            "not available",
            "bluetooth device"
        ]

        if ignoreExact.contains(n) { return true }
        if ignoreContains.contains(where: { n.contains($0) }) { return true }

        return false
    }

  /// Fallback classifier when Class-of-Device isn't useful.
  /// Returns nil when we can't classify confidently (=> no popup).
    private func fallbackKindFromName(_ name: String) -> BluetoothDeviceKind? {
        let n = normalize(name)
        guard !n.isEmpty else { return nil }

        if let airpods = airPodsKindFromName(n) {
            return airpods
        }

        if n.contains("beats") || n.contains("bose") || n.contains("sony")
            || n.contains("jbl") || n.contains("headphone") || n.contains("headset")
            || n.contains("earbud") || n.contains("earphone") || n.contains("buds")
        {
            return .audio
        }

        if n.contains("keyboard") || n.contains("clavier") || n.contains("keychron")
            || n.contains("mx keys") || n.contains("magic keyboard")
        {
            return .keyboard
        }

        if n.contains("mouse") || n.contains("souris") || n.contains("mx master")
            || n.contains("magic mouse") || n.contains("trackpad") || n.contains("magic trackpad")
        {
            return .mouse
        }

        if n.contains("dualsense") || n.contains("ps5 controller") {
            return .dualsense
        }

        if n.contains("controller") || n.contains("gamepad") || n.contains("dualshock")
            || n.contains("dualsense") || n.contains("xbox") || n.contains("ps5") || n.contains("ps4")
        {
            return .gamepad
        }

        return nil
    }

  /// AirPods classification based on the device name.
  /// - Note: Pro & Max are typically reliable via name.
  ///     Legacy vs Basic depends on whether the name contains generation hints.
    private func airPodsKindFromName(_ normalizedName: String) -> BluetoothDeviceKind? {
        guard normalizedName.contains("airpods") else { return nil }

        if normalizedName.contains("airpods max") || normalizedName.contains("airpodsmax") {
            return .airpodsMax
        }

        if normalizedName.contains("airpods pro") || normalizedName.contains("airpodspro") {
            return .airpodsPro
        }

        let basicHints: [String] = [
            "(3rd generation)", "3rd generation", "third generation",
            "(4th generation)", "4th generation", "fourth generation",
            "airpods 3", "airpods 4",
            "gen 3", "gen3", "gen 4", "gen4",
            "4 anc", "anc"
        ]
        if basicHints.contains(where: { normalizedName.contains($0) }) {
            return .airpodsBasic
        }

        return .airpodsLegacy
    }


  // MARK: - DualSense detection (PS5 controller)

  /// Attempts to detect DualSense / DualSense Edge using Sony vendor/product IDs when available.
  /// Returns nil if IDs are unavailable (common over Bluetooth on some macOS versions).
    private func dualSenseKindFromSonyPID(device: IOBluetoothDevice) -> BluetoothDeviceKind? {
        let vid: Int? = (device.value(forKey: "vendorID") as? NSNumber)?.intValue
        let pid: Int? = (device.value(forKey: "productID") as? NSNumber)?.intValue

        guard let vid, let pid else { return nil }
        guard vid == 0x054C else { return nil }

        if pid == 0x0CE6 || pid == 0x0DF2 {
            return .dualsense
        }
        return nil
    }

  /// Name-based fallback for DualSense when VID/PID is not accessible.
    private func dualSenseKindFromName(_ normalizedName: String) -> BluetoothDeviceKind? {
        let n = normalizedName
        guard !n.isEmpty else { return nil }

        if n.contains("dualsense") { return .dualsense }
        if n.contains("ps5") && n.contains("controller") { return .dualsense }
        return nil
    }


// MARK: - AirPods detection via Apple Bluetooth VID/PID (most reliable when available)

/// Returns an AirPods bucket using Apple Bluetooth VendorID/ProductID when available.
/// If we cannot read VID/PID (or PID is unknown), returns nil.
private func airPodsKindFromApplePID(device: IOBluetoothDevice) -> BluetoothDeviceKind? {
    func readUInt16(_ key: String) -> UInt16? {
        if device.responds(to: NSSelectorFromString(key)),
           let num = device.value(forKey: key) as? NSNumber {
            return num.uint16Value
        }
        if let num = device.value(forKey: key) as? NSNumber {
            return num.uint16Value
        }
        return nil
    }

    guard let vendor = readUInt16("vendorID"), vendor == 0x004C else { return nil } // Apple
    guard let pid = readUInt16("productID") else { return nil }

    switch pid {
    case 0x2002, 0x200F:
        return .airpodsLegacy

    case 0x2013, 0x2019, 0x201B:
        return .airpodsBasic

    case 0x200E, 0x2014, 0x2024:
        return .airpodsPro

    case 0x200A:
        return .airpodsMax

    default:
        return nil
    }
}

    private func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )

        if connectNotification == nil {
            print("[WARN] BluetoothActivityManager: failed to register connect notification")
        }
    }

    private func stop() {
        connectNotification?.unregister()
        connectNotification = nil
    }
    
  /// Returns nil when the type can't be determined reliably.
  /// Nil means "do not show a popup".
    private func detectKind(from device: IOBluetoothDevice) -> BluetoothDeviceKind? {
        let cod = UInt32(device.classOfDevice)
        let major = (cod >> 8) & 0x1F
        let minor = (cod >> 2) & 0x3F

        switch major {
        case 0x04: // Audio/Video
            return .audio

        case 0x05: // Peripheral
            let peripheralTop2 = (minor >> 4) & 0x03
            switch peripheralTop2 {
            case 0x01: return .keyboard
            case 0x02: return .mouse
            case 0x03: return .keyboardMouseCombo
            default:
                if minor == 0x02 { return .gamepad } // often gamepad/joystick on some stacks
                return nil
            }

        case 0x01: // Computer
            return .computer

        case 0x02: // Phone
            return .phone

        default:
            return nil
        }
    }


    deinit {
        stop()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = (device.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Bluetooth device"
        let address = device.addressString ?? ""

        if shouldIgnoreDeviceName(name) {
            return
        }

        let normalized = normalize(name)
        let kind = airPodsKindFromApplePID(device: device)
            ?? airPodsKindFromName(normalized)
            ?? dualSenseKindFromSonyPID(device: device)
            ?? dualSenseKindFromName(normalized)
            ?? detectKind(from: device)
            ?? fallbackKindFromName(name)

        guard let finalKind = kind else {
            return
        }

        let info = DeviceInfo(name: name, address: address, kind: finalKind)

        if let (lastInfo, lastDate) = lastEvent {
            if lastInfo == info, Date().timeIntervalSince(lastDate) < minInterval { return }
        }
        lastEvent = (info, Date())

        DispatchQueue.main.async { [weak self] in
            self?.onDeviceConnected?(info)
        }
    }
}
