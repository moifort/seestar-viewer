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

    /// Rend la prochaine trame disponible, ou `nil` s'il manque des octets.
    public mutating func next() -> RawFrame? {
        while true {
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
