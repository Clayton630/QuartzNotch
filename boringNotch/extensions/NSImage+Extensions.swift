
import SwiftUI
import AppKit
import Cocoa
import Foundation
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

extension NSImage {

    
    func averageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height
            
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let data = context.data else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
            
            var totalRed: UInt64 = 0
            var totalGreen: UInt64 = 0
            var totalBlue: UInt64 = 0
            
            for i in 0..<totalPixels {
                let color = pointer[i]
                totalRed += UInt64(color & 0xFF)
                totalGreen += UInt64((color >> 8) & 0xFF)
                totalBlue += UInt64((color >> 16) & 0xFF)
            }
            
            let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
            let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
            let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
            
            let minBrightness: CGFloat = 0.5
            let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
            
            var finalColor: NSColor
            
            if isNearBlack {
                finalColor = NSColor(white: minBrightness, alpha: 1.0)
            } else {
                var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                
                if brightness < minBrightness {
                    let saturationScale = brightness / minBrightness
                    color = NSColor(hue: hue,
                                    saturation: saturation * saturationScale,
                                    brightness: minBrightness,
                                    alpha: alpha)
                }
                
                finalColor = color
            }
            
            DispatchQueue.main.async {
                completion(finalColor)
            }
        }
        
    }
    
    func getBrightness() -> CGFloat {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        
        let inputImage = CIImage(cgImage: cgImage)
        
        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent
        
        guard let outputImage = filter.outputImage else {
            return 0
        }
        
        let context = CIContext(options: nil)
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let brightness = (0.2126 * CGFloat(bitmap[0]) + 0.7152 * CGFloat(bitmap[1]) + 0.0722 * CGFloat(bitmap[2])) / 255.0
        
        return brightness
    }

    func verticalGradientColors(completion: @escaping (_ top: NSColor?, _ bottom: NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            let width = cgImage.width
            let height = cgImage.height
            guard width > 0, height > 0 else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let data = context.data else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
            let bytesPerRow = width * 4
            let sampleStep = max(1, min(width, height) / 170)
            let topZoneEnd = max(1, Int(CGFloat(height) * 0.58))
            let bottomZoneStart = min(height - 1, Int(CGFloat(height) * 0.42))

            var topBins: [Int: Int] = [:]
            var bottomBins: [Int: Int] = [:]
            var globalBins: [Int: Int] = [:]

            var sumR: UInt64 = 0
            var sumG: UInt64 = 0
            var sumB: UInt64 = 0
            var sampledCount: UInt64 = 0

            var y = 0
            while y < height {
                let inTopZone = y <= topZoneEnd
                let inBottomZone = y >= bottomZoneStart

                let rowOffset = y * bytesPerRow
                var x = 0
                while x < width {
                    let idx = rowOffset + (x * 4)
                    let r8 = bytes[idx + 0]
                    let g8 = bytes[idx + 1]
                    let b8 = bytes[idx + 2]
                    let a8 = bytes[idx + 3]

                    if a8 > 12 {
                        let r = CGFloat(r8) / 255.0
                        let g = CGFloat(g8) / 255.0
                        let b = CGFloat(b8) / 255.0
                        let sat = Self.saturation(red: r, green: g, blue: b)
                        let bri = max(r, max(g, b))

                        if !(bri < 0.08 && sat < 0.15) {
                            sumR += UInt64(r8)
                            sumG += UInt64(g8)
                            sumB += UInt64(b8)
                            sampledCount += 1

                            let key = Self.quantizedKey(r8: r8, g8: g8, b8: b8)
                            globalBins[key, default: 0] += 1
                            if inTopZone {
                                topBins[key, default: 0] += 1
                            }
                            if inBottomZone {
                                bottomBins[key, default: 0] += 1
                            }
                        }
                    }
                    x += sampleStep
                }
                y += sampleStep
            }

            guard sampledCount > 0 else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            let meanColor = NSColor(
                red: CGFloat(sumR) / CGFloat(sampledCount) / 255.0,
                green: CGFloat(sumG) / CGFloat(sampledCount) / 255.0,
                blue: CGFloat(sumB) / CGFloat(sampledCount) / 255.0,
                alpha: 1
            )

            let topRaw = Self.bestDominantColor(in: topBins, avoiding: nil)
                ?? Self.bestDominantColor(in: globalBins, avoiding: nil)
                ?? meanColor

            var bottomRaw = Self.bestDominantColor(in: bottomBins, avoiding: topRaw)
                ?? Self.bestDominantColor(in: globalBins, avoiding: topRaw)
                ?? topRaw

            if Self.colorDistance(topRaw, bottomRaw) < 0.14,
               let forcedAlt = Self.secondDistinctDominantColor(in: globalBins, primary: topRaw, minDistance: 0.17) {
                bottomRaw = forcedAlt
            }

            let unifiedTop = Self.blend(topRaw, with: meanColor, amount: 0.22)
            let unifiedBottom = Self.blend(bottomRaw, with: meanColor, amount: 0.22)

            let topColor = Self.makeReadableColor(from: unifiedTop)
            let bottomColor = Self.makeReadableColor(from: unifiedBottom)

            DispatchQueue.main.async {
                completion(topColor, bottomColor)
            }
        }
    }

    private static func makeReadableColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
        let minBrightness: CGFloat = 0.48
        let isNearBlack = red < 0.03 && green < 0.03 && blue < 0.03
        if isNearBlack {
            return NSColor(white: minBrightness, alpha: 1.0)
        }

        var color = NSColor(red: red, green: green, blue: blue, alpha: 1.0)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if brightness < minBrightness {
            let saturationScale = max(0.55, brightness / max(minBrightness, 0.0001))
            color = NSColor(
                hue: hue,
                saturation: saturation * saturationScale,
                brightness: minBrightness,
                alpha: alpha
            )
        }
        return color
    }

    private static func makeReadableColor(from color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            return makeReadableColor(red: 0.8, green: 0.8, blue: 0.8)
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return makeReadableColor(red: r, green: g, blue: b)
    }

    private static func quantizedKey(r8: UInt8, g8: UInt8, b8: UInt8) -> Int {
        let bins = 14
        let rq = min(bins - 1, Int(r8) * bins / 256)
        let gq = min(bins - 1, Int(g8) * bins / 256)
        let bq = min(bins - 1, Int(b8) * bins / 256)
        return (rq << 8) | (gq << 4) | bq
    }

    private static func colorFromQuantizedKey(_ key: Int) -> NSColor {
        let bins = 14
        let rq = (key >> 8) & 0xF
        let gq = (key >> 4) & 0xF
        let bq = key & 0xF
        let step = 1.0 / CGFloat(bins)
        let r = (CGFloat(rq) + 0.5) * step
        let g = (CGFloat(gq) + 0.5) * step
        let b = (CGFloat(bq) + 0.5) * step
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func saturation(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        let maxC = max(red, max(green, blue))
        let minC = min(red, min(green, blue))
        guard maxC > 0 else { return 0 }
        return (maxC - minC) / maxC
    }

    private static func colorDistance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let ca = a.usingColorSpace(.sRGB),
              let cb = b.usingColorSpace(.sRGB) else { return 0 }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let dr = ar - br
        let dg = ag - bg
        let db = ab - bb
        return sqrt((dr * dr + dg * dg + db * db) / 3.0)
    }

    private static func blend(_ a: NSColor, with b: NSColor, amount: CGFloat) -> NSColor {
        let t = min(max(amount, 0), 1)
        guard let ca = a.usingColorSpace(.sRGB),
              let cb = b.usingColorSpace(.sRGB) else { return a }

        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        return NSColor(
            red: ar * (1 - t) + br * t,
            green: ag * (1 - t) + bg * t,
            blue: ab * (1 - t) + bb * t,
            alpha: aa
        )
    }

    private static func bestDominantColor(in bins: [Int: Int], avoiding avoidColor: NSColor?) -> NSColor? {
        guard !bins.isEmpty else { return nil }
        var bestKey: Int?
        var bestScore: CGFloat = -1
        for (key, count) in bins {
            let color = colorFromQuantizedKey(key)
            guard let srgb = color.usingColorSpace(.sRGB) else { continue }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

            let sat = saturation(red: r, green: g, blue: b)
            let bri = max(r, max(g, b))
            var score = CGFloat(count)
            score *= (0.32 + sat * 1.5)
            score *= (0.46 + bri * 0.92)
            if sat < 0.06 { score *= 0.62 }
            if bri < 0.08 { score *= 0.22 }

            if let avoidColor {
                let dist = colorDistance(color, avoidColor)
                score *= (0.62 + dist * 2.1)
            }

            if score > bestScore {
                bestScore = score
                bestKey = key
            }
        }
        guard let key = bestKey else { return nil }
        return colorFromQuantizedKey(key)
    }

    private static func secondDistinctDominantColor(
        in bins: [Int: Int],
        primary: NSColor,
        minDistance: CGFloat
    ) -> NSColor? {
        var bestColor: NSColor?
        var bestScore: CGFloat = -1
        for (key, count) in bins {
            let candidate = colorFromQuantizedKey(key)
            let dist = colorDistance(candidate, primary)
            guard dist >= minDistance else { continue }

            guard let srgb = candidate.usingColorSpace(.sRGB) else { continue }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            let sat = saturation(red: r, green: g, blue: b)
            let bri = max(r, max(g, b))
            var score = CGFloat(count)
            score *= (0.30 + sat * 1.45)
            score *= (0.46 + bri * 0.88)
            score *= (0.78 + dist * 1.55)

            if score > bestScore {
                bestScore = score
                bestColor = candidate
            }
        }
        return bestColor
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else {
            return self // Return original color if factor is out of bounds
        }
        
        let nsColor = NSColor(self)
        
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return self // Return original color if conversion fails
        }
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)
        
        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}
