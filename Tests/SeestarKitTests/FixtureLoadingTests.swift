import Foundation
import Testing
@testable import SeestarKit

/// Accès aux données réelles capturées sur le Seestar le 2026-08-12.
enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    /// Trame de preview mesurée : 1080x1920, Bayer 16 bits, 4 147 200 octets.
    static func frameData() throws -> Data {
        try Data(contentsOf: url("frame_21_000_1080x1920.bin"))
    }

    static func eventLines() throws -> [String] {
        let text = try String(contentsOf: url("events.jsonl"), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }
}

@Test func lesJeuxDEssaiSontChargeables() throws {
    let frame = try Fixtures.frameData()
    #expect(frame.count == 4_147_200)
    #expect(frame.count == 1080 * 1920 * 2)

    let events = try Fixtures.eventLines()
    #expect(events.count == 11)
}
