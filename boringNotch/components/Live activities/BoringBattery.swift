import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    var icon: String = "battery.0"

    private var pillIconGray: Color { .gray.opacity(0.65) }

  // CHANGE: bolt instead of plug when plugged in
    var iconStatus: String {
        if isCharging || isPluggedIn { return "bolt" }
        else { return "" }
    }

    var batteryTint: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn {
            return .green
        } else {
            return isForNotification ? .white : pillIconGray
        }
    }

    var outlineColor: Color {
        batteryTint.opacity(isForNotification ? 0.55 : 0.65)
    }

    var statusIconColor: Color {
        batteryTint
    }

    var body: some View {
        let fillHeight: CGFloat = batteryWidth * 0.3083
        let fillCornerRadius: CGFloat = max(1.0, fillHeight * 0.18)

        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(outlineColor)
                .frame(width: batteryWidth + 1)

            RoundedRectangle(cornerRadius: fillCornerRadius, style: .continuous)
                .fill(batteryTint)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: fillHeight
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || Defaults[.showPowerStatusIcons]) {
                Image(systemName: icon)
                    .resizable()
                    .fontWeight(.thin)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.clear)
                    .frame(width: batteryWidth + 1)
                    .overlay {
                        Image(iconStatus)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(statusIconColor)
                            .frame(width: 13, height: 13)
                            .offset(x: -1)
                    }
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct BatteryMenuView: View {

    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacity))%")
                    .font(.subheadline)
                    .fontWeight(.regular)

                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}

struct BoringBatteryView: View {

    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false

    var allowPercentage: Bool = true

    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: BoringViewModel

    private var pillIconGray: Color { .gray.opacity(0.65) }

    private var percentageColor: Color {
        if isInLowPowerMode { return .yellow }
        if levelBattery <= 20 && !isCharging && !isPluggedIn { return .red }
        if isCharging || isPluggedIn { return .green }
        return isForNotification ? .white : pillIconGray
    }

    var body: some View {
        Button(action: {
            withAnimation {
                showPopupMenu.toggle()
            }
        }) {
            HStack(spacing: 4) {
                if allowPercentage && Defaults[.showBatteryPercentage] {
                    Text("\(Int(levelBattery))%")
                        .font(isForNotification
                              ? .callout
                              : .system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .foregroundStyle(percentageColor)
                        .baselineOffset(isForNotification ? 0 : -0.5)
                }

                BatteryView(
                    levelBattery: levelBattery,
                    isPluggedIn: isPluggedIn,
                    isCharging: isCharging,
                    isInLowPowerMode: isInLowPowerMode,
                    batteryWidth: batteryWidth,
                    isForNotification: isForNotification
                )
                .padding(.leading, allowPercentage ? 0 : 4)
            }
            .frame(height: isForNotification ? nil : 14, alignment: .center)
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom
        ) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { showPopupMenu = false }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) {
            vm.isBatteryPopoverActive = showPopupMenu
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
}

#Preview {
    BoringBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        isForNotification: false,
        allowPercentage: true
    )
    .frame(width: 200, height: 200)
}
