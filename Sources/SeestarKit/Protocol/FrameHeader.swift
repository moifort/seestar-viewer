import Foundation

/// En-tête binaire précédant chaque trame du port 4800.
///
/// Mesuré sur le matériel : 80 octets, dont seuls les 20 premiers portent
/// de l'information, en big-endian, au format ">HHHIHHBBHH".
public struct FrameHeader: Equatable, Sendable {
    /// Taille totale de l'en-tête sur le fil.
    public static let byteCount = 80

    /// Nombre d'octets de charge utile qui suivent l'en-tête.
    public let size: Int
    public let code: UInt8
    /// 21 pour une preview, 23 pour une image empilée.
    public let id: UInt8
    public let width: Int
    public let height: Int

    public init?(_ data: Data) {
        let bytes = [UInt8](data.prefix(20))
        guard bytes.count == 20 else { return nil }

        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }

        self.size = u32(6)
        self.code = bytes[14]
        self.id = bytes[15]
        self.width = u16(16)
        self.height = u16(18)
    }
}
