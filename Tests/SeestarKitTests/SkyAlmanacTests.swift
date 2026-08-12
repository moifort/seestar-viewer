import Foundation
import Testing
@testable import SeestarKit

/// Instant UTC, pour comparer aux éphémérides publiées.
private func utc(_ description: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: description)!
}

@Test func laNouvelleLuneEstNoire() {
    // Nouvelle lune du 11 janvier 2024 à 11h57 UTC.
    let phase = MoonPhase(date: utc("2024-01-11 11:57"))
    #expect(phase.percentage == 0)
}

@Test func laPleineLuneEstEntiere() {
    // Pleine lune du 25 janvier 2024 à 17h54 UTC.
    let phase = MoonPhase(date: utc("2024-01-25 17:54"))
    #expect(phase.percentage == 100)
}

@Test func lePremierQuartierEstAMoitieEclaireEtCroissant() {
    let phase = MoonPhase(date: utc("2024-01-18 03:53"))
    #expect(abs(phase.illuminatedFraction - 0.5) < 0.02)
    #expect(phase.isWaxing)
}

@Test func leDernierQuartierDecroit() {
    let phase = MoonPhase(date: utc("2024-02-02 23:18"))
    #expect(abs(phase.illuminatedFraction - 0.5) < 0.02)
    #expect(!phase.isWaxing)
}

@Test func leSoleilDeParisSeLeveEtSeCoucheAuSolstice() {
    // Solstice d'été : lever 03h47 UTC, coucher 19h58 UTC à Paris.
    let sun = SunTimes(date: utc("2024-06-21 12:00"), latitude: 48.8566, longitude: 2.3522)
    #expect(abs(sun.sunrise!.timeIntervalSince(utc("2024-06-21 03:47"))) < 120)
    #expect(abs(sun.sunset!.timeIntervalSince(utc("2024-06-21 19:58"))) < 120)
}

@Test func leSoleilDeParisTientLaJourneeLaPlusCourte() {
    // Solstice d'hiver : lever 07h41 UTC, coucher 15h56 UTC.
    let sun = SunTimes(date: utc("2024-12-21 12:00"), latitude: 48.8566, longitude: 2.3522)
    #expect(abs(sun.sunrise!.timeIntervalSince(utc("2024-12-21 07:41"))) < 120)
    #expect(abs(sun.sunset!.timeIntervalSince(utc("2024-12-21 15:56"))) < 120)
}

@Test func leSoleilDeMinuitNAniLeverNiCoucher() {
    // Tromsø au solstice d'été : le soleil ne passe pas sous l'horizon.
    let sun = SunTimes(date: utc("2024-06-21 12:00"), latitude: 69.65, longitude: 18.96)
    #expect(sun.sunrise == nil)
    #expect(sun.sunset == nil)
}

@Test func lesHorairesSontCeuxDuJourDemande() {
    // Une nuit d'observation en cours : les deux bornes doivent rester dans la
    // journée civile locale, sans sauter au lendemain.
    let sun = SunTimes(date: utc("2024-08-15 22:00"), latitude: 48.8566, longitude: 2.3522)
    let calendar = Calendar(identifier: .gregorian)
    var utcCalendar = calendar
    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
    #expect(utcCalendar.isDate(sun.sunrise!, inSameDayAs: utc("2024-08-15 12:00")))
    #expect(utcCalendar.isDate(sun.sunset!, inSameDayAs: utc("2024-08-15 12:00")))
}
