import Foundation
import Network

/// Connexion directe au télescope, un socket par canal.
///
/// Les deux canaux sont indépendants : la chute de l'un n'affecte pas l'autre.
/// Chacun se reconnecte seul, avec un délai exponentiel plafonné.
public actor DirectTransport: SeestarTransport {
    public static let controlPort: UInt16 = 4700
    public static let imagingPort: UInt16 = 4800

    /// Seule commande jamais envoyée au télescope, et uniquement sur le 4800.
    public static let beginStreamingCommand =
        Data(#"{"id": 21, "method": "begin_streaming"}"#.utf8) + Data("\r\n".utf8)

    private let host: NWEndpoint.Host
    private var imagingConnection: NWConnection?
    private var controlConnection: NWConnection?
    private var frameContinuation: AsyncStream<RawFrame>.Continuation?
    private var eventContinuation: AsyncStream<SeestarEvent>.Continuation?
    private var running = false

    public init(host: String) {
        self.host = NWEndpoint.Host(host)
    }

    /// `bufferingNewest(1)` est une exigence de la spec, pas un détail : une
    /// trame pèse 4 Mo et arrive chaque seconde. Si le décodage prend du
    /// retard, on jette la trame en retard au lieu de l'empiler en mémoire.
    public nonisolated func frames() -> AsyncStream<RawFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            Task { await self.setFrameContinuation(continuation) }
        }
    }

    public nonisolated func events() -> AsyncStream<SeestarEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            Task { await self.setEventContinuation(continuation) }
        }
    }

    private func setFrameContinuation(_ continuation: AsyncStream<RawFrame>.Continuation) {
        frameContinuation = continuation
    }

    private func setEventContinuation(_ continuation: AsyncStream<SeestarEvent>.Continuation) {
        eventContinuation = continuation
    }

    public func start() async {
        guard !running else { return }
        running = true
        Task { await runImaging(attempt: 0) }
        Task { await runControl(attempt: 0) }
    }

    public func stop() async {
        running = false
        imagingConnection?.cancel()
        controlConnection?.cancel()
        imagingConnection = nil
        controlConnection = nil
        frameContinuation?.finish()
        eventContinuation?.finish()
    }

    /// Délai exponentiel plafonné à 30 secondes.
    private func backoff(_ attempt: Int) -> Duration {
        .seconds(min(30, 1 << min(attempt, 5)))
    }

    // MARK: - Canal d'imagerie

    private func runImaging(attempt: Int) async {
        guard running else { return }
        let connection = NWConnection(
            host: host, port: .init(rawValue: Self.imagingPort)!, using: .tcp
        )
        imagingConnection = connection
        var parser = FrameStreamParser()

        // Seul envoi de toute l'application, et uniquement une fois la
        // connexion prête.
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.send(
                content: Self.beginStreamingCommand,
                completion: .contentProcessed { _ in }
            )
        }
        connection.start(queue: .global(qos: .userInitiated))

        while running {
            guard let data = await receive(on: connection) else { break }
            parser.append(data)
            while let frame = parser.next() {
                frameContinuation?.yield(frame)
            }
        }

        connection.cancel()
        guard running else { return }
        try? await Task.sleep(for: backoff(attempt))
        await runImaging(attempt: attempt + 1)
    }

    // MARK: - Canal d'événements (lecture stricte)

    private func runControl(attempt: Int) async {
        guard running else { return }
        let connection = NWConnection(
            host: host, port: .init(rawValue: Self.controlPort)!, using: .tcp
        )
        controlConnection = connection
        var parser = EventStreamParser()

        // On n'écrit jamais sur ce socket : les commandes non authentifiées
        // sont ignorées, et un socket insistant se fait couper.
        connection.start(queue: .global(qos: .utility))

        while running {
            guard let data = await receive(on: connection) else { break }
            parser.append(data)
            while let event = parser.next() {
                eventContinuation?.yield(event)
            }
        }

        connection.cancel()
        guard running else { return }
        try? await Task.sleep(for: backoff(attempt))
        await runControl(attempt: attempt + 1)
    }

    private func receive(on connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
                data, _, isComplete, error in
                // `nil` signale la fin du canal et déclenche la reconnexion.
                if error != nil || (isComplete && (data?.isEmpty ?? true)) {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
