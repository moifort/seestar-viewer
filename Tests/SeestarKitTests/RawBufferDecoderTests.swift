import Foundation
import Testing
@testable import SeestarKit

/// Construit une mosaïque de Bayer GRBG synthétique de 4x4 échantillons.
/// Motif : ligne paire « G R », ligne impaire « B G ».
func makeBayerGRBG() -> Data {
    let values: [UInt16] = [
        100, 200, 100, 200,   // G R G R
        300, 400, 300, 400,   // B G B G
        100, 200, 100, 200,
        300, 400, 300, 400,
    ]
    var data = Data(capacity: values.count * 2)
    for value in values {
        data.append(UInt8(value & 0xFF))          // little-endian
        data.append(UInt8((value >> 8) & 0xFF))
    }
    return data
}

@Test func leBinningBayerProduitLaDemiResolution() throws {
    let image = try #require(RawBufferDecoder.decode(makeBayerGRBG(), width: 4, height: 4))
    #expect(image.width == 2)
    #expect(image.height == 2)
    #expect(image.pixels.count == 2 * 2 * 3)
}

@Test func leBinningPlaceLesComposantesAuBonEndroit() throws {
    let image = try #require(RawBufferDecoder.decode(makeBayerGRBG(), width: 4, height: 4))
    // Bloc 2x2 : G=100 (haut gauche), R=200 (haut droit),
    //            B=300 (bas gauche), G=400 (bas droit).
    // R = 200, G = (100 + 400) / 2 = 250, B = 300.
    let scale = Float(65535)
    #expect(abs(image.pixels[0] - 200 / scale) < 1e-6)
    #expect(abs(image.pixels[1] - 250 / scale) < 1e-6)
    #expect(abs(image.pixels[2] - 300 / scale) < 1e-6)
}

@Test func leBufferRGB16BitsEstReconnu() throws {
    // Cas w*h*6 : trois canaux de 16 bits, sans dématriçage.
    var data = Data()
    for value: UInt16 in [1000, 2000, 3000, 4000, 5000, 6000] {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }
    let image = try #require(RawBufferDecoder.decode(data, width: 2, height: 1))
    #expect(image.width == 2)
    #expect(image.height == 1)
    #expect(abs(image.pixels[0] - 1000 / Float(65535)) < 1e-6)
}

@Test func uneTailleInattendueEstRefusee() {
    #expect(RawBufferDecoder.decode(Data(repeating: 0, count: 7), width: 4, height: 4) == nil)
}

@Test func laTrameReelleEstDecodee() throws {
    let payload = try Fixtures.frameData()
    let image = try #require(RawBufferDecoder.decode(payload, width: 1080, height: 1920))
    #expect(image.width == 540)
    #expect(image.height == 960)
    // La trame mesurée est saturée à 57 % : la valeur médiane doit être haute.
    let sorted = image.pixels.sorted()
    #expect(sorted[sorted.count / 2] > 0.9)
}
