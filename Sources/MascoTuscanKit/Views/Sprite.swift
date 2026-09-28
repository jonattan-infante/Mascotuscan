// Sprites del usuario, incluidos GIF y PNG animados.
//
// Los cuadros se leen con ImageIO y no con NSBitmapImageRep, por dos defectos
// medidos el 2026-09-27 (ver docs/adr/0013):
//   1. NSBitmapImageRep descomprime el cuadro en cada dibujo. A 30 fps eso era
//      el 44 % del tiempo activo del hilo principal (`sample`), y en un PNG
//      animado componer un cuadro obliga a decodificar los anteriores.
//   2. En un PNG animado devuelve la duracion del primer cuadro para todos.
// Aqui cada cuadro se decodifica una sola vez, al tamano en que se dibuja, y
// cada uno conserva su propia duracion.

import AppKit
import ImageIO

final class Sprite {
    /// Imagenes de un solo cuadro (incluido PDF, que ImageIO no lee).
    private let still: NSImage?
    private let source: CGImageSource?
    let frameCount: Int
    let durations: [Double]
    let total: Double
    let size: CGSize

    /// Cuadros ya decodificados y escalados, por indice. Se tiran si cambia el
    /// tamano en pixeles al que se dibuja (otra pantalla, otra escala).
    private var frames: [Int: CGImage] = [:]
    private var framesPixelSize: CGSize = .zero

    /// Cuantos cuadros hubo que decodificar. Para los tests: dibujar el mismo
    /// cuadro dos veces no puede decodificarlo dos veces.
    private(set) var decodes = 0

    init?(url: URL) {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(src) > 1,
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let pw = props[kCGImagePropertyPixelWidth] as? Int,
           let ph = props[kCGImagePropertyPixelHeight] as? Int {
            let n = CGImageSourceGetCount(src)
            let d = (0..<n).map { Sprite.frameDuration(src, $0) }
            source = src
            still = nil
            frameCount = n
            durations = d
            total = d.reduce(0, +)
            // Mismo tamano en puntos que reportaria NSImage: pixeles a 72 dpi.
            let dpi = (props[kCGImagePropertyDPIWidth] as? Double).map { $0 > 0 ? $0 : 72 } ?? 72
            size = CGSize(width: Double(pw) * 72 / dpi, height: Double(ph) * 72 / dpi)
            return
        }
        guard let img = NSImage(contentsOf: url) else { return nil }
        still = img
        source = nil
        frameCount = 1
        durations = []
        total = 0
        size = img.size
    }

    /// La duracion que declara el cuadro. Menos de 20 ms cuenta como 100 ms,
    /// igual que en los navegadores: muchos GIF traen 0 ms.
    static func frameDuration(_ src: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] ?? [:]
        let dicts: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dict, unclamped, clamped) in dicts {
            guard let d = props[dict] as? [CFString: Any] else { continue }
            let raw = (d[unclamped] as? Double) ?? (d[clamped] as? Double) ?? 0.1
            return raw < 0.02 ? 0.1 : raw
        }
        return 0.1
    }

    /// El cuadro que toca en ese instante. Sin `loops`, se queda en el primero o
    /// el ultimo fuera del rango: asi se reproduce un gesto de una sola vez.
    func frameIndex(at time: Double, loops: Bool = true) -> Int {
        guard frameCount > 1, total > 0 else { return 0 }
        var t = loops ? time.truncatingRemainder(dividingBy: total)
                      : min(max(time, 0), total - 1e-6)
        if t < 0 { t += total }
        for (i, d) in durations.enumerated() {
            if t < d { return i }
            t -= d
        }
        return frameCount - 1
    }

    /// Dibuja el cuadro correspondiente al tiempo dado.
    func draw(in rect: CGRect, at time: Double, loops: Bool = true) {
        guard source != nil, let ctx = NSGraphicsContext.current?.cgContext else {
            still?.draw(in: rect)
            return
        }
        // Pixeles reales en los que cae el rectangulo: incluye la escala Retina
        // y sirve igual si el dibujo viene espejado.
        let m = ctx.userSpaceToDeviceSpaceTransform
        let scale = max(1, (m.a * m.a + m.b * m.b).squareRoot())
        let px = CGSize(width: (rect.width * scale).rounded(.up),
                        height: (rect.height * scale).rounded(.up))
        guard let img = frame(frameIndex(at: time, loops: loops), pixelSize: px) else { return }
        ctx.draw(img, in: rect)
    }

    /// El cuadro `i` ya escalado a `px`, decodificado solo la primera vez.
    func frame(_ i: Int, pixelSize px: CGSize) -> CGImage? {
        if px != framesPixelSize {
            frames.removeAll()
            framesPixelSize = px
        }
        if let cached = frames[i] { return cached }
        guard let src = source, px.width >= 1, px.height >= 1,
              let full = CGImageSourceCreateImageAtIndex(src, i, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: Int(px.width), height: Int(px.height),
                                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .high
        small.draw(full, in: CGRect(origin: .zero, size: px))
        guard let img = small.makeImage() else { return nil }
        decodes += 1
        frames[i] = img
        return img
    }
}

/// Desde cuando se ve cada imagen. Una imagen empieza en su primer cuadro al
/// aparecer, no donde vaya el reloj global: asi un estado puede tener un gesto
/// de una sola vez, como sacar algo al terminar un trabajo.
struct SpriteClock {
    private var key: String?
    private var since: Double = 0

    /// Segundos que lleva visible la imagen `key`. Cambiar de imagen, o volver
    /// a una anterior, la empieza de nuevo.
    mutating func time(showing key: String, now: Double) -> Double {
        if key != self.key {
            self.key = key
            since = now
        }
        return now - since
    }
}
