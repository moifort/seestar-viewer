import Foundation
import Testing
@testable import SeestarKit

@Test func lAdresseManuellePrimeSurLaDecouverte() async {
    // Une IP saisie par l'utilisateur court-circuite le mDNS : c'est le repli
    // quand Bonjour ne répond pas sur le réseau.
    let hote = await SeestarDiscovery.resolve(manualHost: "192.168.1.42")
    #expect(hote == "192.168.1.42")
}

@Test func uneAdresseManuelleVideEstIgnoree() async {
    let hote = await SeestarDiscovery.resolve(manualHost: "   ")
    #expect(hote != "   ")
}

@Test func lHoteBonjourEstCeluiMesure() {
    #expect(SeestarDiscovery.bonjourHost == "seestar.local")
}
