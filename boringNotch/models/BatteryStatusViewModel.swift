import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    private init() {
        setupPowerStatus()
        setupMonitor()
    }

  /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

  /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

  /// Handles battery events and updates the corresponding properties
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {

        case .powerSourceChanged(let pluggedIn):
            print("🔌 Power source: \(pluggedIn ? "Connected" : "Disconnected")")

      // Update state immediately with a snapshot (not through an event queue).
      // Goal: content ready on the first animation frame.
            if pluggedIn {
                let snap = managerBattery.currentBatteryInfo()
                withAnimation {
                    self.isPluggedIn = true
                    self.levelBattery = snap.currentCapacity
                    self.maxCapacity = snap.maxCapacity
                    self.isCharging = snap.isCharging
                    self.isInLowPowerMode = snap.isInLowPowerMode
                    self.timeToFullCharge = snap.timeToFullCharge
                    self.statusText = "Charging"
                }
                notifyImportanChangeStatus()
            } else {
                withAnimation {
                    self.isPluggedIn = false
          // No live activity on unplug.
                    self.statusText = ""
                }
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation {
                self.levelBattery = level
            }

        case .lowPowerModeChanged(let isEnabled):
            print("[PERF] Low power mode: \(isEnabled ? "Enabled" : "Disabled")")

            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }

      // (unchanged) low power mode remains a notification
            notifyImportanChangeStatus()

        case .isChargingChanged(let charging):
            print("🔌 Charging: \(charging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")

      // IMPORTANT:
      // Do not trigger a live activity here anymore.
      // Sinon tu retrouves exactement ton double-pop ("Plugged" puis "Charging").
            withAnimation {
                self.isCharging = charging
                if charging {
                    self.statusText = "Charging"
                } else if self.isPluggedIn {
                    self.statusText = (self.maxCapacity > 0 && self.levelBattery >= self.maxCapacity)
                        ? "Full charge"
                        : "Not charging"
                } else {
                    self.statusText = ""
                }
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("[WARN] Error: \(description)")
        }
    }

  /// Updates the battery information with the given BatteryInfo instance
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity

      // Consistent behavior: if already plugged in at launch, set "charging"; otherwise empty
            self.statusText = batteryInfo.isPluggedIn ? "Charging" : ""
        }
    }

  /// Notifies important changes in the battery status with an optional delay
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }
}
