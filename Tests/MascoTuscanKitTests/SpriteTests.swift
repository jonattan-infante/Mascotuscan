// Los sprites animados: que cada cuadro dure lo que declara y que se decodifique
// una sola vez. Las dos cosas fallaban con NSBitmapImageRep (docs/adr/0013): los
// PNG animados duraban lo del primer cuadro, y cada dibujo descomprimia de nuevo.

import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import MascoTuscanKit

final class SpriteTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sprite-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Una animacion de colores planos, un cuadro por duracion.
    private func animation(_ name: String, _ type: UTType, _ durations: [Double]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, durations.count, nil))
        for (i, d) in durations.enumerated() {
            let ctx = try XCTUnwrap(CGContext(
                data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(srgbRed: CGFloat(i) / CGFloat(durations.count),
                                     green: 0.5, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            let props: [CFString: Any] = type == .gif
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: d,
                                                   kCGImagePropertyGIFUnclampedDelayTime: d]]
                : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: d,
                                                   kCGImagePropertyAPNGUnclampedDelayTime: d]]
            CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), props as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func assertDurations(_ s: Sprite, _ expected: [Double],
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.durations.count, expected.count, file: file, line: line)
        for (a, b) in zip(s.durations, expected) {
            XCTAssertEqual(a, b, accuracy: 0.01, file: file, line: line)
        }
    }

    /// Era el defecto: AppKit daba 2.0 s a los tres cuadros.
    func testPNGAnimadoRespetaLaDuracionDeCadaCuadro() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("a.png", .png, [2.0, 0.05, 0.5])))
        XCTAssertEqual(s.frameCount, 3)
        assertDurations(s, [2.0, 0.05, 0.5])
        XCTAssertEqual(s.total, 2.55, accuracy: 0.02)
    }

    func testGIFRespetaLaDuracionDeCadaCuadro() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("a.gif", .gif, [2.0, 0.05, 0.5])))
        assertDurations(s, [2.0, 0.05, 0.5])
    }

    /// Muchos GIF traen 0 ms; los navegadores los muestran a 100 ms.
    func testCeroMsCuentaComoCien() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("cero.gif", .gif, [0, 0.2])))
        assertDurations(s, [0.1, 0.2])
    }

    func testElCuadroSegunElTiempo() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("t.png", .png, [1.0, 0.5, 0.5])))
        XCTAssertEqual(s.frameIndex(at: 0.2), 0)
        XCTAssertEqual(s.frameIndex(at: 1.2), 1)
        XCTAssertEqual(s.frameIndex(at: 1.7), 2)
        XCTAssertEqual(s.frameIndex(at: 2.2), 0, "en bucle vuelve a empezar")
        XCTAssertEqual(s.frameIndex(at: 5, loops: false), 2, "una sola vez se queda en el ultimo")
        XCTAssertEqual(s.frameIndex(at: -1, loops: false), 0)
    }

    /// Era el costo de CPU: dibujar el mismo cuadro a 30 fps lo descomprimia 30
    /// veces por segundo.
    func testCadaCuadroSeDecodificaUnaSolaVez() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("c.png", .png, [0.1, 0.1, 0.1])))
        let px = CGSize(width: 20, height: 20)
        for _ in 0..<30 { XCTAssertNotNil(s.frame(1, pixelSize: px)) }
        XCTAssertEqual(s.decodes, 1)
        _ = s.frame(0, pixelSize: px)
        _ = s.frame(0, pixelSize: px)
        XCTAssertEqual(s.decodes, 2)
    }

    /// Otra pantalla u otra escala: los cuadros se vuelven a hacer a su tamano,
    /// no se estira uno chico.
    func testOtroTamanoVuelveADecodificar() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("d.png", .png, [0.1, 0.1])))
        let a = try XCTUnwrap(s.frame(0, pixelSize: CGSize(width: 20, height: 20)))
        let b = try XCTUnwrap(s.frame(0, pixelSize: CGSize(width: 40, height: 40)))
        XCTAssertEqual(a.width, 20)
        XCTAssertEqual(b.width, 40)
        XCTAssertEqual(s.decodes, 2)
    }

    /// Una animacion que no cabe en el tope no guarda todos sus cuadros: cuantos
    /// hay lo decide el autor del paquete, y la memoria no puede depender de eso.
    func testUnaAnimacionQueNoCabeNoGuardaSusCuadros() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("grande.png", .png, [0.1, 0.1, 0.1])))
        let px = CGSize(width: 20, height: 20)
        s.cacheBudget = 3 * 20 * 20 * 4 - 1
        _ = s.frame(0, pixelSize: px)
        _ = s.frame(1, pixelSize: px)
        _ = s.frame(0, pixelSize: px)
        XCTAssertEqual(s.decodes, 3, "el cuadro 0 se volvio a decodificar")
        // El cuadro actual si queda: a 30 fps se dibuja varias veces seguidas.
        _ = s.frame(0, pixelSize: px)
        XCTAssertEqual(s.decodes, 3)
    }

    /// La memoria es la de la imagen visible: al dejar de verse, suelta sus cuadros.
    func testAlDejarDeVerseSueltaSusCuadros() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("e.png", .png, [0.1, 0.1])))
        let px = CGSize(width: 20, height: 20)
        _ = s.frame(0, pixelSize: px)
        s.releaseFrames()
        _ = s.frame(0, pixelSize: px)
        XCTAssertEqual(s.decodes, 2)
    }

    /// En un TIFF las imagenes son la misma a otros tamanos: animarlo la haria
    /// parpadear entre versiones.
    func testUnTIFFConVariasImagenesNoSeAnima() throws {
        let url = dir.appendingPathComponent("hidpi.tiff")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 2, nil))
        for side in [40, 80] {
            let ctx = try XCTUnwrap(CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let s = try XCTUnwrap(Sprite(url: url))
        XCTAssertEqual(s.frameCount, 1)
        XCTAssertEqual(s.total, 0)
    }

    func testUnaImagenFijaNoSeAnima() throws {
        let s = try XCTUnwrap(Sprite(url: try animation("fija.png", .png, [0.1])))
        XCTAssertEqual(s.frameCount, 1)
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(s.frameIndex(at: 3), 0)
        XCTAssertEqual(s.size, CGSize(width: 40, height: 40))
    }
}
