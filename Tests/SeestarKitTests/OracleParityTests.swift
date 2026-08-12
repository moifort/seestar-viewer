import CoreGraphics
import Foundation
import Testing
@testable import SeestarKit

/// Valeurs produites par l'oracle `decode_frame.py` sur la trame réelle
/// `frame_21_000_1080x1920.bin`, chaîne complète : binning GRBG 2x2 puis
/// étirement automatique. Moyennes par canal sur 0-255.
///
/// Ce test est le garde-fou du portage : si le Swift dérive du Python, on le
/// sait immédiatement, sans avoir à comparer des images à l'œil.
private enum Oracle {
    static let width = 540
    static let height = 960
    static let meanRed: Double = 112.1957
    static let meanGreen: Double = 253.9587
    static let meanBlue: Double = 62.7504
}

/// Moyennes par canal d'une image rendue, sur l'échelle 0-255.
private func channelMeans(_ image: CGImage) throws -> (Double, Double, Double) {
    let data = try #require(image.dataProvider?.data as Data?)
    #expect(data.count == image.width * image.height * 3)

    var sums = (0.0, 0.0, 0.0)
    let bytes = [UInt8](data)
    for pixel in 0..<(image.width * image.height) {
        sums.0 += Double(bytes[pixel * 3])
        sums.1 += Double(bytes[pixel * 3 + 1])
        sums.2 += Double(bytes[pixel * 3 + 2])
    }
    let count = Double(image.width * image.height)
    return (sums.0 / count, sums.1 / count, sums.2 / count)
}

@Test func leDecodageSwiftCorrespondALOraclePython() throws {
    let frame = RawFrame(id: 21, width: 1080, height: 1920, payload: try Fixtures.frameData())
    let decoded = try #require(FrameDecoder.decode(frame))

    #expect(decoded.image.width == Oracle.width)
    #expect(decoded.image.height == Oracle.height)

    let (red, green, blue) = try channelMeans(decoded.image)

    // Tolérance d'un niveau sur 255 : les deux implémentations arrondissent
    // et échantillonnent identiquement, l'écart résiduel tient au flottant.
    #expect(abs(red - Oracle.meanRed) < 1.0)
    #expect(abs(green - Oracle.meanGreen) < 1.0)
    #expect(abs(blue - Oracle.meanBlue) < 1.0)
}
