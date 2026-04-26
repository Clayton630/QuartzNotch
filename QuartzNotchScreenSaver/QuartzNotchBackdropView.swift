import AppKit
import CoreImage
import ScreenSaver

final class QuartzNotchBackdropView: ScreenSaverView {
    fileprivate static let backdropDirectory: URL = {
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Library/Application Support/QuartzNotch/LockScreenBackdrop", isDirectory: true)
    }()

    fileprivate static let artworkURL = backdropDirectory.appendingPathComponent("current-artwork.png")
    fileprivate static let metadataURL = backdropDirectory.appendingPathComponent("metadata.plist")

    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var renderedBackdrop: NSImage?
    private var lastArtworkSignature: ArtworkSignature?
    private var lastBoundsSize: CGSize = .zero

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        reloadBackdropIfNeeded(force: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        reloadBackdropIfNeeded(force: true)
    }

    override func animateOneFrame() {
        reloadBackdropIfNeeded(force: false)
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()

        guard let image = renderedBackdrop else { return }
        image.draw(in: bounds)
    }

    private func reloadBackdropIfNeeded(force: Bool) {
        let signature = ArtworkSignature.current()
        let size = bounds.size
        guard force || signature != lastArtworkSignature || size != lastBoundsSize else { return }

        lastArtworkSignature = signature
        lastBoundsSize = size
        renderedBackdrop = Self.makeBackdrop(
            from: Self.artworkURL,
            metadataURL: Self.metadataURL,
            canvasSize: size,
            context: imageContext
        )
    }

    private static func makeBackdrop(
        from artworkURL: URL,
        metadataURL: URL,
        canvasSize: CGSize,
        context: CIContext
    ) -> NSImage? {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return nil }
        guard let source = NSImage(contentsOf: artworkURL), let ciSource = CIImage(data: source.tiffRepresentation ?? Data()) else {
            return nil
        }

        let scale = max(canvasSize.width / ciSource.extent.width, canvasSize.height / ciSource.extent.height)
        let scaled = ciSource.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (canvasSize.width - scaled.extent.width) * 0.5
        let dy = (canvasSize.height - scaled.extent.height) * 0.5
        var composited = scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(composited, forKey: kCIInputImageKey)
            blur.setValue(48.0, forKey: kCIInputRadiusKey)
            composited = blur.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? composited
        }

        if let saturation = CIFilter(name: "CIColorControls") {
            saturation.setValue(composited, forKey: kCIInputImageKey)
            saturation.setValue(1.18, forKey: kCIInputSaturationKey)
            saturation.setValue(0.02, forKey: kCIInputBrightnessKey)
            saturation.setValue(1.08, forKey: kCIInputContrastKey)
            composited = saturation.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? composited
        }

        let overlay = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.18))
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
        if let multiply = CIFilter(name: "CIMultiplyCompositing") {
            multiply.setValue(overlay, forKey: kCIInputImageKey)
            multiply.setValue(composited, forKey: kCIInputBackgroundImageKey)
            composited = multiply.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? composited
        }

        let accentColor = MetadataReader.accentColor(from: metadataURL) ?? NSColor.white.withAlphaComponent(0.08)
        let accent = CIImage(color: CIColor(cgColor: accentColor.cgColor))
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
        if let screen = CIFilter(name: "CIScreenBlendMode") {
            screen.setValue(accent, forKey: kCIInputImageKey)
            screen.setValue(composited, forKey: kCIInputBackgroundImageKey)
            composited = screen.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? composited
        }

        guard let cgImage = context.createCGImage(composited, from: CGRect(origin: .zero, size: canvasSize)) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: canvasSize)
    }
}

private struct ArtworkSignature: Equatable {
    let modificationDate: Date?
    let artworkSize: UInt64
    let metadataDate: Date?

    static func current() -> ArtworkSignature? {
        guard let artworkValues = try? QuartzNotchBackdropView.artworkURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        let metadataValues = try? QuartzNotchBackdropView.metadataURL.resourceValues(forKeys: [.contentModificationDateKey])
        return ArtworkSignature(
            modificationDate: artworkValues.contentModificationDate,
            artworkSize: UInt64(artworkValues.fileSize ?? 0),
            metadataDate: metadataValues?.contentModificationDate
        )
    }
}

private enum MetadataReader {
    static func accentColor(from metadataURL: URL) -> NSColor? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        guard let rgba = plist?["accentColorRGBA"] as? [NSNumber], rgba.count == 4 else { return nil }
        return NSColor(
            calibratedRed: CGFloat(truncating: rgba[0]),
            green: CGFloat(truncating: rgba[1]),
            blue: CGFloat(truncating: rgba[2]),
            alpha: CGFloat(truncating: rgba[3])
        )
    }
}
