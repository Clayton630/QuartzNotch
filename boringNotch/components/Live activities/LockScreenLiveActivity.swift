
import SwiftUI
import AppKit

struct LockScreenLiveActivity: View {
  /// true = screen locked ; false = unlocked
    let isLocked: Bool
    let contentWidth: CGFloat
    let height: CGFloat
    @ObservedObject private var musicManager = MusicManager.shared

    private var iconSize: CGFloat { max(0, height - 12) }
    private var shouldShowMediaPanel: Bool {
        isLocked && (musicManager.isPlaying || !musicManager.isPlayerIdle || !musicManager.isUsingIdleMetadata)
    }

    @State private var iconBlur: CGFloat = 0
    @State private var blurTask: Task<Void, Never>?
    private let blurMax: CGFloat = 18

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: contentWidth, height: height)

            if shouldShowMediaPanel {
                lockScreenMediaPanel
                    .frame(width: contentWidth, height: height)
            } else {
                LockIconAnimatedBlurView(
                    isLocked: isLocked,
                    size: iconSize,
                    iconColor: .white,
                    blurRadius: iconBlur
                )
            }
        }
        .frame(width: contentWidth, height: height)
        .onAppear { applyBlurTransition(isLocked: isLocked, initial: true) }
        .onChange(of: isLocked) { locked in
            applyBlurTransition(isLocked: locked, initial: false)
        }
    }

    private func applyBlurTransition(isLocked: Bool, initial: Bool) {
        blurTask?.cancel()
        if isLocked {
            iconBlur = blurMax
            let startDelayMs = initial ? 360 : 300

            blurTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(startDelayMs))
                guard !Task.isCancelled else { return }

                withAnimation(NotchMotion.liveActivityIn) { iconBlur = 12 }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }

                withAnimation(NotchMotion.liveActivityIn) { iconBlur = 6 }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }

                withAnimation(NotchMotion.liveActivityOut) { iconBlur = 0 }
            }
        } else {
            iconBlur = 0
        }
    }

    @ViewBuilder
    private var lockScreenMediaPanel: some View {
        HStack(spacing: 7) {
            Group {
                if let albumImage = musicManager.albumArt.copy() as? NSImage {
                    Image(nsImage: albumImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.songTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.98))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(musicManager.artistName)
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
