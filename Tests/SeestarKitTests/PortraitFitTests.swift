import CoreGraphics
import Testing
@testable import SeestarUI

/// La rotation de l'image ne dépend pas de la forme de l'écran mais de la
/// capacité de l'utilisateur à orienter l'appareil. Un téléviseur ne tourne
/// pas : c'est à l'image de s'adapter. Un iPhone tourne : on respecte le geste.

@Test func leTeleviseurFaitPivoterLImagePortrait() {
    #expect(PortraitFit.shouldRotate(policy: .fillWideScreen,
                                     container: CGSize(width: 1920, height: 1080)))
}

@Test func leTelephoneNeFaitJamaisPivoterLImage() {
    // Ni debout...
    #expect(!PortraitFit.shouldRotate(policy: .alwaysUpright,
                                      container: CGSize(width: 393, height: 852)))
    // ...ni couché : l'image reste dans son sens, encadrée de noir.
    #expect(!PortraitFit.shouldRotate(policy: .alwaysUpright,
                                      container: CGSize(width: 852, height: 393)))
}

@Test func laTabletteBasculeeNeFaitPasPivoterLImage() {
    #expect(!PortraitFit.shouldRotate(policy: .alwaysUpright,
                                      container: CGSize(width: 1180, height: 820)))
}

@Test func unEcranLargeMaisDeboutNeProvoquePasDeRotation() {
    // Cas theorique d'un ecran fige en portrait : rien a gagner a tourner.
    #expect(!PortraitFit.shouldRotate(policy: .fillWideScreen,
                                      container: CGSize(width: 1080, height: 1920)))
}

@Test func uneTailleVideNeProvoquePasDeRotation() {
    // SwiftUI passe une taille nulle au premier calcul de disposition.
    #expect(!PortraitFit.shouldRotate(policy: .fillWideScreen, container: .zero))
}

@Test func laPolitiqueDeLaPlateformeDeTestEstCelleDunAppareilOrientable() {
    // La suite tourne sur macOS : on doit y lire la politique iPhone/iPad.
    #expect(PortraitFit.platformPolicy == .alwaysUpright)
}

extension PortraitFit.Policy: Equatable {}
