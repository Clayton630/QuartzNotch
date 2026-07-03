
import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20

@MainActor
final class OpenNotchPlayerAccessoryState: ObservableObject {
    static let shared = OpenNotchPlayerAccessoryState()

    @Published var isVolumeSliderExpanded: Bool = false
    @Published var isLockScreenVolumeSliderExpanded: Bool = false

    private init() {}
}

enum OpenNotchLayoutMetrics {
    static let shellSize: CGSize = .init(width: 640, height: 190)
    static let lyricsExtraHeight: CGFloat = 15
    static let volumeExtraHeight: CGFloat = 7
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

@MainActor private func openNotchAccessoryExtraHeight() -> CGFloat {
    let lyricsExtra = Defaults[.enableNotchLyrics] ? OpenNotchLayoutMetrics.lyricsExtraHeight : 0
    let volumeExtra = OpenNotchPlayerAccessoryState.shared.isVolumeSliderExpanded ? OpenNotchLayoutMetrics.volumeExtraHeight : 0
    return lyricsExtra + volumeExtra
}

@MainActor private func openNotchContentExtraHeight() -> CGFloat {
    Defaults[.enableNotchLyrics] ? OpenNotchLayoutMetrics.lyricsExtraHeight : 0
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

let cinemaModeScale: CGFloat = 2.0

@MainActor func getOpenNotchSize(screenUUID: String? = nil) -> CGSize {
    let base = OpenNotchLayoutMetrics.shellSize
    return CGSize(
        width: base.width,
        height: base.height + openNotchAccessoryExtraHeight()
    )
}

@MainActor func getWindowSize(screenUUID: String? = nil) -> CGSize {
    let base = OpenNotchLayoutMetrics.shellSize
    let scale: CGFloat = Defaults[.cinemaMode] ? cinemaModeScale : 1
    return .init(
        width: base.width * scale + openNotchHorizontalOverhang * 2,
        height: (base.height + OpenNotchLayoutMetrics.lyricsExtraHeight + OpenNotchLayoutMetrics.volumeExtraHeight) * scale + shadowPadding
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

@MainActor func getOpenHeaderLayoutSpacerHeight() -> CGFloat {
    OpenNotchLayoutMetrics.headerHeight
}

@MainActor func getOpenContentViewportHeight() -> CGFloat {
    OpenNotchLayoutMetrics.contentViewportHeight + openNotchContentExtraHeight()
        + (OpenNotchPlayerAccessoryState.shared.isVolumeSliderExpanded ? OpenNotchLayoutMetrics.volumeExtraHeight : 0)
}

@MainActor func getOpenContentTopLift() -> CGFloat {
    OpenNotchLayoutMetrics.contentTopLift
}

@MainActor func getOpenContentBottomPadding() -> CGFloat {
    OpenNotchLayoutMetrics.contentBottomPadding
}

@MainActor func getOpenContentBottomBleed() -> CGFloat {
    let hasLyrics = Defaults[.enableNotchLyrics]
    let hasVolume = OpenNotchPlayerAccessoryState.shared.isVolumeSliderExpanded
    let volumeBleed = hasVolume ? OpenNotchLayoutMetrics.volumeExtraHeight : 0
    return OpenNotchLayoutMetrics.contentBottomBleed + volumeBleed
}

let windowSize: CGSize = .init(
    width: OpenNotchLayoutMetrics.shellSize.width + openNotchHorizontalOverhang * 2,
    height: OpenNotchLayoutMetrics.shellSize.height + OpenNotchLayoutMetrics.lyricsExtraHeight + OpenNotchLayoutMetrics.volumeExtraHeight + shadowPadding
)

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    .init(
        width: measuredClosedNotchWidth(for: screenUUID),
        height: getEffectiveClosedNotchHeight(screenUUID: screenUUID)
    )
}
