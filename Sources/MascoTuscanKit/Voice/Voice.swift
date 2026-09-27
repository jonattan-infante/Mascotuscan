// Voz de la mascota activa.
//
// Las frases no viven en el codigo: cada pack trae su personalidad en prosa
// (persona.md) y sus frases de respaldo (phrases.json). Claude Code local
// convierte esa personalidad en plantillas, que se guardan en
// ~/.mascotuscan/voices/<id>.json.
//
// Ver docs/adr/0002 (por que plantillas y no mensajes) y
// docs/adr/0005 (por que la personalidad vive en el pack).

import Foundation

public final class Voice {
    public static let shared = Voice()

    /// Marcadores obligatorios de cada clase de aviso. Es el vocabulario que
    /// comparten el generador, el validador y el formato de pack.
    public static let kinds: [String: Set<String>] = [
        "agentDone":    ["agent", "where"],
        "commandDone":  ["cmd", "time", "where"],
        "commandError": ["cmd", "code", "where"],
        "attention":    ["agent", "what", "where"],
        "working":      ["agent", "doing", "time", "where"],
        "portUp":       ["port", "where"],
        "portDown":     ["port", "where"],
        "greeting":     [],
        "updateAvailable": ["version"],
    ]

    /// Cuantas plantillas por clase se le piden al generador.
    static let batchPerKind = 8

    private var pack: PetPack?
    private var generated: [String: [String]] = [:]
    private var fallback: [String: [String]] = [:]
    private var lastPick: [String: Int] = [:]
    private var generating = false

    private var voiceURL: URL? {
        pack.map { PetLibrary.voiceURL(for: $0.id) }
    }

    public var isLoaded: Bool { !generated.isEmpty || !fallback.isEmpty }
    public var hasGenerated: Bool { !generated.isEmpty }

    public var ageInDays: Double? {
        guard let url = voiceURL,
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let d = attrs[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(d) / 86400
    }

    // MARK: activar una mascota

    /// Cambia de mascota: carga su respaldo y sus frases generadas si las hay.
    public func activate(_ pack: PetPack) {
        self.pack = pack
        lastPick = [:]
        fallback = pack.fallbackPhrases
        generated = [:]
        if let url = voiceURL,
           let data = try? Data(contentsOf: url),
           let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            generated = Voice.validate(raw)
        }
        plog("voz de \(pack.name): \(generated.count) clases generadas, \(fallback.count) de respaldo")
    }

    // MARK: usar

