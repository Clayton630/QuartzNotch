
import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

private func resolvedPlayerTintColor(
    from nsColor: NSColor,
    minimumBrightness: CGFloat = 0.72,
    saturationBoost: CGFloat = 1.12
) -> Color {
    let brightened = Color(nsColor: nsColor).ensureMinimumBrightness(factor: minimumBrightness)
    let rgbColor = (NSColor(brightened)).usingColorSpace(.sRGB) ?? NSColor(brightened)

    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0

    rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    let boostedSaturation = min(1.0, saturation * saturationBoost)
    let liftedBrightness = min(1.0, max(minimumBrightness, brightness))

    return Color(
        nsColor: NSColor(
            hue: hue,
            saturation: boostedSaturation,
            brightness: liftedBrightness,
            alpha: alpha
        )
    )
}

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    let albumArtNamespace: Namespace.ID
    let albumRevealCompensationProgress: CGFloat

    var body: some View {
        let sidePadding: CGFloat = 24 - (4 * openLayoutCompression)
        let topPadding: CGFloat = 10 - (2 * openLayoutCompression)
        let bottomPadding: CGFloat = 12 - (4 * openLayoutCompression)
        let albumSize: CGFloat = 114 - (10 * openLayoutCompression)
        let innerSpacing: CGFloat = 12 - (3 * openLayoutCompression)
        let controlsMaxWidth: CGFloat = 290 - (18 * openLayoutCompression)

        return HStack(spacing: innerSpacing) {
            AlbumArtView(
                vm: vm,
                albumArtNamespace: albumArtNamespace,
                revealCompensationProgress: albumRevealCompensationProgress
            )
                .frame(width: albumSize, height: albumSize)
                .offset(y: 1)

            MusicControlsView()
                .drawingGroup()
                .compositingGroup()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: controlsMaxWidth, alignment: .leading)
        }
        .padding(.leading, sidePadding)
        .padding(.trailing, sidePadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    let revealCompensationProgress: CGFloat
    var customCornerRadius: CGFloat? = nil
    var disablePausedScaleShrink: Bool = false
    var showsSourceAppIcon: Bool = true
    var showsStaticPausedDarkOverlay: Bool = true
    var tapAction: (() -> Void)? = nil
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    private var resolvedCornerRadius: CGFloat {
        customCornerRadius
            ?? (Defaults[.cornerRadiusScaling]
                ? MusicPlayerImageSizes.cornerRadiusInset.opened
                : MusicPlayerImageSizes.cornerRadiusInset.closed)
    }

    var body: some View {
        let p = max(0, min(1, revealCompensationProgress))
        let active = p < 0.999
        let parentScaleY: CGFloat = 0.72 + (0.28 * p)
        let inverseScaleY: CGFloat = active ? (1 / max(0.001, parentScaleY)) : 1
        let inverseOffsetY: CGFloat = active ? (92 * (1 - p)) : 0

        ZStack(alignment: .bottomTrailing) {
            albumArtButton
        }
        .scaleEffect(x: 1, y: inverseScaleY, anchor: .top)
        .offset(y: inverseOffsetY)
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: resolvedCornerRadius)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        Button {
            if let tapAction {
                tapAction()
            } else {
                musicManager.openMusicApp()
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                albumArtImage

                if showsStaticPausedDarkOverlay && !pageUseLiquidGlassBackground {
                    albumArtDarkOverlay
                }

                appIconOverlay
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(disablePausedScaleShrink ? 1 : (musicManager.isPlaying ? 1 : 0.85))
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(pageUseLiquidGlassBackground ? Color.white : Color.black)
            .opacity(
                musicManager.isPlaying
                    ? 0
                    : (pageUseLiquidGlassBackground ? 0.22 : 0.8)
            )
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        AlbumArtFlipView(
            currentImage: musicManager.albumArt,
            eventID: musicManager.albumArtFlipEventID,
            incomingImage: musicManager.albumArtFlipImage,
            direction: musicManager.albumArtFlipDirection,
            cornerRadius: resolvedCornerRadius,
            pausedDimOpacity: musicManager.isPlaying ? 0 : (pageUseLiquidGlassBackground ? 0.30 : 0.18),
            geometryID: "albumArt",
            namespace: albumArtNamespace
        )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if showsSourceAppIcon
            && vm.notchState == .open
            && !musicManager.usingAppIconForArtwork
            && !musicManager.isUsingIdleMetadata
            && musicManager.hasResolvableBundleIcon,
           let bundleID = musicManager.bundleIdentifier {
            AppIcon(for: bundleID)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}


struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    var forceLightGrayUI: Bool = false
    var forceDarkUI: Bool = false
    var iconButtonSize: CGFloat = 34
    @StateObject private var titleArtistMarqueeSync = MarqueeSyncCoordinator()
    @State private var shuffleDrawActive: Bool = false
    @State private var repeatDrawActive: Bool = false
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    var prefersCenteredInfoLayout: Bool = false

    private var infoFrameAlignment: Alignment {
        prefersCenteredInfoLayout ? .center : .leading
    }

    private var infoHorizontalAlignment: HorizontalAlignment {
        prefersCenteredInfoLayout ? .center : .leading
    }

    var body: some View {
        let stackSpacing: CGFloat = 3 - (0.8 * openLayoutCompression)

        VStack(alignment: infoHorizontalAlignment, spacing: stackSpacing) {
            songInfoBlock
            slotToolbar
                .padding(.top, 5 - (1.5 * openLayoutCompression))
                .padding(.bottom, 1)
                .offset(y: -1)
            musicSlider
                .padding(.top, -2 + openLayoutCompression)
                .padding(.horizontal, 6 - openLayoutCompression)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoBlock: some View {
        GeometryReader { geo in
            songInfo(width: max(0, geo.size.width))
                .frame(maxWidth: .infinity, alignment: infoFrameAlignment)
        }
        .frame(height: Defaults[.enableLyrics] ? (56 - (4 * openLayoutCompression)) : (34 - (2 * openLayoutCompression)))
        .padding(.top, 9 - (2 * openLayoutCompression))
        .padding(.horizontal, 6 - openLayoutCompression)
    }

    private func songInfo(width: CGFloat) -> some View {
        let hasArtistName = !musicManager.artistName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let shouldCenterTitleOnly = !hasArtistName && !Defaults[.enableLyrics]
        let neutralArtistTint: Color = forceDarkUI
            ? .black.opacity(0.62)
            : forceLightGrayUI
            ? .white.opacity(0.56)
            : .gray.opacity(0.78)
        let artistTint: Color = forceDarkUI
            ? .black.opacity(0.62)
            : forceLightGrayUI
            ? .white.opacity(0.56)
            : Defaults[.playerColorTinting] && musicManager.isArtworkTintReady
            ? resolvedPlayerTintColor(from: musicManager.avgColor)
            : neutralArtistTint
        let artistTintIdentity: String = {
            if forceDarkUI { return "dark" }
            if forceLightGrayUI { return "lightGray" }
            guard Defaults[.playerColorTinting], musicManager.isArtworkTintReady else {
                return "neutral"
            }
            let nsColor = musicManager.avgColor.usingColorSpace(.deviceRGB) ?? musicManager.avgColor
            return String(
                format: "tinted-%.5f-%.5f-%.5f-%.5f",
                nsColor.redComponent,
                nsColor.greenComponent,
                nsColor.blueComponent,
                nsColor.alphaComponent
            )
        }()

        return VStack(alignment: infoHorizontalAlignment, spacing: 0) {
            if shouldCenterTitleOnly {
                Spacer(minLength: 0)
            }

            MarqueeText(
                $musicManager.songTitle,
                font: .system(size: 13.2, weight: .medium),
                nsFont: .subheadline,
                textColor: forceDarkUI ? .black : .white,
                frameWidth: width,
                useEdgeFade: true,
                syncCoordinator: titleArtistMarqueeSync,
                frameAlignment: infoFrameAlignment,
                measuredPointSize: 13.2,
                measuredWeight: .medium,
                isPaused: !musicManager.isPlaying)

            if hasArtistName {
                MarqueeText(
                    $musicManager.artistName,
                    font: .system(size: 11.2, weight: .regular),
                    nsFont: .footnote,
                    textColor: artistTint,
                    frameWidth: width,
                    useEdgeFade: true,
                    syncCoordinator: titleArtistMarqueeSync,
                    frameAlignment: infoFrameAlignment,
                    measuredPointSize: 11.2,
                    measuredWeight: .regular,
                    isPaused: !musicManager.isPlaying
                )
                .id("artist-\(musicManager.artistName)-\(artistTintIdentity)")
                .padding(.top, 4)
            }

            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: width,
                        frameAlignment: infoFrameAlignment
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if shouldCenterTitleOnly {
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: prefersCenteredInfoLayout ? .top : .topLeading)
        .offset(y: 3)
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                forceLightGrayUI: forceLightGrayUI,
                forceDarkUI: forceDarkUI
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .offset(y: 2)
            .padding(.top, 0)
            .frame(height: 36 - (4 * openLayoutCompression))
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        let base: CGFloat = 6 - (1.5 * openLayoutCompression)
        let count = visibleSlotCount(for: slots)
        let spacing: CGFloat = base + CGFloat(5 - count) * 5
        // Narrow size range: 16.5 pt (5 icons) → 19.5 pt (1 icon), 3 pt total spread
        let iconFont: CGFloat = 20.25 - CGFloat(count) * 0.75
        return toolbarContent(slots: slots, spacing: spacing, iconFontSize: iconFont, iconButtonSize: iconButtonSize)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func visibleSlotCount(for slots: [MusicControlButton]) -> Int {
        if slots.count >= 5 {
            let s = effectiveSlots(from: slots)
            return [s[0], s[1], s[3], s[4]].filter { $0 != .none }.count + 1
        } else if slots.count >= 3 {
            return (slots[0] != .none ? 1 : 0) + 1 + (slots[2] != .none ? 1 : 0)
        }
        return 1
    }

    @ViewBuilder
    private func toolbarContent(slots: [MusicControlButton], spacing: CGFloat, iconFontSize: CGFloat, iconButtonSize: CGFloat) -> some View {
        if slots.count >= 5 {
            let s = effectiveSlots(from: slots)
            HStack(spacing: spacing) {
                if s[0] != .none { slotView(for: s[0], at: 0, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize) }
                if s[1] != .none { slotView(for: s[1], at: 1, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize) }
                slotView(for: .playPause, at: 2, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize)
                if s[3] != .none { slotView(for: s[3], at: 3, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize) }
                if s[4] != .none { slotView(for: s[4], at: 4, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize) }
            }
        } else if slots.count >= 3 {
            let leftSlot = slots[0]
            let rightSlot = slots[2]
            HStack(spacing: spacing) {
                if leftSlot != .none { slotView(for: leftSlot, at: 1, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize) }
                slotView(for: .playPause, at: 2, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize)
                if rightSlot != .none { slotView(for: rightSlot, at: 3, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize) }
            }
        } else {
            slotView(for: .playPause, at: 2, iconFontSize: iconFontSize, iconButtonSize: iconButtonSize)
        }
    }

    private func effectiveSlots(from slots: [MusicControlButton]) -> [MusicControlButton] {
        var s = slots
        for i in [0, 1, 3, 4] where i < s.count {
            if s[i] == .playPause { s[i] = .none }
        }
        if s.count > 2 { s[2] = .playPause }
        return s
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        let shouldHideEdges =
            Defaults[.showCalendar]
            && Defaults[.showMirror]
            && webcamManager.cameraAvailable
            && vm.isCameraExpanded
            && !vm.suppressCameraLayoutInOpenContent
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }


    @ViewBuilder
    private func slotView(for slot: MusicControlButton, at index: Int, iconFontSize: CGFloat = 18, iconButtonSize: CGFloat = 34) -> some View {
        let tintColor = resolvedPlayerTintColor(from: musicManager.avgColor)
        let playerTintingEnabled = ((forceLightGrayUI || forceDarkUI) ? false : Defaults[.playerColorTinting])
        let neutralControlTint: Color = forceDarkUI
            ? .black.opacity(0.60)
            : forceLightGrayUI
            ? .white.opacity(0.56)
            : playerTintingEnabled
            ? tintColor
            : .gray.opacity(0.78)
        let isFlankingPosition = index == 1 || index == 3
        let iconSize = iconButtonSize
        // backward.fill / forward.fill are visually narrower — keep 3 pt higher to match perceived weight
        let arrowFontSize: CGFloat = iconFontSize + 3
        let positionalColor: Color = isFlankingPosition ? .primary : neutralControlTint

        switch slot {
        case .shuffle:
            ZStack(alignment: .bottom) {
                if #available(macOS 26.0, *) {
                    HoverButton(icon: "shuffle", iconColor: positionalColor, scale: .medium, customSize: iconSize, customIconFontSize: iconFontSize + 1) {
                        MusicManager.shared.toggleShuffle()
                    }
                    .symbolEffect(.drawOn, isActive: shuffleDrawActive)
                } else {
                    HoverButton(icon: "shuffle", iconColor: positionalColor, scale: .medium, customSize: iconSize, customIconFontSize: iconFontSize + 1) {
                        MusicManager.shared.toggleShuffle()
                    }
                    .symbolEffect(.bounce, options: .nonRepeating, value: musicManager.isShuffled)
                }
                Circle()
                    .fill(positionalColor)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(musicManager.isShuffled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: musicManager.isShuffled)
            }
            .onChange(of: musicManager.isShuffled) { _, _ in
                guard #available(macOS 26.0, *) else { return }
                shuffleDrawActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shuffleDrawActive = false }
            }
        case .previous:
            HoverButton(
                icon: slot.filledIconName,
                iconColor: positionalColor,
                scale: .medium,
                customSize: iconSize,
                customIconFontSize: arrowFontSize,
                animateOnTap: true,
                externalAnimationEvent: .previousTrackSkip,
                tapNudgeX: -5
            ) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large, customSize: 44, customIconFontSize: 24) {
                MusicManager.shared.togglePlay()
            }
            .offset(y: 1)
        case .next:
            HoverButton(
                icon: slot.filledIconName,
                iconColor: positionalColor,
                scale: .medium,
                customSize: iconSize,
                customIconFontSize: arrowFontSize,
                animateOnTap: true,
                externalAnimationEvent: .nextTrackSkip,
                tapNudgeX: 5
            ) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            let repeatActive = musicManager.repeatMode != .off
            ZStack(alignment: .bottom) {
                if #available(macOS 26.0, *) {
                    HoverButton(icon: repeatIcon, iconColor: positionalColor, scale: .medium, customSize: iconSize, customIconFontSize: iconFontSize + 1) {
                        MusicManager.shared.toggleRepeat()
                    }
                    .symbolEffect(.drawOn, isActive: repeatDrawActive)
                } else {
                    HoverButton(icon: repeatIcon, iconColor: positionalColor, scale: .medium, customSize: iconSize, customIconFontSize: iconFontSize + 1) {
                        MusicManager.shared.toggleRepeat()
                    }
                    .symbolEffect(.bounce, options: .nonRepeating, value: musicManager.repeatMode)
                }
                Circle()
                    .fill(positionalColor)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(repeatActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: repeatActive)
            }
            .onChange(of: musicManager.repeatMode) { oldValue, newValue in
                guard #available(macOS 26.0, *) else { return }
                // Skip drawOn when transitioning between .all and .one — the icon itself changes
                // (repeat → repeat.1), and SwiftUI would replay the effect on the new symbol.
                let iconChanges = (oldValue == .one) != (newValue == .one)
                guard !iconChanges else { return }
                repeatDrawActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { repeatDrawActive = false }
            }
        case .volume:
            VolumeControlView(forceDarkUI: forceDarkUI, iconFontSize: iconFontSize)
        case .favorite:
            FavoriteControlButton(forceDarkUI: forceDarkUI, inactiveColor: positionalColor, customSize: iconSize, customIconFontSize: iconFontSize)
        case .goBackward:
            HoverButton(
                icon: "gobackward.15",
                iconColor: positionalColor,
                scale: .medium,
                customSize: iconSize,
                customIconFontSize: iconFontSize,
                tapSymbolRotateDirection: .counterClockwise
            ) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(
                icon: "goforward.15",
                iconColor: positionalColor,
                scale: .medium,
                customSize: iconSize,
                customIconFontSize: iconFontSize,
                tapSymbolRotateDirection: .clockwise
            ) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return forceDarkUI ? .black.opacity(0.72) : .gray.opacity(0.78)
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared
    var forceDarkUI: Bool = false
    var inactiveColor: Color? = nil
    var customSize: CGFloat? = nil
    var customIconFontSize: CGFloat? = nil

    var body: some View {
        let size = customSize ?? 34
        let fontSize = customIconFontSize ?? 18
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium, customSize: size, customIconFontSize: fontSize) {
            MusicManager.shared.toggleFavoriteTrack()
        }
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "star.fill" : "star"
    }

    private var iconColor: Color {
        if let custom = inactiveColor { return custom }
        return forceDarkUI ? .black.opacity(0.72) : .gray.opacity(0.78)
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    var forceDarkUI: Bool = false
    var iconFontSize: CGFloat = 18
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: iconFontSize, weight: .medium))
                    .foregroundColor(
                        musicManager.volumeControlSupported
                            ? (forceDarkUI ? .black.opacity(0.72) : .gray.opacity(0.78))
                            : .gray
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 34)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: forceDarkUI ? .black.opacity(0.74) : .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.openNotchLayoutCompression) private var openLayoutCompression
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror

    let albumArtNamespace: Namespace.ID
    let albumRevealCompensationProgress: CGFloat

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        .transition(.opacity)
        .onChange(of: showCalendar) { _, newValue in
            if !newValue {
                vm.isHoveringCalendar = false
            }
        }
    }

    private var mainContent: some View {
        let mainSpacing = 15 - (3 * openLayoutCompression)

        return HStack(alignment: .top, spacing: mainSpacing) {
            MusicPlayerView(
                albumArtNamespace: albumArtNamespace,
                albumRevealCompensationProgress: albumRevealCompensationProgress
            )
        }
        .transition(.opacity)
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    @Environment(\.colorScheme) private var colorScheme
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var forceLightGrayUI: Bool = false
    var forceDarkUI: Bool = false
    var onValueChange: (Double) -> Void
    @State private var localSeekTargetValue: Double?
    @State private var localSeekStartedAt: Date = .distantPast
    @State private var isInteractingWithSlider: Bool = false

    var body: some View {
        let neutralTimestampTint: Color = {
            if forceDarkUI { return .black.opacity(0.60) }
            if forceLightGrayUI { return .white.opacity(0.56) }
            guard pageUseLiquidGlassBackground else { return .gray.opacity(0.78) }
            return colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.78)
        }()

        let sliderTrackColor: Color = forceDarkUI
            ? .black.opacity(0.16)
            : forceLightGrayUI
            ? .white.opacity(0.28)
            : pageUseLiquidGlassBackground
            ? (colorScheme == .dark ? .white.opacity(0.28) : .black.opacity(0.24))
            : .gray.opacity(0.3)

        let timestampShadowColor: Color = forceDarkUI
            ? .clear
            : pageUseLiquidGlassBackground
            ? (colorScheme == .dark ? .black.opacity(0.50) : .white.opacity(0.45))
            : .clear

        let playerTintingEnabled = ((forceLightGrayUI || forceDarkUI) ? false : Defaults[.playerColorTinting])

        let sliderFillStrokeColor: Color = forceDarkUI
            ? .clear
            : forceLightGrayUI
            ? .clear
            : playerTintingEnabled
            ? .clear
            : pageUseLiquidGlassBackground
            ? (colorScheme == .dark ? .black.opacity(0.34) : .white.opacity(0.38))
            : .clear

        let timestampTint: Color =
            playerTintingEnabled
            ? resolvedPlayerTintColor(from: color)
            : neutralTimestampTint

        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: forceDarkUI
                    ? .black.opacity(0.72)
                    : forceLightGrayUI
                    ? .white.opacity(0.70)
                    : timestampTint,
                dragging: $dragging,
                lastDragged: $lastDragged,
                trackColor: sliderTrackColor,
                fillStrokeColor: sliderFillStrokeColor,
                fillStrokeWidth: (forceLightGrayUI || forceDarkUI || playerTintingEnabled) ? 0 : (pageUseLiquidGlassBackground ? 0.7 : 0),
                onValueChange: { newValue in
                    localSeekTargetValue = newValue
                    localSeekStartedAt = currentDate
                    onValueChange(newValue)
                },
                onInteractionChanged: { isActive in
                    isInteractingWithSlider = isActive
                }
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text("-\(timeString(from: max(0, duration - sliderValue)))")
            }
            .fontWeight(.medium)
            .foregroundColor(timestampTint)
            .shadow(
                color: (forceLightGrayUI || forceDarkUI) ? .clear : timestampShadowColor,
                radius: (forceLightGrayUI || forceDarkUI) ? 0 : (pageUseLiquidGlassBackground ? 0.85 : 0),
                x: 0,
                y: 0.25
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
            guard !isInteractingWithSlider else { return }
            let estimated = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
            if let target = localSeekTargetValue {
                sliderValue = min(duration, max(0, target))

                let dt = max(0, currentDate.timeIntervalSince(localSeekStartedAt))
                let providerAckedSeek = timestampDate >= localSeekStartedAt.addingTimeInterval(-0.03)
                let isSynced = abs(estimated - target) <= 0.45
                let didTimeout = dt > 1.1

                if isSynced || (providerAckedSeek && dt > 0.12) || didTimeout {
                    localSeekTargetValue = nil
                    sliderValue = min(duration, max(0, estimated))
                }
                return
            }
            sliderValue = min(duration, max(0, estimated))
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct LeadingRoundedTrackShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + r),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

struct ProgressFillTrackShape: Shape {
    var radius: CGFloat
    var roundsLeading: Bool = true
    var roundsTrailing: Bool = false

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        let tl: CGFloat = roundsLeading ? r : 0
        let bl: CGFloat = roundsLeading ? r : 0
        let tr: CGFloat = roundsTrailing ? r : 0
        let br: CGFloat = roundsTrailing ? r : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))

        if tr > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))

        if br > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))

        if bl > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - bl),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))

        if tl > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + tl, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var trackColor: Color = .gray.opacity(0.3)
    var fillStrokeColor: Color = .clear
    var fillStrokeWidth: CGFloat = 0
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)? = nil
    @State private var isInteractionActive: Bool = false
    @State private var isSlideGesture: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(isSlideGesture ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width
            let trackShape = RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            let fillShape = ProgressFillTrackShape(
                radius: height / 2,
                roundsLeading: true,
                roundsTrailing: filledTrackWidth >= (width - 0.5)
            )

            ZStack(alignment: .leading) {
                trackShape
                    .fill(trackColor)
                    .frame(height: height)

                if filledTrackWidth > 0 {
                    fillShape
                        .fill(color)
                        .overlay {
                            fillShape
                                .stroke(fillStrokeColor, lineWidth: fillStrokeWidth)
                        }
                        .frame(width: filledTrackWidth, height: height)
                }
            }
            .clipShape(trackShape)
            .frame(height: height)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isInteractionActive {
                            isInteractionActive = true
                            onInteractionChanged?(true)
                        }
                        let translationDistance = hypot(gesture.translation.width, gesture.translation.height)
                        let isSlide = translationDistance > 2
                        if isSlide && !isSlideGesture {
                            isSlideGesture = true
                            withAnimation {
                                dragging = true
                            }
                        }

                        let safeWidth = max(width, 1)
                        let newValue = range.lowerBound + Double(gesture.location.x / safeWidth) * rangeSpan
                        let clampedValue = min(max(newValue, range.lowerBound), range.upperBound)
                        withAnimation(.easeOut(duration: 0.18)) {
                            value = clampedValue
                        }
                        onDragChange?(value)
                    }
                    .onEnded { gesture in
                        let safeWidth = max(width, 1)
                        let newValue = range.lowerBound + Double(gesture.location.x / safeWidth) * rangeSpan
                        let clampedValue = min(max(newValue, range.lowerBound), range.upperBound)
                        withAnimation(.easeOut(duration: 0.18)) {
                            value = clampedValue
                        }

                        lastDragged = Date()
                        if isSlideGesture {
                            dragging = false
                        }
                        isSlideGesture = false
                        if isInteractionActive {
                            isInteractionActive = false
                            onInteractionChanged?(false)
                        }
                        onValueChange?(clampedValue)
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
