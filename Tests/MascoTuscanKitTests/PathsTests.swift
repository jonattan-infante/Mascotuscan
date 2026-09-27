// Mismos casos que windows/tests/test_paths.py: si se agrega uno aca, va alla
// tambien. La migracion corre sobre el directorio real del usuario, asi que un
// error aqui le borra o le esconde su configuracion.

import XCTest
@testable import MascoTuscanKit

final class PathsTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("paths-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func dir(_ name: String, config: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let config = config {
            try config.write(to: url.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        }
        return url
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testMigraElNombreAnterior() throws {
        let home = root.appendingPathComponent(".mascotuscan")
        let lucy = try dir(".lucy", config: "lucy")
        XCTAssertEqual(PetPaths.migrateLegacyHome(to: home, from: [lucy]), lucy)
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("config.json"), encoding: .utf8), "lucy")
        XCTAssertFalse(exists(lucy))
    }

    func testPrefiereElNombreMasReciente() throws {
        let home = root.appendingPathComponent(".mascotuscan")
        let lucy = try dir(".lucy", config: "lucy")
        let cmuxPet = try dir(".cmux-pet", config: "cmux-pet")
        XCTAssertEqual(PetPaths.migrateLegacyHome(to: home, from: [lucy, cmuxPet]), lucy)
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("config.json"), encoding: .utf8), "lucy")
        XCTAssertTrue(exists(cmuxPet), "el mas viejo se queda donde estaba")
    }

    func testMigraElMasViejoSiEsElUnico() throws {
        let home = root.appendingPathComponent(".mascotuscan")
        let lucy = root.appendingPathComponent(".lucy")
        let cmuxPet = try dir(".cmux-pet", config: "cmux-pet")
        XCTAssertEqual(PetPaths.migrateLegacyHome(to: home, from: [lucy, cmuxPet]), cmuxPet)
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("config.json"), encoding: .utf8), "cmux-pet")
    }

    func testNoPisaUnEstadoNuevo() throws {
        let home = try dir(".mascotuscan", config: "nuevo")
        let lucy = try dir(".lucy", config: "lucy")
        XCTAssertNil(PetPaths.migrateLegacyHome(to: home, from: [lucy]))
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("config.json"), encoding: .utf8), "nuevo")
        XCTAssertTrue(exists(lucy))
    }

    func testSinNadaQueMigrarNoCreaNada() {
        let home = root.appendingPathComponent(".mascotuscan")
        XCTAssertNil(PetPaths.migrateLegacyHome(to: home, from: [root.appendingPathComponent(".lucy")]))
        XCTAssertFalse(exists(home), "crear el directorio es trabajo de ensureHome")
    }
}
