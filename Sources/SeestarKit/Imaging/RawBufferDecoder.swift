import Foundation

/// Transforme le buffer brut d'une trame en image RVB.
///
/// Deux formats mesurés ou attendus, distingués par la taille :
///   - `width * height * 2` : mosaïque de Bayer 16 bits (preview)
///   - `width * height * 6` : trois canaux de 16 bits (empilement)
public enum RawBufferDecoder {
    /// Motif de Bayer du capteur. `GRBG` est repris de seestar_alp et reste à
    /// confirmer sur une trame nocturne non saturée (hypothèse 1 de la spec).
    public enum BayerPattern: Sendable {
        case grbg, rggb, bggr, gbrg

        /// Positions (ligne, colonne) dans le bloc 2x2.
        var offsets: (r: (Int, Int), g: ((Int, Int), (Int, Int)), b: (Int, Int)) {
            switch self {
            case .grbg: return (r: (0, 1), g: ((0, 0), (1, 1)), b: (1, 0))
            case .rggb: return (r: (0, 0), g: ((0, 1), (1, 0)), b: (1, 1))
            case .bggr: return (r: (1, 1), g: ((0, 1), (1, 0)), b: (0, 0))
            case .gbrg: return (r: (1, 0), g: ((0, 0), (1, 1)), b: (0, 1))
            }
        }
    }

    private static let scale = Float(65535)

    public static func decode(
        _ payload: Data,
        width: Int,
        height: Int,
        pattern: BayerPattern = .grbg
    ) -> RGBImage? {
        guard width > 0, height > 0 else { return nil }
        let samples = readLittleEndianUInt16(payload)

        if samples.count == width * height * 3 {
            return decodeRGB(samples, width: width, height: height)
        }
        if samples.count == width * height {
            return binBayer(samples, width: width, height: height, pattern: pattern)
        }
        return nil
    }

    private static func readLittleEndianUInt16(_ data: Data) -> [UInt16] {
        guard data.count % 2 == 0 else { return [] }
        var out = [UInt16](repeating: 0, count: data.count / 2)
        let bytes = [UInt8](data)
        for i in 0..<out.count {
            out[i] = UInt16(bytes[2 * i]) | (UInt16(bytes[2 * i + 1]) << 8)
        }
        return out
    }

    private static func decodeRGB(_ samples: [UInt16], width: Int, height: Int) -> RGBImage {
        var pixels = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            pixels[i] = Float(samples[i]) / scale
        }
        return RGBImage(width: width, height: height, pixels: pixels)
    }

    /// Binning 2x2 : chaque bloc devient un pixel. Pas d'interpolation, donc
    /// aucun artefact de dématriçage, et le bruit baisse. On perd la moitié de
    /// la résolution, sans conséquence pour un affichage télévisé.
    private static func binBayer(
        _ samples: [UInt16], width: Int, height: Int, pattern: BayerPattern
    ) -> RGBImage {
        let outWidth = width / 2
        let outHeight = height / 2
        let offsets = pattern.offsets
        var pixels = [Float](repeating: 0, count: outWidth * outHeight * 3)

        @inline(__always)
        func sample(_ blockY: Int, _ blockX: Int, _ position: (Int, Int)) -> Float {
            let y = blockY * 2 + position.0
            let x = blockX * 2 + position.1
            return Float(samples[y * width + x])
        }

        for blockY in 0..<outHeight {
            for blockX in 0..<outWidth {
                let base = (blockY * outWidth + blockX) * 3
                pixels[base] = sample(blockY, blockX, offsets.r) / scale
                pixels[base + 1] = (sample(blockY, blockX, offsets.g.0)
                    + sample(blockY, blockX, offsets.g.1)) / 2 / scale
                pixels[base + 2] = sample(blockY, blockX, offsets.b) / scale
            }
        }
        return RGBImage(width: outWidth, height: outHeight, pixels: pixels)
    }
}
