//
// BluetoothStatusViewModel.swift
// boringNotch
//
// Created by Clayton on 29/01/2026.
//

import Foundation
import SwiftUI
import Defaults

@MainActor
final class BluetoothStatusViewModel: ObservableObject {

    static let shared = BluetoothStatusViewModel()

    @Published private(set) var lastConnectedDeviceName: String = ""
    @Published private(set) var lastConnectedDeviceKind: BluetoothActivityManager.BluetoothDeviceKind = .other
    @Published private(set) var lastConnectedBatteryPercent: Int? = nil
    @Published var lastConnectedAliasName: String?

  // Battery cache to make the UI feel instant when reconnecting the same device.
    private var batteryCache: [String: (percent: Int, ts: Date)] = [:]
    private let batteryCacheTTL: TimeInterval = 20 * 60

    private let coordinator = BoringViewCoordinator.shared
    private let manager = BluetoothActivityManager.shared
    private let xpc = XPCHelperClient.shared

    private init() {
        manager.onDeviceConnected = { [weak self] info in
            guard let self else { return }
            guard Defaults[.bluetoothLiveActivityEnabled] else { return }
            self.lastConnectedDeviceName = info.name
            self.lastConnectedDeviceKind = info.kind
            self.lastConnectedBatteryPercent = nil

      // Instant feel: show cached value (if fresh), then refresh.
            let cacheKey = self.cacheKey(address: info.address, name: info.name)
            if let entry = self.batteryCache[cacheKey], Date().timeIntervalSince(entry.ts) < self.batteryCacheTTL {
                self.lastConnectedBatteryPercent = entry.percent
            }

            self.xpc.warmUpBluetoothBatteryCache()
            self.resolveBatteryFast(address: info.address, name: info.name)
            self.coordinator.toggleExpandingView(status: true, type: .bluetooth)
        }
    }

    private func cacheKey(address: String, name: String) -> String {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveBatteryFast(address: String, name: String) {
        let delays: [TimeInterval] = [0.0, 0.4, 0.9, 1.6, 2.6]
        let addr = address
        let nm = name
        let key = cacheKey(address: addr, name: nm)

        for delay in delays {
            Task.detached { [weak self] in
                guard let self else { return }
                guard Defaults[.bluetoothLiveActivityEnabled] else { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                if let p = await self.xpc.bluetoothBatteryPercent(forDeviceAddress: addr, deviceName: nm) {
                    await MainActor.run {
            // Don't bounce the UI if already set to the same value.
                        if self.lastConnectedBatteryPercent != p {
                            self.lastConnectedBatteryPercent = p
                        }
                        self.batteryCache[key] = (p, Date())
                    }
                }
            }
        }
    }
}
