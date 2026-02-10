//
// BoringHeader.swift
// boringNotch
//
// Created by Harsh Vardhan Goswami on 04/08/24
//

import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel

    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    @Default(Defaults.Keys.showCalendar) private var showCalendar
    @Default(Defaults.Keys.showCalendarToggle) private var showCalendarToggle

    @Default(.toolbarEnabled) private var toolbarEnabled

    @Default(.pageHomeEnabled) private var pageHomeEnabled
    @Default(.pageShelfEnabled) private var pageShelfEnabled

@Default(.pageThirdEnabled) private var pageThirdEnabled
    var body: some View {
        GeometryReader { geo in

            let centerWidth: CGFloat = (vm.notchState == .open) ? (vm.closedNotchSize.width + 40) : 0
            let sideWidth: CGFloat = max(0, (geo.size.width - centerWidth) / 2)

            let enabledPagesCount: Int =
            (pageHomeEnabled ? 1 : 0) +
            (pageShelfEnabled ? 1 : 0) +
            (pageThirdEnabled ? 1 : 0)

            let leftHasDots: Bool = toolbarEnabled
                && enabledPagesCount > 1
                && ((!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf])

            let hudIsShowing: Bool = isHUDType(coordinator.sneakPeek.type)
                && coordinator.sneakPeek.show
                && Defaults[.showOpenNotchHUD]

            let hasRightPill: Bool = toolbarEnabled && (
                Defaults[.settingsIconInNotch]
                || Defaults[.showMirror]
                || showCalendarToggle
                || Defaults[.showBatteryIndicator]
            )

            let shouldBorrow: Bool =
                vm.notchState == .open
                && !hudIsShowing
                && Defaults[.showBatteryIndicator]
                && Defaults[.showBatteryPercentage]

            let borrow: CGFloat = shouldBorrow ? (leftHasDots ? 16 : 24) : 0
            let leftWidth: CGFloat = max(0, sideWidth - borrow)
            let rightWidth: CGFloat = sideWidth + borrow

            let rightPillShift: CGFloat = 4

            HStack(alignment: .top, spacing: 0) {

        // MARK: - Left
                HStack {
                    if toolbarEnabled && enabledPagesCount > 1 && (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                        TabSelectionView()
                            .environmentObject(vm)
                            .padding(.top, 10)
                    } else if vm.notchState == .open {
                        EmptyView()
                    }
                }
                .frame(width: leftWidth, alignment: .leading)
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                .zIndex(2)

        // MARK: - Center Mask
                if vm.notchState == .open {
                    Rectangle()
                        .fill(
                            NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?
                                .safeAreaInsets.top ?? 0 > 0 ? .black : .clear
                        )
                        .frame(width: centerWidth)
                        .mask { NotchShape() }
                        .allowsHitTesting(false)
                        .zIndex(1)
                }

        // MARK: - Right
                VStack(alignment: .trailing, spacing: 6) {
                    if vm.notchState == .open {
                        if hudIsShowing {
                            OpenNotchHUD(
                                type: $coordinator.sneakPeek.type,
                                value: $coordinator.sneakPeek.value,
                                icon: $coordinator.sneakPeek.icon
                            )
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        } else if hasRightPill {
                            rightPill
                                .padding(.top, 10)
                                .offset(x: rightPillShift)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: rightWidth, height: geo.size.height, alignment: .topTrailing)
                .font(.system(.headline, design: .rounded))
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                .zIndex(2)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .onChange(of: showCalendarToggle) { _, newValue in
            if !newValue && showCalendar {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                    showCalendar = false
                }
            }
        }
    }

  // MARK: - Right pill

    private var rightPill: some View {
        let baseFill = Color(nsColor: .secondarySystemFill)
        let unifiedBaseOpacity: Double = 0.985
        let unifiedDoubleFillOpacity: Double = 0.24

        let dotSize: CGFloat = 8
        let iconSize: CGFloat = 11
        let hitPadding: CGFloat = 4

        let iconSpacing: CGFloat = 3
        let pillHInset: CGFloat = 6
        let pillVInset: CGFloat = 3

        let batteryWidth: CGFloat = 17
        let batteryHeight: CGFloat = 11
        let iconBox: CGFloat = dotSize + (hitPadding * 2)

    // Large notch mode: camera OR calendar visible
        let expandedNotch = vm.isCameraExpanded || showCalendar
    // Minimum notch mode: open + no camera + no calendar
        let smallOpenNotch = (vm.notchState == .open) && !expandedNotch

        let nonBatteryIconsCount =
            (Defaults[.showMirror] ? 1 : 0)
          + (showCalendarToggle ? 1 : 0)
          + (Defaults[.settingsIconInNotch] ? 1 : 0)

    // Rule: in minimum notch mode, if there are 3 icons (2 non-battery), hide %
    // Also keep % hidden when there are 4 icons.
        let allowBatteryPercentage = !(smallOpenNotch && nonBatteryIconsCount >= 2)

    // Specific case: minimum notch + 4 icons (3 non-battery) + no %
        let isFourIconsMinimalNoPercent = smallOpenNotch && !allowBatteryPercentage && nonBatteryIconsCount == 3

    // Reliable gap: use padding on the battery block, not Spacer.
    // - minimum notch + % visible: 4 (unchanged)
    // - notch grand + % visible: 5 (juste +1)
    // - % hidden: 2 (unchanged), except 4-icon minimum notch case => 1
        let batteryGap: CGFloat = {
            if allowBatteryPercentage {
                return expandedNotch ? 5 : 4
            } else {
                return isFourIconsMinimalNoPercent ? 1 : 2
            }
        }()

        return HStack(spacing: 0) {

      // Order: Camera, Calendar, Settings
            HStack(spacing: iconSpacing) {

                if Defaults[.showMirror] {
                    miniIcon(
                        systemName: "web.camera",
                        isActive: vm.isCameraExpanded,
                        dotSize: dotSize,
                        iconSize: iconSize,
                        hitPadding: hitPadding,
                        accessibility: vm.isCameraExpanded ? "Hide camera" : "Show camera"
                    ) {
                        vm.toggleCameraPreview()
                    }
                }

                if showCalendarToggle {
                    miniIcon(
                        systemName: "calendar",
                        isActive: showCalendar,
                        dotSize: dotSize,
                        iconSize: iconSize,
                        hitPadding: hitPadding,
                        accessibility: showCalendar ? "Hide calendar" : "Show calendar"
                    ) {
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                            showCalendar.toggle()
                        }
                    }
                }

                if Defaults[.settingsIconInNotch] {
                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(.gray.opacity(0.65))
                            .frame(width: dotSize, height: dotSize)
                            .padding(hitPadding)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }

            if Defaults[.showBatteryIndicator] {
                BoringBatteryView(
                    batteryWidth: batteryWidth,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxCapacity: batteryModel.maxCapacity,
                    timeToFullCharge: batteryModel.timeToFullCharge,
                    isForNotification: false,
                    allowPercentage: allowBatteryPercentage
                )
                .padding(.leading, batteryGap)
                .frame(height: batteryHeight)
                .frame(height: iconBox, alignment: .center)
                .compositingGroup()
            }
        }
        .padding(.horizontal, pillHInset)
        .padding(.vertical, pillVInset)
        .background(
            Capsule()
                .fill(baseFill)
        // Unified background opacity (match NotchCardBackground / TabSelectionView).
                .overlay {
                    Capsule()
                        .fill(baseFill)
                        .opacity(unifiedDoubleFillOpacity)
                }
                .opacity(unifiedBaseOpacity)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.025), lineWidth: 1)
                }
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
    }

    private func miniIcon(
        systemName: String,
        isActive: Bool,
        dotSize: CGFloat,
        iconSize: CGFloat,
        hitPadding: CGFloat,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(isActive ? .white : .gray.opacity(0.65))
            .frame(width: dotSize, height: dotSize)
            .padding(hitPadding)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
