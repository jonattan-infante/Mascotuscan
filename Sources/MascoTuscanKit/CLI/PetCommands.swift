// Los comandos de la mascota: listar, cambiar, instalar, crear, validar.
//
// Viven en la libreria y no en main.swift para que se puedan probar. Cada
// comando devuelve un codigo de salida y escribe a stdout: es una herramienta de
// terminal, no una interfaz.

import Foundation

public enum PetCommands {
    // MARK: entrada

    /// Ejecuta un subcomando. Devuelve el codigo de salida, o nil si el
    /// argumento no es un subcomando y hay que arrancar la app.
    public static func run(_ args: [String]) -> Int32? {
        guard let cmd = args.first else { return nil }
        let rest = Array(args.dropFirst())

        switch cmd {
        case "list", "ls":       return list()
        case "use":              return use(rest)
        case "info":             return info(rest)
        case "install", "add":   return install(rest)
        case "uninstall", "rm":  return uninstall(rest)
        case "new", "create":    return scaffold(rest)
        case "sprite", "image":  return sprite(rest)
        case "fork", "copy":     return fork(rest)
        case "renderers":        return renderers()
        case "validate", "check":return validate(rest)
        case "voice":            return voice(rest)
        case "search":           return search(rest)
        case "update", "upgrade": return update(rest)
        case "help", "--help", "-h": return help()
        default:                 return nil
        }
    }

    // MARK: utilidades de salida

    static func out(_ s: String = "") { print(s) }
    static func err(_ s: String) { FileHandle.standardError.write(Data("\(s)\n".utf8)) }

    static func bold(_ s: String) -> String { "\u{1B}[1m\(s)\u{1B}[0m" }
    static func dim(_ s: String) -> String { "\u{1B}[2m\(s)\u{1B}[0m" }

    // MARK: help

    static func help() -> Int32 {
        out("""
        \(bold("mascotuscan")) — MascoTuscan, la mascota flotante que vigila tus agentes de IA

        \(bold("Uso"))
          mascotuscan                     arranca la mascota activa
          mascotuscan <comando> [opciones]

        \(bold("Mascotas instaladas"))
          list                            lista las mascotas y marca la activa
          use <id>                        cambia la mascota activa
          info <id>                       muestra el detalle de una mascota
          uninstall <id>                  la quita, con sus frases

        \(bold("Conseguir mascotas"))
          search [texto]                  busca en el marketplace
          install <id>                    instala del marketplace
          install <url-git>               instala de un repositorio
          install <ruta>                  instala de una carpeta local
            --force                       reemplaza si ya estaba instalada
            --use                         la activa despues de instalar

        \(bold("Crear y personalizar"))
          new <id>                        crea un paquete nuevo listo para editar
            --sprites                     con carpeta de imagenes en vez de vectorial
            --name <texto>                nombre para mostrar
          fork <origen> <nuevo-id>        copia editable de una mascota existente
          sprite <id> <estado> <archivo>  ponle una imagen a un estado
          sprite <id> --dir <carpeta>     varias a la vez, por nombre de archivo
          sprite <id> --clear             vuelve al dibujo vectorial
          renderers                       dibujos integrados disponibles
          validate <ruta>                 revisa un paquete y explica cada fallo
          voice [<id>]                    reescribe sus frases con Claude Code

        \(bold("Otros"))
          update                          reinstala la última versión publicada
            --check                       solo dice si hay una más nueva
          --render <carpeta>              dibuja cada estado a PNG, sin abrir ventana
          --version
          help

        Formato de paquete: docs/reference/pet-pack.md
        """)
        return 0
    }

    // MARK: list

    static func list() -> Int32 {
        PetLibrary.ensureDirs()
        let pets = PetLibrary.installed()
        guard !pets.isEmpty else {
            out("No hay mascotas instaladas.")
            out("")
            out("  mascotuscan search           ver el marketplace")
            out("  mascotuscan install astro    instalar la de por defecto")
            out("  mascotuscan new mi-mascota   crear una propia")
            return 0
        }
        let config = PetConfig.load()
        let activeID = PetLibrary.active(config: config)?.id
        out(bold("Mascotas instaladas"))
        for p in pets {
            let mark = p.id == activeID ? "*" : " "
            let voice = fm.fileExists(atPath: PetLibrary.voiceURL(for: p.id).path)
                ? "" : dim("  (sin frases generadas)")
            out(" \(mark) \(p.id.padding(toLength: max(14, p.id.count + 1), withPad: " ", startingAt: 0))"
                + "\(p.name)  \(dim("v\(p.version)  \(p.renderer.raw)"))\(voice)")
        }
        out("")
        out(dim("  * activa. Cambiar con: mascotuscan use <id>"))
        return 0
    }

