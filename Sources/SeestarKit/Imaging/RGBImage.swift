import Foundation

/// Image intermédiaire en flottants, canaux entrelacés R, V, B entre 0 et 1.
///
/// Les valeurs sont linéaires : affichée telle quelle, une image astro est
/// quasiment noire. L'étirement (`AutoStretch`) est indispensable.
public struct RGBImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}
