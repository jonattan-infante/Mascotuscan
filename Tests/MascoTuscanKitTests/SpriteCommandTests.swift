// Poner una imagen reescribe el manifiesto del usuario. Si eso queda a medias,
// la mascota deja de cargar: por eso el cambio se revalida y se revierte solo.
//
// Los tests trabajan sobre paquetes en carpetas temporales, nunca sobre la
// biblioteca real: `updateManifest` solo reinicia la app si el paquete vive
// dentro de ~/.mascotuscan/pets.

import AppKit
import XCTest
@testable import MascoTuscanKit

final class SpriteCommandTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sprite-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "id": "prueba",
          "name": "Prueba",
          "version": "1.0.0",
          "author": "alguien",
          "description": "Una mascota de prueba.",
          "renderer": "vector:droid",
          "sprites": {}
        }
        """.write(to: dir.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
        try "Eres una mascota de prueba."
            .write(to: dir.appendingPathComponent("persona.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Un PNG real y minimo: `setSprite` rechaza lo que NSImage no pueda abrir,
    /// asi que no sirve un archivo con bytes cualquiera.
    func makePNG(_ name: String) throws -> URL {
        let img = NSImage(size: NSSize(width: 8, height: 8))
        img.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("no pude generar el PNG de prueba")
        }
        let url = dir.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    func loadPack() throws -> PetPack {
        guard case .success(let p) = PetPack.load(from: dir) else {
            throw XCTSkip("el paquete base no carga")
        }
        return p
    }

    // MARK: casos felices

    func testPonerImagenActualizaElManifiesto() throws {
        let png = try makePNG("origen.png")
        let pack = try loadPack()

        XCTAssertEqual(PetCommands.setSprite(pack, state: "idle", file: png.path), 0)

        let updated = try loadPack()
        XCTAssertEqual(updated.renderer, .sprites, "poner una imagen cambia el renderer")
        XCTAssertEqual(updated.spritePaths["idle"]?.lastPathComponent, "idle.png")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("sprites/idle.png").path))
    }

    /// La imagen se copia con el nombre del estado, no con el suyo: el manifiesto
    /// queda predecible y no se pisan dos archivos distintos.
    func testLaImagenSeRenombraAlEstado() throws {
        let png = try makePNG("un-nombre-cualquiera.png")
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "done", file: png.path), 0)
        XCTAssertEqual(try loadPack().spritePaths["done"]?.lastPathComponent, "done.png")
    }

    /// Un estado tiene UNA imagen: cambiar de formato no puede dejar las dos,
    /// o el manifiesto apuntaria a una y en disco quedarian dos.
    func testCambiarDeFormatoNoDejaHuerfanos() throws {
        let png = try makePNG("a.png")
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "idle", file: png.path), 0)

        // Ahora la misma cara pero en otro formato.
        let tiffURL = dir.appendingPathComponent("b.tiff")
        let img = NSImage(size: NSSize(width: 8, height: 8))
        img.lockFocus(); NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill(); img.unlockFocus()
        try XCTUnwrap(img.tiffRepresentation).write(to: tiffURL)

        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "idle", file: tiffURL.path), 0)

        let sprites = dir.appendingPathComponent("sprites")
        let files = try FileManager.default.contentsOfDirectory(atPath: sprites.path)
            .filter { $0.hasPrefix("idle.") }
        XCTAssertEqual(files, ["idle.tiff"], "quedo un huerfano: \(files)")
        XCTAssertEqual(try loadPack().spritePaths["idle"]?.lastPathComponent, "idle.tiff")
    }

    func testQuitarLasImagenesVuelveAlVector() throws {
        let png = try makePNG("origen.png")
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "idle", file: png.path), 0)
        XCTAssertEqual(PetCommands.clearSprites(try loadPack()), 0)

        let updated = try loadPack()
        XCTAssertEqual(updated.renderer, .vector("vector:droid"))
        XCTAssertTrue(updated.spritePaths.isEmpty)
        // Las imagenes no se borran: quitarlas del manifiesto no es tirarlas.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("sprites/idle.png").path))
    }

    // MARK: rechazos

    func testRechazaEstadoDesconocido() throws {
        let png = try makePNG("origen.png")
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "contento", file: png.path), 2)
        XCTAssertEqual(try loadPack().renderer, .vector("vector:droid"), "no debio tocar el manifiesto")
    }

    func testRechazaArchivoInexistente() throws {
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "idle", file: "/no/existe.png"), 1)
        XCTAssertEqual(try loadPack().renderer, .vector("vector:droid"))
    }

    func testRechazaFormatoNoSoportado() throws {
        let txt = dir.appendingPathComponent("no-soy-imagen.txt")
        try "hola".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "idle", file: txt.path), 1)
    }

    /// Extension correcta pero contenido basura: si no se comprueba, el fallo
    /// aparece recien al dibujar y la mascota se ve invisible.
    func testRechazaImagenCorrupta() throws {
        let fake = dir.appendingPathComponent("mentira.png")
        try Data("esto no es un png".utf8).write(to: fake)
        XCTAssertEqual(PetCommands.setSprite(try loadPack(), state: "idle", file: fake.path), 1)
        XCTAssertEqual(try loadPack().renderer, .vector("vector:droid"))
    }

    // MARK: reversion

    /// Si el cambio dejaria el paquete invalido, se revierte. Un manifiesto roto
    /// deja al usuario sin mascota y sin saber por que.
    ///
    /// Se compara el CONTENIDO, no el texto: escribir el manifiesto lo reformatea
    /// (claves ordenadas, indentacion propia), asi que un paquete editado a mano
    /// no conserva su formato original. Es aceptable y deterministico, pero hay
    /// que saberlo antes de escribir una comparacion byte a byte.
    func testUnCambioInvalidoSeRevierte() throws {
        let pack = try loadPack()
        let data = try Data(contentsOf: pack.manifestURL)
        let antes = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]) as NSDictionary

        let code = PetCommands.updateManifest(pack) { m in
            m["version"] = "no-es-semver"
        } then: { _ in
            XCTFail("no deberia reportar exito")
        }

        XCTAssertEqual(code, 1)
        let despues = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: pack.manifestURL))
                as? [String: Any]) as NSDictionary
        XCTAssertEqual(antes, despues, "el manifiesto quedo modificado pese al fallo")
        XCTAssertEqual(try loadPack().version, "1.0.0")
    }

    /// El renderer "sprites" sin sprites no carga: poner y luego borrar el
    /// archivo a mano tiene que dejar el paquete recuperable, no roto.
    func testNoDejaElPaqueteEnRendererSpritesSinImagenes() throws {
        let pack = try loadPack()
        let code = PetCommands.updateManifest(pack) { m in
            m["renderer"] = "sprites"      // sin declarar ninguno
        } then: { _ in
            XCTFail("no deberia reportar exito")
        }
        XCTAssertEqual(code, 1)
        XCTAssertEqual(try loadPack().renderer, .vector("vector:droid"))
    }
}
