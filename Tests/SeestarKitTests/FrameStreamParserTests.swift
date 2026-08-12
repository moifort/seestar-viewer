import Foundation
import Testing
@testable import SeestarKit

@Test func leDecoupageRendUneTrameComplete() {
    var parser = FrameStreamParser()
    let payload = Data(repeating: 0xAB, count: 1000)
    parser.append(makeHeader(size: 1000, code: 0, id: 21, width: 10, height: 50) + payload)

    let frame = parser.next()
    #expect(frame?.id == 21)
    #expect(frame?.payload.count == 1000)
    #expect(parser.next() == nil)
}

@Test func leDecoupageAttendLesOctetsManquants() {
    var parser = FrameStreamParser()
    let payload = Data(repeating: 0xAB, count: 1000)
    let full = makeHeader(size: 1000, code: 0, id: 21, width: 10, height: 50) + payload

    // Arrivée en trois morceaux, comme sur un vrai socket.
    parser.append(full.prefix(40))
    #expect(parser.next() == nil)
    parser.append(full.dropFirst(40).prefix(500))
    #expect(parser.next() == nil)
    parser.append(full.dropFirst(540))
    #expect(parser.next()?.payload.count == 1000)
}

@Test func leDecoupageEnchaineDeuxTrames() {
    var parser = FrameStreamParser()
    let a = makeHeader(size: 4, code: 0, id: 21, width: 2, height: 1) + Data([1, 2, 3, 4])
    let b = makeHeader(size: 2, code: 0, id: 23, width: 1, height: 1) + Data([5, 6])
    parser.append(a + b)

    #expect(parser.next()?.id == 21)
    #expect(parser.next()?.id == 23)
    #expect(parser.next() == nil)
}

@Test func lesTramesDeTailleNulleSontIgnorees() {
    var parser = FrameStreamParser()
    let vide = makeHeader(size: 0, code: 0, id: 21, width: 0, height: 0)
    let utile = makeHeader(size: 2, code: 0, id: 21, width: 1, height: 1) + Data([7, 8])
    parser.append(vide + utile)

    #expect(parser.next()?.payload.count == 2)
}

@Test func leMessageTexteDuScopeEstReconnu() {
    var parser = FrameStreamParser()
    let texte = Data("only available for continuous exposure".utf8)
    parser.append(makeHeader(size: texte.count, code: 0, id: 21, width: 0, height: 0) + texte)

    let frame = parser.next()
    #expect(frame?.textMessage == "only available for continuous exposure")
}

@Test func uneAlerteJsonBruteNEstPasLueCommeUnEnTete() {
    // Mesuré sur le matériel : le scope envoie parfois une ligne JSON nue sur
    // le port 4800, sans en-tête binaire. Lue comme un en-tête, elle annonçait
    // une trame de 1,9 Go et faisait dérailler la connexion.
    var parser = FrameStreamParser()
    let alerte = #"{"Event":"Alert","Msg":"Exceed the maximum number of connections"}"#
    parser.append(Data((alerte + "\r\n").utf8))

    let frame = parser.next()
    #expect(frame?.textMessage == alerte)
    #expect(frame?.id == RawFrame.jsonLineID)
}

@Test func uneTrameBinaireSuivantUneAlerteResteLisible() {
    // Le flux doit se resynchroniser : après la ligne JSON, la trame suivante
    // se décode normalement.
    var parser = FrameStreamParser()
    let alerte = Data((#"{"Event":"Alert"}"# + "\r\n").utf8)
    let trame = makeHeader(size: 4, code: 0, id: 21, width: 2, height: 1) + Data([1, 2, 3, 4])
    parser.append(alerte + trame)

    #expect(parser.next()?.id == RawFrame.jsonLineID)
    #expect(parser.next()?.id == 21)
}

@Test func uneLigneJsonIncompleteEstAttendue() {
    var parser = FrameStreamParser()
    parser.append(Data(#"{"Event":"Al"#.utf8))
    #expect(parser.next() == nil)
    parser.append(Data((#"ert"}"# + "\r\n").utf8))
    #expect(parser.next()?.textMessage == #"{"Event":"Alert"}"#)
}

@Test func unePayloadBinaireNEstPasDuTexte() {
    var parser = FrameStreamParser()
    let binaire = Data(repeating: 0x00, count: 4_147_200)
    parser.append(makeHeader(size: binaire.count, code: 0, id: 21, width: 1080, height: 1920) + binaire)

    #expect(parser.next()?.textMessage == nil)
}
