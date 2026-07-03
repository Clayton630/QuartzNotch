// NowPlayingMorphingGlyph.swift
import Defaults
import SwiftUI

struct NowPlayingAudioGlyph: View {
    @EnvironmentObject private var vm: QuartzViewModel

    var progress: CGFloat
    let isPlaying: Bool
    let shouldAnimateWaveform: Bool
    let tintTop: Color
    let tintBottom: Color
    let artwork: NSImage?

    @Default(.liveAudioWaveform) private var liveEnabled
    @StateObject private var audioEngine = WaveSpectrumLiveModel()

    private var shouldRunLiveAudio: Bool {
        liveEnabled && shouldAnimateWaveform && !vm.isNotchTransitioning
    }

    private var shouldDriveWaveform: Bool {
        shouldAnimateWaveform && !vm.isNotchTransitioning
    }

    var body: some View {
        NowPlayingMorphingGlyph(
            progress: progress,
            isPlaying: isPlaying,
            shouldAnimateWaveform: shouldDriveWaveform,
            tintTop: tintTop,
            tintBottom: tintBottom,
            artwork: artwork,
            audioEngine: shouldRunLiveAudio ? audioEngine : nil
        )
        .onChange(of: shouldRunLiveAudio) { _, enabled in
            if enabled {
                audioEngine.startLive()
            } else {
                audioEngine.stopLive()
            }
        }
        .onAppear {
            if shouldRunLiveAudio {
                audioEngine.startLive()
            }
        }
        .onDisappear { audioEngine.stopLive() }
    }
}

struct NowPlayingMorphingGlyph: View {
    var progress: CGFloat
    let isPlaying: Bool
    let shouldAnimateWaveform: Bool
    let tintTop: Color
    let tintBottom: Color
    let artwork: NSImage?
    var audioEngine: WaveSpectrumLiveModel? = nil

