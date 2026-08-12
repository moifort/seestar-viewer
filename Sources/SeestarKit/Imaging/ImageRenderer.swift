import CoreGraphics
import Foundation

/// Convertit une image flottante en `CGImage` 8 bits, prête pour l'affichage.
public enum ImageRenderer {
    public static func render(_ image: RGBImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              image.pixels.count == image.width * image.height * 3
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: image.pixels.count)
        for i in 0..<image.pixels.count {
            bytes[i] = UInt8(min(max(image.pixels[i], 0), 1) * 255)
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: image.width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
