// Puente con el CLI de cmux. Todo el control de cmux pasa por aqui.

import Foundation

let cmuxPath: String = {
    let candidates = [
        "/Applications/cmux.app/Contents/Resources/bin/cmux",
        "/opt/homebrew/bin/cmux",
        "/usr/local/bin/cmux",
        homeURL.appendingPathComponent(".local/bin/cmux").path,
    ]
    for c in candidates where fm.isExecutableFile(atPath: c) { return c }
    return "/usr/bin/env"
}()

/// Ejecuta cmux y devuelve el JSON parseado. Bloquea: usar fuera del main thread.
func cmuxJSON(_ args: [String]) -> [String: Any]? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmuxPath)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// Arma el JSON de parametros para `cmux rpc <metodo> <json>` sin concatenar
/// strings a mano (un id o una seleccion con comillas rompería eso).
func cmuxParams(_ dict: [String: Any]) -> String {
    (try? JSONSerialization.data(withJSONObject: dict))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

/// Lanza cmux y olvida. No bloquea.
func cmuxFire(_ args: [String]) {
    DispatchQueue.global(qos: .utility).async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmuxPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
