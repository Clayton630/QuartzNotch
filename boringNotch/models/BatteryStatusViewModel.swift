import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

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

    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {

        case .powerSourceChanged(let pluggedIn):
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
                    self.statusText = ""
                }
            }

        case .batteryLevelChanged(let level):
            withAnimation {
                self.levelBattery = level
            }

        case .lowPowerModeChanged(let isEnabled):
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }

        case .isChargingChanged(let charging):
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
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            statusText = description
        }
    }

    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity

            self.statusText = batteryInfo.isPluggedIn ? "Charging" : ""
        }
    }

    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    deinit {
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }
}
