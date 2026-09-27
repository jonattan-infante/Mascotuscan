// El marketplace: un JSON servido por raw.github, sin servidor.
//
// Cada entrada dice donde vive el paquete (`source` + `path`), asi que el arte y
// el codigo se quedan en el repositorio de su autor. Publicar es abrir un PR que
// agrega una entrada. Ver docs/marketplace.md.

import Foundation

public struct RegistryEntry {
    public let id: String
    public let name: String
    public let description: String
    public let author: String
    public let version: String
    public let language: String
    public let renderer: String
    /// Repositorio git donde vive el paquete.
    public let source: String
    /// Subcarpeta dentro de ese repositorio, si el paquete no esta en la raiz.
    public let path: String?
    public let tags: [String]
}

public enum Registry {
    /// El indice oficial. Se puede apuntar a otro con MASCOTUSCAN_REGISTRY, que es
    /// como se prueba un registro propio o uno de empresa.
    public static var url: URL {
        if let custom = ProcessInfo.processInfo.environment["MASCOTUSCAN_REGISTRY"],
           let u = URL(string: custom) {
            return u
        }
        return URL(string: "https://raw.githubusercontent.com/jonattan-infante/mascotuscan/main/registry.json")!
    }

    static var cacheURL: URL { PetPaths.home.appendingPathComponent("registry-cache.json") }

    /// Descarga el indice. Si la red falla, usa el cache: quedarse sin
    /// marketplace por estar en un avion no deberia romper `list` ni `install`.
    public static func fetch(timeout: TimeInterval = 12) -> [RegistryEntry]? {
        var data: Data?
        let sem = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { d, _, _ in
            data = d
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 2)

        if let d = data, let parsed = parse(d) {
            try? d.write(to: cacheURL, options: .atomic)
            return parsed
        }
        // Sin red: el cache es mejor que nada, y se dice en el log.
        if let d = try? Data(contentsOf: cacheURL), let parsed = parse(d) {
            plog("marketplace: sin red, uso el cache local")
            return parsed
        }
        return nil
    }

    public static func find(id: String) -> RegistryEntry? {
        fetch()?.first { $0.id == id }
    }

    static func parse(_ data: Data) -> [RegistryEntry]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = root["schemaVersion"] as? Int, version == 1,
              let pets = root["pets"] as? [[String: Any]]
        else { return nil }

        return pets.compactMap { p in
            guard let id = p["id"] as? String,
                  let name = p["name"] as? String,
                  let description = p["description"] as? String,
                  let author = p["author"] as? String,
                  let version = p["version"] as? String,
                  let source = p["source"] as? String
            else { return nil }
            return RegistryEntry(
                id: id,
                name: name,
                description: description,
                author: author,
                version: version,
                language: (p["language"] as? String) ?? "es",
                renderer: (p["renderer"] as? String) ?? "vector:droid",
                source: source,
                path: p["path"] as? String,
                tags: (p["tags"] as? [String]) ?? []
            )
        }
    }
}
