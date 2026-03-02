//
// NotchHomeView.swift
// boringNotch
//
// Created by Hugo Persson on 2024-08-18.
// Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        let sidePadding: CGFloat = 22
        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = 12
        let albumSize: CGFloat = 114     // <- ajuste ici si tu veux (88/90/92)
        let innerSpacing: CGFloat = 12

        return HStack(spacing: innerSpacing) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                .frame(width: albumSize, height: albumSize)
                .offset(y: 1)

            MusicControlsView()
                .drawingGroup()
                .compositingGroup()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: 290, alignment: .leading)
        }
        .padding(.leading, sidePadding + 1)
        .padding(.trailing, sidePadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)

            if !pageUseLiquidGlassBackground {
                albumArtDarkOverlay
            }
        }
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
            cornerRadius: Defaults[.cornerRadiusScaling]
                ? MusicPlayerImageSizes.cornerRadiusInset.opened
                : MusicPlayerImageSizes.cornerRadiusInset.closed,
            pausedDimOpacity: musicManager.isPlaying ? 0 : (pageUseLiquidGlassBackground ? 0.30 : 0.18),
            geometryID: "albumArt",
            namespace: albumArtNamespace
        )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open
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
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            songInfoBlock
            slotToolbar
                .padding(.top, 5)
                .padding(.bottom, 1)
                .offset(y: -1)
            musicSlider
                .padding(.top, -2)
                .padding(.leading, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoBlock: some View {
        GeometryReader { geo in
            songInfo(width: geo.size.width)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Defaults[.enableLyrics] ? 56 : 34)
        .padding(.top, 9)
        .padding(.leading, 6)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .system(size: 13.2, weight: .medium), nsFont: .subheadline, textColor: .white,
                frameWidth: width,
                useEdgeFade: true,
                measuredPointSize: 13.2,
                measuredWeight: .medium,
                isPaused: !musicManager.isPlaying)
            MarqueeText(
                $musicManager.artistName,
                font: .system(size: 11.2, weight: .regular),
                nsFont: .footnote,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray.opacity(0.78),
                frameWidth: width,
                useEdgeFade: true,
                measuredPointSize: 11.2,
                measuredWeight: .regular,
                isPaused: !musicManager.isPlaying
            )
            .padding(.top, 4)
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
                        frameWidth: width
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
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
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .offset(y: 2)
            .padding(.top, 0)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
    // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium, customSize: 27, customIconFontSize: 14) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium, customSize: 34, customIconFontSize: 18, animateOnTap: true, tapNudgeX: -5) {
                MusicManager.shared.previousTrack()
            }
            .padding(.trailing, 6)
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large, customSize: 44, customIconFontSize: 24) {
                MusicManager.shared.togglePlay()
            }
            .offset(y: 1)
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium, customSize: 34, customIconFontSize: 18, animateOnTap: true, tapNudgeX: 5) {
                MusicManager.shared.nextTrack()
            }
            .padding(.leading, 6)
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium, customSize: 27, customIconFontSize: 14) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium, customSize: 27, customIconFontSize: 14) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium, customSize: 27, customIconFontSize: 14) {
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
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
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
        // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
      // volumeUpdateTask?.cancel() // No longer needed
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
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror

    let albumArtNamespace: Namespace.ID
    private let cameraReservedWidth: CGFloat = 132

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

    private var shouldShowCamera: Bool {
        showMirror && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && showCalendar) ? 10 : 15) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
            if shouldShowCamera {
                Spacer(minLength: 0)
                    .frame(width: cameraReservedWidth, height: 0)
            }
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: showCalendar)
        .transition(.opacity)
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void
    @State private var localSeekTargetValue: Double?
    @State private var localSeekStartedAt: Date = .distantPast
    @State private var isInteractingWithSlider: Bool = false


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
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
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray.opacity(0.78)
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
            guard !isInteractingWithSlider else { return }
            let estimated = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
            if let target = localSeekTargetValue {
                // Freeze exactly at the chosen seek target until playback catches up.
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

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
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

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
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

                        // Stamp seek time before firing external seek to prevent transient snapback.
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
