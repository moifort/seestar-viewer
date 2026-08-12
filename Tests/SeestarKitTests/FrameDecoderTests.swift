import CoreGraphics
import Foundation
import Testing
@testable import SeestarKit

@Test func leRenduProduitUneImageAuxBonnesDimensions() throws {
    let pixels = [Float](repeating: 0.5, count: 4 * 3 * 3)
    let image = try #require(ImageRenderer.render(RGBImage(width: 4, height: 3, pixels: pixels)))
    #expect(image.width == 4)
    #expect(image.height == 3)
}

@Test func laChaineCompleteDecodeLaTrameReelle() throws {
    let frame = RawFrame(id: 21, width: 1080, height: 1920, payload: try Fixtures.frameData())
    let decoded = try #require(FrameDecoder.decode(frame))
    #expect(decoded.kind == .preview)
    // Binning 2x2 : la trame 1080x1920 rend une image 540x960.
    #expect(decoded.image.width == 540)
    #expect(decoded.image.height == 960)
}

@Test func unMessageTexteNeProduitPasDImage() {
    let payload = Data("only available for continuous exposure".utf8)
    let frame = RawFrame(id: 21, width: 0, height: 0, payload: payload)
    #expect(FrameDecoder.decode(frame) == nil)
}

@Test func uneTailleIncoherenteEstRejeteeSansPlanter() {
    let frame = RawFrame(id: 21, width: 1080, height: 1920, payload: Data(repeating: 0, count: 99))
    #expect(FrameDecoder.decode(frame) == nil)
}

@Test func uneTrameNonZippeeEstTraiteeCommeUnBufferBrut() throws {
    // Filet de sécurité tant que l'hypothèse 2 n'est pas levée : si la trame
    // d'empilement n'est pas une archive, on la lit directement.
    var payload = Data()
    for value: UInt16 in [1000, 2000, 3000, 4000, 5000, 6000] {
        payload.append(UInt8(value & 0xFF))
        payload.append(UInt8((value >> 8) & 0xFF))
    }
    let frame = RawFrame(id: 23, width: 2, height: 1, payload: payload)
    let decoded = try #require(FrameDecoder.decode(frame))
    #expect(decoded.kind == .stack)
    #expect(decoded.image.width == 2)
}

@Test func uneTrameDEmpilementZippeeEstDecodee() throws {
    // Chemin nominal supposé pour id=23 : archive contenant `raw_data`.
    var buffer = Data()
    for value: UInt16 in [1000, 2000, 3000, 4000, 5000, 6000] {
        buffer.append(UInt8(value & 0xFF))
        buffer.append(UInt8((value >> 8) & 0xFF))
    }
    let archive = try makeArchive(entryName: "raw_data", payload: buffer, compressed: true)
    let frame = RawFrame(id: 23, width: 2, height: 1, payload: archive)

    let decoded = try #require(FrameDecoder.decode(frame))
    #expect(decoded.kind == .stack)
    #expect(decoded.image.width == 2)
    #expect(decoded.image.height == 1)
}
