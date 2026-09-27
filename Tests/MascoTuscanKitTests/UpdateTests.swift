// El contrato de docs/reference/versioning.md, caso por caso. Los mismos casos
// viven en windows/tests/test_update.py: si se agrega uno aqui, va alla.

import XCTest
@testable import MascoTuscanKit

final class UpdateTests: XCTestCase {
    // MARK: semver

    func testParseaConYSinPrefijo() {
        XCTAssertEqual(Semver("v0.2.0")?.description, "0.2.0")
        XCTAssertEqual(Semver("0.2.0")?.description, "0.2.0")
        XCTAssertEqual(Semver(" 1.0.0\n")?.description, "1.0.0")
    }

    /// Un prerelease no es una version publicada: no se compara ni se anuncia.
    func testRechazaLoQueNoEsXYZ() {
        XCTAssertNil(Semver("0.3.0-beta.1"))
        XCTAssertNil(Semver("0.3"))
        XCTAssertNil(Semver("main"))
        XCTAssertNil(Semver(""))
    }

    /// Comparar como texto diria que 0.9.0 > 0.10.0.
    func testComparaNumericamente() {
        XCTAssertTrue(Semver("0.9.0")! < Semver("0.10.0")!)
        XCTAssertTrue(Semver("0.2.0")! < Semver("1.0.0")!)
        XCTAssertTrue(Semver("1.0.0")! < Semver("1.0.1")!)
        XCTAssertEqual(Semver("v1.2.3"), Semver("1.2.3"))
    }

    // MARK: respuesta de GitHub

    func testSacaLaVersionDelTagName() {
        let data = Data(#"{"tag_name":"v0.3.0","name":"mascotuscan 0.3.0"}"#.utf8)
        XCTAssertEqual(UpdateCheck.parseLatest(data)?.description, "0.3.0")
    }

    func testRespuestaSinTagNoEsVersion() {
        XCTAssertNil(UpdateCheck.parseLatest(Data(#"{"message":"Not Found"}"#.utf8)))
        XCTAssertNil(UpdateCheck.parseLatest(Data("no es json".utf8)))
    }

    // MARK: cadencia

    func testConsultaSiNuncaConsulto() {
        XCTAssertTrue(UpdateCheck.shouldQuery(state: UpdateState()))
    }

    func testNoConsultaDosVecesEnUnDia() {
        let now = Date()
        let hace1h = UpdateState(checkedAt: now.addingTimeInterval(-3600))
        XCTAssertFalse(UpdateCheck.shouldQuery(state: hace1h, now: now))
        let hace25h = UpdateState(checkedAt: now.addingTimeInterval(-25 * 3600))
        XCTAssertTrue(UpdateCheck.shouldQuery(state: hace25h, now: now))
    }

    // MARK: regla de silencio

    func testAnunciaUnaVersionMasNueva() {
        let (announce, state) = UpdateCheck.decide(current: Semver("0.2.0")!, latest: Semver("0.3.0"),
                                                   state: UpdateState())
        XCTAssertEqual(announce?.description, "0.3.0")
        XCTAssertEqual(state.announced, "0.3.0")
        XCTAssertEqual(state.latest, "0.3.0")
        XCTAssertNotNil(state.checkedAt)
    }

    /// Reiniciar la mascota no puede repetir el aviso.
    func testNoRepiteLaMismaVersion() {
        let ya = UpdateState(checkedAt: nil, latest: "0.3.0", announced: "0.3.0")
        let (announce, _) = UpdateCheck.decide(current: Semver("0.2.0")!, latest: Semver("0.3.0"),
                                               state: ya)
        XCTAssertNil(announce)
    }

    func testSiVuelveAHaberOtraMasNuevaLaAnuncia() {
        let ya = UpdateState(checkedAt: nil, latest: "0.3.0", announced: "0.3.0")
        let (announce, state) = UpdateCheck.decide(current: Semver("0.2.0")!, latest: Semver("0.4.0"),
                                                   state: ya)
        XCTAssertEqual(announce?.description, "0.4.0")
        XCTAssertEqual(state.announced, "0.4.0")
    }

    func testCallaSiEstaAlDiaOAdelantado() {
        XCTAssertNil(UpdateCheck.decide(current: Semver("0.3.0")!, latest: Semver("0.3.0"),
                                        state: UpdateState()).announce)
        XCTAssertNil(UpdateCheck.decide(current: Semver("0.4.0")!, latest: Semver("0.3.0"),
                                        state: UpdateState()).announce)
    }

    /// Sin release publicado (404) se registra la consulta y no se habla.
    func testSinReleaseRegistraLaConsultaYCalla() {
        let (announce, state) = UpdateCheck.decide(current: Semver("0.2.0")!, latest: nil,
                                                   state: UpdateState())
        XCTAssertNil(announce)
        XCTAssertNotNil(state.checkedAt)
        XCTAssertNil(state.latest)
    }

    // MARK: estado en disco

    func testEstadoCorruptoEsEstadoVacio() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-\(UUID().uuidString).json")
        try? "{{ no es json".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(UpdateState.load(from: url), UpdateState())
    }

    func testElEstadoSobreviveElViaje() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = UpdateState(checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
                            latest: "0.3.0", announced: "0.3.0")
        s.save(to: url)
        let back = UpdateState.load(from: url)
        XCTAssertEqual(back.latest, "0.3.0")
        XCTAssertEqual(back.announced, "0.3.0")
        XCTAssertEqual(back.checkedAt, s.checkedAt)
        // La forma del archivo es la que lee Windows: claves planas e ISO 8601.
        let text = try? String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text?.contains("\"checkedAt\" : \"2027-01-15T08:00:00Z\"") == true, text ?? "")
    }
}
