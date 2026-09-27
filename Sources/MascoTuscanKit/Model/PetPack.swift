// Un pet pack: la unidad que define una mascota. Ver docs/reference/pet-pack.md,
// que es el contrato del que depende este archivo.

import AppKit
import Foundation

/// Cómo se dibuja una mascota.
public enum PetRendererKind: Equatable {
    /// Uno de los dibujos integrados, tintado con los colores del pack.
    case vector(String)
    /// Las imágenes del propio pack.
    case sprites
    /// Declarado en el manifiesto pero desconocido para esta versión.
    case unknown(String)

    init(raw: String) {
        if raw == "sprites" {
            self = .sprites
        } else if VectorRenderers.named(raw) != nil {
            self = .vector(raw)
        } else {
            self = .unknown(raw)
        }
    }

    public var raw: String {
        switch self {
        case .vector(let id):   return id
        case .sprites:          return "sprites"
        case .unknown(let s):   return s
        }
    }
}

/// El manifiesto y las rutas de un pack. Inmutable: se carga y se usa.
public struct PetPack {
    public let root: URL
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let license: String
    public let language: String
    public let renderer: PetRendererKind
    /// estado -> ruta absoluta de la imagen
    public let spritePaths: [String: URL]
    /// estado -> color de acento declarado por el pack
    public let accents: [String: NSColor]

    public var personaURL: URL { root.appendingPathComponent("persona.md") }
    public var phrasesURL: URL { root.appendingPathComponent("phrases.json") }
    public var manifestURL: URL { root.appendingPathComponent("pet.json") }

    /// La personalidad en prosa que se le pasa al generador de frases.
    public var persona: String? {
        guard let s = try? String(contentsOf: personaURL, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Frases de respaldo del propio pack, ya validadas.
    public var fallbackPhrases: [String: [String]] {
        guard let d = try? Data(contentsOf: phrasesURL),
              let raw = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        else { return [:] }
        return Voice.validate(raw)
    }
}

// MARK: - Carga y validación

public extension PetPack {
    /// El schemaVersion que entiende esta versión del programa.
    static let supportedSchemaVersion = 1

    static let validStates = ["idle", "working", "done", "error", "attention", "info", "default"]

    /// Carga un pack desde una carpeta. Devuelve el pack y la lista de problemas.
    /// Un pack con problemas graves no se devuelve; con advertencias, sí.
    static func load(from dir: URL) -> Result<PetPack, PackError> {
        let manifest = dir.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifest) else {
            return .failure(.noManifest(dir.path))
        }
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.badJSON("pet.json"))
        }

        let schema = (raw["schemaVersion"] as? Int) ?? 0
        guard schema == supportedSchemaVersion else {
            return .failure(.schemaMismatch(found: schema, supported: supportedSchemaVersion))
        }

        func str(_ key: String) -> String? {
            guard let v = raw[key] as? String,
                  !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return v
        }

        guard let id = str("id") else { return .failure(.missingField("id")) }
        guard isValidID(id) else { return .failure(.badID(id)) }
        guard let name = str("name") else { return .failure(.missingField("name")) }
        guard let version = str("version") else { return .failure(.missingField("version")) }
        guard isValidSemver(version) else { return .failure(.badVersion(version)) }
        guard let author = str("author") else { return .failure(.missingField("author")) }
        guard let description = str("description") else { return .failure(.missingField("description")) }
        guard let rendererRaw = str("renderer") else { return .failure(.missingField("renderer")) }

        let renderer = PetRendererKind(raw: rendererRaw)

        // Sprites: se resuelven contra la carpeta del pack y no pueden escaparse.
        var sprites: [String: URL] = [:]
        if let declared = raw["sprites"] as? [String: String] {
            for (state, rel) in declared {
                guard validStates.contains(state) else {
                    return .failure(.unknownState(state))
                }
                guard !rel.contains("..") else { return .failure(.escapingPath(rel)) }
                let url = dir.appendingPathComponent(rel)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return .failure(.missingSprite(state: state, path: rel))
                }
                sprites[state] = url
            }
        }
        if renderer == .sprites && sprites.isEmpty {
            return .failure(.spritesRendererWithoutSprites)
        }

        var accents: [String: NSColor] = [:]
        if let declared = raw["accent"] as? [String: String] {
            for (state, hex) in declared {
                guard validStates.contains(state) else { return .failure(.unknownState(state)) }
                guard let c = NSColor(hex: hex) else {
                    return .failure(.badColor(state: state, value: hex))
                }
                accents[state] = c
            }
        }

        let pack = PetPack(
            root: dir,
            id: id,
            name: name,
            version: version,
            author: author,
            description: description,
            license: str("license") ?? "unlicensed",
            language: str("language") ?? "es",
            renderer: renderer,
            spritePaths: sprites,
            accents: accents
        )

        guard pack.persona != nil else { return .failure(.noPersona) }
        return .success(pack)
    }

    static func isValidID(_ s: String) -> Bool {
        guard s.count >= 2, s.count <= 32 else { return false }
        return s.allSatisfy { $0.isLowercase && $0.isASCII || $0.isNumber || $0 == "-" }
            && s.first != "-" && s.last != "-"
    }

    static func isValidSemver(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

/// Los fallos posibles al cargar un pack, con mensaje para el usuario. Cada
/// mensaje dice qué arreglar, no solo qué pasó.
public enum PackError: Error, CustomStringConvertible {
    case noManifest(String)
    case badJSON(String)
    case schemaMismatch(found: Int, supported: Int)
    case missingField(String)
    case badID(String)
    case badVersion(String)
    case unknownState(String)
    case escapingPath(String)
    case missingSprite(state: String, path: String)
    case spritesRendererWithoutSprites
    case badColor(state: String, value: String)
    case noPersona
    case emptyPhraseClass(String)

    public var description: String {
        switch self {
        case .noManifest(let p):
            return "no encuentro pet.json en \(p)"
        case .badJSON(let f):
            return "\(f) no es JSON válido"
        case .schemaMismatch(let found, let supported):
            return "schemaVersion \(found) no soportado; esta versión entiende \(supported)"
        case .missingField(let f):
            return "falta el campo obligatorio \"\(f)\" en pet.json"
        case .badID(let id):
            return "el id \"\(id)\" no sirve: usa 2 a 32 caracteres de [a-z0-9-], sin empezar ni terminar en guion"
        case .badVersion(let v):
            return "la versión \"\(v)\" no es semver (tres números: 1.0.0)"
        case .unknownState(let s):
            return "estado desconocido \"\(s)\"; válidos: \(PetPack.validStates.joined(separator: ", "))"
        case .escapingPath(let p):
            return "la ruta \"\(p)\" se sale del paquete; no se permite \"..\""
        case .missingSprite(let state, let path):
            return "el sprite de \"\(state)\" apunta a \"\(path)\", que no existe en el paquete"
        case .spritesRendererWithoutSprites:
            return "renderer \"sprites\" pero no declaraste ninguno en \"sprites\""
        case .badColor(let state, let value):
            return "el color de \"\(state)\" es \"\(value)\"; se espera #RRGGBB"
        case .noPersona:
            return "falta persona.md, o está vacío: sin personalidad no hay mascota"
        case .emptyPhraseClass(let k):
            return "en phrases.json la clase \"\(k)\" se queda sin plantillas válidas al validar marcadores"
        }
    }
}

// MARK: - Color desde hex

extension NSColor {
    /// Acepta "#RRGGBB". Devuelve nil si no encaja: un color mal escrito debe
    /// fallar la validación, no pintarse de negro en silencio.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }
}
