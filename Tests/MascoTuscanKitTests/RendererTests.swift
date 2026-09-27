// El registro de dibujos integrados es lo que conecta el manifiesto con lo que
// se pinta. Si un id no coincide, la mascota se ve como otra y nadie lo nota
// hasta mirar la pantalla.

import AppKit
import XCTest
@testable import MascoTuscanKit

final class RendererTests: XCTestCase {
    func testElRegistroTieneLosTres() {
        XCTAssertEqual(Set(VectorRenderers.ids),
                       Set(["vector:droid", "vector:ball", "vector:sage"]))
    }

    /// Todo renderer registrado se encuentra por su propio id: un id mal escrito
    /// haria que el pack cayera al droide en silencio.
    func testCadaRendererSeEncuentraPorSuID() {
        for r in VectorRenderers.all {
            XCTAssertNotNil(VectorRenderers.named(r.id), "no se encuentra \(r.id)")
            XCTAssertEqual(VectorRenderers.named(r.id)?.id, r.id)
        }
    }

    func testTodosTienenNombreYResumen() {
        for r in VectorRenderers.all {
            XCTAssertFalse(r.title.isEmpty, "\(r.id) sin título")
            XCTAssertFalse(r.summary.isEmpty, "\(r.id) sin resumen")
            XCTAssertTrue(r.id.hasPrefix("vector:"), "\(r.id) no usa el prefijo vector:")
        }
    }

    /// El manifiesto declara un id de texto; el mapeo tiene que reconocerlos
    /// todos como vectoriales, no como desconocidos.
    func testElManifiestoMapeaATodos() {
        for id in VectorRenderers.ids {
            XCTAssertEqual(PetRendererKind(raw: id), .vector(id))
        }
        XCTAssertEqual(PetRendererKind(raw: "sprites"), .sprites)
        XCTAssertEqual(PetRendererKind(raw: "vector:dragon"), .unknown("vector:dragon"))
    }

    /// Un pack que declara cualquiera de los renderers tiene que cargar.
    func testUnPackConCadaRendererCarga() throws {
        for id in VectorRenderers.ids {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("rend-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            try """
            {"schemaVersion":1,"id":"prueba","name":"P","version":"1.0.0",
             "author":"a","description":"d","renderer":"\(id)"}
            """.write(to: dir.appendingPathComponent("pet.json"),
                      atomically: true, encoding: .utf8)
            try "Voz."
                .write(to: dir.appendingPathComponent("persona.md"),
                       atomically: true, encoding: .utf8)

            guard case .success(let p) = PetPack.load(from: dir) else {
                return XCTFail("un pack con \(id) deberia cargar")
            }
            XCTAssertEqual(p.renderer.raw, id)
        }
    }

    /// Cada dibujo tiene que pintar algo en los seis estados sin explotar. No se
    /// juzga como se ve (para eso esta `make render`), solo que no reviente y que
    /// deje pixeles.
    func testCadaRendererPintaEnLosSeisEstados() throws {
        let size = NSSize(width: 96, height: 108)
        for r in VectorRenderers.all {
            for mood in Mood.allCases {
                let img = NSImage(size: size)
                img.lockFocus()
                guard let ctx = NSGraphicsContext.current?.cgContext else {
                    img.unlockFocus()
                    return XCTFail("sin contexto de dibujo")
                }
                let anim = PetAnimation(mood: mood, phase: 1.3, age: 0.4, blinking: false)
                r.draw(CGRect(x: 20, y: 16, width: 50, height: 64), anim, ctx)
                img.unlockFocus()

                guard let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff) else {
                    return XCTFail("\(r.id)/\(mood.rawValue): no produjo imagen")
                }
                // Se recorre el bitmap COMPLETO en sus propios pixeles: en pantalla
                // Retina el rep es 2x los puntos, y muestrear en coordenadas de
                // punto hace que un dibujo pequeno parezca vacio.
                var painted = 0
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                        if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.2 {
                            painted += 1
                        }
                    }
                }
                // Un cuerpo de verdad ocupa cientos de pixeles; un renderer que
                // solo trazara una linea suelta no cumple su trabajo.
                XCTAssertGreaterThan(painted, 200,
                                     "\(r.id) apenas pintó en \(mood.rawValue)")
            }
        }
    }

    /// Las animaciones de una sola vez tienen que apagarse: si no decayeran, la
    /// mascota se quedaria saltando o temblando para siempre.
    func testLasAnimacionesTransitoriasDecaen() {
        let saltando = PetAnimation(mood: .done, phase: 0, age: 0.1, blinking: false)
        let quieto = PetAnimation(mood: .done, phase: 0, age: 5, blinking: false)
        XCTAssertGreaterThan(abs(saltando.lift), abs(quieto.lift))

        let temblando = PetAnimation(mood: .error, phase: 0, age: 0.1, blinking: false)
        let calmado = PetAnimation(mood: .error, phase: 0, age: 5, blinking: false)
        XCTAssertGreaterThan(abs(temblando.shake), abs(calmado.shake))
        XCTAssertEqual(calmado.shake, 0, accuracy: 0.001)
    }

    /// Solo el estado de fallo se sacude: si otro lo hiciera, el gesto dejaria de
    /// significar algo.
    func testSoloElFalloSeSacude() {
        for mood in Mood.allCases where mood != .error {
            let a = PetAnimation(mood: mood, phase: 1, age: 0.2, blinking: false)
            XCTAssertEqual(a.shake, 0, "\(mood.rawValue) no deberia sacudirse")
        }
    }
}
