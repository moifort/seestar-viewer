import CoreGraphics
import Foundation

public enum FrameKind: Sendable {
    case preview
    case stack
}

public struct DecodedFrame: @unchecked Sendable {
    public let kind: FrameKind
    public let image: CGImage
    public var width: Int { image.width }
    public var height: Int { image.height }
}

/// Chaîne complète : trame brute → buffer → étirement → image affichable.
///
/// Seule unité à connaître le format des données. Toute évolution du protocole
/// se corrige ici, sans toucher au transport ni à l'affichage.
public enum FrameDecoder {
    public static func decode(_ frame: RawFrame) -> DecodedFrame? {
        // Une réponse en clair du scope n'est pas une image.
        guard frame.textMessage == nil else { return nil }

        let kind: FrameKind = frame.id == 23 ? .stack : .preview

        var buffer = frame.payload
        if kind == .stack, StackUnpacker.isArchive(buffer) {
            guard let extracted = try? StackUnpacker.unpack(buffer) else { return nil }
            buffer = extracted
        }

        guard let linear = RawBufferDecoder.decode(
            buffer, width: frame.width, height: frame.height
        ) else { return nil }

        guard let image = ImageRenderer.render(AutoStretch.apply(linear)) else { return nil }
        return DecodedFrame(kind: kind, image: image)
    }
}
