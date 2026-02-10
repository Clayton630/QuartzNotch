//
// AlbumArtFlipView.swift
// boringNotch
//
// Dynamic Island-like album art flip (2D-ish, direction-aware, non-linear).
// Perf-focused + reliable under rapid taps:
//
// Fix for your exact bug:
// - If you click twice quickly, we DO NOT replace the running flip's target.
// - The running flip always lands on the first requested artwork.
// - Any extra tap while animating is queued and will trigger a second flip immediately after.
// - If you spam more than twice, we coalesce the queue to the latest (but still guarantee
//  at least one follow-up flip after the current one).
//
// Visual behavior kept the same (soft / organic / amortie).
//

import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AlbumArtFlipView: View {
    let currentImage: NSImage
    let eventID: UUID
    let incomingImage: NSImage
    let direction: AlbumArtFlipDirection

    let cornerRadius: CGFloat
    let geometryID: String
    let namespace: Namespace.ID

  // Front face (currently displayed track)
    @State private var frontImage: NSImage
    @State private var frontBlurredImage: NSImage?

  // Back face TARGET for the CURRENT flip.
  // IMPORTANT: while animating, this must NOT change, otherwise you "skip" intermediate flips.
    @State private var backImage: NSImage

  // Direction locked for the CURRENT flip
    @State private var activeDirection: AlbumArtFlipDirection

  // Queue: latest request that arrives while animating (will play AFTER current flip)
    @State private var queuedImage: NSImage?
    @State private var queuedDirection: AlbumArtFlipDirection?

  // Animation states
    @State private var blurMix: CGFloat = 0
    @State private var liveBlurRadius: CGFloat = 0
    @State private var flipAngle: Double = 0
    @State private var squeezeX: CGFloat = 1
    @State private var bounceScale: CGFloat = 1
    @State private var isAnimating: Bool = false
    @State private var didClearBlur: Bool = false

    init(
        currentImage: NSImage,
        eventID: UUID,
        incomingImage: NSImage,
        direction: AlbumArtFlipDirection,
        cornerRadius: CGFloat,
        geometryID: String,
        namespace: Namespace.ID
    ) {
        self.currentImage = currentImage
        self.eventID = eventID
        self.incomingImage = incomingImage
        self.direction = direction
        self.cornerRadius = cornerRadius
        self.geometryID = geometryID
        self.namespace = namespace

        _frontImage = State(initialValue: currentImage)
        _backImage = State(initialValue: incomingImage)
        _activeDirection = State(initialValue: direction)
    }

    var body: some View {
        ZStack {
      // FRONT face (old artwork). Crossfade sharp -> blurred.
            ZStack {
                Image(nsImage: frontImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .blur(radius: liveBlurRadius) // fallback only during ramp
                    .opacity(frontBlurredImage == nil ? 1 : (1 - blurMix))

                if let blurred = frontBlurredImage {
                    Image(nsImage: blurred)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .opacity(blurMix)
                }
            }
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0
            )
            .opacity(frontVisible ? 1 : 0)

      // BACK face (target of the current flip), always crisp.
            Image(nsImage: backImage)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    perspective: 0
                )
                .rotation3DEffect(
                    .degrees(flipAngle),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    perspective: 0
                )
                .opacity(frontVisible ? 0 : 1)
        }
    // Direction cue: subtle, but makes next/previous clearly different
        .offset(x: xCue)
        .shadow(radius: 9, x: shadowXCue, y: 0)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .scaleEffect(x: squeezeX, y: 1)
        .scaleEffect(bounceScale)
        .matchedGeometryEffect(id: geometryID, in: namespace)
        .onAppear {
            frontImage = currentImage
            backImage = incomingImage
            activeDirection = direction
            queuedImage = nil
            queuedDirection = nil
            frontBlurredImage = nil
            prepareBlurredFrontAsync()
        }
    // Single source of truth for playback changes: eventID
        .onChange(of: eventID) { _, _ in
            handleFlipEvent(newIncoming: incomingImage, newDirection: direction)
        }
        .onChange(of: frontImage) { _, _ in
            frontBlurredImage = nil
            prepareBlurredFrontAsync()
        }
    }

    private var frontVisible: Bool { abs(normalizedAngle) <= 90 }

    private var normalizedAngle: Double {
        var a = flipAngle
        while a > 180 { a -= 360 }
        while a < -180 { a += 360 }
        return a
    }

  // MARK: - Direction cue (locked to the current flip)

    private var dirSign: CGFloat { (activeDirection == .next) ? 1 : -1 }

    private var directionCue: CGFloat {
        let a = CGFloat(abs(normalizedAngle)) * .pi / 180
        return sin(a) // 0 → 1 → 0
    }

    private var xCue: CGFloat { dirSign * directionCue * 5.5 }
    private var shadowXCue: CGFloat { dirSign * directionCue * 3.8 }

  // MARK: - Reliable event handling (fixes “second tap doesn’t animate”)

    private func handleFlipEvent(newIncoming: NSImage, newDirection: AlbumArtFlipDirection) {
    // If we are idle, this event becomes the immediate flip target.
        if !isAnimating {
      // Update the target for the next flip
            backImage = newIncoming
            activeDirection = newDirection
            startFlipIfNeeded()
            return
        }

    // If we are currently animating:
    // DO NOT change backImage (running target) — otherwise you skip a flip visually.
    // Instead queue the new request so we play it right after this flip finishes.
        queuedImage = newIncoming
        queuedDirection = newDirection
    }

  // MARK: - Animation

    private func startFlipIfNeeded() {
    // No-op if already showing same image instance
        if backImage === frontImage { return }
        startFlip()
    }

    private func startFlip() {
        isAnimating = true
        didClearBlur = false

        let sign: Double = (activeDirection == .next) ? 1 : -1

    // Tunables (soft / organic / amortie)
        let blurRampDuration: TimeInterval = 0.34
        let flipStartDelay: TimeInterval = 0.02
        let flipDuration: TimeInterval = 1.02
        let minSqueeze: CGFloat = 0.44
        let strongBlurRadius: CGFloat = 18

    // Reset
        blurMix = 0
        liveBlurRadius = 0
        flipAngle = 0
        squeezeX = 1
        bounceScale = 1

        if frontBlurredImage == nil {
            prepareBlurredFrontAsync()
        }

    // Blur ramps immediately
        if frontBlurredImage != nil {
            withAnimation(.timingCurve(0.10, 0.00, 0.16, 1.00, duration: blurRampDuration)) {
                blurMix = 1
            }
        } else {
            withAnimation(.timingCurve(0.10, 0.00, 0.16, 1.00, duration: blurRampDuration)) {
                liveBlurRadius = strongBlurRadius
            }
        }

    // Flip overlaps blur ramp
        DispatchQueue.main.asyncAfter(deadline: .now() + flipStartDelay) {
            withAnimation(.timingCurve(0.20, 0.80, 0.06, 1.00, duration: flipDuration)) {
                flipAngle = sign * 180
            }
        }

    // Squeeze updates
        let steps = 64
        for i in 0...steps {
            let t = flipStartDelay + (flipDuration * Double(i) / Double(steps))
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                let theta = abs(normalizedAngle) * Double.pi / 180.0
                let raw = CGFloat(abs(cos(theta)))
                let softened = pow(max(0, raw), 0.35)
                squeezeX = max(minSqueeze, softened)

        // As soon as we cross to back face: kill blur so new is crisp
                if !didClearBlur, abs(normalizedAngle) >= 90 {
                    didClearBlur = true
                    withAnimation(.timingCurve(0.18, 0.00, 0.18, 1.00, duration: 0.10)) {
                        blurMix = 0
                        liveBlurRadius = 0
                    }
                }
            }
        }

    // End: commit backImage → frontImage, then chain queued flip if any
        DispatchQueue.main.asyncAfter(deadline: .now() + flipStartDelay + flipDuration) {
      // Commit the running target (backImage) as the new front
            frontImage = backImage
            frontBlurredImage = nil

      // Reset transforms
            flipAngle = 0
            blurMix = 0
            liveBlurRadius = 0
            squeezeX = 1

      // Warm blur for next time
            prepareBlurredFrontAsync()

      // Softer rebound
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 34)) {
                bounceScale = 1.0065
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 38)) {
                    bounceScale = 1.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                isAnimating = false
                didClearBlur = false

        // If a request arrived while animating, play it now (guaranteed second flip)
                if let qImg = queuedImage, let qDir = queuedDirection {
                    queuedImage = nil
                    queuedDirection = nil

          // Set new target + direction for the next flip
                    backImage = qImg
                    activeDirection = qDir

          // Start immediately if it actually changes the image
                    startFlipIfNeeded()
                }
            }
        }
    }

  // MARK: - Blur preparation (robust)

    private func prepareBlurredFrontAsync() {
        let source = frontImage

        DispatchQueue.global(qos: .userInitiated).async {
            let blurred = Self.makeBlurredImage(from: source, radius: 18, maxDimension: 640)

            DispatchQueue.main.async {
                if self.frontImage === source {
                    self.frontBlurredImage = blurred

          // If we were using live blur fallback mid-ramp, switch smoothly to bitmap blur.
                    if self.liveBlurRadius > 0, blurred != nil, self.blurMix == 0 {
                        withAnimation(.linear(duration: 0.10)) {
                            self.blurMix = 1
                            self.liveBlurRadius = 0
                        }
                    }
                }
            }
        }
    }

    static func makeBlurredImage(from image: NSImage, radius: CGFloat, maxDimension: CGFloat) -> NSImage? {
        guard let cg = cgImageFromNSImage(image) else { return nil }

        let ci = CIImage(cgImage: cg)

        let w = ci.extent.width
        let h = ci.extent.height
        let scale = min(1.0, maxDimension / max(w, h))
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let filter = CIFilter.gaussianBlur()
        filter.inputImage = scaled
        filter.radius = Float(radius)

        guard let out = filter.outputImage else { return nil }
        let cropped = out.cropped(to: scaled.extent)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let outCG = context.createCGImage(cropped, from: cropped.extent) else { return nil }

        return NSImage(cgImage: outCG, size: image.size)
    }

    static func cgImageFromNSImage(_ image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }

        let size = image.size
        guard size.width > 1, size.height > 1 else { return nil }

        let pixelsWide = Int(size.width)
        let pixelsHigh = Int(size.height)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        return rep.cgImage
    }
}
