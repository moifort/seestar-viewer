import Foundation
import Testing
@testable import SeestarKit

@Test func lesEvenementsReelsSontTousDecodes() throws {
    var parser = EventStreamParser()
    for line in try Fixtures.eventLines() {
        parser.append(Data((line + "\r\n").utf8))
    }
    var noms: [String] = []
    while let event = parser.next() { noms.append(event.name) }

    #expect(noms.count == 11)
    #expect(noms.contains("PiStatus"))
    #expect(noms.contains("View"))
    #expect(noms.contains("ContinuousExposure"))
    #expect(noms.contains("ScopeTrack"))
}

@Test func leModeDeVueEstExtrait() {
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"View","Timestamp":"1360.9","state":"cancel","mode":"scenery"}"#.utf8))
    parser.append(Data("\r\n".utf8))

    let event = parser.next()
    #expect(event?.name == "View")
    #expect(event?.mode == "scenery")
    #expect(event?.state == "cancel")
    #expect(event?.timestamp == 1360.9)
}

@Test func laTelemetrieEstExtraite() {
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus","Timestamp":"82.4","battery_capacity":100,"temp":56.3}"#.utf8))
    parser.append(Data("\r\n".utf8))

    let event = parser.next()
    #expect(event?.batteryCapacity == 100)
    #expect(event?.temperature == 56.3)
}

@Test func leDecoupageAttendLaFinDeLigne() {
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus"}"#.utf8))
    #expect(parser.next() == nil)
    parser.append(Data("\r\n".utf8))
    #expect(parser.next()?.name == "PiStatus")
}

@Test func uneLigneInvalideEstIgnoreeSansBloquerLaSuite() {
    var parser = EventStreamParser()
    parser.append(Data("ceci n'est pas du json\r\n".utf8))
    parser.append(Data(#"{"Event":"PiStatus"}"#.utf8))
    parser.append(Data("\r\n".utf8))

    #expect(parser.next()?.name == "PiStatus")
}
