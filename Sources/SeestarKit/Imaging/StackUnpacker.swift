import Foundation
import ZIPFoundation

/// Extrait le buffer brut d'une trame d'empilement.
///
/// D'après le code de seestar_alp, les trames `id=23` sont des archives ZIP
/// contenant une entrée `raw_data`. Hypothèse 2 de la spec, à confirmer sur
/// une session nocturne : d'ici là, `isArchive` permet de basculer sur le
/// traitement brut si la trame n'est pas zippée.
public enum StackUnpacker {
    public enum Erreur: Error, Equatable {
        case archiveIllisible
        case entreeAbsente
    }

    private static let entryName = "raw_data"

    /// Signature d'une archive ZIP : les deux octets « PK ».
    public static func isArchive(_ payload: Data) -> Bool {
        payload.count >= 2 && payload[payload.startIndex] == 0x50
            && payload[payload.startIndex + 1] == 0x4B
    }

    public static func unpack(_ payload: Data) throws -> Data {
        // `pathEncoding` explicite : sans lui, l'appel résout vers un
        // initialiseur déprécié qui ne lance pas d'erreur.
        guard let archive = try? Archive(data: payload, accessMode: .read, pathEncoding: nil)
        else {
            throw Erreur.archiveIllisible
        }
        guard let entry = archive[entryName] else {
            throw Erreur.entreeAbsente
        }
        var extracted = Data()
        _ = try archive.extract(entry, skipCRC32: true) { chunk in
            extracted.append(chunk)
        }
        return extracted
    }
}
