// Ponerle imagenes a una mascota, y sacar copias propias de las de fabrica.
//
// Antes esto exigia editar pet.json a mano: cambiar el renderer, declarar cada
// ruta y copiar los archivos al lugar correcto. Nadie que no haya leido el
// formato podia hacerlo, que es justo el publico al que apunta el proyecto.

import AppKit
import Foundation

extension PetCommands {
    static let spriteExtensions = ["gif", "png", "webp", "heic", "jpg", "jpeg", "tiff", "pdf"]

    // MARK: sprite

    /// `mascotuscan sprite <id> <estado> <archivo>` pone una imagen.
    /// `mascotuscan sprite <id> --dir <carpeta>` toma varias por nombre de archivo.
    /// `mascotuscan sprite <id> --clear` vuelve al dibujo vectorial.
    static func sprite(_ args: [String]) -> Int32 {
        let positional = args.filter { !$0.hasPrefix("--") }
        guard let id = positional.first else {
            err("falta el id. Uso: mascotuscan sprite <id> <estado> <archivo>")
            err("                 mascotuscan sprite <id> --dir <carpeta>")
            err("                 mascotuscan sprite <id> --clear")
            return 2
        }
        guard let pack = PetLibrary.find(id) else {
            err("no tengo instalada \"\(id)\". Mira \"mascotuscan list\".")
            return 1
        }
        // Las mascotas de fabrica se reemplazan en cada instalacion: editarlas
        // seria perder el trabajo sin aviso.
        if PetLibrary.isBundled(id) {
            err("\"\(id)\" viene con mascotuscan y se reemplaza al actualizar.")
            err("Saca tu propia copia y edítala:")
            err("    mascotuscan fork \(id) mi-\(id)")
            err("    mascotuscan sprite mi-\(id) \(positional.count > 1 ? positional[1] : "idle") <archivo>")
            return 1
        }

        if args.contains("--clear") { return clearSprites(pack) }

        if let i = args.firstIndex(of: "--dir") {
            guard i + 1 < args.count else {
                err("--dir necesita una carpeta")
                return 2
            }
            return spritesFromDir(pack, dir: args[i + 1])
        }

        guard positional.count >= 3 else {
            err("faltan argumentos. Uso: mascotuscan sprite \(id) <estado> <archivo>")
            err("Estados: \(PetPack.validStates.joined(separator: ", "))")
            return 2
        }
        return setSprite(pack, state: positional[1], file: positional[2])
    }

    /// Copia una imagen al paquete y la declara en el manifiesto.
    static func setSprite(_ pack: PetPack, state: String, file: String) -> Int32 {
        guard PetPack.validStates.contains(state) else {
            err("estado desconocido \"\(state)\". Válidos: \(PetPack.validStates.joined(separator: ", "))")
            return 2
        }
        let src = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        guard fm.fileExists(atPath: src.path) else {
            err("no encuentro el archivo \(src.path)")
            return 1
        }
        let ext = src.pathExtension.lowercased()
        guard spriteExtensions.contains(ext) else {
            err("formato \".\(ext)\" no soportado. Usa: \(spriteExtensions.joined(separator: ", "))")
            return 1
        }
        // Que la imagen abra de verdad: un archivo corrupto dejaria la mascota
        // invisible y el fallo apareceria recien al dibujar.
        guard NSImage(contentsOf: src) != nil else {
            err("no pude leer \(src.lastPathComponent) como imagen")
            return 1
        }

        let spritesDir = pack.root.appendingPathComponent("sprites")
        try? fm.createDirectory(at: spritesDir, withIntermediateDirectories: true)

        // Un estado tiene una sola imagen: se quitan las de otras extensiones.
        for e in spriteExtensions {
            try? fm.removeItem(at: spritesDir.appendingPathComponent("\(state).\(e)"))
        }
        let dest = spritesDir.appendingPathComponent("\(state).\(ext)")
        do {
            try fm.copyItem(at: src, to: dest)
        } catch {
            err("no pude copiar la imagen: \(error.localizedDescription)")
            return 1
        }

        return updateManifest(pack) { m in
            var sprites = (m["sprites"] as? [String: String]) ?? [:]
            sprites[state] = "sprites/\(state).\(ext)"
            m["sprites"] = sprites
            m["renderer"] = "sprites"
        } then: { updated in
            out("\(bold(updated.name)): \(state) ahora usa \(src.lastPathComponent)")
            reportMissingStates(updated)
        }
    }

