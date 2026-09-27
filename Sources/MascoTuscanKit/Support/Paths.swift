// Rutas del asistente y utilidades base.

import Foundation

public let mascoTuscanVersion = "0.3.0"

let fm = FileManager.default
let homeURL = fm.homeDirectoryForCurrentUser

/// Todo el estado en disco vive bajo ~/.mascotuscan. El repo nunca escribe ahi:
/// el instalador lo crea y la app lo mantiene.
public enum PetPaths {
    public static let home = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent(".mascotuscan")

    public static var config: URL { home.appendingPathComponent("config.json") }
    public static var voice: URL { home.appendingPathComponent("voice.json") }
    public static var shellLog: URL { home.appendingPathComponent("shell.jsonl") }
    public static var pid: URL { home.appendingPathComponent("pet.pid") }
    public static var sprites: URL { home.appendingPathComponent("sprites") }
    /// Misma forma en macOS y Windows: ver docs/reference/versioning.md.
    public static var update: URL { home.appendingPathComponent("update.json") }

    /// Los nombres anteriores del producto escribian aqui, del mas reciente al
    /// mas viejo: LucyGlow en ~/.lucy y cmux-pet en ~/.cmux-pet. Migrar en vez
    /// de empezar de cero: nadie deberia perder su configuracion, sus mascotas
    /// o sus frases generadas solo porque el producto cambio de nombre.
    static var legacyHomes: [URL] {
        [".lucy", ".cmux-pet"].map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0)
        }
    }

    public static func ensureHome() {
        if let old = migrateLegacyHome(to: home, from: legacyHomes) {
            plog("migrado ~/\(old.lastPathComponent) -> ~/.mascotuscan (el producto ahora se llama MascoTuscan)")
        }
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    /// Mueve a `home` el primer directorio viejo que exista. Si `home` ya
    /// existe no toca nada: mezclar dos estados podria pisar el nuevo con el
    /// viejo. Devuelve el directorio que se movio.
    static func migrateLegacyHome(to home: URL, from candidates: [URL]) -> URL? {
        guard !FileManager.default.fileExists(atPath: home.path) else { return nil }
        guard let old = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return nil }
        do {
            try FileManager.default.moveItem(at: old, to: home)
            return old
        } catch {
            plog("no pude migrar \(old.path) a \(home.path): \(error.localizedDescription)")
            return nil
        }
    }
}

let petHome = PetPaths.home
let configURL = PetPaths.config
let shellLogURL = PetPaths.shellLog
let pidURL = PetPaths.pid

/// Traza a stderr. Bajo el arranque normal termina en ~/.mascotuscan/pet.log y es
/// el primer lugar donde mirar cuando un aviso no llega.
func plog(_ s: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    if let d = "[\(stamp)] \(s)\n".data(using: .utf8) {
        FileHandle.standardError.write(d)
    }
}

/// Instancia unica: si habia otra corriendo, se le pide que salga y tomamos el relevo.
public func takeOverPidFile() {
    if let s = try? String(contentsOf: PetPaths.pid, encoding: .utf8),
       let old = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)),
       old != getpid(), kill(old, 0) == 0 {
        kill(old, SIGTERM)
        usleep(400_000)
    }
    try? "\(getpid())".write(to: PetPaths.pid, atomically: true, encoding: .utf8)
}
