// Sprites del usuario, incluidos GIF y PNG animados.
//
// Los cuadros se leen con ImageIO y no con NSBitmapImageRep, por dos defectos
// medidos el 2026-09-27 (ver docs/adr/0013):
//   1. NSBitmapImageRep descomprime el cuadro en cada dibujo. A 30 fps eso era
//      el 44 % del tiempo activo del hilo principal (`sample`), y en un PNG
//      animado componer un cuadro obliga a decodificar los anteriores.
//   2. En un PNG animado devuelve la duracion del primer cuadro para todos.
// Aqui cada cuadro se decodifica una sola vez por aparicion, al tamano en que
// se dibuja, y cada uno conserva su propia duracion.

import AppKit
import ImageIO

final class Sprite {
    /// Formatos en que varias imagenes son los cuadros de una animacion. En un
    /// TIFF, un HEIC o un ICNS son la misma imagen a otros tamanos: animarlos
    /// la haria parpadear entre versiones, asi que se dibujan quietos.
    static let animatedTypes: Set<String> = [
        "com.compuserve.gif", "public.png", "org.webmproject.webp", "public.heics",
    ]

    /// Tope de lo que una animacion guarda ya decodificado. Una de unos 60
    /// cuadros al tamano de la mascota en Retina entra entera; una de cientos,
    /// que decide el autor del paquete, se decodifica al vuelo en vez de llenar
    /// la memoria.
    static let defaultCacheBudget = 16 * 1024 * 1024

    /// Imagenes de un solo cuadro (incluido PDF, que ImageIO no lee).
    private let still: NSImage?
    private let source: CGImageSource?
    let frameCount: Int
    let durations: [Double]
    let total: Double
    let size: CGSize

    /// Cuadros ya decodificados y escalados, por indice. Se tiran si cambia el
    /// tamano en pixeles al que se dibuja (otra pantalla, otra escala) y cuando
    /// la imagen deja de verse (`releaseFrames`).
    private var frames: [Int: CGImage] = [:]
    private var framesPixelSize: CGSize = .zero
    var cacheBudget = Sprite.defaultCacheBudget

    /// Un cuadro que no se pudo decodificar. No se reintenta en cada dibujo: la
    /// vista cae al dibujo vectorial y el fallo queda una vez en el log.
    private(set) var broken = false
    private let name: String

    /// Cuantos cuadros hubo que decodificar. Para los tests: dibujar el mismo
    /// cuadro dos veces no puede decodificarlo dos veces.
    private(set) var decodes = 0

    init?(url: URL) {
        name = url.lastPathComponent
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(src) > 1,
           let type = CGImageSourceGetType(src) as String?,
           Sprite.animatedTypes.contains(type),
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

    /// Dibuja el cuadro correspondiente al tiempo dado. Devuelve false si no
    /// dibujo nada, para que la vista caiga al dibujo vectorial en vez de dejar
    /// la mascota invisible.
    @discardableResult
    func draw(in rect: CGRect, at time: Double, loops: Bool = true) -> Bool {
        guard source != nil, let ctx = NSGraphicsContext.current?.cgContext else {
            guard let still = still else { return false }
            still.draw(in: rect)
            return true
        }
        // Pixeles reales en los que cae el rectangulo: incluye la escala Retina
        // y sirve igual si el dibujo viene espejado.
        let m = ctx.userSpaceToDeviceSpaceTransform
        let scale = max(1, (m.a * m.a + m.b * m.b).squareRoot())
        let px = CGSize(width: (rect.width * scale).rounded(.up),
                        height: (rect.height * scale).rounded(.up))
        guard let img = frame(frameIndex(at: time, loops: loops), pixelSize: px) else { return false }
        ctx.draw(img, in: rect)
        return true
    }

    /// El cuadro `i` ya escalado a `px`. Se decodifica solo la primera vez si
    /// la animacion entera cabe en `cacheBudget`; si no, cada vez que le toca.
    func frame(_ i: Int, pixelSize px: CGSize) -> CGImage? {
        if px != framesPixelSize {
            frames.removeAll()
            framesPixelSize = px
        }
        if let cached = frames[i] { return cached }
        guard !broken, let src = source, px.width >= 1, px.height >= 1 else { return nil }
        guard let full = CGImageSourceCreateImageAtIndex(src, i, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: Int(px.width), height: Int(px.height),
                                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            broken = true
            plog("no pude decodificar el cuadro \(i) de \(name); se dibuja el vectorial")
            return nil
        }
        small.interpolationQuality = .high
        small.draw(full, in: CGRect(origin: .zero, size: px))
        guard let img = small.makeImage() else {
            broken = true
            plog("no pude escalar el cuadro \(i) de \(name); se dibuja el vectorial")
            return nil
        }
        decodes += 1
        if frameCount * Int(px.width) * Int(px.height) * 4 <= cacheBudget {
            frames[i] = img
        } else {
            // No cabe entera: se guarda solo el cuadro actual, que a 30 fps se
            // dibuja varias veces seguidas.
            frames = [i: img]
        }
        return img
    }

    /// La imagen dejo de verse: sus cuadros se vuelven a decodificar si vuelve.
    /// Asi la memoria es la de la imagen visible, no la de todas las que se vieron.
    func releaseFrames() {
        frames.removeAll()
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

    /// No se ve ninguna imagen (se dibuja el vectorial): la proxima que
    /// aparezca, aunque sea la misma de antes, empieza desde su primer cuadro.
    mutating func reset() {
        key = nil
    }
}