    /// Toma una carpeta y usa los archivos cuyo nombre sea un estado conocido.
    static func spritesFromDir(_ pack: PetPack, dir: String) -> Int32 {
        let root = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            err("no puedo leer la carpeta \(root.path)")
            return 1
        }
        var found = 0
        for f in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let state = f.deletingPathExtension().lastPathComponent.lowercased()
            guard PetPack.validStates.contains(state),
                  spriteExtensions.contains(f.pathExtension.lowercased()) else { continue }
            guard let fresh = PetLibrary.find(pack.id) else { break }
            if setSprite(fresh, state: state, file: f.path) == 0 { found += 1 }
        }
        guard found > 0 else {
            err("ningún archivo de esa carpeta se llama como un estado.")
            err("Nombres esperados: \(PetPack.validStates.joined(separator: ", "))")
            err("Ejemplo: idle.png, working.gif, done.png")
            return 1
        }
        out("\(found) imagen(es) puestas.")
        return 0
    }

    /// Vuelve al dibujo vectorial sin borrar las imagenes: solo deja de usarlas.
    static func clearSprites(_ pack: PetPack) -> Int32 {
        updateManifest(pack) { m in
            m["sprites"] = [String: String]()
            m["renderer"] = "vector:droid"
        } then: { updated in
            out("\(bold(updated.name)) vuelve al dibujo vectorial.")
            out(dim("  las imágenes siguen en \(pack.root.appendingPathComponent("sprites").path)"))
        }
    }

    /// Avisa de los estados que todavia no tienen imagen: sin sprite ni default,
    /// ese estado cae al vectorial y la mascota se ve mezclada.
    static func reportMissingStates(_ pack: PetPack) {
        guard pack.spritePaths["default"] == nil else { return }
        let missing = Mood.allCases.map(\.rawValue).filter { pack.spritePaths[$0] == nil }
        guard !missing.isEmpty else {
            out(dim("  los seis estados tienen imagen"))
            return
        }
        out(dim("  faltan: \(missing.joined(separator: ", "))"))
        out(dim("  esos estados se dibujan con el vector; pon un \"default\" para cubrirlos todos"))
    }

    // MARK: fork

    /// Saca una copia editable de una mascota. Es la forma correcta de partir de
    /// una de fabrica sin que la proxima actualizacion se lleve los cambios.
    static func fork(_ args: [String]) -> Int32 {
        let positional = args.filter { !$0.hasPrefix("--") }
        guard positional.count >= 2 else {
            err("Uso: mascotuscan fork <origen> <nuevo-id> [--name <texto>]")
            return 2
        }
        let (from, newID) = (positional[0], positional[1])
        guard let source = PetLibrary.find(from) else {
            err("no tengo instalada \"\(from)\".")
            return 1
        }
        guard PetPack.isValidID(newID) else {
            err("\(PackError.badID(newID))")
            return 2
        }
        guard PetLibrary.find(newID) == nil else {
            err("ya existe una mascota con id \"\(newID)\".")
            return 1
        }
        var displayName = newID.capitalized
        if let i = args.firstIndex(of: "--name"), i + 1 < args.count { displayName = args[i + 1] }

        let dest = PetLibrary.petsDir.appendingPathComponent(newID)
        do {
            try fm.copyItem(at: source.root, to: dest)
            // El marcador de fabrica no se hereda: la copia es tuya.
            try? fm.removeItem(at: dest.appendingPathComponent(".bundled"))
        } catch {
            err("no pude copiar el paquete: \(error.localizedDescription)")
            return 1
        }

        guard case .success(let copy) = PetPack.load(from: dest) else {
            try? fm.removeItem(at: dest)
            err("la copia no carga; no la dejo instalada")
            return 1
        }
        let code = updateManifest(copy) { m in
            m["id"] = newID
            m["name"] = displayName
            m["version"] = "0.1.0"
            m["author"] = "tu-usuario"
        } then: { updated in
            out("Copiada \(bold(source.name)) a \(bold(updated.name)) (\(newID))")
            out("")
            out("  1. Edita  \(dest.path)/persona.md   " + dim("cómo habla"))
            out("  2. mascotuscan sprite \(newID) idle <imagen.png>   " + dim("o --dir <carpeta>"))
            out("  3. mascotuscan use \(newID)")
            out("  4. mascotuscan voice \(newID)          " + dim("frases con su personalidad"))
        }
        return code
    }

    // MARK: manifiesto

    /// Lee, muta y reescribe pet.json, validando el resultado. Si la mascota
    /// editada es la activa, se reinicia la app para que el cambio se vea.
    static func updateManifest(_ pack: PetPack,
                               _ mutate: (inout [String: Any]) -> Void,
                               then report: (PetPack) -> Void) -> Int32 {
        guard let data = try? Data(contentsOf: pack.manifestURL),
              var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            err("no pude leer \(pack.manifestURL.path)")
            return 1
        }
        let backup = manifest
        mutate(&manifest)

        func write(_ m: [String: Any]) -> Bool {
            guard let out = try? JSONSerialization.data(
                withJSONObject: m, options: [.prettyPrinted, .sortedKeys]) else { return false }
            return (try? out.write(to: pack.manifestURL, options: .atomic)) != nil
        }
        guard write(manifest) else {
            err("no pude escribir el manifiesto")
            return 1
        }

        // Se relee de disco: lo que vale es lo que quedo escrito, no lo que
        // creimos escribir.
        switch PetPack.load(from: pack.root) {
        case .failure(let e):
            _ = write(backup)
            err("el cambio dejaría el paquete inválido, lo revertí: \(e)")
            return 1
        case .success(let updated):
            report(updated)
            // Solo se reinicia si el paquete es el activo Y vive en la
            // biblioteca. Editar una carpeta suelta no puede tocar la app que
            // esta corriendo, y asi los tests no reinician nada.
            let inLibrary = updated.root.standardizedFileURL.path
                .hasPrefix(PetLibrary.petsDir.standardizedFileURL.path)
            if inLibrary, PetLibrary.active(config: PetConfig.load())?.id == updated.id {
                if restartRunningApp() { out(dim("  asistente reiniciado")) }
            }
            return 0
        }
    }
}
