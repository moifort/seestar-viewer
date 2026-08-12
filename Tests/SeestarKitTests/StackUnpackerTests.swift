import Foundation
import Testing
import ZIPFoundation
@testable import SeestarKit

/// Fabrique une archive contenant une entrée `raw_data`, comme celle
/// qu'émet le télescope pour les images empilées.
///
/// ZIPFoundation ne publie pas les octets d'une archive créée en mémoire :
/// on passe donc par un fichier temporaire, seule voie publique.
func makeArchive(entryName: String, payload: Data, compressed: Bool) throws -> Data {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".zip")
    let archive = try Archive(url: url, accessMode: .create)
    try archive.addEntry(
        with: entryName,
        type: .file,
        uncompressedSize: Int64(payload.count),
        compressionMethod: compressed ? .deflate : .none,
        provider: { position, size in
            payload.subdata(in: Int(position)..<(Int(position) + size))
        }
    )
    defer { try? FileManager.default.removeItem(at: url) }
    return try Data(contentsOf: url)
}

@Test func uneArchiveCompresseeEstDepaquetee() throws {
    let contenu = Data(repeating: 0x42, count: 5000)
    let archive = try makeArchive(entryName: "raw_data", payload: contenu, compressed: true)
    #expect(try StackUnpacker.unpack(archive) == contenu)
}

@Test func uneArchiveStockeeEstDepaquetee() throws {
    // Hypothèse 2 de la spec : le télescope peut stocker sans compresser.
    let contenu = Data(repeating: 0x37, count: 5000)
    let archive = try makeArchive(entryName: "raw_data", payload: contenu, compressed: false)
    #expect(try StackUnpacker.unpack(archive) == contenu)
}

@Test func laSignatureZipEstReconnue() throws {
    let archive = try makeArchive(entryName: "raw_data", payload: Data([1, 2, 3]), compressed: true)
    #expect(StackUnpacker.isArchive(archive))
    #expect(!StackUnpacker.isArchive(Data([0xE0, 0xFF, 0x40, 0xF6])))
}

@Test func uneArchiveSansEntreeAttendueEchoue() throws {
    let archive = try makeArchive(entryName: "autre", payload: Data([1, 2, 3]), compressed: true)
    #expect(throws: StackUnpacker.Erreur.entreeAbsente) {
        try StackUnpacker.unpack(archive)
    }
}
