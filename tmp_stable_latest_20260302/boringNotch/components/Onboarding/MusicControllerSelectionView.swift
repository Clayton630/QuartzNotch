//
// MusicControllerSelectionView.swift
// boringNotch
//
// Created by Alexander on 2025-06-23.
// Updated by Clayton on 2026-01-24.
//

import SwiftUI
import Defaults

/// Kept the original filename so the onboarding flow doesn't need refactors.
/// The UX is now a simple 2-mode choice:
/// - System Wide: follow macOS "Now Playing" (any media app)
/// - Music Only: only Music/Spotify/YouTube Music
struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.playbackScope) private var playbackScope
    @State private var selectedScope: PlaybackScope = Defaults[.playbackScope]

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose a Media Mode")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Pick how boringNotch should decide what to show. You can change this later in Settings → Media.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 12) {
                ScopeOptionView(
                    scope: .systemWide,
                    isSelected: selectedScope == .systemWide
                )
                .onTapGesture { selectedScope = .systemWide }

                ScopeOptionView(
                    scope: .musicOnly,
                    isSelected: selectedScope == .musicOnly
                )
                .onTapGesture { selectedScope = .musicOnly }
            }
            .padding(.horizontal)

            Spacer()

            Button("Continue") {
                playbackScope = selectedScope
                NotificationCenter.default.post(name: .playbackScopeChanged, object: nil)
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

private struct ScopeOptionView: View {
    let scope: PlaybackScope
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .effectiveAccent : .secondary.opacity(0.5))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(scope.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(scopeDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.effectiveAccent.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.effectiveAccent : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private var scopeDescription: String {
        switch scope {
        case .systemWide:
            return "Shows whatever macOS reports as Now Playing (any media app, including browsers)."
        case .musicOnly:
            return "Only follows Music, Spotify, and YouTube Music. Useful if videos keep stealing focus."
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 420, height: 560)
}
