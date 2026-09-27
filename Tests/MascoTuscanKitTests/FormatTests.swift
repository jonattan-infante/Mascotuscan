// Formateo y limpieza de texto. Todo esto sale en pantalla, asi que un error
// aqui es visible para el usuario.

import XCTest
@testable import MascoTuscanKit

final class FormatTests: XCTestCase {
    func testDuracionCorta() {
        XCTAssertEqual(humanDuration(0.25), "250 ms")
        XCTAssertEqual(humanDuration(45), "45.0 s")
    }

    func testDuracionEnMinutos() {
        XCTAssertEqual(humanDuration(60), "1 min")
        XCTAssertEqual(humanDuration(94), "1 min 34 s")
    }

    func testDuracionEnHoras() {
        XCTAssertEqual(humanDuration(3600), "1 h 0 min")
        XCTAssertEqual(humanDuration(4500), "1 h 15 min")
    }

    func testDuracionCompacta() {
        XCTAssertEqual(compactDuration(40), "40 s")
        XCTAssertEqual(compactDuration(240), "4 min")
        XCTAssertEqual(compactDuration(4320), "1 h 12 min")
    }

    func testTruncadoRespetaElLimite() {
        let s = truncate("abcdefghij", 5)
        XCTAssertEqual(s.count, 5)
        XCTAssertTrue(s.hasSuffix("\u{2026}"))
    }

    func testTruncadoNoTocaLoCorto() {
        XCTAssertEqual(truncate("  hola  ", 20), "hola")
    }

    /// cmux prefija el titulo con un spinner braille cuando el workspace esta
    /// activo. Dentro de una frase eso es basura.
    func testLimpiaSpinnerDelTitulo() {
        XCTAssertEqual(PetController.cleanTitle("\u{2802} Crear asistente"), "Crear asistente")
        XCTAssertEqual(PetController.cleanTitle("\u{2733} Fineract"), "Fineract")
        XCTAssertEqual(PetController.cleanTitle("* Backend"), "Backend")
        XCTAssertEqual(PetController.cleanTitle("Contabilidad"), "Contabilidad")
    }

    func testLimpiaTituloVacio() {
        XCTAssertEqual(PetController.cleanTitle(""), "")
        XCTAssertEqual(PetController.cleanTitle("\u{2802}"), "")
    }

    /// El verbo que se muestra sale del nombre de la herramienta, porque
    /// tool_input viene redactado en los eventos de cmux.
    func testHerramientaATexto() {
        XCTAssertEqual(Wording.activity("Bash"), "corriendo comandos")
        XCTAssertEqual(Wording.activity("Edit"), "editando archivos")
        XCTAssertEqual(Wording.activity("Grep"), "buscando en el código")
        XCTAssertEqual(Wording.activity(nil), "arrancando")
        XCTAssertEqual(Wording.activity("HerramientaNueva"), "usando HerramientaNueva")
    }

    /// {where} ya trae la preposicion: las plantillas lo pegan directo.
    func testUbicacionTraeLaPreposicion() {
        XCTAssertEqual(Wording.at("Fineract"), " en Fineract")
        XCTAssertEqual(Wording.at(""), "")
    }
}
