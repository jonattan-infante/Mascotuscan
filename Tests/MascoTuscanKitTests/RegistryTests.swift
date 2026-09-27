// El indice del marketplace lo escriben terceros via PR, asi que el parseo tiene
// que ser tolerante con lo que sobra y estricto con lo que falta.

import XCTest
@testable import MascoTuscanKit

final class RegistryTests: XCTestCase {
    func parse(_ json: String) -> [RegistryEntry]? {
        Registry.parse(Data(json.utf8))
    }

    func testParseaEntradaCompleta() {
        let entries = parse("""
        {
          "schemaVersion": 1,
          "pets": [{
            "id": "gatito", "name": "Gatito",
            "description": "Un gato.", "author": "alguien",
            "version": "1.0.0", "language": "es", "renderer": "sprites",
            "source": "https://github.com/alguien/gatito.git",
            "path": "pets/gatito", "tags": ["gato", "arte"]
          }]
        }
        """)
        XCTAssertEqual(entries?.count, 1)
        let e = entries![0]
        XCTAssertEqual(e.id, "gatito")
        XCTAssertEqual(e.path, "pets/gatito")
        XCTAssertEqual(e.tags, ["gato", "arte"])
    }

    /// `path` es opcional: un paquete puede vivir en la raiz de su repositorio.
    func testPathOpcional() {
        let entries = parse("""
        {"schemaVersion": 1, "pets": [{
          "id": "x", "name": "X", "description": "d", "author": "a",
          "version": "1.0.0", "source": "https://ejemplo/x.git"
        }]}
        """)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertNil(entries?[0].path)
        XCTAssertEqual(entries?[0].language, "es", "idioma por defecto")
    }

    /// Una entrada incompleta se salta sin tumbar el resto del indice: un PR mal
    /// hecho no puede romper el marketplace para todos.
    func testEntradaIncompletaSeSaltaSinRomperLasDemas() {
        let entries = parse("""
        {"schemaVersion": 1, "pets": [
          {"id": "roto"},
          {"id": "bueno", "name": "Bueno", "description": "d", "author": "a",
           "version": "1.0.0", "source": "https://ejemplo/b.git"}
        ]}
        """)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?[0].id, "bueno")
    }

    func testRechazaSchemaDistinto() {
        XCTAssertNil(parse(#"{"schemaVersion": 2, "pets": []}"#))
    }

    func testRechazaJSONInvalido() {
        XCTAssertNil(parse("no soy json"))
    }

    func testIndiceVacioEsValido() {
        XCTAssertEqual(parse(#"{"schemaVersion": 1, "pets": []}"#)?.count, 0)
    }

    /// El registro se puede apuntar a otro sitio: es como se prueba uno propio
    /// o el de una empresa.
    func testRegistroConfigurablePorEntorno() {
        let original = ProcessInfo.processInfo.environment["MASCOTUSCAN_REGISTRY"]
        setenv("MASCOTUSCAN_REGISTRY", "https://ejemplo.interno/pets.json", 1)
        XCTAssertEqual(Registry.url.absoluteString, "https://ejemplo.interno/pets.json")
        if let o = original { setenv("MASCOTUSCAN_REGISTRY", o, 1) } else { unsetenv("MASCOTUSCAN_REGISTRY") }
        XCTAssertTrue(Registry.url.absoluteString.contains("registry.json"))
    }

    /// El registro que se publica en este repo tiene que ser valido: si no, el
    /// marketplace queda roto para todos en el momento del merge.
    func testElRegistroDelRepoEsValido() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MascoTuscanKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // raiz
        let data = try Data(contentsOf: repo.appendingPathComponent("registry.json"))
        guard let entries = Registry.parse(data) else {
            return XCTFail("registry.json no parsea")
        }
        XCTAssertFalse(entries.isEmpty, "el marketplace no puede estar vacio")

        var ids = Set<String>()
        for e in entries {
            XCTAssertTrue(PetPack.isValidID(e.id), "id invalido: \(e.id)")
            XCTAssertTrue(PetPack.isValidSemver(e.version), "version invalida en \(e.id)")
            XCTAssertTrue(e.source.hasPrefix("http"), "source no clonable en \(e.id)")
            XCTAssertFalse(e.description.isEmpty, "sin descripcion: \(e.id)")
            XCTAssertTrue(ids.insert(e.id).inserted, "id duplicado en el registro: \(e.id)")
        }
    }

    /// Cada mascota del registro que vive en este repo debe existir y cargar. Sin
    /// esto, `mascotuscan install <id>` fallaria despues del clon.
    func testLasMascotasDelRepoCargan() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("registry.json"))
        let entries = Registry.parse(data) ?? []
        for e in entries where e.source.contains("jonattan-infante/mascotuscan") {
            guard let path = e.path else { continue }
            let dir = repo.appendingPathComponent(path)
            switch PetPack.load(from: dir) {
            case .success(let p):
                XCTAssertEqual(p.id, e.id, "el id del paquete no coincide con el registro")
                XCTAssertEqual(p.version, e.version, "la version del registro no coincide con \(e.id)")
            case .failure(let err):
                XCTFail("la mascota \(e.id) del registro no carga: \(err)")
            }
        }
    }
}