    /// Rellena una plantilla. Lo generado gana; el respaldo del pack cubre los
    /// huecos. Devuelve nil solo si la mascota no tiene nada para esa clase.
    public func phrase(_ kind: String, _ vars: [String: String]) -> String? {
        let options = generated[kind] ?? fallback[kind] ?? []
        guard !options.isEmpty else { return nil }

        var i = Int.random(in: 0..<options.count)
        // No repetir la misma frase dos veces seguidas.
        if options.count > 1, let last = lastPick[kind], last == i {
            i = (i + 1) % options.count
        }
        lastPick[kind] = i

        var s = options[i]
        for (k, v) in vars {
            s = s.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return s.replacingOccurrences(of: "  ", with: " ")
    }

    // MARK: validar

    /// Solo sobreviven las plantillas que usan todos sus marcadores y ninguno
    /// inventado. Sin esto, una mascota podria mostrar "{time}" literal.
    public static func validate(_ raw: [String: Any]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        let allowed = Set(kinds.values.flatMap { $0 })
        for (kind, required) in kinds {
            guard let list = raw[kind] as? [String] else { continue }
            let good = list.filter { t in
                guard t.count <= 220, !t.contains("\n") else { return false }
                for r in required where !t.contains("{\(r)}") { return false }
                var scan = Substring(t)
                while let open = scan.firstIndex(of: "{") {
                    guard let close = scan[open...].firstIndex(of: "}") else { break }
                    let name = String(scan[scan.index(after: open)..<close])
                    if !allowed.contains(name) { return false }
                    scan = scan[scan.index(after: close)...]
                }
                return true
            }
            if !good.isEmpty { out[kind] = good }
        }
        return out
    }

    /// Igual que `validate` pero reporta que clases se quedaron vacias. Lo usa
    /// `mascotuscan validate` para explicar el problema en vez de callarlo.
    public static func validateReporting(_ raw: [String: Any]) -> (ok: [String: [String]], empty: [String]) {
        let ok = validate(raw)
        let declared = kinds.keys.filter { raw[$0] != nil }
        return (ok, declared.filter { ok[$0] == nil })
    }

    // MARK: generar

    /// El binario real de Claude Code, no el envoltorio de cmux: el envoltorio
    /// inyecta hooks y el asistente terminaria anunciando a su propio generador.
    static func claudeBinary() -> String? {
        let candidates = [
            homeURL.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/Applications/cmux.app/Contents/Resources/bin/claude",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Pide un lote nuevo para la mascota activa. Corre en segundo plano; si
    /// falla, se sigue con lo que haya.
    public func regenerate(_ reason: String, done: ((Bool, String) -> Void)? = nil) {
        guard !generating else { return }
        guard let pack = pack, let persona = pack.persona, let url = voiceURL else {
            done?(false, "no hay mascota activa")
            return
        }
        guard let bin = Voice.claudeBinary() else {
            plog("voz: no encuentro el binario de claude")
            done?(false, "no encuentro el binario de claude; instala Claude Code")
            return
        }
        generating = true
        plog("voz: escribiendo frases para \(pack.name) (\(reason))")

        let prompt = Voice.prompt(persona: persona, language: pack.language)

        DispatchQueue.global(qos: .background).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-p", "--model", "sonnet", "--output-format", "text", prompt]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice   // sin esto espera stdin y avisa

            var ok = false
            var detail = ""
            do {
                try p.run()
                // Perro guardian: una generacion no puede colgarse para siempre.
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 240) {
                    if p.isRunning { p.terminate() }
                }

                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()

                if let text = String(data: data, encoding: .utf8),
                   let i = text.firstIndex(of: "{"), let j = text.lastIndex(of: "}"), i < j,
                   let obj = (try? JSONSerialization.jsonObject(
                        with: Data(text[i...j].utf8))) as? [String: Any] {
                    let valid = Voice.validate(obj)
                    // Cobertura completa: media voz es peor que ninguna. El
                    // respaldo del pack cubre mientras tanto.
                    if valid.count == Voice.kinds.count,
                       valid.values.allSatisfy({ $0.count >= 3 }) {
                        try? JSONSerialization
                            .data(withJSONObject: obj, options: [.prettyPrinted])
                            .write(to: url, options: .atomic)
                        let total = valid.values.reduce(0) { $0 + $1.count }
                        DispatchQueue.main.async { self.generated = valid }
                        plog("voz: \(total) plantillas nuevas para \(pack.id)")
                        detail = "\(total) frases nuevas para \(pack.name)"
                        ok = true
                    } else {
                        let faltan = Voice.kinds.keys.filter { valid[$0] == nil }.sorted()
                        plog("voz: lote incompleto, faltan \(faltan.joined(separator: ", "))")
                        detail = "el lote vino incompleto; sigo con las frases anteriores"
                    }
                } else {
                    plog("voz: la respuesta no traia JSON usable")
                    detail = "la respuesta no traía JSON usable"
                }
            } catch {
                plog("voz: no pude ejecutar claude: \(error)")
                detail = "no pude ejecutar claude"
            }

            DispatchQueue.main.async {
                self.generating = false
                done?(ok, detail)
            }
        }
    }

    /// Compone el prompt: la personalidad la pone el pack, el contrato lo pone
    /// el programa. Asi una mascota nueva no tiene que saber nada del formato.
    public static func prompt(persona: String, language: String) -> String {
        let idioma = language == "es" ? "español neutro" : "el idioma con código \"\(language)\""
        return """
        Eres el guionista de una mascota de escritorio que vive flotando sobre la \
        pantalla de un programador y le avisa qué hacen sus agentes de IA y sus \
        comandos.

        ESTA ES LA PERSONALIDAD DE LA MASCOTA. Respétala en cada frase:

        \(persona)

        Escribe en \(idioma).

        Genera plantillas de frases para sus avisos. Devuelve SOLO un objeto JSON, \
        sin texto alrededor y sin bloque de código.

        Claves obligatorias y sus marcadores permitidos (escríbelos EXACTAMENTE así):

        - "agentDone":    {agent} {where}          el agente terminó su turno
        - "commandDone":  {cmd} {time} {where}     un comando largo terminó bien
        - "commandError": {cmd} {code} {where}     un comando falló
        - "attention":    {agent} {what} {where}   el agente necesita al humano
        - "working":      {agent} {doing} {time} {where}   reporte de avance
        - "portUp":       {port} {where}           un puerto empezó a escuchar
        - "portDown":     {port} {where}           un puerto se cerró
        - "greeting":     (ninguno)                saludo al arrancar
        - "updateAvailable": {version}             hay una versión nueva de la propia mascota

        Cada clave debe tener un arreglo de \(batchPerKind) plantillas distintas entre sí.

        Qué contiene cada marcador:
        - {agent} nombre propio: "Claude", "Codex".
        - {cmd} un comando de shell: "./gradlew build".
        - {time} una duración ya formateada: "1 min 34 s".
        - {code} un número de exit code: "1".
        - {port} un número de puerto: "3000".
        - {doing} una frase con gerundio: "corriendo comandos", "editando archivos".
        - {what} un sustantivo: "un permiso para usar Bash", "una pregunta".
        - {version} un número de versión: "0.3.0". Es una actualización del programa \
          de la mascota; la frase debe invitar a actualizar.
        - {where} YA TRAE la preposición incluida (" en Fineract") o viene vacío.

        Reglas estrictas:
        1. Una sola oración, o dos muy cortas. Máximo 110 caracteres sin contar marcadores.
        2. Un solo párrafo. Sin saltos de línea. Sin listas.
        3. CERO emojis. Solo texto.
        4. Usa TODOS los marcadores de su clave, cada uno al menos una vez, tal cual.
        5. No inventes marcadores nuevos.
        6. Pega {where} directo después de una palabra, nunca escribas "en {where}".
        7. Nunca sonar como un log de sistema: la mascota tiene carácter.
        """
    }
}
