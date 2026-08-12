import Foundation
import SeestarKit

/// Vérification de bout en bout de `SeestarKit` : se connecte à un télescope
/// (réel ou au faux de `Tools/fake_seestar.py`), consomme les deux canaux et
/// rend compte de ce qu'il reçoit.
///
///     swift run seestar-probe [hote] [duree_secondes]
///
/// Sert de garde-fou : c'est le seul chemin qui exerce réellement les sockets,
/// que les tests unitaires n'ouvrent jamais.

let arguments = CommandLine.arguments
let manualHost = arguments.count > 1 ? arguments[1] : nil
let duration = arguments.count > 2 ? (Double(arguments[2]) ?? 15) : 15

guard let host = await SeestarDiscovery.resolve(manualHost: manualHost) else {
    print("Aucun Seestar trouvé. Passe une adresse : swift run seestar-probe 192.168.1.170")
    exit(1)
}
print("cible \(host), écoute \(Int(duration)) s")

let transport = DirectTransport(host: host)
let model = await ViewerModel()

let frames = Task {
    var decoded = 0
    var messages = Set<String>()
    for await frame in transport.frames() {
        if let message = frame.textMessage {
            if messages.insert(message).inserted {
                print("  message du scope : \(message)")
            }
            await model.consume(frame)
            continue
        }
        await model.consume(frame)
        decoded += 1
        if let image = await model.displayedFrame {
            print("  trame \(decoded) : id=\(frame.id) \(frame.payload.count) o "
                  + "-> image \(image.width)x\(image.height)")
        } else {
            print("  trame \(decoded) : id=\(frame.id) NON DÉCODÉE")
        }
    }
    return decoded
}

let events = Task {
    var count = 0
    for await event in transport.events() {
        count += 1
        if count <= 3 { print("  événement : \(event.name)") }
        await model.consume(event)
    }
    return count
}

await transport.start()
try? await Task.sleep(for: .seconds(duration))
await transport.stop()

frames.cancel()
events.cancel()

let status = await model.status
let telemetry = await model.telemetry
let battery: String = telemetry.batteryCapacity.map { "\($0)" } ?? "-"
let temperature: String = telemetry.temperature.map { "\($0)" } ?? "-"
let mode: String = telemetry.mode ?? "-"

print("\nétat final   : \(status)")
print("télémétrie   : batterie=\(battery) temp=\(temperature) mode=\(mode)")
if let image = await model.displayedFrame {
    print("image à l'écran : \(image.width)x\(image.height), source \(image.kind)")
} else {
    print("image à l'écran : aucune")
}
