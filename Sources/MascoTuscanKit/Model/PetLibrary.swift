// La biblioteca de mascotas instaladas: qué hay, cuál está activa, instalar y
// quitar. Es el modelo detrás de los comandos `mascotuscan list/use/install`.

import Foundation

public struct PetLibrary {
    public static var petsDir: URL { PetPaths.home.appendingPathComponent("pets") }
    public static var voicesDir: URL { PetPaths.home.appendingPathComponent("voices") }

    public static func ensureDirs() {
        try? FileManager.default.createDirectory(at: petsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)
    }

    /// Las frases generadas viven fuera del pack para que actualizarlo no las
    /// borre y para que un pack de solo lectura nunca se modifique.
    public static func voiceURL(for id: String) -> URL {
        voicesDir.appendingPathComponent("\(id).json")
    }

    // MARK: consultar

    /// Todos los packs instalados que cargan sin error, ordenados por id.
    public static func installed() -> [PetPack] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: petsDir, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { dir -> PetPack? in
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return nil }
            switch PetPack.load(from: dir) {
            case .success(let p): return p
            case .failure(let e):
                plog("mascota inválida en \(dir.lastPathComponent): \(e)")
                return nil
            }
        }.sorted { $0.id < $1.id }
    }

    /// Las mascotas que trae el instalador se reemplazan al actualizar, asi que
    /// editarlas seria perder el trabajo sin aviso. El marcador lo escribe
    /// install.sh al copiarlas.
    public static func isBundled(_ id: String) -> Bool {
        FileManager.default.fileExists(
            atPath: petsDir.appendingPathComponent(id).appendingPathComponent(".bundled").path)
    }

    public static func find(_ id: String) -> PetPack? {
        switch PetPack.load(from: petsDir.appendingPathComponent(id)) {
        case .success(let p): return p
        case .failure: return nil
        }
    }

    /// La mascota activa. Si la configurada no existe, cae a la primera instalada.
    public static func active(config: PetConfig) -> PetPack? {
        if let id = config.activePet, let p = find(id) { return p }
        return installed().first
    }

    // MARK: modificar

    /// Copia un pack desde una carpeta a la biblioteca. Valida antes de escribir:
    /// nunca se instala algo que no carga.
    public static func install(from source: URL, overwrite: Bool) -> Result<PetPack, InstallError> {
        ensureDirs()
        let pack: PetPack
        switch PetPack.load(from: source) {
        case .success(let p): pack = p
        case .failure(let e): return .failure(.invalid(e))
        }

        let dest = petsDir.appendingPathComponent(pack.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            guard overwrite else { return .failure(.alreadyInstalled(pack.id)) }
            try? FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }

        // Se relee desde el destino: lo que queda instalado es lo que se valida.
        switch PetPack.load(from: dest) {
        case .success(let p): return .success(p)
        case .failure(let e):
            try? FileManager.default.removeItem(at: dest)
            return .failure(.invalid(e))
        }
    }

    /// Quita un pack. Las frases generadas se van con él: son suyas.
    public static func remove(_ id: String) -> Bool {
        let dir = petsDir.appendingPathComponent(id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: voiceURL(for: id))
        return true
    }

    public enum InstallError: Error, CustomStringConvertible {
        case invalid(PackError)
        case alreadyInstalled(String)
        case copyFailed(String)

        public var description: String {
            switch self {
            case .invalid(let e):
                return "el paquete no es válido: \(e)"
            case .alreadyInstalled(let id):
                return "\"\(id)\" ya está instalada; usa --force para reemplazarla"
            case .copyFailed(let m):
                return "no pude copiar el paquete: \(m)"
            }
        }
    }
}