    // MARK: use

    static func use(_ args: [String]) -> Int32 {
        guard let id = args.first else {
            err("falta el id. Uso: mascotuscan use <id>")
            return 2
        }
        guard let pack = PetLibrary.find(id) else {
            err("no tengo instalada \"\(id)\". Mira \"mascotuscan list\".")
            return 1
        }
        var config = PetConfig.load()
        config.activePet = pack.id
        config.save()
        out("Mascota activa: \(bold(pack.name)) (\(pack.id))")

        // La app relee la configuracion al arrancar, asi que hay que reiniciarla.
        if restartRunningApp() {
            out(dim("  asistente reiniciado"))
        } else {
            out(dim("  abre una terminal de cmux para que arranque"))
        }
        return 0
    }

    // MARK: info

    static func info(_ args: [String]) -> Int32 {
        guard let id = args.first else {
            err("falta el id. Uso: mascotuscan info <id>")
            return 2
        }
        guard let p = PetLibrary.find(id) else {
            err("no tengo instalada \"\(id)\".")
            return 1
        }
        out(bold(p.name) + "  " + dim("\(p.id) v\(p.version)"))
        out("")
        out("  \(p.description)")
        out("")
        out("  autor       \(p.author)")
        out("  licencia    \(p.license)")
        out("  idioma      \(p.language)")
        out("  renderer    \(p.renderer.raw)")
        if !p.spritePaths.isEmpty {
            let states = p.spritePaths.keys.sorted().joined(separator: ", ")
            out("  sprites     \(states)")
        }
        if !p.accents.isEmpty {
            out("  colores     \(p.accents.keys.sorted().joined(separator: ", "))")
        }
        let voiceURL = PetLibrary.voiceURL(for: p.id)
        if let d = try? Data(contentsOf: voiceURL),
           let raw = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            let n = Voice.validate(raw).values.reduce(0) { $0 + $1.count }
            out("  frases      \(n) generadas")
        } else {
            let n = p.fallbackPhrases.values.reduce(0) { $0 + $1.count }
            out("  frases      \(n) de respaldo, ninguna generada todavía")
            out(dim("              mascotuscan voice \(p.id)"))
        }
        out("")
        out("  \(dim(p.root.path))")
        return 0
    }

    // MARK: install

    static func install(_ args: [String]) -> Int32 {
        let force = args.contains("--force")
        let thenUse = args.contains("--use")
        guard let target = args.first(where: { !$0.hasPrefix("--") }) else {
            err("falta qué instalar. Uso: mascotuscan install <id|url-git|ruta>")
            return 2
        }

        PetLibrary.ensureDirs()

        // Una ruta local se instala tal cual.
        let asPath = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        if fm.fileExists(atPath: asPath.appendingPathComponent("pet.json").path) {
            return finishInstall(PetLibrary.install(from: asPath, overwrite: force), use: thenUse)
        }

        // Una URL de git se clona a temporal.
        if target.hasPrefix("http") || target.hasPrefix("git@") || target.hasSuffix(".git") {
            return installFromGit(url: target, subpath: nil, force: force, use: thenUse)
        }

        // Si no, es un id del marketplace.
        guard let entry = Registry.find(id: target) else {
            err("no encuentro \"\(target)\" en el marketplace ni como ruta local.")
            err("Prueba: mascotuscan search")
            return 1
        }
        out("Instalando \(bold(entry.name)) de \(entry.author)")
        return installFromGit(url: entry.source, subpath: entry.path, force: force, use: thenUse)
    }

    static func installFromGit(url: String, subpath: String?, force: Bool, use: Bool) -> Int32 {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mascotuscan-install-\(getpid())")
        defer { try? fm.removeItem(at: tmp) }

        out(dim("  clonando \(url)"))
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        git.arguments = ["git", "clone", "--depth", "1", url, tmp.path]
        git.standardOutput = FileHandle.nullDevice
        git.standardError = FileHandle.nullDevice
        do { try git.run() } catch {
            err("no pude ejecutar git")
            return 1
        }
        git.waitUntilExit()
        guard git.terminationStatus == 0 else {
            err("el clon falló. Revisa la URL y tu acceso.")
            return 1
        }

        let source = subpath.map { tmp.appendingPathComponent($0) } ?? tmp
        return finishInstall(PetLibrary.install(from: source, overwrite: force), use: use)
    }

    static func finishInstall(_ result: Result<PetPack, PetLibrary.InstallError>, use: Bool) -> Int32 {
        switch result {
        case .failure(let e):
            err("\(e)")
            return 1
        case .success(let p):
            out("Instalada \(bold(p.name)) (\(p.id)) v\(p.version)")
            if p.fallbackPhrases.isEmpty {
                out(dim("  no trae frases de respaldo: conviene generarlas"))
                out(dim("  mascotuscan voice \(p.id)"))
            }
            if use {
                return PetCommands.use([p.id])
            }
            out(dim("  activar con: mascotuscan use \(p.id)"))
            return 0
        }
    }

    // MARK: uninstall

    static func uninstall(_ args: [String]) -> Int32 {
        guard let id = args.first else {
            err("falta el id. Uso: mascotuscan uninstall <id>")
            return 2
        }
        guard PetLibrary.remove(id) else {
            err("no tengo instalada \"\(id)\".")
            return 1
        }
        out("Quitada \"\(id)\".")

        // Si era la activa, hay que dejar otra o la app no tiene qué mostrar.
        var config = PetConfig.load()
        if config.activePet == id {
            config.activePet = PetLibrary.installed().first?.id
            config.save()
            if let next = config.activePet {
                out("Mascota activa ahora: \(next)")
                _ = restartRunningApp()
            } else {
                out(dim("  no queda ninguna instalada; instala otra con: mascotuscan install astro"))
            }
        }
        return 0
    }

    // MARK: new

    static func scaffold(_ args: [String]) -> Int32 {
        guard let id = args.first(where: { !$0.hasPrefix("--") }) else {
            err("falta el id. Uso: mascotuscan new <id> [--sprites] [--name <texto>]")
            return 2
        }
        guard PetPack.isValidID(id) else {
            err("\(PackError.badID(id))")
            return 2
        }
        let useSprites = args.contains("--sprites")
        var displayName = id.capitalized
        if let i = args.firstIndex(of: "--name"), i + 1 < args.count {
            displayName = args[i + 1]
        }

        let dir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(id)
        guard !fm.fileExists(atPath: dir.path) else {
            err("la carpeta \"\(id)\" ya existe aquí.")
            return 1
        }

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if useSprites {
                try fm.createDirectory(at: dir.appendingPathComponent("sprites"),
                                       withIntermediateDirectories: true)
            }
            try Scaffold.manifest(id: id, name: displayName, sprites: useSprites)
                .write(to: dir.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
            try Scaffold.persona(name: displayName)
                .write(to: dir.appendingPathComponent("persona.md"), atomically: true, encoding: .utf8)
            try Scaffold.phrases(name: displayName)
                .write(to: dir.appendingPathComponent("phrases.json"), atomically: true, encoding: .utf8)
            if useSprites {
                try Scaffold.spritesReadme()
                    .write(to: dir.appendingPathComponent("sprites/LEEME.txt"),
                           atomically: true, encoding: .utf8)
            }
        } catch {
            err("no pude crear el paquete: \(error.localizedDescription)")
            return 1
        }

        out("Mascota \(bold(displayName)) creada en ./\(id)")
        out("")
        out("  1. Edita  \(id)/persona.md   " + dim("cómo habla"))
        if useSprites {
            out("  2. Pon tus imágenes en \(id)/sprites/  " + dim("idle, working, done, error, attention, info"))
        } else {
            out("  2. Ajusta los colores en \(id)/pet.json  " + dim("usa el droide vectorial integrado"))
        }
        out("  3. mascotuscan validate ./\(id)")
        out("  4. mascotuscan install ./\(id) --use")
        out("  5. mascotuscan voice \(id)      " + dim("Claude Code le escribe las frases"))
        out("")
        out(dim("  Publicar en el marketplace: docs/marketplace.md"))
        return 0
    }

    // MARK: renderers

    /// Los dibujos integrados. Se listan desde el registro para que agregar uno
    /// no obligue a actualizar la ayuda a mano.
    static func renderers() -> Int32 {
        out(bold("Dibujos integrados"))
        for r in VectorRenderers.all {
            out("  \(r.id.padding(toLength: 16, withPad: " ", startingAt: 0))\(r.title)")
            out("  \(dim("                \(r.summary)"))")
        }
        out("")
        out("  \(("sprites").padding(toLength: 16, withPad: " ", startingAt: 0))Tus propias imágenes")
        out("  \(dim("                mascotuscan sprite <id> <estado> <archivo>"))")
        out("")
        out(dim("  Se declara en pet.json, campo \"renderer\"."))
        return 0
    }

    // MARK: validate

    static func validate(_ args: [String]) -> Int32 {
        let target = args.first(where: { !$0.hasPrefix("--") }) ?? "."
        let dir = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
            .standardizedFileURL

        out("Revisando \(dir.lastPathComponent)")
        var problems = 0

        switch PetPack.load(from: dir) {
        case .failure(let e):
            out("  falla  \(e)")
            problems += 1
        case .success(let p):
            out("  ok     manifiesto: \(p.name) v\(p.version) de \(p.author)")
            out("  ok     renderer: \(p.renderer.raw)")
            if case .unknown(let r) = p.renderer {
                out("  aviso  renderer \"\(r)\" desconocido; se usará el vectorial")
            }
            if p.renderer == .sprites {
                let faltan = Mood.allCases.map(\.rawValue)
                    .filter { p.spritePaths[$0] == nil }
                if p.spritePaths["default"] != nil {
                    out("  ok     sprites: \(p.spritePaths.count) declarados, con default de respaldo")
                } else if faltan.isEmpty {
                    out("  ok     sprites: los seis estados declarados")
                } else {
                    out("  aviso  sin sprite ni default para: \(faltan.joined(separator: ", "))")
                    out("         esos estados caerán al droide vectorial")
                }
            }
            if let r = p.roam {
                let arranque = r.start.map { "arranque \($0.lastPathComponent), " } ?? "sin arranque, "
                out("  ok     roam: \(arranque)bucle \(r.loop.lastPathComponent), \(Int(r.speed)) pt/s")
            }
            out("  ok     persona.md: \(p.persona?.count ?? 0) caracteres")

            // phrases.json es opcional, pero si esta, tiene que servir.
            if fm.fileExists(atPath: p.phrasesURL.path) {
                guard let d = try? Data(contentsOf: p.phrasesURL),
                      let raw = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
                    out("  falla  phrases.json no es JSON válido")
                    problems += 1
                    break
                }
                let (ok, empty) = Voice.validateReporting(raw)
                for k in empty {
                    out("  falla  \(PackError.emptyPhraseClass(k))")
                    problems += 1
                }
                let total = ok.values.reduce(0) { $0 + $1.count }
                out("  ok     phrases.json: \(total) plantillas válidas en \(ok.count) clases")
                let sinCubrir = Voice.kinds.keys.filter { ok[$0] == nil }.sorted()
                if !sinCubrir.isEmpty {
                    out("  aviso  sin frases de respaldo para: \(sinCubrir.joined(separator: ", "))")
                    out("         hasta generar frases, esos avisos no saldrán")
                }
            } else {
                out("  aviso  sin phrases.json: la mascota no habla hasta generar frases")
            }
        }

        out("")
        if problems == 0 {
            out("Sin problemas. Instalar con: mascotuscan install \(target) --use")
            return 0
        }
        out("\(problems) problema(s). Ver docs/reference/pet-pack.md")
        return 1
    }

    // MARK: voice

    static func voice(_ args: [String]) -> Int32 {
        let config = PetConfig.load()
        let id = args.first(where: { !$0.hasPrefix("--") })
        let pack: PetPack?
        if let id = id {
            pack = PetLibrary.find(id)
            if pack == nil { err("no tengo instalada \"\(id)\"."); return 1 }
        } else {
            pack = PetLibrary.active(config: config)
            if pack == nil { err("no hay mascota activa. Instala una: mascotuscan install astro"); return 1 }
        }
        guard let p = pack else { return 1 }

        out("Escribiendo frases para \(bold(p.name)) con Claude Code.")
        out(dim("  usa tu sesión local, sin API key. Tarda cerca de un minuto."))

        Voice.shared.activate(p)
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Voice.shared.regenerate("pedido por el comando voice") { ok, detail in
            if ok {
                out("Listo: \(detail)")
                if let phrase = Voice.shared.phrase("greeting", [:]) {
                    out("")
                    out("  \(phrase)")
                }
            } else {
                err("no salió: \(detail)")
                code = 1
            }
            sem.signal()
        }
        // El comando es sincronico a proposito: el usuario espera el resultado.
        _ = sem.wait(timeout: .now() + 300)

        if code == 0 && PetLibrary.active(config: config)?.id == p.id {
            _ = restartRunningApp()
        }
        return code
    }

    // MARK: search

    static func search(_ args: [String]) -> Int32 {
        let query = args.filter { !$0.hasPrefix("--") }.joined(separator: " ").lowercased()
        out(dim("  consultando el marketplace"))
        guard let entries = Registry.fetch() else {
            err("no pude leer el marketplace. Revisa tu conexión.")
            err("También puedes instalar de una ruta local o una URL de git.")
            return 1
        }
        let installed = Set(PetLibrary.installed().map(\.id))
        let hits = query.isEmpty ? entries : entries.filter {
            $0.id.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
                || $0.tags.contains { $0.lowercased().contains(query) }
        }
        guard !hits.isEmpty else {
            out("Nada coincide con \"\(query)\".")
            return 0
        }
        out(bold("Marketplace de mascotas"))
        for e in hits {
            let mark = installed.contains(e.id) ? "*" : " "
            out(" \(mark) \(e.id.padding(toLength: max(14, e.id.count + 1), withPad: " ", startingAt: 0))"
                + "\(e.name)  \(dim("v\(e.version) · \(e.author) · \(e.language)"))")
            out("   \(dim(e.description))")
        }
        out("")
        out(dim("  * ya instalada.  Instalar: mascotuscan install <id> --use"))
        return 0
    }

    // MARK: update

    static let installerURL =
        "https://raw.githubusercontent.com/jonattan-infante/mascotuscan/main/install.sh"

    /// `update --check` compara y dice; `update` reinstala con el mismo
    /// instalador que usa la terminal. Que el instalador decida que version:
    /// asi el CLI y el curl del README hacen exactamente lo mismo.
    static func update(_ args: [String]) -> Int32 {
        guard let current = Semver(mascoTuscanVersion) else { return 1 }
        out("mascotuscan \(current)")

        let sem = DispatchSemaphore(value: 0)
        var latest: Semver?
        var problem: String?
        UpdateCheck.fetchLatest { v, p in latest = v; problem = p; sem.signal() }
        sem.wait()

        if let problem = problem {
            out(dim("  \(problem)"))
        } else if let latest = latest {
            out(latest > current ? "Hay una versión nueva: \(bold(latest.description))"
                                 : "Estás en la última versión publicada.")
        }
        if args.contains("--check") { return 0 }
        if let latest = latest, latest <= current, !args.contains("--force") {
            out(dim("  para reinstalar igual: mascotuscan update --force"))
            return 0
        }

        out("")
        out("Reinstalando con \(dim(installerURL))")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "curl -fsSL \"\(installerURL)\" | bash"]
        do { try p.run() } catch {
            err("no pude ejecutar el instalador: \(error)")
            return 1
        }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: reiniciar la app

    /// La app lee la configuracion al arrancar, asi que cambiar de mascota
    /// implica reiniciarla. Devuelve true si habia una corriendo.
    @discardableResult
    static func restartRunningApp() -> Bool {
        guard let pidStr = try? String(contentsOf: PetPaths.pid, encoding: .utf8),
              let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0
        else { return false }

        let binary = PetPaths.home.appendingPathComponent("bin/mascotuscan")
        kill(pid, SIGTERM)
        usleep(500_000)

        guard fm.isExecutableFile(atPath: binary.path) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // nohup + & para que sobreviva a la salida de este comando.
        p.arguments = ["-c", "nohup \(binary.path) >> \(PetPaths.home.path)/pet.log 2>&1 &"]
        try? p.run()
        p.waitUntilExit()
        return true
    }
}
