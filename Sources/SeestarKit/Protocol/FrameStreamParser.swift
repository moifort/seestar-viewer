import Foundation

/// Reconstitue des trames complètes à partir d'octets arrivant par morceaux.
///
/// Un socket ne respecte aucune frontière de message : on accumule jusqu'à
/// disposer de l'en-tête puis de la charge utile annoncée.
public struct FrameStreamParser: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    private static let lineSeparator = Data("\r\n".utf8)
    private static let openingBrace = UInt8(ascii: "{")

    /// Rend la prochaine trame disponible, ou `nil` s'il manque des octets.
    public mutating func next() -> RawFrame? {
        while true {
            // Le scope glisse parfois une ligne JSON nue dans ce flux, sans
            // en-tête binaire — mesuré avec l'alerte de saturation des
            // connexions. Lue comme un en-tête, elle annonce une taille
            // délirante et fait dérailler la lecture : on la reconnaît à son
            // accolade ouvrante et on la consomme jusqu'au saut de ligne.
            if let first = buffer.first, first == Self.openingBrace {
                guard let range = buffer.range(of: Self.lineSeparator) else { return nil }
                let line = Data(buffer[buffer.startIndex..<range.lowerBound])
                buffer = Data(buffer[range.upperBound...])
                return RawFrame(id: RawFrame.jsonLineID, width: 0, height: 0, payload: line)
            }

            guard buffer.count >= FrameHeader.byteCount,
                  let header = FrameHeader(Data(buffer.prefix(20)))
            else { return nil }

            let total = FrameHeader.byteCount + header.size
            guard buffer.count >= total else { return nil }

            let payload = Data(buffer.prefix(total).dropFirst(FrameHeader.byteCount))
            // On rebase systématiquement : les index d'un Data tranché ne
            // repartent pas de zéro, source classique de bogues.
            buffer = Data(buffer.dropFirst(total))

            // Une trame vide n'est pas une erreur, seulement du remplissage.
            if header.size == 0 { continue }

            return RawFrame(
                id: header.id,
                width: header.width,
                height: header.height,
                payload: payload
            )
        }
    }
}
