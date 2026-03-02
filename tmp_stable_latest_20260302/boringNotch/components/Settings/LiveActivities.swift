//
// LiveActivities.swift
// boringNotch
//
// Created by Clayton on 26/01/2026.
//

import SwiftUI
import Defaults
import AppKit
import Foundation

struct LiveActivities: View {
  // Wiring:
  // - Charging state -> Battery: showPowerStatusNotifications
  // - Shelf content -> controls the closed-notch tray counter popup
  // - Lock screen  -> controls the lock/unlock popup shown on the lock screen
  // - Now playing  -> uses the existing AppStorage toggle used by the coordinator
    @AppStorage("musicLiveActivityEnabled") private var musicLiveActivityEnabled: Bool = true
    @Default(.quickTimerAlertToneID) private var quickTimerAlertToneID
    @ObservedObject private var fullDiskAccess = FullDiskAccessPermissionStore.shared

    private let timerToneOptions: [(id: String, label: String)] = [
        ("systemDefault", "Clock default"),
        ("system:Radial", "Radial"),
        ("system:Radar", "Radar"),
        ("system:Alarm", "Alarm"),
        ("system:Beacon", "Beacon"),
        ("system:Bell Tower", "Bell Tower"),
        ("system:Chimes", "Chimes"),
        ("system:Cosmic", "Cosmic"),
        ("system:Ripples", "Ripples"),
        ("system:Sencha", "Sencha"),
        ("system:Uplift", "Uplift"),
        ("globalAlert", "macOS alert sound")
    ]

    var body: some View {
        Form {
            Section {
                if !fullDiskAccess.isAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Full Disk Access required for custom Focus icon and color", systemImage: "externaldrive.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Without this permission, Focus name can still be detected, but icon and tint may stay generic.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Request Full Disk Access") {
                            fullDiskAccess.requestAccessPrompt()
                        }
                    }
                    .padding(.vertical, 4)
                }

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

                Defaults.Toggle(key: .focusLiveActivityEnabled) {
                    Text("Focus mode")
                }
                .tint(.effectiveAccent)

                Defaults.Toggle(key: .liveActivityTimerEnabled) {
                    Text("Timer")
                }
                .tint(.effectiveAccent)

                Defaults.Toggle(key: .mirrorSystemClockTimer) {
                    Text("Mirror Clock app timer")
                }
                .tint(.effectiveAccent)

                Picker("Timer ringtone", selection: $quickTimerAlertToneID) {
                    ForEach(timerToneOptions, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Now playing", isOn: $musicLiveActivityEnabled)
                    .tint(.effectiveAccent)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“Shelf content” shows or hides the closed-notch tray counter popup.")
                    Text("“Lock screen” shows or hides the lock/unlock popup. (The notch visibility on lock screen is controlled in Advanced → Show notch on lock screen.)")
                    Text("“Bluetooth” shows or hides the device-connected popup.")
                    Text("“Focus mode” shows or hides the concentration live activity in the closed notch.")
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
        .onAppear {
            fullDiskAccess.refreshStatus()
        }
    }
}

@MainActor
private final class FullDiskAccessPermissionStore: ObservableObject {
    static let shared = FullDiskAccessPermissionStore()
    @Published private(set) var isAuthorized: Bool = FullDiskAccessPermissionStore.hasPermission()
    @Published private(set) var canReadDoNotDisturbDB: Bool = false
    @Published private(set) var canReadTCCDB: Bool = false
    @Published private(set) var bundlePath: String = Bundle.main.bundleURL.path

    private var pollingTask: Task<Void, Never>?

    private init() {
        refreshStatus()
    }

    deinit {
        pollingTask?.cancel()
    }

    func refreshStatus() {
        bundlePath = Bundle.main.bundleURL.path
        let status = Self.readabilityStatus()
        canReadDoNotDisturbDB = status.doNotDisturbDB
        canReadTCCDB = status.tccDB
        isAuthorized = status.doNotDisturbDB || status.tccDB
    }

    func requestAccessPrompt() {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "QuartzNotch needs Full Disk Access to read Focus metadata (custom icon and color). Click Continue, then add QuartzNotch in Privacy & Security > Full Disk Access."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
            revealAppBundleInFinder()
        }

        beginPollingForStatusChanges()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealAppBundleInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    private func beginPollingForStatusChanges() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let status = Self.readabilityStatus()
                await MainActor.run {
                    self.canReadDoNotDisturbDB = status.doNotDisturbDB
                    self.canReadTCCDB = status.tccDB
                    self.isAuthorized = status.doNotDisturbDB || status.tccDB
                }
                if status.doNotDisturbDB || status.tccDB { break }
            }
        }
    }

    private static func hasPermission() -> Bool {
        let status = readabilityStatus()
        return status.doNotDisturbDB || status.tccDB
    }

    private static func readabilityStatus() -> (doNotDisturbDB: Bool, tccDB: Bool) {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
        ]

        var tccReadable = false
        var dndReadable = false

        for url in paths {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            if let handle = try? FileHandle(forReadingFrom: url) {
                try? handle.close()
                if url.lastPathComponent == "TCC.db" {
                    tccReadable = true
                } else if url.lastPathComponent == "ModeConfigurations.json" {
                    dndReadable = true
                }
            }
        }
        return (dndReadable, tccReadable)
    }
}

#Preview {
    LiveActivities()
}
