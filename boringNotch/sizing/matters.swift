
import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20

/// Canonical metrics for the opened notch.
///
/// These values deliberately do not read `NSScreen`, `safeAreaInsets`,
/// menu-bar height, calendar state, camera state, or debug preview state.
/// Physical screen measurements are valid for the closed notch only. The
/// opened notch is a fixed designed surface; side overlays may extend width,
/// but they must never mutate page height, page scale, or page origin.
enum OpenNotchLayoutMetrics {
    static let shellSize: CGSize = .init(width: 640, height: 190)
    static let horizontalWindowOverhang: CGFloat = 30
    static let headerCenterWidth: CGFloat = 190
    static let headerHeight: CGFloat = 32
    static let headerTopPadding: CGFloat = 6
    static let contentTopLift: CGFloat = 8
    static let contentBottomPadding: CGFloat = 12
    static let contentBottomBleed: CGFloat = 12
    static let contentViewportHeight: CGFloat = shellSize.height
        - headerHeight
        - headerTopPadding
        - contentBottomPadding
    static let contentScale: CGFloat = 1
    static let contentCompression: CGFloat = 0
    static let headerShoulderSafetyInset: CGFloat = 0
}

let openNotchSize: CGSize = OpenNotchLayoutMetrics.shellSize
let openNotchHorizontalOverhang: CGFloat = OpenNotchLayoutMetrics.horizontalWindowOverhang

private struct OpenNotchContentUsableHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private struct OpenNotchLayoutCompressionKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var openNotchContentUsableHeight: CGFloat? {
        get { self[OpenNotchContentUsableHeightKey.self] }
        set { self[OpenNotchContentUsableHeightKey.self] = newValue }
    }

    var openNotchLayoutCompression: CGFloat {
        get { self[OpenNotchLayoutCompressionKey.self] }
        set { self[OpenNotchLayoutCompressionKey.self] = newValue }
    }
}

let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 34), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    selectedScreen(for: screenUUID)?.frame
}

@MainActor private func selectedScreen(for screenUUID: String? = nil) -> NSScreen? {
    if let uuid = screenUUID {
        return NSScreen.screen(withUUID: uuid)
    }
    return NSScreen.main
}

@MainActor private func measuredClosedNotchWidth(for screenUUID: String? = nil) -> CGFloat {
    var notchWidth: CGFloat = 185

    if let screen = selectedScreen(for: screenUUID),
       let topLeftNotchpadding = screen.auxiliaryTopLeftArea?.width,
       let topRightNotchpadding = screen.auxiliaryTopRightArea?.width
    {
        notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
    }

    return notchWidth
}

@MainActor private func measuredClosedNotchHeight(for screenUUID: String? = nil) -> CGFloat {
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]

    if let screen = selectedScreen(for: screenUUID) {
        if screen.safeAreaInsets.top > 0 {
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return notchHeight
}

@MainActor func getEffectiveClosedNotchHeight(screenUUID: String? = nil) -> CGFloat {
    return measuredClosedNotchHeight(for: screenUUID)
}

@MainActor func getOpenHeaderCenterWidth(screenUUID: String? = nil) -> CGFloat {
    OpenNotchLayoutMetrics.headerCenterWidth
}

@MainActor func getOpenLayoutReferenceHeight(screenUUID: String? = nil) -> CGFloat {
    OpenNotchLayoutMetrics.headerHeight
}

@MainActor func getOpenNotchSize(screenUUID: String? = nil) -> CGSize {
    OpenNotchLayoutMetrics.shellSize
}

@MainActor func getWindowSize(screenUUID: String? = nil) -> CGSize {
    let openSize = getOpenNotchSize(screenUUID: screenUUID)
    return .init(
        width: openSize.width + openNotchHorizontalOverhang * 2,
        height: openSize.height + shadowPadding
    )
}

@MainActor func getOpenContentVerticalLift(screenUUID: String? = nil) -> CGFloat {
    0
}

@MainActor func getOpenContentLayoutScale(screenUUID: String? = nil) -> CGFloat {
    OpenNotchLayoutMetrics.contentScale
}

@MainActor func getOpenLayoutCompression(screenUUID: String? = nil) -> CGFloat {
    OpenNotchLayoutMetrics.contentCompression
}

@MainActor func getOpenHeaderShoulderSafetyInset(screenUUID: String? = nil) -> CGFloat {
    OpenNotchLayoutMetrics.headerShoulderSafetyInset
}

/// Fixed spacer height reserved for the open-notch header overlay.
/// Keeping this at the 13" reference height prevents the open content
/// from being pushed downward on taller 15"/16" built-in displays.
@MainActor func getOpenHeaderLayoutSpacerHeight() -> CGFloat {
    OpenNotchLayoutMetrics.headerHeight
}

@MainActor func getOpenContentViewportHeight() -> CGFloat {
    OpenNotchLayoutMetrics.contentViewportHeight
}

@MainActor func getOpenContentTopLift() -> CGFloat {
    OpenNotchLayoutMetrics.contentTopLift
}

@MainActor func getOpenContentBottomPadding() -> CGFloat {
    OpenNotchLayoutMetrics.contentBottomPadding
}

@MainActor func getOpenContentBottomBleed() -> CGFloat {
    OpenNotchLayoutMetrics.contentBottomBleed
}

let windowSize: CGSize = .init(
    width: openNotchSize.width + openNotchHorizontalOverhang * 2,
    height: openNotchSize.height + shadowPadding
)

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    .init(
        width: measuredClosedNotchWidth(for: screenUUID),
        height: getEffectiveClosedNotchHeight(screenUUID: screenUUID)
    )
}
