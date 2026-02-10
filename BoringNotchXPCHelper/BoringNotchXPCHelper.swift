//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {

    // MARK: - Bluetooth Battery (best-effort)

    private static let spCacheQueue = DispatchQueue(label: "theboringteam.boringnotch.spbt.cache")
    private static var spCache: (ts: Date, json: [String: Any])?
    private static let spCacheTTL: TimeInterval = 12.0

    @objc func warmUpBluetoothBatteryCache() {
        _ = Self.loadSystemProfilerBTJSON()
    }

    @objc func bluetoothBatteryPercent(forDeviceAddress address: String, deviceName: String, with reply: @escaping (NSNumber?) -> Void) {
        let normalizedAddr = Self.normalizeBTAddress(address)
        let normalizedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Apple HID path (Magic Keyboard/Mouse/Trackpad) via IORegistry
        if !normalizedAddr.isEmpty, let p = Self.readHIDBatteryPercent(matchingNormalizedAddress: normalizedAddr) {
            reply(NSNumber(value: p))
            return
        }

        // 1.5) Gamepad HID path (DualShock / DualSense / some controllers) via IORegistry (IOHIDDevice)
        if let p = Self.readGamepadHIDBatteryPercent(
            matchingNormalizedAddress: normalizedAddr,
            deviceName: normalizedName
        ) {
            reply(NSNumber(value: p))
            return
        }

        // 2) system_profiler SPBluetoothDataType -json (AirPods + some BT devices)
        if let p = Self.readSystemProfilerBatteryPercent(matchingNormalizedAddress: normalizedAddr, deviceName: normalizedName) {
            reply(NSNumber(value: p))
            return
        }

        reply(nil)
    }

    private static func normalizeBTAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return stripped
    }

    // MARK: - IORegistry/HID (Magic devices)

    private static func readHIDBatteryPercent(matchingNormalizedAddress normalized: String) -> Int? {
        let classes = [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDKeyboard",
            "BNBTrackpadDevice",
            "BNBMouseDevice"
        ]

        for cls in classes {
            if let p = readHIDBatteryPercent(inClass: cls, matchingNormalizedAddress: normalized) {
                return p
            }
        }
        return nil
    }

    private static func readHIDBatteryPercent(inClass className: String, matchingNormalizedAddress normalized: String) -> Int? {
        let matching = IOServiceMatching(className)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            var outDict: Unmanaged<CFMutableDictionary>?
            let kr = IORegistryEntryCreateCFProperties(service, &outDict, kCFAllocatorDefault, 0)
            guard kr == KERN_SUCCESS, let unmanaged = outDict else { continue }

            let cfDict = unmanaged.takeRetainedValue()
            guard let props = cfDict as? [String: Any] else { continue }

            var addrNorm: String?
            if let s = props["DeviceAddress"] as? String {
                addrNorm = normalizeBTAddress(s)
            } else if let d = props["DeviceAddress"] as? Data {
                addrNorm = d.map { String(format: "%02x", $0) }.joined()
            }

            guard let a = addrNorm, !a.isEmpty, a == normalized else { continue }

            if let n = props["BatteryPercent"] as? NSNumber {
                let v = n.intValue
                if (0...100).contains(v) { return v }
            } else if let v = props["BatteryPercent"] as? Int {
                if (0...100).contains(v) { return v }
            }
        }

        return nil
    }

    // MARK: - IORegistry/HID (Gamepads: DualShock / DualSense)

    // Try to read battery percent from IOHIDDevice for gamepads.
    // Matching strategy:
    // - Prefer BT address match (walk up the IORegistry parents to find DeviceAddress-like keys)
    // - Fallback to deviceName match when address is missing
    private static func readGamepadHIDBatteryPercent(matchingNormalizedAddress normalizedAddr: String, deviceName: String) -> Int? {

        let wantedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantedNameLower = wantedName.lowercased()

        let matching = IOServiceMatching("IOHIDDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let props = readServiceProperties(service) else { continue }

            // Filter: keep conservative so we don't steal non-gamepad devices.
            // Sony vendor id (when present): 0x054C
            let vendor = (props["VendorID"] as? NSNumber)?.intValue ?? (props["VendorID"] as? Int)
            let productStr = ((props["Product"] as? String) ?? "").lowercased()
            let manufacturerStr = ((props["Manufacturer"] as? String) ?? "").lowercased()

            let looksLikeGamepad =
                (vendor == 0x054C)
                || productStr.contains("dualsense")
                || productStr.contains("dualshock")
                || productStr.contains("wireless controller")
                || productStr.contains("controller")
                || manufacturerStr.contains("sony")

            if !looksLikeGamepad {
                continue
            }

            // 1) Best match: by Bluetooth address (if we have one)
            if !normalizedAddr.isEmpty {
                if let foundAddr = findBTAddressInParents(start: service),
                   foundAddr == normalizedAddr
                {
                    if let p = extractBatteryPercent(from: props) { return p }
                    if let p = extractBatteryPercentFromParents(start: service) { return p }
                }
            }

            // 2) Fallback match: by device name (when address not available)
            if !wantedNameLower.isEmpty {
                let candidates: [String] = [
                    (props["Product"] as? String) ?? "",
                    (props["DeviceName"] as? String) ?? "",
                    (props["Name"] as? String) ?? ""
                ]
                let joined = candidates.joined(separator: " ").lowercased()

                let joinedTrim = joined.trimmingCharacters(in: .whitespacesAndNewlines)
                    let directMatch = joined.contains(wantedNameLower) || wantedNameLower.contains(joinedTrim)

                    // Loose but safe-ish matching for Sony controllers where the BT name differs from the HID product string.
                    // Example: wantedName = "DualSense Wireless Controller" but HID Product = "Wireless Controller".
                    let dualSenseLooseMatch = wantedNameLower.contains("dualsense") && joined.contains("wireless controller")
                    let dualShockLooseMatch = wantedNameLower.contains("dualshock") && joined.contains("wireless controller")

                    if directMatch || dualSenseLooseMatch || dualShockLooseMatch {
                    if let p = extractBatteryPercent(from: props) { return p }
                    if let p = extractBatteryPercentFromParents(start: service) { return p }
                }
            }
        }

        return nil
    }

    private static func readServiceProperties(_ service: io_registry_entry_t) -> [String: Any]? {
        var outDict: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &outDict, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let unmanaged = outDict else { return nil }
        let cfDict = unmanaged.takeRetainedValue()
        return cfDict as? [String: Any]
    }

    private static func extractBatteryPercent(from props: [String: Any]) -> Int? {
        func doubleFrom(_ any: Any?) -> Double? {
            if let n = any as? NSNumber { return n.doubleValue }
            if let i = any as? Int { return Double(i) }
            if let d = any as? Double { return d }
            if let f = any as? Float { return Double(f) }
            if let s = any as? String {
                // Keep digits and at most one dot, then parse.
                let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Double(cleaned) { return v }
                let digits = cleaned.filter { $0.isNumber }
                return Double(digits)
            }
            return nil
        }

        func clampPercent(_ v: Int?) -> Int? {
            guard let v, (0...100).contains(v) else { return nil }
            return v
        }

        func isLowSignalKey(_ keyLower: String) -> Bool {
            // These keys often store enums/flags (0/1/2...) and cause "always 0/1%" bugs if treated as a percent.
            return keyLower.contains("status")
                || keyLower.contains("state")
                || keyLower.contains("flags")
                || keyLower.contains("charging")
                || keyLower.contains("present")
        }

        func mapIfBatteryLevel(_ raw: Int, keyLower: String) -> Int {
            // Many controllers expose battery as "bars": 0..4 (sometimes 0..10).
            if keyLower.contains("level") || keyLower == "battery" || keyLower.contains("batterylevel") {
                if (0...4).contains(raw) { return raw * 25 }
                if (0...10).contains(raw) { return raw * 10 }
            }
            return raw
        }

        func keyScore(_ keyLower: String) -> Int {
            if keyLower.contains("percent") { return 90 }
            if keyLower.contains("level") { return 80 }
            if keyLower.contains("capacity") { return 70 }
            return 40
        }

        let primaryKeys = [
            "BatteryPercent",
            "BatteryPercentRemaining",
            "BatteryLevel",
            "BatteryLevelMain",
            "DeviceBatteryPercent",
            "BatteryCapacity",
            "BatteryRemaining",
            "BatteryCharge",
            "Battery",
            "BatteryLevelPercent"
        ]

        var best: (value: Int, score: Int)?

        func consider(_ value: Int, score: Int) {
            if let b = best {
                if score > b.score { best = (value, score); return }
                if score == b.score, b.value <= 1, value > b.value { best = (value, score); return }
            } else {
                best = (value, score)
            }
        }

        func interpret(_ any: Any?, keyLower: String) -> Int? {
            guard let d = doubleFrom(any) else { return nil }

            // If we get a fraction (0.0..1.0), treat it as a percent fraction.
            if d > 0, d <= 1.0, (keyLower.contains("percent") || keyLower.contains("level") || keyLower.contains("capacity")) {
                return clampPercent(Int((d * 100.0).rounded()))
            }

            let rawInt = Int(d.rounded())
            let mapped = mapIfBatteryLevel(rawInt, keyLower: keyLower)
            return clampPercent(mapped)
        }

        // 1) Direct lookup on known keys (highest confidence)
        for k in primaryKeys {
            let kl = k.lowercased()
            if let p = interpret(props[k], keyLower: kl) {
                consider(p, score: 100)
                if p >= 5 { return p } // Avoid returning 0/1 too early (often "bars" or flags).
            }
        }

        // 2) Nested dictionaries / arrays (some HID stacks wrap battery info)
        for (_, v) in props {
            if let dict = v as? [String: Any], let p = extractBatteryPercent(from: dict) {
                consider(p, score: 95)
                if p >= 5 { return p }
            } else if let arr = v as? [Any] {
                for item in arr {
                    if let dict = item as? [String: Any], let p = extractBatteryPercent(from: dict) {
                        consider(p, score: 95)
                        if p >= 5 { return p }
                    }
                }
            }
        }

        // 3) Scan any key containing "battery" but avoid low-signal keys (status/state/flags -> often 0/1)
        for (k, v) in props {
            let kl = k.lowercased()
            guard kl.contains("battery") else { continue }
            guard !isLowSignalKey(kl) else { continue }

            if let p = interpret(v, keyLower: kl) {
                // Treat 0/1 as weak unless the key name strongly indicates a percent.
                let s = keyScore(kl) + ((p <= 1 && !kl.contains("percent")) ? -30 : 0)
                consider(p, score: s)
            }
        }

        return best?.value
    }


    // Walk parents to find a bluetooth address-like property and normalize it.
    private static func findBTAddressInParents(start: io_registry_entry_t) -> String? {
        var current: io_registry_entry_t = start
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<10 {
            if let props = readServiceProperties(current) {
                if let s = props["DeviceAddress"] as? String {
                    return normalizeBTAddress(s)
                } else if let d = props["DeviceAddress"] as? Data {
                    return d.map { String(format: "%02x", $0) }.joined()
                }

                if let s = props["BluetoothDeviceAddress"] as? String {
                    return normalizeBTAddress(s)
                }
                if let s = props["BD_ADDR"] as? String {
                    return normalizeBTAddress(s)
                }
            }

            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if kr != KERN_SUCCESS || parent == 0 { return nil }

            // Move up safely (release current retain, retain parent)
            IOObjectRelease(current)
            current = parent
            IOObjectRetain(current)
        }

        return nil
    }

    private static func extractBatteryPercentFromParents(start: io_registry_entry_t) -> Int? {
        var current: io_registry_entry_t = start
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<10 {
            if let props = readServiceProperties(current),
               let p = extractBatteryPercent(from: props) {
                return p
            }

            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if kr != KERN_SUCCESS || parent == 0 { return nil }

            IOObjectRelease(current)
            current = parent
            IOObjectRetain(current)
        }

        return nil
    }

    // MARK: - system_profiler (AirPods + some BT devices)

    private static func readSystemProfilerBatteryPercent(matchingNormalizedAddress normalizedAddr: String, deviceName: String) -> Int? {
        guard let json = loadSystemProfilerBTJSON() else { return nil }

        // First try: match by device_address when available.
        var match: [String: Any]?

        func walkForAddress(_ node: Any) {
            if match != nil { return }
            if let dict = node as? [String: Any] {
                if !normalizedAddr.isEmpty,
                   let addr = dict["device_address"] as? String,
                   normalizeBTAddress(addr) == normalizedAddr {
                    match = dict
                    return
                }
                for (_, v) in dict {
                    walkForAddress(v)
                    if match != nil { return }
                }
            } else if let arr = node as? [Any] {
                for v in arr {
                    walkForAddress(v)
                    if match != nil { return }
                }
            }
        }

        walkForAddress(json)

        // Second try (AirPods-friendly): match by device_name if address wasn't found.
        if match == nil {
            let wantedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !wantedName.isEmpty {
                func walkForName(_ node: Any) {
                    if match != nil { return }
                    if let dict = node as? [String: Any] {
                        if let n = dict["device_name"] as? String {
                            // Case-insensitive exact match first; then contains.
                            let dn = n.trimmingCharacters(in: .whitespacesAndNewlines)
                            if dn.compare(wantedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                                match = dict
                                return
                            }
                            if dn.range(of: wantedName, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                                match = dict
                                return
                            }
                        }
                        for (_, v) in dict {
                            walkForName(v)
                            if match != nil { return }
                        }
                    } else if let arr = node as? [Any] {
                        for v in arr {
                            walkForName(v)
                            if match != nil { return }
                        }
                    }
                }
                walkForName(json)
            }
        }

        guard let device = match else { return nil }

        func doubleFrom(_ any: Any?) -> Double? {
            if let n = any as? NSNumber { return n.doubleValue }
            if let i = any as? Int { return Double(i) }
            if let d = any as? Double { return d }
            if let f = any as? Float { return Double(f) }
            if let s = any as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Double(trimmed) { return v }
                let digits = trimmed.filter { $0.isNumber }
                return Double(digits)
            }
            return nil
        }

        func normalizePercent(_ raw: Int, keyLower: String) -> Int? {
            // system_profiler often returns "battery level bars" for controllers: 0..4 (or 0..10).
            if keyLower.contains("batterylevel") || (keyLower.contains("battery") && keyLower.contains("level")) {
                if (0...4).contains(raw) { return raw * 25 }
                if (0...10).contains(raw) { return raw * 10 }
            }
            guard (0...100).contains(raw) else { return nil }
            return raw
        }

        func percentFrom(_ any: Any?, keyLower: String) -> Int? {
            guard let d = doubleFrom(any) else { return nil }
            if d > 0, d <= 1.0, (keyLower.contains("percent") || keyLower.contains("level")) {
                return Int((d * 100.0).rounded())
            }
            return normalizePercent(Int(d.rounded()), keyLower: keyLower)
        }

        if let main = percentFrom(device["device_batteryLevelMain"], keyLower: "device_batterylevelmain") { return main }

        let left = percentFrom(device["device_batteryLevelLeft"], keyLower: "device_batterylevelleft")
        let right = percentFrom(device["device_batteryLevelRight"], keyLower: "device_batterylevelright")
        if let l = left, let r = right { return max(l, r) }
        if let l = left { return l }
        if let r = right { return r }

        if let generic = percentFrom(device["device_batteryLevel"], keyLower: "device_batterylevel") { return generic }

        // Some devices (including controllers) may expose battery under different keys.
        // Be conservative: only accept keys that look like a level/percent, not flags/status.
        for (k, v) in device {
            let kl = k.lowercased()
            guard kl.contains("battery") else { continue }
            guard (kl.contains("level") || kl.contains("percent")) else { continue }
            if let p = percentFrom(v, keyLower: kl) { return p }
        }

        return nil
    }

    private static func loadSystemProfilerBTJSON() -> [String: Any]? {
        let cached: (ts: Date, json: [String: Any])? = spCacheQueue.sync { spCache }
        if let c = cached, Date().timeIntervalSince(c.ts) < spCacheTTL {
            return c.json
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard !data.isEmpty else { return nil }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else { return nil }
            spCacheQueue.sync {
                spCache = (Date(), dict)
            }
            return dict
        } catch {
            return nil
        }
    }

    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }

    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
