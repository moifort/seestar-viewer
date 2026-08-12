import Foundation
import Testing
@testable import SeestarKit

/// Trame RGB 16 bits minimale, décodable sans passer par le Bayer.
func trameRGB(id: UInt8, width: Int = 2, height: Int = 1) -> RawFrame {
    var payload = Data()
    for _ in 0..<(width * height * 3) {
        payload.append(0x00)
        payload.append(0x80)  // 0x8000, une valeur médiane
    }
    return RawFrame(id: id, width: width, height: height, payload: payload)
}

@MainActor
@Test func lEmpilementPrendLaPlaceDuLive() {
    let model = ViewerModel()
    let debut = Date()

    model.consume(trameRGB(id: 21), at: debut)
    #expect(model.displayedFrame?.kind == .preview)

    model.consume(trameRGB(id: 23), at: debut.addingTimeInterval(1))
    #expect(model.displayedFrame?.kind == .stack)
    #expect(model.status == .stacking)
}

@MainActor
@Test func leLiveNeRemplacePasUnEmpilementRecent() {
    let model = ViewerModel()
    let debut = Date()
    model.consume(trameRGB(id: 23), at: debut)
    model.consume(trameRGB(id: 21), at: debut.addingTimeInterval(5))

    // L'empilement reste à l'écran tant qu'il est frais.
    #expect(model.displayedFrame?.kind == .stack)
}

@MainActor
@Test func leLiveRevientQuandLEmpilementSeTait() {
    let model = ViewerModel()
    let debut = Date()
    model.consume(trameRGB(id: 23), at: debut)
    // Au-delà du délai de péremption, le live reprend la main.
    model.consume(trameRGB(id: 21), at: debut.addingTimeInterval(ViewerModel.stackExpiry + 1))

    #expect(model.displayedFrame?.kind == .preview)
    #expect(model.status == .live)
}

@MainActor
@Test func laDerniereImageEstConserveeQuandToutSarrete() {
    let model = ViewerModel()
    model.consume(trameRGB(id: 23), at: Date())
    model.connectionLost()

    // Règle d'or : jamais d'écran noir.
    #expect(model.displayedFrame != nil)
    #expect(model.status == .disconnected)
}

@MainActor
@Test func leMessageDAttenteNEstPasUneErreur() {
    let model = ViewerModel()
    let attente = RawFrame(id: 21, width: 0, height: 0,
                           payload: Data("only available for continuous exposure".utf8))
    model.consume(attente, at: Date())

    #expect(model.status == .waitingForExposure)
    #expect(model.displayedFrame == nil)
}

@MainActor
@Test func toutSigneDeVieSortDeLEtatDeRecherche() {
    // Mesuré sur le vrai S30 : au repos il répond « done » à begin_streaming
    // puis n'envoie plus rien. On est connecté, pas en train de chercher.
    let model = ViewerModel()
    #expect(model.status == .searching)

    let done = RawFrame(id: 21, width: 0, height: 0, payload: Data("done".utf8))
    model.consume(done, at: Date())
    #expect(model.status == .waitingForExposure)
}

@MainActor
@Test func unEvenementSuffitAProuverLaConnexion() {
    let model = ViewerModel()
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus","temp":40.0}"#.utf8))
    parser.append(Data("\r\n".utf8))
    model.consume(parser.next()!)

    #expect(model.status == .waitingForExposure)
}

@MainActor
@Test func unEvenementNeDegradePasUnAffichageEnCours() {
    // La télémétrie ne doit jamais faire reculer l'état d'affichage.
    let model = ViewerModel()
    model.consume(trameRGB(id: 23), at: Date())
    #expect(model.status == .stacking)

    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus","temp":40.0}"#.utf8))
    parser.append(Data("\r\n".utf8))
    model.consume(parser.next()!)

    #expect(model.status == .stacking)
}

@MainActor
@Test func laTelemetrieEstMiseAJour() {
    let model = ViewerModel()
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus","battery_capacity":87,"temp":41.5}"#.utf8))
    parser.append(Data("\r\n".utf8))
    model.consume(parser.next()!)

    #expect(model.telemetry.batteryCapacity == 87)
    #expect(model.telemetry.temperature == 41.5)
}
