
import Defaults
import SwiftUI

struct QuartzHeader: View {
    @EnvironmentObject var vm: QuartzViewModel

    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    @Default(Defaults.Keys.showCalendar) private var showCalendar
    @Default(Defaults.Keys.showCalendarToggle) private var showCalendarToggle

    @Default(.toolbarEnabled) private var toolbarEnabled

    private let edgeInset: CGFloat = 10
    private let headerVerticalOffset: CGFloat = -3
    var body: some View {
        GeometryReader { geo in

            let centerWidth: CGFloat = (vm.notchState == .open) ? getOpenHeaderCenterWidth(screenUUID: vm.screenUUID) : 0
            let sideWidth: CGFloat = max(0, (geo.size.width - centerWidth) / 2)
            let shoulderSafetyInset: CGFloat = (vm.notchState == .open)
                ? getOpenHeaderShoulderSafetyInset(screenUUID: vm.screenUUID)
                : 0

            let enabledPagesCount: Int = presentableNotchViewsInConfiguredOrder(currentView: coordinator.currentView).count

            let leftHasDots: Bool = enabledPagesCount > 1
                && ((!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf])

            let hasRightPill: Bool = toolbarEnabled && (
                Defaults[.settingsIconInNotch]
                || Defaults[.showMirror]
                || showCalendarToggle
                || Defaults[.showBatteryIndicator]
            )

            let shouldBorrow: Bool =
                vm.notchState == .open
                && Defaults[.showBatteryIndicator]
                && Defaults[.showBatteryPercentage]

            let borrow: CGFloat = shouldBorrow ? (leftHasDots ? 16 : 24) : 0
            let leftWidth: CGFloat = max(0, sideWidth - borrow - edgeInset - shoulderSafetyInset)
            let rightWidth: CGFloat = max(0, sideWidth + borrow - edgeInset - shoulderSafetyInset)

            let rightPillShift: CGFloat = 0

            HStack(alignment: .top, spacing: 0) {

        // MARK: - Left
                HStack {
                    if leftHasDots {
                        TabSelectionView(availableWidth: leftWidth)
                            .environmentObject(vm)
                            .padding(.top, 10)
                    } else if vm.notchState == .open {
                        EmptyView()
                    }
                }
                .padding(.leading, edgeInset)
                .frame(width: leftWidth, alignment: .leading)
                .offset(y: headerVerticalOffset)
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                .zIndex(2)

        // MARK: - Center Mask
                if vm.notchState == .open {
                    let openBottomRadius: CGFloat = Defaults[.cornerRadiusScaling]
                        ? cornerRadiusInsets.opened.bottom
                        : cornerRadiusInsets.closed.bottom

                    Rectangle()
                        .fill(.clear)
                        .frame(width: centerWidth)
                        .mask {
                            NotchShape(
                                topCornerRadius: 0,
                                bottomCornerRadius: openBottomRadius,
                                useExactBounds: true
                            )
                        }
                        .allowsHitTesting(false)
                        .zIndex(1)
                }

        // MARK: - Right
                VStack(alignment: .trailing, spacing: 6) {
                    if vm.notchState == .open {
                        if hasRightPill {
                            rightPill(availableWidth: rightWidth)
                                .padding(.top, 10)
                                .offset(x: rightPillShift)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.trailing, edgeInset)
                .frame(width: rightWidth, height: geo.size.height, alignment: .topTrailing)
                .offset(y: headerVerticalOffset)
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

    private func rightPill(availableWidth: CGFloat) -> some View {
        let baseFill = Color(nsColor: .secondarySystemFill)
        let unifiedBaseOpacity: Double = 0.985
        let unifiedDoubleFillOpacity: Double = 0.24

        func mix(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
            from + (to - from) * progress
        }

        let expandedNotch = vm.isCameraExpanded || showCalendar
        let smallOpenNotch = (vm.notchState == .open) && !expandedNotch

        let nonBatteryIconsCount =
            (Defaults[.showMirror] ? 1 : 0)
          + (showCalendarToggle ? 1 : 0)
          + (Defaults[.settingsIconInNotch] ? 1 : 0)
        let iconCount = nonBatteryIconsCount

        struct ToolbarMetrics {
            let dotSize: CGFloat
            let iconSize: CGFloat
            let hitPadding: CGFloat
            let iconSpacing: CGFloat
            let pillHInset: CGFloat
            let pillVInset: CGFloat
            let batteryWidth: CGFloat
            let batteryHeight: CGFloat = 11

            var iconBox: CGFloat { dotSize + (hitPadding * 2) }
        }

        let baseMetrics = ToolbarMetrics(
            dotSize: 8,
            iconSize: 11,
            hitPadding: 4,
            iconSpacing: 3,
            pillHInset: 6,
            pillVInset: 3,
            batteryWidth: 17
        )

        let compactMetrics = ToolbarMetrics(
            dotSize: 7,
            iconSize: 10,
            hitPadding: 3,
            iconSpacing: 2,
            pillHInset: 4.5,
            pillVInset: 2.6,
            batteryWidth: 15
        )

        func estimatedWidth(metrics: ToolbarMetrics, includeBatteryPercentage: Bool) -> CGFloat {
            var width = metrics.pillHInset * 2

            if iconCount > 0 {
                width += CGFloat(iconCount) * metrics.iconBox
                width += CGFloat(max(0, iconCount - 1)) * metrics.iconSpacing
            }

            if Defaults[.showBatteryIndicator] {
                let batteryGap: CGFloat = includeBatteryPercentage
                    ? (expandedNotch ? 5 : 4)
                    : (smallOpenNotch && iconCount == 3 ? 1.2 : 2)
                width += batteryGap + metrics.batteryWidth

                if includeBatteryPercentage {
                    width += 34
                }
            }

            return width
        }

        let clampedWidth = max(52, availableWidth)
        let roomForPercentage = clampedWidth >= estimatedWidth(metrics: baseMetrics, includeBatteryPercentage: true) - 4
        let allowBatteryPercentage = roomForPercentage && !(smallOpenNotch && nonBatteryIconsCount >= 2)

        let baseWidth = estimatedWidth(metrics: baseMetrics, includeBatteryPercentage: allowBatteryPercentage)
        let compactWidth = estimatedWidth(metrics: compactMetrics, includeBatteryPercentage: false)
        let compression: CGFloat = {
            guard baseWidth > clampedWidth else { return 0 }
            guard baseWidth > compactWidth else { return 1 }
            return min(1, max(0, (baseWidth - clampedWidth) / (baseWidth - compactWidth)))
        }()
        let dotSize: CGFloat = mix(baseMetrics.dotSize, compactMetrics.dotSize, compression)
        let iconSize: CGFloat = mix(baseMetrics.iconSize, compactMetrics.iconSize, compression)
        let hitPadding: CGFloat = mix(baseMetrics.hitPadding, compactMetrics.hitPadding, compression)
        let iconSpacing: CGFloat = mix(baseMetrics.iconSpacing, compactMetrics.iconSpacing, compression)
        let pillHInset: CGFloat = mix(baseMetrics.pillHInset, compactMetrics.pillHInset, compression)
        let pillVInset: CGFloat = mix(baseMetrics.pillVInset, compactMetrics.pillVInset, compression)
        let batteryWidth: CGFloat = mix(baseMetrics.batteryWidth, compactMetrics.batteryWidth, compression)
        let batteryHeight: CGFloat = baseMetrics.batteryHeight
        let iconBox: CGFloat = dotSize + (hitPadding * 2)

        let isFourIconsMinimalNoPercent = smallOpenNotch && !allowBatteryPercentage && nonBatteryIconsCount == 3

        let batteryGap: CGFloat = {
            if allowBatteryPercentage {
                return expandedNotch ? 5 : 4
            } else {
                return isFourIconsMinimalNoPercent ? mix(1.2, 0.8, compression) : mix(2, 1.2, compression)
            }
        }()

        return HStack(spacing: 0) {

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
                QuartzBatteryView(
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
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? .white : .gray.opacity(0.65))
                .frame(width: dotSize, height: dotSize)
                .padding(hitPadding)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
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
    QuartzHeader().environmentObject(QuartzViewModel())
}
