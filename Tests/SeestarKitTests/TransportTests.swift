import Foundation
import Testing
@testable import SeestarKit

/// Transport de test : rejoue des trames sans ouvrir de socket.
/// Prouve que le reste du code ne dépend pas de la connexion directe —
/// c'est ce qui permettra d'ajouter un relais sans rien réécrire.
final class TransportFactice: SeestarTransport {
    private let tramesAEmettre: [RawFrame]
    private let evenementsAEmettre: [SeestarEvent]

    init(trames: [RawFrame], evenements: [SeestarEvent] = []) {
        self.tramesAEmettre = trames
        self.evenementsAEmettre = evenements
    }

    func frames() -> AsyncStream<RawFrame> {
        let trames = tramesAEmettre
        return AsyncStream { continuation in
            for frame in trames { continuation.yield(frame) }
            continuation.finish()
        }
    }

    func events() -> AsyncStream<SeestarEvent> {
        let evenements = evenementsAEmettre
        return AsyncStream { continuation in
            for event in evenements { continuation.yield(event) }
            continuation.finish()
        }
    }

    func start() async {}
    func stop() async {}
}

@Test func leTransportFacticeEmetSesTrames() async {
    let trame = RawFrame(id: 21, width: 2, height: 2, payload: Data(repeating: 1, count: 8))
    let transport = TransportFactice(trames: [trame, trame])

    var recues = 0
    for await _ in transport.frames() { recues += 1 }
    #expect(recues == 2)
}

@Test func laCommandeDeDemarrageEstConformeAuProtocole() {
    // Un seul octet ne doit jamais être écrit sur le 4800, et jamais rien sur le 4700.
    #expect(DirectTransport.beginStreamingCommand
        == Data(#"{"id": 21, "method": "begin_streaming"}"#.utf8) + Data("\r\n".utf8))
}

@Test func lesPortsSontCeuxMesures() {
    #expect(DirectTransport.controlPort == 4700)
    #expect(DirectTransport.imagingPort == 4800)
}
