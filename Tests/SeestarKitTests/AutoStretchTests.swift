import Foundation
import Testing
@testable import SeestarKit

@Test func laFonctionDeTransfertRespecteSesBornes() {
    #expect(abs(AutoStretch.midtoneTransfer(0, 0.25)) < 1e-6)
    #expect(abs(AutoStretch.midtoneTransfer(1, 0.25) - 1) < 1e-6)
}

@Test func laFonctionDeTransfertEclaircitLesTonsSombres() {
    // Avec un point médian bas, une valeur d'entrée doit ressortir plus claire.
    let sortie = AutoStretch.midtoneTransfer(0.1, 0.25)
    #expect(sortie > 0.1)
}

@Test func lEtirementRemonteUnFondSombre() {
    // Image linéaire très sombre, comme une brute astro : après étirement,
    // la médiane doit se rapprocher de la cible de fond.
    var pixels = [Float]()
    for i in 0..<(64 * 64 * 3) {
        pixels.append(0.01 + Float(i % 7) * 0.0005)
    }
    let image = RGBImage(width: 64, height: 64, pixels: pixels)

    let avant = image.pixels.sorted()[image.pixels.count / 2]
    let apres = AutoStretch.apply(image).pixels.sorted()[image.pixels.count / 2]

    #expect(avant < 0.05)
    #expect(apres > 0.15)
}

@Test func lEtirementResteDansLesBornes() {
    let pixels = (0..<(32 * 32 * 3)).map { Float($0 % 100) / 100 }
    let sortie = AutoStretch.apply(RGBImage(width: 32, height: 32, pixels: pixels))
    #expect(sortie.pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
}

@Test func uneImageUniformeNeProduitPasDeNaN() {
    // Écart absolu médian nul : le calcul doit rester défini.
    let pixels = [Float](repeating: 0.5, count: 16 * 16 * 3)
    let sortie = AutoStretch.apply(RGBImage(width: 16, height: 16, pixels: pixels))
    #expect(sortie.pixels.allSatisfy { $0.isFinite })
}
