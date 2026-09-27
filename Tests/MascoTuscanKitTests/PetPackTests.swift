// El formato de paquete es el contrato del marketplace: cualquiera puede
// escribir uno, asi que la validacion es la frontera del sistema. Un pack malo
// tiene que fallar con un mensaje que diga como arreglarlo, no romper la app.

import XCTest
@testable import MascoTuscanKit

final class PetPackTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pack-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: helpers

    func write(_ name: String, _ content: String) throws {
        try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func manifest(
        id: String = "prueba",
        version: String = "1.0.0",
        renderer: String = "vector:droid",
        extra: String = ""
    ) -> String {
        """
        {
          "schemaVersion": 1,
          "id": "\(id)",
          "name": "Prueba",
          "version": "\(version)",
          "author": "alguien",
          "description": "Una mascota de prueba.",
          "renderer": "\(renderer)"\(extra.isEmpty ? "" : ",\n  " + extra)
        }
        """
    }

    func writeValidPack() throws {
        try write("pet.json", manifest())
        try write("persona.md", "Eres una mascota de prueba. Hablas corto.")
    }

    func loadError() -> PackError? {
        if case .failure(let e) = PetPack.load(from: dir) { return e }
        return nil
    }

    // MARK: casos felices

    func testCargaPaqueteMinimo() throws {
        try writeValidPack()
        guard case .success(let p) = PetPack.load(from: dir) else {
            return XCTFail("deberia cargar: \(String(describing: loadError()))")
        }
        XCTAssertEqual(p.id, "prueba")
        XCTAssertEqual(p.renderer, .vector("vector:droid"))
        XCTAssertEqual(p.license, "unlicensed", "sin declarar, la licencia es explicita")
        XCTAssertEqual(p.language, "es")
    }

    func testLeeColoresDeclarados() throws {
        try write("pet.json", manifest(extra: ##""accent": {"idle": "#112233"}"##))
        try write("persona.md", "Corta.")
        guard case .success(let p) = PetPack.load(from: dir) else { return XCTFail("deberia cargar") }
        XCTAssertNotNil(p.accents["idle"])
    }

    func testSpritesResueltosContraLaCarpeta() throws {
        let sprites = dir.appendingPathComponent("sprites")
        try FileManager.default.createDirectory(at: sprites, withIntermediateDirectories: true)
        try Data([0x89]).write(to: sprites.appendingPathComponent("idle.png"))
        try write("pet.json", manifest(renderer: "sprites",
                                      extra: #""sprites": {"idle": "sprites/idle.png"}"#))
        try write("persona.md", "Corta.")
        guard case .success(let p) = PetPack.load(from: dir) else {
            return XCTFail("deberia cargar: \(String(describing: loadError()))")
        }
        XCTAssertEqual(p.renderer, .sprites)
        XCTAssertEqual(p.spritePaths["idle"]?.lastPathComponent, "idle.png")
    }

    // MARK: rechazos

    func testRechazaSinManifiesto() {
        guard case .noManifest = loadError() else { return XCTFail("esperaba noManifest") }
    }

    func testRechazaJSONInvalido() throws {
        try write("pet.json", "{ esto no es json")
        guard case .badJSON = loadError() else { return XCTFail("esperaba badJSON") }
    }

    /// Un pack de una version futura no se adivina: se rechaza diciendo por que.
    func testRechazaSchemaDistinto() throws {
        try write("pet.json", #"{"schemaVersion": 99, "id": "x"}"#)
        try write("persona.md", "Corta.")
        guard case .schemaMismatch(let found, let supported) = loadError() else {
            return XCTFail("esperaba schemaMismatch")
        }
        XCTAssertEqual(found, 99)
        XCTAssertEqual(supported, PetPack.supportedSchemaVersion)
    }

    func testRechazaCampoFaltante() throws {
        try write("pet.json", #"{"schemaVersion": 1, "id": "prueba"}"#)
        try write("persona.md", "Corta.")
        guard case .missingField(let f) = loadError() else { return XCTFail("esperaba missingField") }
        XCTAssertEqual(f, "name")
    }

    func testRechazaIDInvalido() throws {
        try write("pet.json", manifest(id: "Mi Mascota"))
        try write("persona.md", "Corta.")
        guard case .badID = loadError() else { return XCTFail("esperaba badID") }
    }

    func testRechazaVersionNoSemver() throws {
        try write("pet.json", manifest(version: "1.0"))
        try write("persona.md", "Corta.")
        guard case .badVersion = loadError() else { return XCTFail("esperaba badVersion") }
    }

    /// Sin personalidad no hay mascota: es lo unico que la hace distinta.
    func testRechazaSinPersona() throws {
        try write("pet.json", manifest())
        guard case .noPersona = loadError() else { return XCTFail("esperaba noPersona") }
    }

    func testRechazaPersonaVacia() throws {
        try write("pet.json", manifest())
        try write("persona.md", "   \n  \n")
        guard case .noPersona = loadError() else { return XCTFail("esperaba noPersona") }
    }

    /// Un sprite declarado que no existe seria una mascota invisible.
    func testRechazaSpriteInexistente() throws {
        try write("pet.json", manifest(renderer: "sprites",
                                      extra: #""sprites": {"idle": "sprites/no-esta.png"}"#))
        try write("persona.md", "Corta.")
        guard case .missingSprite = loadError() else { return XCTFail("esperaba missingSprite") }
    }

    func testRechazaRendererSpritesSinSprites() throws {
        try write("pet.json", manifest(renderer: "sprites"))
        try write("persona.md", "Corta.")
        guard case .spritesRendererWithoutSprites = loadError() else {
            return XCTFail("esperaba spritesRendererWithoutSprites")
        }
    }

    /// Una ruta con ".." podria leer archivos fuera del paquete.
    func testRechazaRutaQueSeEscapa() throws {
        try write("pet.json", manifest(renderer: "sprites",
                                      extra: #""sprites": {"idle": "../../../etc/passwd"}"#))
        try write("persona.md", "Corta.")
        guard case .escapingPath = loadError() else { return XCTFail("esperaba escapingPath") }
    }

    func testRechazaEstadoDesconocido() throws {
        try write("pet.json", manifest(extra: ##""accent": {"contento": "#112233"}"##))
        try write("persona.md", "Corta.")
        guard case .unknownState = loadError() else { return XCTFail("esperaba unknownState") }
    }

    func testRechazaColorMalEscrito() throws {
        try write("pet.json", manifest(extra: #""accent": {"idle": "azul"}"#))
        try write("persona.md", "Corta.")
        guard case .badColor = loadError() else { return XCTFail("esperaba badColor") }
    }

    /// Un renderer que esta version no conoce no debe romper: se cae al
    /// vectorial y se avisa. Un pack del futuro sigue siendo usable.
    func testRendererDesconocidoNoRompe() throws {
        try write("pet.json", manifest(renderer: "vector:dragon"))
        try write("persona.md", "Corta.")
        guard case .success(let p) = PetPack.load(from: dir) else {
            return XCTFail("un renderer desconocido no debe impedir la carga")
        }
        XCTAssertEqual(p.renderer, .unknown("vector:dragon"))
    }

    /// Un campo que esta version no conoce se ignora, para no romper packs nuevos.
    func testCampoDesconocidoSeIgnora() throws {
        try write("pet.json", manifest(extra: #""algoDelFuturo": {"a": 1}"#))
        try write("persona.md", "Corta.")
        guard case .success = PetPack.load(from: dir) else {
            return XCTFail("un campo extra no debe romper la carga")
        }
    }

    // MARK: reglas de identificador y version

    func testReglasDeID() {
        XCTAssertTrue(PetPack.isValidID("astro"))
        XCTAssertTrue(PetPack.isValidID("mi-gato-2"))
        XCTAssertFalse(PetPack.isValidID("a"), "muy corto")
        XCTAssertFalse(PetPack.isValidID("Mayuscula"))
        XCTAssertFalse(PetPack.isValidID("con espacio"))
        XCTAssertFalse(PetPack.isValidID("-empieza-en-guion"))
        XCTAssertFalse(PetPack.isValidID("termina-en-guion-"))
        XCTAssertFalse(PetPack.isValidID(String(repeating: "a", count: 33)))
    }

    func testReglasDeVersion() {
        XCTAssertTrue(PetPack.isValidSemver("0.1.0"))
        XCTAssertTrue(PetPack.isValidSemver("10.20.30"))
        XCTAssertFalse(PetPack.isValidSemver("1.0"))
        XCTAssertFalse(PetPack.isValidSemver("1.0.0-beta"))
        XCTAssertFalse(PetPack.isValidSemver("v1.0.0"))
    }

    // MARK: mensajes de error

    /// Los mensajes los lee alguien creando su mascota: tienen que decir que
    /// arreglar, no solo que fallo.
    func testLosMensajesExplicanQueArreglar() {
        XCTAssertTrue("\(PackError.badID("X"))".contains("a-z0-9-"))
        XCTAssertTrue("\(PackError.badVersion("1.0"))".contains("1.0.0"))
        XCTAssertTrue("\(PackError.noPersona)".contains("persona.md"))
        XCTAssertTrue("\(PackError.escapingPath("../x"))".contains(".."))
        XCTAssertTrue("\(PackError.unknownState("x"))".contains("idle"))
    }
}
