// Preferencias persistentes en ~/.mascotuscan/config.json

import Foundation

public struct PetConfig: Codable {
    public var x: Double? = nil
    public var y: Double? = nil
    public var quiet: Bool = false
    public var watchPorts: Bool = true
    public var scale: Double = 1.0
    /// Avisar de comandos del pane que estas mirando en este momento. Por defecto no: seria ruido.
    public var notifyWhileWatching: Bool = false
    /// La mascota activa, por id de paquete. nil = la primera instalada.
    public var activePet: String? = nil
    /// Cada cuanto cuenta en que van los agentes mientras trabajan. 0 lo apaga.
    public var narrateEverySeconds: Double = 150
    /// Consultar una vez al dia si hay una version publicada mas nueva.
    public var checkUpdates: Bool = true

    public static func load() -> PetConfig {
        guard let d = try? Data(contentsOf: configURL),
              let c = try? JSONDecoder().decode(PetConfig.self, from: d)
        else { return PetConfig() }
        return c
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: configURL, options: .atomic)
    }
}
