//
// LiveActivities.swift
// boringNotch
//
// Created by Clayton on 26/01/2026.
//

import SwiftUI
import Defaults

struct LiveActivities: View {
  // Wiring:
  // - Charging state -> Battery: showPowerStatusNotifications
  // - Shelf content -> controls the closed-notch tray counter popup
  // - Lock screen  -> controls the lock/unlock popup shown on the lock screen
  // - Now playing  -> uses the existing AppStorage toggle used by the coordinator
    @AppStorage("musicLiveActivityEnabled") private var musicLiveActivityEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Charging state")
                }
                .tint(.effectiveAccent)

                Defaults.Toggle(key: .liveActivityShelfContent) {
                    Text("Shelf content")
                }
                .tint(.effectiveAccent)

                Defaults.Toggle(key: .liveActivityLockScreen) {
                    Text("Lock screen")
                }
                .tint(.effectiveAccent)

                Defaults.Toggle(key: .bluetoothLiveActivityEnabled) {
                    Text("Bluetooth")
                }
                .tint(.effectiveAccent)

                Defaults.Toggle(key: .liveActivityTimerEnabled) {
                    Text("Timer")
                }
                .tint(.effectiveAccent)

                Toggle("Now playing", isOn: $musicLiveActivityEnabled)
                    .tint(.effectiveAccent)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“Shelf content” shows or hides the closed-notch tray counter popup.")
                    Text("“Lock screen” shows or hides the lock/unlock popup. (The notch visibility on lock screen is controlled in Advanced → Show notch on lock screen.)")
                    Text("“Bluetooth” shows or hides the device-connected popup.")
                    Text("“Timer” shows or hides the closed-notch timer indicator for Quick Timers (page 3).")
                }
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
                .tint(.effectiveAccent)
            } header: {
                Text("Inactive")
            }
        }
        .navigationTitle("Live Activities")
    }
}

#Preview {
    LiveActivities()
}
