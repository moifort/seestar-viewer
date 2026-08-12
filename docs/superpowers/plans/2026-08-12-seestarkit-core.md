# SeestarKit — Plan d'implémentation du cœur

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire `SeestarKit`, le package Swift qui découvre un Seestar S30 sur le réseau local, reçoit son flux d'événements et ses trames d'image, et les transforme en images affichables — sans aucune dépendance à SwiftUI ni à une plateforme d'affichage.

**Architecture:** Trois couches strictement séparées. Le **protocole** découpe les octets en trames et en événements, sans rien interpréter. L'**imagerie** transforme une trame en `CGImage` par des fonctions pures. Le **transport** gère les sockets derrière une interface, pour que la connexion directe puisse être remplacée par un relais sans toucher au reste. Un `ViewerModel` arbitre au-dessus.

**Tech Stack:** Swift 6, Swift Testing, Network.framework, Core Graphics, ZIPFoundation.

## Global Constraints

- Plateformes : `tvOS 17`, `iOS 17`, `macOS 14`. macOS est inclus pour que les tests unitaires tournent en ligne de commande sur le Mac.
- Aucun test unitaire n'ouvre de socket. Les analyseurs sont alimentés par des `Data` en mémoire.
- Les commentaires et les messages sont en français, comme les outils Python déjà présents.
- **Le port 4700 est en lecture stricte.** Aucun octet n'est jamais écrit dessus : les commandes non authentifiées sont ignorées et un socket insistant se fait couper par le télescope.
- Le seul octet écrit sur le port 4800 est `{"id": 21, "method": "begin_streaming"}\r\n`, une fois par connexion.
- Trames mesurées le 2026-08-12 : en-tête de 80 octets, 20 premiers utiles en big-endian ; preview `id=21` en 1080×1920, 4 147 200 octets, Bayer 16 bits little-endian.
- L'oracle des tests de décodage est `decode_frame.py`, validé sur trame réelle.
- Deux hypothèses restent ouvertes (§8 de la spec) : le motif de Bayer `GRBG` et l'encapsulation ZIP des trames d'empilement. Le code les isole et les rend interchangeables.

---

## Structure des fichiers

```
Package.swift
Sources/SeestarKit/
  Protocol/
    FrameHeader.swift          en-tête binaire de 80 octets
    RawFrame.swift             trame brute, non interprétée
    FrameStreamParser.swift    découpage incrémental du flux 4800
    SeestarEvent.swift         modèle des événements
    EventStreamParser.swift    découpage \r\n et décodage du flux 4700
  Imaging/
    RGBImage.swift             image flottante intermédiaire
    RawBufferDecoder.swift     buffer 16 bits -> RGBImage (Bayer ou RGB)
    StackUnpacker.swift        archive ZIP -> buffer brut
    AutoStretch.swift          étirement d'histogramme
    ImageRenderer.swift        RGBImage -> CGImage
    FrameDecoder.swift         assemble la chaîne complète
  Transport/
    SeestarTransport.swift     interface de transport
    DirectTransport.swift      connexion directe par NWConnection
    SeestarDiscovery.swift     résolution Bonjour et repli sur IP
  ViewerModel.swift            arbitrage empilement / live et états
Tests/SeestarKitTests/
  FrameHeaderTests.swift
  FrameStreamParserTests.swift
  EventStreamParserTests.swift
  RawBufferDecoderTests.swift
  AutoStretchTests.swift
  FrameDecoderTests.swift
  ViewerModelTests.swift
  Fixtures/
    frame_21_000_1080x1920.bin
    events.jsonl
Tools/fake_seestar.py          rejoue une session enregistrée
```

---

### Task 1: Squelette du package et jeux d'essai

**Files:**
- Create: `Package.swift`
- Create: `Sources/SeestarKit/SeestarKit.swift`
- Create: `Tests/SeestarKitTests/FixtureLoadingTests.swift`
- Create: `Tests/SeestarKitTests/Fixtures/frame_21_000_1080x1920.bin` (copie)
- Create: `Tests/SeestarKitTests/Fixtures/events.jsonl` (copie)

**Interfaces:**
- Consumes: rien
- Produces: `Fixtures.frameData()` et `Fixtures.eventLines()`, utilisés par toutes les tâches suivantes pour charger les données réelles.

