import CoreGraphics
import Testing
@testable import SeestarUI

/// La barre de télémétrie doit tenir sur la largeur d'un iPhone. Quand elle
/// n'y tient pas, c'est à elle de prendre une ligne de plus : jamais aux mots
/// de se briser.

@Test func uneSeuleLigneQuandLaPlaceSuffit() {
    let rows = FlowLayout.rows(of: [100, 100, 100], spacing: 20, available: 400)
    #expect(rows == [[0, 1, 2]])
}

@Test func lesElementsPassentALaLigneQuandLaPlaceManque() {
    // 100 + 20 + 100 = 220 tiennent dans 240, le troisième non.
    let rows = FlowLayout.rows(of: [100, 100, 100], spacing: 20, available: 240)
    #expect(rows == [[0, 1], [2]])
}

@Test func unElementPlusLargeQueLEcranGardeSaLigne() {
    // Mieux vaut le voir déborder que le voir disparaître ou se briser.
    let rows = FlowLayout.rows(of: [50, 500, 50], spacing: 20, available: 200)
    #expect(rows == [[0], [1], [2]])
}

@Test func uneBarreSansElementNeProduitAucuneLigne() {
    #expect(FlowLayout.rows(of: [], spacing: 20, available: 400).isEmpty)
}

@Test func laLargeurExacteNeProvoquePasDeRetourALaLigne() {
    // Les largeurs mesurées par SwiftUI sont fractionnaires : une comparaison
    // trop stricte renverrait une ligne à la moindre poussière de virgule.
    let rows = FlowLayout.rows(of: [100, 100], spacing: 20, available: 220)
    #expect(rows == [[0, 1]])
}
