import Foundation

/// Étirement d'histogramme automatique, méthode classique des logiciels astro.
///
/// Une image astronomique linéaire est quasiment noire : cette étape n'est pas
/// cosmétique, elle est indispensable à l'affichage. Le traitement canal par
/// canal corrige au passage la dominante de couleur.
///
/// Miroir Swift de `autostretch()` dans `decode_frame.py`, qui sert d'oracle.
public enum AutoStretch {
    /// Fonction de transfert de tons (midtone transfer function).
    public static func midtoneTransfer(_ x: Float, _ m: Float) -> Float {
        let denominator = (2 * m - 1) * x - m
        guard denominator != 0 else { return 0 }
        return min(max((m - 1) * x / denominator, 0), 1)
    }

    public static func apply(
        _ image: RGBImage,
        targetBackground: Float = 0.25,
        shadowClip: Float = -2.8
    ) -> RGBImage {
        var pixels = image.pixels
        let pixelCount = image.width * image.height

        for channel in 0..<3 {
            // Statistiques sur un pixel sur 16 : seize fois plus rapide, et
            // suffisamment représentatif pour une médiane.
            var sample = [Float]()
            sample.reserveCapacity(pixelCount / 16 + 1)
            var index = 0
            while index < pixelCount {
                sample.append(pixels[index * 3 + channel])
                index += 16
            }
            guard !sample.isEmpty else { continue }

            let median = self.median(of: sample)
            let deviations = sample.map { abs($0 - median) }
            let mad = self.median(of: deviations) * 1.4826
            guard mad > 0 else { continue }

            let blackPoint = min(max(median + shadowClip * mad, 0), 1)
            let span = max(1 - blackPoint, 1e-6)
            let rawMidtone = midtoneTransfer((median - blackPoint) / span, targetBackground)
            let midtone = min(max(rawMidtone, 1e-4), 1 - 1e-4)

            for pixel in 0..<pixelCount {
                let offset = pixel * 3 + channel
                let normalized = min(max((pixels[offset] - blackPoint) / span, 0), 1)
                pixels[offset] = midtoneTransfer(normalized, midtone)
            }
        }

        return RGBImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func median(of values: [Float]) -> Float {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
