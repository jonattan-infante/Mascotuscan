// La validacion de plantillas es la defensa contra un lote malo de Claude Code.
// Si esto se rompe, el droide puede acabar mostrando "{time}" en pantalla.

import XCTest
@testable import MascoTuscanKit

final class VoiceTests: XCTestCase {
    /// Una plantilla que usa todos sus marcadores obligatorios sobrevive.
    func testAceptaPlantillaCompleta() {
        let raw: [String: Any] = [
            "commandError": ["*bzzzt* {cmd} falló con código {code}{where}."],
        ]
        let out = Voice.validate(raw)
        XCTAssertEqual(out["commandError"]?.count, 1)
    }

    /// Le falta {code}: rellenarla dejaria un aviso incompleto.
    func testRechazaMarcadorFaltante() {
        let raw: [String: Any] = [
            "commandError": ["*bzzzt* {cmd} falló{where}."],
        ]
        XCTAssertNil(Voice.validate(raw)["commandError"])
    }

    /// {usuario} no existe: quedaria literal en pantalla.
    func testRechazaMarcadorInventado() {
        let raw: [String: Any] = [
            "commandError": ["*bzzzt* {cmd} falló con {code}{where}, {usuario}."],
        ]
        XCTAssertNil(Voice.validate(raw)["commandError"])
    }

    /// La burbuja es de un solo parrafo: un salto de linea rompe el layout.
    func testRechazaSaltoDeLinea() {
        let raw: [String: Any] = [
            "greeting": ["*bip*\nhola"],
        ]
        XCTAssertNil(Voice.validate(raw)["greeting"])
    }

    /// Un lote mezclado conserva solo lo bueno en vez de descartar todo.
    func testConservaLasBuenasYDescartaLasMalas() {
        let raw: [String: Any] = [
            "portUp": [
                "*blip* puerto {port} escuchando{where}.",
                "*blip* un puerto se abrió.",                 // sin marcadores
                "*whirr* {port} en línea{where}, listo.",
            ],
        ]
        XCTAssertEqual(Voice.validate(raw)["portUp"]?.count, 2)
    }

    /// greeting no lleva marcadores: no debe exigirse ninguno.
    func testGreetingSinMarcadores() {
        let raw: [String: Any] = ["greeting": ["*bip-bip* aquí estoy."]]
        XCTAssertEqual(Voice.validate(raw)["greeting"]?.count, 1)
    }

    /// Toda clase declarada debe tener sus marcadores dentro del conjunto permitido,
    /// o el prompt y el validador estarian desalineados.
    func testMarcadoresDeclaradosSonCoherentes() {
        let permitidos = Set(Voice.kinds.values.flatMap { $0 })
        for (kind, required) in Voice.kinds {
            for r in required {
                XCTAssertTrue(permitidos.contains(r), "\(kind) exige {\(r)} desconocido")
            }
        }
    }

    /// El prompt que se le manda a Claude Code debe nombrar todas las clases;
    /// si se agrega una clase y no se actualiza el prompt, nunca llegan plantillas.
    func testElPromptCubreTodasLasClases() {
        let prompt = Voice.prompt(persona: "Eres una prueba.", language: "es")
        for kind in Voice.kinds.keys {
            XCTAssertTrue(prompt.contains("\"\(kind)\""),
                          "el prompt no menciona la clase \(kind)")
        }
    }

    /// La personalidad del pack tiene que llegar al prompt: es lo unico que
    /// diferencia una mascota de otra.
    func testElPromptIncluyeLaPersonalidad() {
        let persona = "Eres un gato indiferente que dice mrrp."
        let prompt = Voice.prompt(persona: persona, language: "es")
        XCTAssertTrue(prompt.contains(persona))
        XCTAssertTrue(prompt.contains("PERSONALIDAD"),
                      "la personalidad debe venir marcada para que el modelo la respete")
    }

    /// Una mascota en otro idioma debe pedirlo explicitamente.
    func testElPromptRespetaElIdioma() {
        XCTAssertTrue(Voice.prompt(persona: "x", language: "es").contains("español neutro"))
        XCTAssertTrue(Voice.prompt(persona: "x", language: "pt").contains("\"pt\""))
    }

    /// Las clases del validador y las del formato de pack son el mismo contrato.
    func testLasClasesCoincidenConElFormatoDocumentado() {
        XCTAssertEqual(Set(Voice.kinds.keys), Set([
            "greeting", "agentDone", "commandDone", "commandError",
            "attention", "working", "portUp", "portDown", "updateAvailable",
        ]))
    }

    /// `validateReporting` es lo que usa `mascotuscan validate` para explicar que
    /// clase se quedo sin plantillas en vez de callarlo.
    func testReportaClasesQueSeQuedanVacias() {
        let raw: [String: Any] = [
            "portUp": ["*blip* un puerto se abrió."],          // sin marcadores
            "greeting": ["*bip* hola."],
        ]
        let (ok, empty) = Voice.validateReporting(raw)
        XCTAssertEqual(empty, ["portUp"])
        XCTAssertNotNil(ok["greeting"])
    }
}