- [ ] **Step 1: Créer le manifeste du package**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeestarKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeestarKit", targets: ["SeestarKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "SeestarKit",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .testTarget(
            name: "SeestarKitTests",
            dependencies: ["SeestarKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Copier les jeux d'essai**

```bash
mkdir -p Tests/SeestarKitTests/Fixtures Sources/SeestarKit
cp fixtures/frame_21_000_1080x1920.bin Tests/SeestarKitTests/Fixtures/
cp fixtures/events.jsonl Tests/SeestarKitTests/Fixtures/
```

- [ ] **Step 3: Créer le point d'entrée du module**

`Sources/SeestarKit/SeestarKit.swift` :

```swift
import Foundation

/// Espace de noms du paquet. Les types utiles sont définis dans les
/// sous-dossiers Protocol, Imaging et Transport.
public enum SeestarKit {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Écrire le test de chargement des jeux d'essai**

`Tests/SeestarKitTests/FixtureLoadingTests.swift` :

```swift
import Foundation
import Testing
@testable import SeestarKit

/// Accès aux données réelles capturées sur le Seestar le 2026-08-12.
enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    /// Trame de preview mesurée : 1080x1920, Bayer 16 bits, 4 147 200 octets.
    static func frameData() throws -> Data {
        try Data(contentsOf: url("frame_21_000_1080x1920.bin"))
    }

    static func eventLines() throws -> [String] {
        let text = try String(contentsOf: url("events.jsonl"), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }
}

@Test func lesJeuxDEssaiSontChargeables() throws {
    let frame = try Fixtures.frameData()
    #expect(frame.count == 4_147_200)
    #expect(frame.count == 1080 * 1920 * 2)

    let events = try Fixtures.eventLines()
    #expect(events.count == 11)
}
```

- [ ] **Step 5: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter lesJeuxDEssaiSontChargeables`
Expected: PASS, 1 test.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat(kit): squelette du package SeestarKit et jeux d'essai réels"
```

---

### Task 2: Décodage de l'en-tête de trame

**Files:**
- Create: `Sources/SeestarKit/Protocol/FrameHeader.swift`
- Test: `Tests/SeestarKitTests/FrameHeaderTests.swift`

**Interfaces:**
- Consumes: rien
- Produces: `FrameHeader(_ data: Data) -> FrameHeader?` avec les propriétés `size: Int`, `code: UInt8`, `id: UInt8`, `width: Int`, `height: Int`, et la constante `FrameHeader.byteCount = 80`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/FrameHeaderTests.swift` :

```swift
import Foundation
import Testing
@testable import SeestarKit

/// Fabrique un en-tête de 80 octets au format mesuré :
/// 20 octets utiles en big-endian ">HHHIHHBBHH", le reste ignoré.
func makeHeader(size: Int, code: UInt8, id: UInt8, width: Int, height: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: 80)
    func putU16(_ value: Int, at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }
    func putU32(_ value: Int, at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }
    putU32(size, at: 6)
    bytes[14] = code
    bytes[15] = id
    putU16(width, at: 16)
    putU16(height, at: 18)
    return Data(bytes)
}

@Test func lEnTeteDecodeLesChampsMesures() throws {
    let data = makeHeader(size: 4_147_200, code: 0, id: 21, width: 1080, height: 1920)
    let header = try #require(FrameHeader(data))
    #expect(header.size == 4_147_200)
    #expect(header.id == 21)
    #expect(header.width == 1080)
    #expect(header.height == 1920)
}

@Test func lEnTeteRefuseUnTamponTropCourt() {
    #expect(FrameHeader(Data(repeating: 0, count: 19)) == nil)
}

@Test func lEnTeteAccepteUneTailleNulle() throws {
    // Le scope émet des trames de taille 0 qu'il faut savoir ignorer sans planter.
    let header = try #require(FrameHeader(makeHeader(size: 0, code: 0, id: 21, width: 0, height: 0)))
    #expect(header.size == 0)
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter FrameHeader`
Expected: FAIL — `cannot find 'FrameHeader' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/SeestarKit/Protocol/FrameHeader.swift` :

```swift
import Foundation

/// En-tête binaire précédant chaque trame du port 4800.
///
/// Mesuré sur le matériel : 80 octets, dont seuls les 20 premiers portent
/// de l'information, en big-endian, au format ">HHHIHHBBHH".
public struct FrameHeader: Equatable, Sendable {
    /// Taille totale de l'en-tête sur le fil.
    public static let byteCount = 80

    /// Nombre d'octets de charge utile qui suivent l'en-tête.
    public let size: Int
    public let code: UInt8
    /// 21 pour une preview, 23 pour une image empilée.
    public let id: UInt8
    public let width: Int
    public let height: Int

    public init?(_ data: Data) {
        let bytes = [UInt8](data.prefix(20))
        guard bytes.count == 20 else { return nil }

        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }

        self.size = u32(6)
        self.code = bytes[14]
        self.id = bytes[15]
        self.width = u16(16)
        self.height = u16(18)
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter FrameHeader`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SeestarKit/Protocol/FrameHeader.swift Tests/SeestarKitTests/FrameHeaderTests.swift
git commit -m "feat(kit): décodage de l'en-tête de trame du port 4800"
```

---

### Task 3: Découpage incrémental du flux binaire

**Files:**
- Create: `Sources/SeestarKit/Protocol/RawFrame.swift`
- Create: `Sources/SeestarKit/Protocol/FrameStreamParser.swift`
- Test: `Tests/SeestarKitTests/FrameStreamParserTests.swift`

**Interfaces:**
- Consumes: `FrameHeader`
- Produces: `RawFrame` (propriétés `id: UInt8`, `width: Int`, `height: Int`, `payload: Data`, `textMessage: String?`) et `FrameStreamParser` avec `mutating func append(_ data: Data)` et `mutating func next() -> RawFrame?`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/FrameStreamParserTests.swift` :

```swift
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

@Test func unePayloadBinaireNEstPasDuTexte() {
    var parser = FrameStreamParser()
    let binaire = Data(repeating: 0x00, count: 4_147_200)
    parser.append(makeHeader(size: binaire.count, code: 0, id: 21, width: 1080, height: 1920) + binaire)

    #expect(parser.next()?.textMessage == nil)
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter FrameStreamParser`
Expected: FAIL — `cannot find 'FrameStreamParser' in scope`.

- [ ] **Step 3: Écrire le modèle de trame**

`Sources/SeestarKit/Protocol/RawFrame.swift` :

```swift
import Foundation

/// Trame reçue du port 4800, telle quelle : aucune interprétation du contenu.
public struct RawFrame: Equatable, Sendable {
    /// 21 pour une preview, 23 pour une image empilée.
    public let id: UInt8
    public let width: Int
    public let height: Int
    public let payload: Data

    public init(id: UInt8, width: Int, height: Int, payload: Data) {
        self.id = id
        self.width = width
        self.height = height
        self.payload = payload
    }

    /// Le scope répond en clair pour signaler un état plutôt qu'une image :
    /// « done », « only available for continuous exposure »…
    /// Ces réponses sont courtes et sans octet nul.
    public var textMessage: String? {
        guard payload.count < 200, !payload.prefix(20).contains(0) else { return nil }
        return String(data: payload, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Écrire l'analyseur**

`Sources/SeestarKit/Protocol/FrameStreamParser.swift` :

```swift
import Foundation

/// Reconstitue des trames complètes à partir d'octets arrivant par morceaux.
///
/// Un socket ne respecte aucune frontière de message : on accumule jusqu'à
/// disposer de l'en-tête puis de la charge utile annoncée.
public struct FrameStreamParser: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Rend la prochaine trame disponible, ou `nil` s'il manque des octets.
    public mutating func next() -> RawFrame? {
        while true {
            guard buffer.count >= FrameHeader.byteCount,
                  let header = FrameHeader(Data(buffer.prefix(20)))
            else { return nil }

            let total = FrameHeader.byteCount + header.size
            guard buffer.count >= total else { return nil }

            let payload = Data(buffer.prefix(total).dropFirst(FrameHeader.byteCount))
            // On rebase systématiquement : les index d'un Data tranché ne
            // repartent pas de zéro, source classique de bogues.
            buffer = Data(buffer.dropFirst(total))

            // Une trame vide n'est pas une erreur, seulement du remplissage.
            if header.size == 0 { continue }

            return RawFrame(
                id: header.id,
                width: header.width,
                height: header.height,
                payload: payload
            )
        }
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter FrameStreamParser`
Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SeestarKit/Protocol Tests/SeestarKitTests/FrameStreamParserTests.swift
git commit -m "feat(kit): découpage incrémental du flux binaire d'imagerie"
```

---

### Task 4: Flux d'événements du port 4700

**Files:**
- Create: `Sources/SeestarKit/Protocol/SeestarEvent.swift`
- Create: `Sources/SeestarKit/Protocol/EventStreamParser.swift`
- Test: `Tests/SeestarKitTests/EventStreamParserTests.swift`

**Interfaces:**
- Consumes: `Fixtures.eventLines()`
- Produces: `SeestarEvent` (`name: String`, `timestamp: Double?`, `mode: String?`, `state: String?`, `tracking: Bool?`, `batteryCapacity: Int?`, `temperature: Double?`) et `EventStreamParser` avec `append`/`next`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/EventStreamParserTests.swift` :

```swift
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
    parser.append(Data(#"{"Event":"View","Timestamp":"1360.9","state":"cancel","mode":"scenery"}"# .utf8))
    parser.append(Data("\r\n".utf8))

    let event = parser.next()
    #expect(event?.name == "View")
    #expect(event?.mode == "scenery")
    #expect(event?.state == "cancel")
    #expect(event?.timestamp == 1360.9)
}

@Test func laTelemetrieEstExtraite() {
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus","Timestamp":"82.4","battery_capacity":100,"temp":56.3}"# .utf8))
    parser.append(Data("\r\n".utf8))

    let event = parser.next()
    #expect(event?.batteryCapacity == 100)
    #expect(event?.temperature == 56.3)
}

@Test func leDecoupageAttendLaFinDeLigne() {
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus"}"# .utf8))
    #expect(parser.next() == nil)
    parser.append(Data("\r\n".utf8))
    #expect(parser.next()?.name == "PiStatus")
}

@Test func uneLigneInvalideEstIgnoreeSansBloquerLaSuite() {
    var parser = EventStreamParser()
    parser.append(Data("ceci n'est pas du json\r\n".utf8))
    parser.append(Data(#"{"Event":"PiStatus"}"# .utf8 + "\r\n".utf8))

    #expect(parser.next()?.name == "PiStatus")
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter EventStream`
Expected: FAIL — `cannot find 'EventStreamParser' in scope`.

- [ ] **Step 3: Écrire le modèle d'événement**

`Sources/SeestarKit/Protocol/SeestarEvent.swift` :

```swift
import Foundation

/// Événement diffusé spontanément par le télescope sur le port 4700.
///
/// Le flux est disponible sans authentification, contrairement aux commandes.
/// On ne modélise que les champs réellement exploités par l'affichage.
public struct SeestarEvent: Equatable {
    public let name: String
    public let timestamp: Double?
    /// Présent sur `View` : « star » en mode astro, « scenery » en paysage.
    /// C'est le signal qui indique si le canal d'imagerie va produire des trames.
    public let mode: String?
    public let state: String?
    public let tracking: Bool?
    public let batteryCapacity: Int?
    public let temperature: Double?
    /// Objet JSON complet, pour les champs non modélisés.
    public let raw: [String: Any]

    public static func == (lhs: SeestarEvent, rhs: SeestarEvent) -> Bool {
        lhs.name == rhs.name && lhs.timestamp == rhs.timestamp
            && lhs.mode == rhs.mode && lhs.state == rhs.state
    }

    init?(json: [String: Any]) {
        guard let name = json["Event"] as? String else { return nil }
        self.name = name
        // Le timestamp arrive en chaîne de caractères, pas en nombre.
        self.timestamp = (json["Timestamp"] as? String).flatMap(Double.init)
        self.mode = json["mode"] as? String
        self.state = json["state"] as? String
        self.tracking = json["tracking"] as? Bool
        self.batteryCapacity = json["battery_capacity"] as? Int
        self.temperature = json["temp"] as? Double
        self.raw = json
    }
}

extension SeestarEvent: @unchecked Sendable {}
```

- [ ] **Step 4: Écrire l'analyseur**

`Sources/SeestarKit/Protocol/EventStreamParser.swift` :

```swift
import Foundation

/// Découpe le flux du port 4700 en événements.
///
/// Le protocole est une ligne JSON par message, terminée par `\r\n`.
public struct EventStreamParser: Sendable {
    private var buffer = Data()
    private static let separator = Data("\r\n".utf8)

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    public mutating func next() -> SeestarEvent? {
        while let range = buffer.range(of: Self.separator) {
            let line = Data(buffer[buffer.startIndex..<range.lowerBound])
            buffer = Data(buffer[range.upperBound...])

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let json = object as? [String: Any],
                  let event = SeestarEvent(json: json)
            else { continue }  // Ligne illisible : on l'écarte sans bloquer le flux.

            return event
        }
        return nil
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter EventStream`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SeestarKit/Protocol Tests/SeestarKitTests/EventStreamParserTests.swift
git commit -m "feat(kit): décodage du flux d'événements du port 4700"
```

---

### Task 5: Interprétation du buffer brut

**Files:**
- Create: `Sources/SeestarKit/Imaging/RGBImage.swift`
- Create: `Sources/SeestarKit/Imaging/RawBufferDecoder.swift`
- Test: `Tests/SeestarKitTests/RawBufferDecoderTests.swift`

**Interfaces:**
- Consumes: rien
- Produces: `RGBImage` (`width`, `height`, `pixels: [Float]` entrelacés RVB entre 0 et 1) et `RawBufferDecoder.decode(_ payload: Data, width: Int, height: Int) -> RGBImage?`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/RawBufferDecoderTests.swift` :

```swift
import Foundation
import Testing
@testable import SeestarKit

/// Construit une mosaïque de Bayer GRBG synthétique de 4x4 échantillons.
/// Motif : ligne paire « G R », ligne impaire « B G ».
func makeBayerGRBG() -> Data {
    let values: [UInt16] = [
        100, 200, 100, 200,   // G R G R
        300, 400, 300, 400,   // B G B G
        100, 200, 100, 200,
        300, 400, 300, 400,
    ]
    var data = Data(capacity: values.count * 2)
    for value in values {
        data.append(UInt8(value & 0xFF))          // little-endian
        data.append(UInt8((value >> 8) & 0xFF))
    }
    return data
}

@Test func leBinningBayerProduitLaDemiResolution() throws {
    let image = try #require(RawBufferDecoder.decode(makeBayerGRBG(), width: 4, height: 4))
    #expect(image.width == 2)
    #expect(image.height == 2)
    #expect(image.pixels.count == 2 * 2 * 3)
}

@Test func leBinningPlaceLesComposantesAuBonEndroit() throws {
    let image = try #require(RawBufferDecoder.decode(makeBayerGRBG(), width: 4, height: 4))
    // Bloc 2x2 : G=100 (haut gauche), R=200 (haut droit),
    //            B=300 (bas gauche), G=400 (bas droit).
    // R = 200, G = (100 + 400) / 2 = 250, B = 300.
    let scale = Float(65535)
    #expect(abs(image.pixels[0] - 200 / scale) < 1e-6)
    #expect(abs(image.pixels[1] - 250 / scale) < 1e-6)
    #expect(abs(image.pixels[2] - 300 / scale) < 1e-6)
}

@Test func leBufferRGB16BitsEstReconnu() throws {
    // Cas w*h*6 : trois canaux de 16 bits, sans dématriçage.
    var data = Data()
    for value: UInt16 in [1000, 2000, 3000, 4000, 5000, 6000] {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }
    let image = try #require(RawBufferDecoder.decode(data, width: 2, height: 1))
    #expect(image.width == 2)
    #expect(image.height == 1)
    #expect(abs(image.pixels[0] - 1000 / Float(65535)) < 1e-6)
}

@Test func uneTailleInattendueEstRefusee() {
    #expect(RawBufferDecoder.decode(Data(repeating: 0, count: 7), width: 4, height: 4) == nil)
}

@Test func laTrameReelleEstDecodee() throws {
    let payload = try Fixtures.frameData()
    let image = try #require(RawBufferDecoder.decode(payload, width: 1080, height: 1920))
    #expect(image.width == 540)
    #expect(image.height == 960)
    // La trame mesurée est saturée à 57 % : la valeur médiane doit être haute.
    let sorted = image.pixels.sorted()
    #expect(sorted[sorted.count / 2] > 0.9)
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter RawBufferDecoder`
Expected: FAIL — `cannot find 'RawBufferDecoder' in scope`.

- [ ] **Step 3: Écrire le modèle d'image**

`Sources/SeestarKit/Imaging/RGBImage.swift` :

```swift
import Foundation

/// Image intermédiaire en flottants, canaux entrelacés R, V, B entre 0 et 1.
///
/// Les valeurs sont linéaires : affichée telle quelle, une image astro est
/// quasiment noire. L'étirement (`AutoStretch`) est indispensable.
public struct RGBImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}
```

- [ ] **Step 4: Écrire le décodeur de buffer**

`Sources/SeestarKit/Imaging/RawBufferDecoder.swift` :

```swift
import Foundation

/// Transforme le buffer brut d'une trame en image RVB.
///
/// Deux formats mesurés ou attendus, distingués par la taille :
///   - `width * height * 2` : mosaïque de Bayer 16 bits (preview)
///   - `width * height * 6` : trois canaux de 16 bits (empilement)
public enum RawBufferDecoder {
    /// Motif de Bayer du capteur. `GRBG` est repris de seestar_alp et reste à
    /// confirmer sur une trame nocturne non saturée (hypothèse 1 de la spec).
    public enum BayerPattern: Sendable {
        case grbg, rggb, bggr, gbrg

        /// Positions (ligne, colonne) dans le bloc 2x2.
        var offsets: (r: (Int, Int), g: ((Int, Int), (Int, Int)), b: (Int, Int)) {
            switch self {
            case .grbg: return (r: (0, 1), g: ((0, 0), (1, 1)), b: (1, 0))
            case .rggb: return (r: (0, 0), g: ((0, 1), (1, 0)), b: (1, 1))
            case .bggr: return (r: (1, 1), g: ((0, 1), (1, 0)), b: (0, 0))
            case .gbrg: return (r: (1, 0), g: ((0, 0), (1, 1)), b: (0, 1))
            }
        }
    }

    private static let scale = Float(65535)

    public static func decode(
        _ payload: Data,
        width: Int,
        height: Int,
        pattern: BayerPattern = .grbg
    ) -> RGBImage? {
        guard width > 0, height > 0 else { return nil }
        let samples = readLittleEndianUInt16(payload)

        if samples.count == width * height * 3 {
            return decodeRGB(samples, width: width, height: height)
        }
        if samples.count == width * height {
            return binBayer(samples, width: width, height: height, pattern: pattern)
        }
        return nil
    }

    private static func readLittleEndianUInt16(_ data: Data) -> [UInt16] {
        guard data.count % 2 == 0 else { return [] }
        var out = [UInt16](repeating: 0, count: data.count / 2)
        let bytes = [UInt8](data)
        for i in 0..<out.count {
            out[i] = UInt16(bytes[2 * i]) | (UInt16(bytes[2 * i + 1]) << 8)
        }
        return out
    }

    private static func decodeRGB(_ samples: [UInt16], width: Int, height: Int) -> RGBImage {
        var pixels = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            pixels[i] = Float(samples[i]) / scale
        }
        return RGBImage(width: width, height: height, pixels: pixels)
    }

    /// Binning 2x2 : chaque bloc devient un pixel. Pas d'interpolation, donc
    /// aucun artefact de dématriçage, et le bruit baisse. On perd la moitié de
    /// la résolution, sans conséquence pour un affichage télévisé.
    private static func binBayer(
        _ samples: [UInt16], width: Int, height: Int, pattern: BayerPattern
    ) -> RGBImage {
        let outWidth = width / 2
        let outHeight = height / 2
        let offsets = pattern.offsets
        var pixels = [Float](repeating: 0, count: outWidth * outHeight * 3)

        @inline(__always)
        func sample(_ blockY: Int, _ blockX: Int, _ position: (Int, Int)) -> Float {
            let y = blockY * 2 + position.0
            let x = blockX * 2 + position.1
            return Float(samples[y * width + x])
        }

        for blockY in 0..<outHeight {
            for blockX in 0..<outWidth {
                let base = (blockY * outWidth + blockX) * 3
                pixels[base] = sample(blockY, blockX, offsets.r) / scale
                pixels[base + 1] = (sample(blockY, blockX, offsets.g.0)
                    + sample(blockY, blockX, offsets.g.1)) / 2 / scale
                pixels[base + 2] = sample(blockY, blockX, offsets.b) / scale
            }
        }
        return RGBImage(width: outWidth, height: outHeight, pixels: pixels)
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter RawBufferDecoder`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SeestarKit/Imaging Tests/SeestarKitTests/RawBufferDecoderTests.swift
git commit -m "feat(kit): interprétation du buffer brut, binning Bayer 2x2"
```

---

### Task 6: Étirement automatique d'histogramme

**Files:**
- Create: `Sources/SeestarKit/Imaging/AutoStretch.swift`
- Test: `Tests/SeestarKitTests/AutoStretchTests.swift`

**Interfaces:**
- Consumes: `RGBImage`
- Produces: `AutoStretch.apply(_ image: RGBImage, targetBackground: Float = 0.25, shadowClip: Float = -2.8) -> RGBImage` et `AutoStretch.midtoneTransfer(_ x: Float, _ m: Float) -> Float`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/AutoStretchTests.swift` :

```swift
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
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter AutoStretch`
Expected: FAIL — `cannot find 'AutoStretch' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/SeestarKit/Imaging/AutoStretch.swift` :

```swift
import Foundation

/// Étirement d'histogramme automatique, méthode classique des logiciels astro.
///
/// Une image astronomique linéaire est quasiment noire : cette étape n'est pas
/// cosmétique, elle est indispensable à l'affichage. Le traitement canal par
/// canal corrige au passage la dominante de couleur.
///
/// Miroir Swift de `autostretch()` dans `decode_frame.py`, qui sert d'oracle.
public enum AutoStretch {
    /// Fonction de transfert de tons (midtone transfer function).
    public static func midtoneTransfer(_ x: Float, _ m: Float) -> Float {
        let denominator = (2 * m - 1) * x - m
        guard denominator != 0 else { return 0 }
        return min(max((m - 1) * x / denominator, 0), 1)
    }

    public static func apply(
        _ image: RGBImage,
        targetBackground: Float = 0.25,
        shadowClip: Float = -2.8
    ) -> RGBImage {
        var pixels = image.pixels
        let pixelCount = image.width * image.height

        for channel in 0..<3 {
            // Statistiques sur un pixel sur 16 : seize fois plus rapide, et
            // suffisamment représentatif pour une médiane.
            var sample = [Float]()
            sample.reserveCapacity(pixelCount / 16 + 1)
            var index = 0
            while index < pixelCount {
                sample.append(pixels[index * 3 + channel])
                index += 16
            }
            guard !sample.isEmpty else { continue }

            let median = self.median(of: sample)
            let deviations = sample.map { abs($0 - median) }
            let mad = self.median(of: deviations) * 1.4826
            guard mad > 0 else { continue }

            let blackPoint = min(max(median + shadowClip * mad, 0), 1)
            let span = max(1 - blackPoint, 1e-6)
            let rawMidtone = midtoneTransfer((median - blackPoint) / span, targetBackground)
            let midtone = min(max(rawMidtone, 1e-4), 1 - 1e-4)

            for pixel in 0..<pixelCount {
                let offset = pixel * 3 + channel
                let normalized = min(max((pixels[offset] - blackPoint) / span, 0), 1)
                pixels[offset] = midtoneTransfer(normalized, midtone)
            }
        }

        return RGBImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func median(of values: [Float]) -> Float {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter AutoStretch`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SeestarKit/Imaging/AutoStretch.swift Tests/SeestarKitTests/AutoStretchTests.swift
git commit -m "feat(kit): étirement automatique d'histogramme"
```

---

### Task 7: Dépaquetage des trames d'empilement

**Files:**
- Create: `Sources/SeestarKit/Imaging/StackUnpacker.swift`
- Test: `Tests/SeestarKitTests/StackUnpackerTests.swift`

**Interfaces:**
- Consumes: ZIPFoundation
- Produces: `StackUnpacker.unpack(_ payload: Data) throws -> Data`, qui extrait l'entrée `raw_data`, et `StackUnpacker.isArchive(_ payload: Data) -> Bool`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/StackUnpackerTests.swift` :

```swift
import Foundation
import Testing
import ZIPFoundation
@testable import SeestarKit

/// Fabrique une archive contenant une entrée `raw_data`, comme celle
/// qu'émet le télescope pour les images empilées.
func makeStackArchive(payload: Data, compressed: Bool) throws -> Data {
    let archive = try Archive(accessMode: .create)
    try archive.addEntry(
        with: "raw_data",
        type: .file,
        uncompressedSize: Int64(payload.count),
        compressionMethod: compressed ? .deflate : .none,
        provider: { position, size in
            payload.subdata(in: Int(position)..<(Int(position) + size))
        }
    )
    return archive.data!
}

@Test func uneArchiveCompresseeEstDepaquetee() throws {
    let contenu = Data(repeating: 0x42, count: 5000)
    let archive = try makeStackArchive(payload: contenu, compressed: true)
    #expect(try StackUnpacker.unpack(archive) == contenu)
}

@Test func uneArchiveStockeeEstDepaquetee() throws {
    // Hypothèse 2 de la spec : le télescope peut stocker sans compresser.
    let contenu = Data(repeating: 0x37, count: 5000)
    let archive = try makeStackArchive(payload: contenu, compressed: false)
    #expect(try StackUnpacker.unpack(archive) == contenu)
}

@Test func laSignatureZipEstReconnue() throws {
    let archive = try makeStackArchive(payload: Data([1, 2, 3]), compressed: true)
    #expect(StackUnpacker.isArchive(archive))
    #expect(!StackUnpacker.isArchive(Data([0xE0, 0xFF, 0x40, 0xF6])))
}

@Test func uneArchiveSansEntreeAttendueEchoue() throws {
    let archive = try Archive(accessMode: .create)
    try archive.addEntry(with: "autre", type: .file, uncompressedSize: 3,
                         provider: { _, _ in Data([1, 2, 3]) })
    #expect(throws: StackUnpacker.Erreur.self) {
        try StackUnpacker.unpack(archive.data!)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter StackUnpacker`
Expected: FAIL — `cannot find 'StackUnpacker' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/SeestarKit/Imaging/StackUnpacker.swift` :

```swift
import Foundation
import ZIPFoundation

/// Extrait le buffer brut d'une trame d'empilement.
///
/// D'après le code de seestar_alp, les trames `id=23` sont des archives ZIP
/// contenant une entrée `raw_data`. Hypothèse 2 de la spec, à confirmer sur
/// une session nocturne : d'ici là, `isArchive` permet de basculer sur le
/// traitement brut si la trame n'est pas zippée.
public enum StackUnpacker {
    public enum Erreur: Error, Equatable {
        case archiveIllisible
        case entreeAbsente
    }

    private static let entryName = "raw_data"

    /// Signature d'une archive ZIP : les deux octets « PK ».
    public static func isArchive(_ payload: Data) -> Bool {
        payload.count >= 2 && payload[payload.startIndex] == 0x50
            && payload[payload.startIndex + 1] == 0x4B
    }

    public static func unpack(_ payload: Data) throws -> Data {
        guard let archive = try? Archive(data: payload, accessMode: .read) else {
            throw Erreur.archiveIllisible
        }
        guard let entry = archive[entryName] else {
            throw Erreur.entreeAbsente
        }
        var extracted = Data()
        _ = try archive.extract(entry, skipCRC32: true) { chunk in
            extracted.append(chunk)
        }
        return extracted
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter StackUnpacker`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SeestarKit/Imaging/StackUnpacker.swift Tests/SeestarKitTests/StackUnpackerTests.swift
git commit -m "feat(kit): dépaquetage ZIP des trames d'empilement"
```

---

### Task 8: Rendu en CGImage et chaîne complète

**Files:**
- Create: `Sources/SeestarKit/Imaging/ImageRenderer.swift`
- Create: `Sources/SeestarKit/Imaging/FrameDecoder.swift`
- Test: `Tests/SeestarKitTests/FrameDecoderTests.swift`

**Interfaces:**
- Consumes: `RawFrame`, `RawBufferDecoder`, `AutoStretch`, `StackUnpacker`, `RGBImage`
- Produces: `ImageRenderer.render(_ image: RGBImage) -> CGImage?` et `FrameDecoder.decode(_ frame: RawFrame) -> DecodedFrame?`, où `DecodedFrame` porte `image: CGImage`, `kind: FrameKind` (`.preview` ou `.stack`), `width: Int`, `height: Int`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/FrameDecoderTests.swift` :

```swift
import CoreGraphics
import Foundation
import Testing
@testable import SeestarKit

@Test func leRenduProduitUneImageAuxBonnesDimensions() throws {
    let pixels = [Float](repeating: 0.5, count: 4 * 3 * 3)
    let image = try #require(ImageRenderer.render(RGBImage(width: 4, height: 3, pixels: pixels)))
    #expect(image.width == 4)
    #expect(image.height == 3)
}

@Test func laChaineCompleteDecodeLaTrameReelle() throws {
    let frame = RawFrame(id: 21, width: 1080, height: 1920, payload: try Fixtures.frameData())
    let decoded = try #require(FrameDecoder.decode(frame))
    #expect(decoded.kind == .preview)
    // Binning 2x2 : la trame 1080x1920 rend une image 540x960.
    #expect(decoded.image.width == 540)
    #expect(decoded.image.height == 960)
}

@Test func unMessageTexteNeProduitPasDImage() {
    let payload = Data("only available for continuous exposure".utf8)
    let frame = RawFrame(id: 21, width: 0, height: 0, payload: payload)
    #expect(FrameDecoder.decode(frame) == nil)
}

@Test func uneTailleIncoherenteEstRejeteeSansPlanter() {
    let frame = RawFrame(id: 21, width: 1080, height: 1920, payload: Data(repeating: 0, count: 99))
    #expect(FrameDecoder.decode(frame) == nil)
}

@Test func uneTrameNonZippeeEstTraiteeCommeUnBufferBrut() throws {
    // Filet de sécurité tant que l'hypothèse 2 n'est pas levée : si la trame
    // d'empilement n'est pas une archive, on la lit directement.
    var payload = Data()
    for value: UInt16 in [1000, 2000, 3000, 4000, 5000, 6000] {
        payload.append(UInt8(value & 0xFF))
        payload.append(UInt8((value >> 8) & 0xFF))
    }
    let frame = RawFrame(id: 23, width: 2, height: 1, payload: payload)
    let decoded = try #require(FrameDecoder.decode(frame))
    #expect(decoded.kind == .stack)
    #expect(decoded.image.width == 2)
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter FrameDecoder`
Expected: FAIL — `cannot find 'ImageRenderer' in scope`.

- [ ] **Step 3: Écrire le rendu**

`Sources/SeestarKit/Imaging/ImageRenderer.swift` :

```swift
import CoreGraphics
import Foundation

/// Convertit une image flottante en `CGImage` 8 bits, prête pour l'affichage.
public enum ImageRenderer {
    public static func render(_ image: RGBImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              image.pixels.count == image.width * image.height * 3
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: image.pixels.count)
        for i in 0..<image.pixels.count {
            bytes[i] = UInt8(min(max(image.pixels[i], 0), 1) * 255)
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: image.width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
```

- [ ] **Step 4: Écrire la chaîne complète**

`Sources/SeestarKit/Imaging/FrameDecoder.swift` :

```swift
import CoreGraphics
import Foundation

public enum FrameKind: Sendable {
    case preview
    case stack
}

public struct DecodedFrame: Sendable {
    public let kind: FrameKind
    public let image: CGImage
    public var width: Int { image.width }
    public var height: Int { image.height }
}

/// Chaîne complète : trame brute → buffer → étirement → image affichable.
///
/// Seule unité à connaître le format des données. Toute évolution du protocole
/// se corrige ici, sans toucher au transport ni à l'affichage.
public enum FrameDecoder {
    public static func decode(_ frame: RawFrame) -> DecodedFrame? {
        // Une réponse en clair du scope n'est pas une image.
        guard frame.textMessage == nil else { return nil }

        let kind: FrameKind = frame.id == 23 ? .stack : .preview

        var buffer = frame.payload
        if kind == .stack, StackUnpacker.isArchive(buffer) {
            guard let extracted = try? StackUnpacker.unpack(buffer) else { return nil }
            buffer = extracted
        }

        guard let linear = RawBufferDecoder.decode(
            buffer, width: frame.width, height: frame.height
        ) else { return nil }

        guard let image = ImageRenderer.render(AutoStretch.apply(linear)) else { return nil }
        return DecodedFrame(kind: kind, image: image)
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter FrameDecoder`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SeestarKit/Imaging Tests/SeestarKitTests/FrameDecoderTests.swift
git commit -m "feat(kit): rendu CGImage et chaîne de décodage complète"
```

---

### Task 9: Interface de transport et connexion directe

**Files:**
- Create: `Sources/SeestarKit/Transport/SeestarTransport.swift`
- Create: `Sources/SeestarKit/Transport/DirectTransport.swift`
- Test: `Tests/SeestarKitTests/TransportTests.swift`

**Interfaces:**
- Consumes: `FrameStreamParser`, `EventStreamParser`
- Produces: le protocole `SeestarTransport` avec `func frames() -> AsyncStream<RawFrame>` et `func events() -> AsyncStream<SeestarEvent>`, plus `DirectTransport(host: String)`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/TransportTests.swift` :

```swift
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
    // Un seul octet doit jamais être écrit sur le 4800, et jamais rien sur le 4700.
    #expect(DirectTransport.beginStreamingCommand
        == Data(#"{"id": 21, "method": "begin_streaming"}"# .utf8) + Data("\r\n".utf8))
}

@Test func lesPortsSontCeuxMesures() {
    #expect(DirectTransport.controlPort == 4700)
    #expect(DirectTransport.imagingPort == 4800)
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter Transport`
Expected: FAIL — `cannot find type 'SeestarTransport' in scope`.

- [ ] **Step 3: Écrire l'interface**

`Sources/SeestarKit/Transport/SeestarTransport.swift` :

```swift
import Foundation

/// Source de données du télescope, indépendante du moyen d'y accéder.
///
/// La connexion directe n'en est qu'une implémentation. Si la mesure montre
/// que le télescope ne sert qu'un seul client à la fois (hypothèse 3 de la
/// spec), un relais viendra s'y substituer sans que le reste du code change.
public protocol SeestarTransport: Sendable {
    /// Le flux de trames doit être borné par `bufferingNewest(1)` : à 4 Mo par
    /// trame et une trame par seconde, toute mise en file finit en saturation.
    func frames() -> AsyncStream<RawFrame>
    func events() -> AsyncStream<SeestarEvent>
    func start() async
    func stop() async
}
```

- [ ] **Step 4: Écrire la connexion directe**

`Sources/SeestarKit/Transport/DirectTransport.swift` :

```swift
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
        Data(#"{"id": 21, "method": "begin_streaming"}"# .utf8) + Data("\r\n".utf8)

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

    private func setFrameContinuation(_ c: AsyncStream<RawFrame>.Continuation) {
        frameContinuation = c
    }

    private func setEventContinuation(_ c: AsyncStream<SeestarEvent>.Continuation) {
        eventContinuation = c
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
        let connection = NWConnection(host: host, port: .init(rawValue: Self.imagingPort)!, using: .tcp)
        imagingConnection = connection
        var parser = FrameStreamParser()

        // Seul envoi de toute l'application, et uniquement une fois la
        // connexion prête.
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.send(content: Self.beginStreamingCommand,
                            completion: .contentProcessed { _ in })
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
        let connection = NWConnection(host: host, port: .init(rawValue: Self.controlPort)!, using: .tcp)
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
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter Transport`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SeestarKit/Transport Tests/SeestarKitTests/TransportTests.swift
git commit -m "feat(kit): interface de transport et connexion directe"
```

---

### Task 10: Découverte du télescope

**Files:**
- Create: `Sources/SeestarKit/Transport/SeestarDiscovery.swift`
- Test: `Tests/SeestarKitTests/SeestarDiscoveryTests.swift`

**Interfaces:**
- Consumes: rien
- Produces: `SeestarDiscovery.resolve(manualHost: String?) async -> String?`, qui rend l'hôte à utiliser, et la constante `SeestarDiscovery.bonjourHost = "seestar.local"`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/SeestarDiscoveryTests.swift` :

```swift
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
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter SeestarDiscovery`
Expected: FAIL — `cannot find 'SeestarDiscovery' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/SeestarKit/Transport/SeestarDiscovery.swift` :

```swift
import Foundation
import Network
import os

/// Trouve l'adresse du télescope sur le réseau local.
///
/// Mesuré le 2026-08-12 : le Seestar publie bien `seestar.local` en mDNS
/// lorsqu'il est rattaché au réseau domestique (mode station).
public enum SeestarDiscovery {
    public static let bonjourHost = "seestar.local"

    /// Rend l'hôte à utiliser : l'adresse saisie si elle existe, sinon le nom
    /// mDNS s'il se résout, sinon `nil`.
    public static func resolve(manualHost: String? = nil) async -> String? {
        if let manual = manualHost?.trimmingCharacters(in: .whitespaces), !manual.isEmpty {
            return manual
        }
        return await resolvesOnNetwork(bonjourHost) ? bonjourHost : nil
    }

    /// Vérifie qu'un nom se résout, en ouvrant brièvement une connexion vers
    /// le port de contrôle. Aucun octet n'est envoyé.
    private static func resolvesOnNetwork(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: .init(rawValue: DirectTransport.controlPort)!,
                using: .tcp
            )
            let resumed = OSAllocatedUnfairLock(initialState: false)
            func finish(_ value: Bool) {
                resumed.withLock { alreadyDone in
                    guard !alreadyDone else { return }
                    alreadyDone = true
                    connection.cancel()
                    continuation.resume(returning: value)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter SeestarDiscovery`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SeestarKit/Transport/SeestarDiscovery.swift Tests/SeestarKitTests/SeestarDiscoveryTests.swift
git commit -m "feat(kit): découverte du télescope par mDNS avec repli manuel"
```

---

### Task 11: Arbitrage empilement / live et machine à états

**Files:**
- Create: `Sources/SeestarKit/ViewerModel.swift`
- Test: `Tests/SeestarKitTests/ViewerModelTests.swift`

**Interfaces:**
- Consumes: `SeestarTransport`, `FrameDecoder`, `DecodedFrame`, `SeestarEvent`
- Produces: `ViewerModel` (`@MainActor`, `@Observable`) avec `displayedFrame: DecodedFrame?`, `status: ViewerStatus`, `telemetry: Telemetry`, `func consume(_ frame: RawFrame, at: Date)` et `func consume(_ event: SeestarEvent)`.

- [ ] **Step 1: Écrire les tests en échec**

`Tests/SeestarKitTests/ViewerModelTests.swift` :

```swift
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
@Test func laTelemetrieEstMiseAJour() {
    let model = ViewerModel()
    var parser = EventStreamParser()
    parser.append(Data(#"{"Event":"PiStatus","battery_capacity":87,"temp":41.5}"# .utf8))
    parser.append(Data("\r\n".utf8))
    model.consume(parser.next()!)

    #expect(model.telemetry.batteryCapacity == 87)
    #expect(model.telemetry.temperature == 41.5)
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter ViewerModel`
Expected: FAIL — `cannot find 'ViewerModel' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/SeestarKit/ViewerModel.swift` :

```swift
import Foundation
import Observation

public enum ViewerStatus: Equatable, Sendable {
    case searching
    /// Le télescope répond mais n'expose pas : ce n'est pas une erreur.
    case waitingForExposure
    case live
    case stacking
    case disconnected
}

public struct Telemetry: Equatable, Sendable {
    public var target: String?
    public var mode: String?
    public var tracking: Bool?
    public var batteryCapacity: Int?
    public var temperature: Double?

    public init() {}
}

/// Arbitre l'image affichée et l'état visible.
///
/// L'arbitrage se fonde sur l'arrivée réelle des trames plutôt que sur les
/// événements, qui peuvent arriver en retard.
@MainActor
@Observable
public final class ViewerModel {
    /// Au-delà de ce délai sans nouvelle trame d'empilement, le live reprend
    /// la main. Deux fois l'intervalle typique entre deux subs.
    public static let stackExpiry: TimeInterval = 60

    public private(set) var displayedFrame: DecodedFrame?
    public private(set) var status: ViewerStatus = .searching
    public private(set) var telemetry = Telemetry()

    private var lastStackDate: Date?

    public init() {}

    public func consume(_ frame: RawFrame, at date: Date = Date()) {
        // Réponse en clair : un état, pas une image.
        if let message = frame.textMessage {
            status = message.contains("continuous exposure") ? .waitingForExposure : status
            return
        }

        guard let decoded = FrameDecoder.decode(frame) else { return }

        switch decoded.kind {
        case .stack:
            lastStackDate = date
            displayedFrame = decoded
            status = .stacking

        case .preview:
            // On ne remplace un empilement que s'il a cessé d'être alimenté.
            if let last = lastStackDate, date.timeIntervalSince(last) < Self.stackExpiry {
                return
            }
            lastStackDate = nil
            displayedFrame = decoded
            status = .live
        }
    }

    public func consume(_ event: SeestarEvent) {
        if let mode = event.mode { telemetry.mode = mode }
        if let tracking = event.tracking { telemetry.tracking = tracking }
        if let battery = event.batteryCapacity { telemetry.batteryCapacity = battery }
        if let temperature = event.temperature { telemetry.temperature = temperature }
        if let target = event.raw["target_name"] as? String { telemetry.target = target }
    }

    /// La connexion est tombée : on garde la dernière image à l'écran.
    /// Jamais d'écran noir, c'est la règle d'or d'un affichage contemplatif.
    public func connectionLost() {
        status = .disconnected
    }

    /// Branche le modèle sur un transport et consomme ses deux flux.
    public func attach(to transport: any SeestarTransport) {
        Task {
            for await frame in transport.frames() { consume(frame) }
            connectionLost()
        }
        Task {
            for await event in transport.events() { consume(event) }
        }
        Task { await transport.start() }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `swift test --filter ViewerModel`
Expected: PASS, 6 tests.

- [ ] **Step 5: Lancer la suite complète**

Run: `swift test`
Expected: PASS, environ 42 tests, aucune ouverture de socket.

- [ ] **Step 6: Commit**

```bash
git add Sources/SeestarKit/ViewerModel.swift Tests/SeestarKitTests/ViewerModelTests.swift
git commit -m "feat(kit): arbitrage empilement/live et machine à états"
```

---

### Task 12: Faux Seestar pour développer sans télescope

**Files:**
- Create: `Tools/fake_seestar.py`
- Modify: `README.md` (créer)

**Interfaces:**
- Consumes: `fixtures/frame_21_000_1080x1920.bin`, `fixtures/events.jsonl`
- Produces: un serveur écoutant sur 4700 et 4800, qui se comporte comme le télescope mesuré.

- [ ] **Step 1: Écrire le faux télescope**

`Tools/fake_seestar.py` :

```python
#!/usr/bin/env python3
"""Faux Seestar : rejoue une session enregistree sur les ports 4700 et 4800.

Permet de developper et de tester l'app en plein jour, sans telescope, et de
provoquer a volonte les pannes a gerer.

    python3 Tools/fake_seestar.py [--refuse] [--coupe-apres N]

  --refuse       repond "only available for continuous exposure" au lieu de
                 streamer, pour tester l'ecran d'attente
  --coupe-apres  ferme brutalement le socket apres N trames, pour tester
                 la reconnexion
"""

import argparse
import json
import os
import socket
import struct
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAME = os.path.join(ROOT, "fixtures", "frame_21_000_1080x1920.bin")
EVENTS = os.path.join(ROOT, "fixtures", "events.jsonl")
WIDTH, HEIGHT = 1080, 1920


def make_header(size, frame_id, width, height):
    """Reproduit l'en-tete de 80 octets mesure sur le materiel."""
    head = struct.pack(">HHHIHHBBHH", 0, 0, 0, size, 0, 0, 0, frame_id, width, height)
    return head + b"\x00" * (80 - len(head))


def serve_imaging(args):
    payload = open(FRAME, "rb").read()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", 4800))
    srv.listen(5)
    print("faux Seestar : imagerie sur 4800")

    while True:
        conn, addr = srv.accept()
        threading.Thread(target=imaging_client, args=(conn, addr, payload, args),
                         daemon=True).start()


def imaging_client(conn, addr, payload, args):
    print(f"  client imagerie {addr[0]}")
    try:
        conn.recv(1024)  # begin_streaming
        if args.refuse:
            msg = b"only available for continuous exposure"
            conn.sendall(make_header(len(msg), 21, 0, 0) + msg)
            time.sleep(60)
            return
        conn.sendall(make_header(4, 21, 0, 0) + b"done")
        sent = 0
        while True:
            conn.sendall(make_header(len(payload), 21, WIDTH, HEIGHT) + payload)
            sent += 1
            if args.coupe_apres and sent >= args.coupe_apres:
                print(f"  coupure volontaire apres {sent} trames")
                return
            time.sleep(1.0)
    except OSError:
        pass
    finally:
        conn.close()


def serve_events():
    lines = [l.strip() for l in open(EVENTS) if l.strip()]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", 4700))
    srv.listen(5)
    print("faux Seestar : evenements sur 4700")

    while True:
        conn, addr = srv.accept()
        threading.Thread(target=events_client, args=(conn, addr, lines),
                         daemon=True).start()


def events_client(conn, addr, lines):
    print(f"  client evenements {addr[0]}")
    try:
        while True:
            for line in lines:
                conn.sendall(line.encode() + b"\r\n")
                time.sleep(2)
    except OSError:
        pass
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--refuse", action="store_true")
    parser.add_argument("--coupe-apres", type=int, default=0)
    args = parser.parse_args()

    threading.Thread(target=serve_events, daemon=True).start()
    serve_imaging(args)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Vérifier que le faux télescope sert bien une trame**

```bash
python3 Tools/fake_seestar.py &
sleep 1
python3 - <<'EOF'
import socket, struct
s = socket.create_connection(("127.0.0.1", 4800), timeout=5)
s.sendall(b'{"id": 21, "method": "begin_streaming"}\r\n')
for _ in range(2):
    h = s.recv(80, socket.MSG_WAITALL)
    size, fid = struct.unpack(">HHHIHHBBHH", h[:20])[3], struct.unpack(">HHHIHHBBHH", h[:20])[7]
    p = s.recv(size, socket.MSG_WAITALL)
    print(f"id={fid} size={size} recu={len(p)}")
s.close()
EOF
kill %1
```

Expected: `id=21 size=4 recu=4` puis `id=21 size=4147200 recu=4147200`.

- [ ] **Step 3: Écrire le README**

`README.md` :

```markdown
# Seestar Viewer

Visualiseur Apple TV, iPad et iPhone pour le télescope ZWO Seestar S30.
Affiche en plein écran l'image en cours d'empilement, sur le réseau local.

L'app est **spectatrice** : elle n'envoie aucune commande au télescope, qui
reste piloté par l'application officielle. Voir la spec pour la raison —
le firmware verrouille les commandes derrière une authentification RSA.

## Documents

- Design : `docs/superpowers/specs/2026-08-12-seestar-tvos-viewer-design.md`
- Plan du cœur : `docs/superpowers/plans/2026-08-12-seestarkit-core.md`

## Outils

| Commande | Rôle |
|---|---|
| `python3 probe.py` | Diagnostic : découverte, état, authentification |
| `python3 capture_frames.py <ip>` | Capture de trames vers `fixtures/` |
| `python3 decode_frame.py <trame> --patterns` | Décodage de référence |
| `python3 night_session.py <ip>` | Lève les hypothèses restantes |
| `python3 Tools/fake_seestar.py` | Faux télescope pour développer sans matériel |

## Tests

```bash
swift test
```

Aucun test n'ouvre de socket : les analyseurs sont alimentés par les trames
réelles capturées dans `fixtures/`.
```

- [ ] **Step 4: Commit**

```bash
git add Tools/fake_seestar.py README.md
git commit -m "feat(outils): faux Seestar pour développer sans télescope"
```

---

## Suite

Le plan des applications (`SeestarTV` et `SeestarViewer`) fera l'objet d'un second
document, écrit une fois ce cœur en place. Il couvrira la présentation par
plateforme — rotation, incrustation de télémétrie, neutralisation de la mise en
veille, dérive anti-rémanence, gestion de l'arrière-plan iOS — et l'assemblage des
cibles Xcode.

**Avant de démarrer les applications**, lancer `night_session.py` pendant une session
d'empilement réelle : les trois hypothèses de la spec y sont levées d'un coup, et la
troisième — la diffusion à plusieurs clients — peut imposer un relais entre le
télescope et les appareils.
