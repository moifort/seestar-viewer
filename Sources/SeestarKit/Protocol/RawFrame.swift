import Foundation

/// Trame reçue du port 4800, telle quelle : aucune interprétation du contenu.
public struct RawFrame: Equatable, Sendable {
    /// 21 pour une preview, 23 pour une image empilée.
    public let id: UInt8
    public let width: Int
    public let height: Int
    public let payload: Data

    public init(id: UInt8, width: Int, height: Int, payload: Data) {
        self.id = id
        self.width = width
        self.height = height
        self.payload = payload
    }

    /// Le scope répond en clair pour signaler un état plutôt qu'une image :
    /// « done », « only available for continuous exposure »…
    /// Ces réponses sont courtes et sans octet nul.
    public var textMessage: String? {
        guard payload.count < 200, !payload.prefix(20).contains(0) else { return nil }
        return String(data: payload, encoding: .utf8)
    }
}
