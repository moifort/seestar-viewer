import Foundation
import Testing
@testable import SeestarKit

/// Fabrique un en-tête de 80 octets au format mesuré :
/// 20 octets utiles en big-endian ">HHHIHHBBHH", le reste ignoré.
func makeHeader(size: Int, code: UInt8, id: UInt8, width: Int, height: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: 80)
    func putU16(_ value: Int, at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }
    func putU32(_ value: Int, at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }
    putU32(size, at: 6)
    bytes[14] = code
    bytes[15] = id
    putU16(width, at: 16)
    putU16(height, at: 18)
    return Data(bytes)
}

@Test func lEnTeteDecodeLesChampsMesures() throws {
    let data = makeHeader(size: 4_147_200, code: 0, id: 21, width: 1080, height: 1920)
    let header = try #require(FrameHeader(data))
    #expect(header.size == 4_147_200)
    #expect(header.id == 21)
    #expect(header.width == 1080)
    #expect(header.height == 1920)
}

@Test func lEnTeteRefuseUnTamponTropCourt() {
    #expect(FrameHeader(Data(repeating: 0, count: 19)) == nil)
}

@Test func lEnTeteAccepteUneTailleNulle() throws {
    // Le scope émet des trames de taille 0 qu'il faut savoir ignorer sans planter.
    let header = try #require(FrameHeader(makeHeader(size: 0, code: 0, id: 21, width: 0, height: 0)))
    #expect(header.size == 0)
}