    @State private var displayedIsPlaying: Bool = true
    @State private var incomingIsPlaying: Bool = true
    @State private var iconSwapProgress: CGFloat = 1

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private struct BarSpec {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private struct FallbackWaveParam {
        let f1: Double
        let a1: Double
        let f2: Double
        let a2: Double
        let f3: Double
        let a3: Double
        let center: Double
        let phase: Double
    }

    private static let barXs: [CGFloat] = [-8.75, -5.25, -1.75, 1.75, 5.25, 8.75]
    private static let barW: CGFloat = 2.0
    private static let waveFlat: [BarSpec] = barXs.map { .init(x: $0, width: barW, height: barW) }
    private static let playingTarget: [BarSpec] = [
        .init(x: -8.75, width: 0.05, height: 0.05),
        .init(x: -3.5,  width: 2.0,  height: 12.0),
        .init(x: -3.5,  width: 0.05, height: 0.05),
        .init(x:  3.5,  width: 0.05, height: 0.05),
        .init(x:  3.5,  width: 2.0,  height: 12.0),
        .init(x:  8.75, width: 0.05, height: 0.05),
    ]
    private static let pausedTarget: [BarSpec] = [
        .init(x: -7.5, width: barW, height:  3.0),
        .init(x: -4.5, width: barW, height:  5.0),
        .init(x: -1.5, width: barW, height:  7.0),
        .init(x:  1.5, width: barW, height:  9.0),
        .init(x:  4.5, width: barW, height: 11.0),
        .init(x:  7.5, width: barW, height: 13.0),
    ]
    private static let fallbackWaveParams: [FallbackWaveParam] = [
        .init(f1: 9.1, a1: 0.20, f2: 13.9, a2: 0.13, f3: 19.3, a3: 0.08, center: 0.37, phase: 0.0),
        .init(f1: 5.4, a1: 0.11, f2:  8.4, a2: 0.06, f3: 13.1, a3: 0.07, center: 0.18, phase: 1.8),
        .init(f1: 6.8, a1: 0.14, f2: 10.5, a2: 0.08, f3: 16.7, a3: 0.09, center: 0.22, phase: 3.5),
        .init(f1: 9.5, a1: 0.20, f2: 15.1, a2: 0.11, f3: 11.3, a3: 0.10, center: 0.33, phase: 0.4),
        .init(f1: 9.5, a1: 0.18, f2: 12.3, a2: 0.12, f3: 17.9, a3: 0.09, center: 0.33, phase: 1.1),
        .init(f1: 7.0, a1: 0.20, f2: 11.2, a2: 0.11, f3: 14.3, a3: 0.09, center: 0.30, phase: 5.1),
    ]

    // The artwork or a plain gradient fallback, fitted to 24×24 with a blur
    @ViewBuilder
    private var artworkFill: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipped()
                .saturation(1.25)
                .blur(radius: 5)
                .overlay {
                    Rectangle().fill(Color(white: 0.12)).blendMode(.screen)
                }
        } else {
            LinearGradient(colors: [tintTop, tintBottom], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: (progress > 0.98) || !shouldAnimateWaveform)) { timeline in
            let audioBars: [Float]? = audioEngine?.notchBars()
            let effectiveBars: [Float]? = {
                if let ab = audioBars { return ab }
                guard shouldAnimateWaveform else { return nil }
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Shared groove: occasionally lifts several bars at once with varying heights
                // Slightly faster shared component
                let shared = sin(t * 6.1) * 0.08 + sin(t * 10.1) * 0.05
                return (0..<6).map { i in
                    let param = Self.fallbackWaveParams[i]
                    // Tremor: fast oscillation with irregular bursts and varying speed
                    let tremorEnv  = abs(sin(t * 0.7 + param.phase * 0.4)) * abs(sin(t * 1.3 + param.phase * 0.7)) * 0.13
                    let tremorFreq = 22.0 + abs(sin(t * 0.3 + param.phase * 0.5)) * 20.0
                    let tremor = sin(t * tremorFreq + param.phase * 2.1) * tremorEnv
                    let raw = param.center
                        + sin(t * param.f1 + param.phase) * param.a1
                        + sin(t * param.f2 + param.phase * 1.3) * param.a2
                        + sin(t * param.f3 + param.phase * 0.9) * param.a3
                        + tremor
                        + shared
                    let ceiling: Double = (i == 3 || i == 4) ? 0.83 : 0.96
                    return Float(max(0.04, min(ceiling, raw)))
                }
            }()
            let p = max(0, min(1, progress))
            let eased = p * p * (3 - 2 * p)

            let playingMix: CGFloat = shouldAnimateWaveform ? 1.0 : 0

            let waveActive: [BarSpec] = {
                if let ab = effectiveBars, ab.count >= 6 {
                    return (0..<6).map { i in
                        let raw = CGFloat(max(0, ab[i]))
                        // Slight sensitivity boost for bars 3-6 in live mode only:
                        // power < 1 lifts quiet sounds more, leaves loud sounds nearly unchanged
                        let boost: CGFloat = (i == 2 || i == 5) ? 0.60 : (i >= 2 ? 0.72 : 1.0)
                        let level = audioBars != nil ? pow(raw, boost) : raw
                        let height = Self.barW + level * 22.0
                        return .init(x: Self.barXs[i], width: Self.barW, height: height)
                    }
                }
                return Self.waveFlat
            }()

            let wave: [BarSpec] = (0..<6).map { i in
                let f = Self.waveFlat[i]
                let a = waveActive[i]
                return .init(
                    x: f.x + (a.x - f.x) * playingMix,
                    width: f.width + (a.width - f.width) * playingMix,
                    height: f.height + (a.height - f.height) * playingMix
                )
            }

            let target: [BarSpec] = {
                if effectiveBars == nil {
                    return Self.waveFlat
                }
                if isPlaying {
                    return Self.playingTarget
                } else {
                    return Self.pausedTarget
                }
            }()

            let barsOpacity: CGFloat = {
                if effectiveBars == nil {
                    if p < 0.50 { return 1 }
                    if p >= 0.82 { return 0 }
                    return max(0, 1 - (p - 0.50) / 0.32)
                }
                if p < 0.90 { return 1 }
                if p >= 0.995 { return 0 }
                return max(0, 1 - (p - 0.90) / 0.095)
            }()

            let springBase: Animation? = effectiveBars != nil
                ? .spring(response: 0.18, dampingFraction: 0.65)
                : nil

            let iconOpacity: CGFloat = {
                if effectiveBars == nil {
                    return p < 0.60 ? 0 : min(1, (p - 0.60) / 0.22)
                }
                return p < 0.82 ? 0 : min(1, (p - 0.82) / 0.175)
            }()

            ZStack {
                // Artwork (or gradient fallback) painted through the bars as a single stencil
                artworkFill
                    .mask {
                        ZStack {
                            ForEach(0..<6, id: \.self) { i in
                                let a = wave[i]
                                let b = target[i]
                                let x = a.x + (b.x - a.x) * eased
                                let w = max(0.05, a.width + (b.width - a.width) * eased)
                                let h = max(0.05, a.height + (b.height - a.height) * eased)

                                RoundedRectangle(cornerRadius: min(w, h) * 0.5, style: .continuous)
                                    .frame(width: w, height: h)
                                    .frame(height: 24)
                                    .animation(springBase, value: h)
                                    .offset(x: x)
                            }
                        }
                    }
                .offset(x: -1.0)
                .opacity(barsOpacity)

                if iconOpacity > 0 {
                    artworkFill
                        .mask { controlIconMorphLayer }
                        .opacity(iconOpacity)
                }
            }
            .frame(width: 24, height: 24, alignment: .center)
            .clipped()
        }
        .onAppear {
            displayedIsPlaying = isPlaying
            incomingIsPlaying = isPlaying
            iconSwapProgress = 1
        }
        .onChange(of: isPlaying) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if max(0, min(1, progress)) >= 0.995 {
                displayedIsPlaying = oldValue
                incomingIsPlaying = newValue
                iconSwapProgress = 0
                withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                    iconSwapProgress = 1
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    displayedIsPlaying = newValue
                    incomingIsPlaying = newValue
                    iconSwapProgress = 1
                }
            } else {
                displayedIsPlaying = newValue
                incomingIsPlaying = newValue
                iconSwapProgress = 1
            }
        }
    }

    private var controlIconMorphLayer: some View {
        ZStack {
            controlSymbol(isPlaying: displayedIsPlaying)
                .opacity(1 - iconSwapProgress)
                .scaleEffect(1.0 - 0.14 * iconSwapProgress)
                .offset(x: displayedIsPlaying ? -0.5 * iconSwapProgress : 0.5 * iconSwapProgress)

            controlSymbol(isPlaying: incomingIsPlaying)
                .opacity(iconSwapProgress)
                .scaleEffect(0.86 + 0.14 * iconSwapProgress)
                .offset(x: incomingIsPlaying ? 0.5 * (1 - iconSwapProgress) : -0.5 * (1 - iconSwapProgress))
        }
        .compositingGroup()
    }

    private func controlSymbol(isPlaying: Bool) -> some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }

}
