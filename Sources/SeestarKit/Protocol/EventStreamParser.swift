import Foundation

/// Découpe le flux du port 4700 en événements.
///
/// Le protocole est une ligne JSON par message, terminée par `\r\n`.
public struct EventStreamParser: Sendable {
    private var buffer = Data()
    private static let separator = Data("\r\n".utf8)

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    public mutating func next() -> SeestarEvent? {
        while let range = buffer.range(of: Self.separator) {
            let line = Data(buffer[buffer.startIndex..<range.lowerBound])
            buffer = Data(buffer[range.upperBound...])

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let json = object as? [String: Any],
                  let event = SeestarEvent(json: json)
            else { continue }  // Ligne illisible : on l'écarte sans bloquer le flux.

            return event
        }
        return nil
    }
}
