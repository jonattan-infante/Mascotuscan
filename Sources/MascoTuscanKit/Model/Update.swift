// Comprobacion de actualizaciones. Es la implementacion en Swift del contrato
// de docs/reference/versioning.md; windows/mascotuscan_win/update.py es la misma
// logica en Python y los dos comparten los casos de prueba.
//
// La logica de decision es pura y esta separada de la red a proposito: lo que
// se prueba es "dado este estado y esta version remota, hablo o me callo".

import Foundation

/// Version X.Y.Z comparable. Acepta el prefijo `v` de los tags.
public struct Semver: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        // Un prerelease (0.3.0-beta.1) no es una version publicada para el
        // usuario: no se compara ni se anuncia.
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        major = a; minor = b; patch = c
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (l: Semver, r: Semver) -> Bool {
        (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
    }
}

/// Lo que se recuerda entre arranques: cuando se consulto, que habia, y que se
/// dijo ya. Misma forma en ambas plataformas para que un mismo ~/.mascotuscan
/// sirva a las dos.
public struct UpdateState: Codable, Equatable {
    public var checkedAt: Date?
    public var latest: String?
    public var announced: String?

    public init(checkedAt: Date? = nil, latest: String? = nil, announced: String? = nil) {
        self.checkedAt = checkedAt
        self.latest = latest
        self.announced = announced
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Un archivo corrupto o ausente es un estado vacio, no un fallo: lo peor
    /// que pasa es una consulta de mas.
    public static func load(from url: URL = PetPaths.update) -> UpdateState {
        guard let d = try? Data(contentsOf: url),
              let s = try? decoder.decode(UpdateState.self, from: d) else { return UpdateState() }
        return s
    }

    public func save(to url: URL = PetPaths.update) {
        try? UpdateState.encoder.encode(self).write(to: url, options: .atomic)
    }
}

public enum UpdateCheck {
    /// El endpoint del contrato. `MASCOTUSCAN_UPDATE_URL` lo reemplaza para probar
    /// sin publicar nada (acepta file://).
    public static let defaultEndpoint =
        "https://api.github.com/repos/jonattan-infante/mascotuscan/releases/latest"

    public static var endpoint: URL {
        let raw = ProcessInfo.processInfo.environment["MASCOTUSCAN_UPDATE_URL"] ?? defaultEndpoint
        return URL(string: raw) ?? URL(string: defaultEndpoint)!
    }

    /// Una consulta real por dia como maximo. Los timers pueden disparar mas
    /// seguido; esta es la que manda.
    public static let minInterval: TimeInterval = 24 * 3600

    public static func shouldQuery(state: UpdateState, now: Date = Date()) -> Bool {
        guard let last = state.checkedAt else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }

    /// Saca la version de la respuesta de GitHub (`tag_name`). nil si no hay
    /// release o la respuesta no es la esperada.
    public static func parseLatest(_ data: Data) -> Semver? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        return Semver(tag)
    }

    /// La regla de silencio: se habla una sola vez por version nueva. Devuelve
    /// la version a anunciar y el estado ya actualizado para guardar.
    public static func decide(current: Semver, latest: Semver?, state: UpdateState,
                              now: Date = Date()) -> (announce: Semver?, state: UpdateState) {
        var next = state
        next.checkedAt = now
        next.latest = latest?.description
        guard let latest = latest, latest > current else { return (nil, next) }
        if let done = state.announced, let doneV = Semver(done), doneV >= latest {
            return (nil, next)
        }
        next.announced = latest.description
        return (latest, next)
    }

    /// Consulta en segundo plano. Nunca bloquea; un fallo de red se reporta como
    /// nil y quien llama decide si lo registra.
    public static func fetchLatest(timeout: TimeInterval = 10,
                                   done: @escaping (Semver?, String?) -> Void) {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = timeout
        req.setValue("mascotuscan/\(mascoTuscanVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, error in
            if let error = error { done(nil, "sin red: \(error.localizedDescription)"); return }
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                done(nil, "sin versiones publicadas todavía"); return
            }
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                done(nil, "GitHub respondió \(http.statusCode)"); return
            }
            guard let data = data, let v = parseLatest(data) else {
                done(nil, "la respuesta no traía una versión"); return
            }
            done(v, nil)
        }.resume()
    }
}
