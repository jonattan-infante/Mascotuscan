// El droide: dibujo vectorial, animacion y captura del mouse.

import AppKit

final class PetView: NSView {
    var mood: Mood = .idle {
        didSet { if mood != oldValue { moodChangedAt = CACurrentMediaTime(); needsDisplay = true } }
    }
    var workingCount: Int = 0 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onMenu: ((NSEvent) -> Void)?

    private var phase: Double = 0
    private var moodChangedAt: CFTimeInterval = CACurrentMediaTime()
    private var blinkUntil: CFTimeInterval = 0
    private var nextBlink: CFTimeInterval = CACurrentMediaTime() + 3

    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    private var dragOrigin: CGPoint = .zero
    private var dragWindowOrigin: CGPoint = .zero
    private var dragDistance: CGFloat = 0
    private var mouseDownAt: CFTimeInterval = 0

    /// Tiempo desde que entro al estado actual. Las animaciones transitorias decaen con esto.
    private var age: Double { CACurrentMediaTime() - moodChangedAt }

    func tick(_ dt: Double) {
        phase += dt
        let now = CACurrentMediaTime()
        if now > nextBlink {
            blinkUntil = now + 0.12
            nextBlink = now + Double.random(in: 2.5...6.0)
        }
        needsDisplay = true
    }

    /// Solo el cuerpo captura el mouse; el resto de la ventana es transparente al click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if let r = lastSpriteRect, r.insetBy(dx: -3, dy: -3).contains(p) { return self }
        return bodyRect().insetBy(dx: -4, dy: -4).contains(p) ? self : nil
    }

    // MARK: sprites de la mascota activa

    private var spriteCache: [String: Sprite?] = [:]
    private var lastSpriteRect: CGRect?
    private var spriteClock = SpriteClock()

    /// Se llama al cambiar de mascota y desde el menu. Tira el cache: los
    /// sprites de la mascota anterior no sirven para la nueva.
    func reloadSprites() {
        spriteCache.removeAll()
        lastSpriteRect = nil
        needsDisplay = true
    }

    private func cachedSprite(_ url: URL) -> Sprite? {
        let key = url.path
        if let cached = spriteCache[key] { return cached }
        let loaded = Sprite(url: url)
        if loaded == nil { plog("no pude cargar el sprite \(url.lastPathComponent)") }
        spriteCache[key] = loaded
        return loaded
    }

    // MARK: recorrer la pantalla

    /// En que va la mascota que recorre la pantalla. Lo pone el controlador en
    /// cada cuadro desde `Roamer`; en reposo se dibuja el estado, como siempre.
    var roamPhase: Roamer.Phase = .resting
    var roamAge: Double = 0

    /// Lo que dura el `start` del pack activo: el controlador espera a que
    /// termine de girar antes de mover la ventana.
    func roamStartDuration() -> Double {
        guard let url = PetTheme.shared.pack?.roam?.start else { return 0 }
        return cachedSprite(url)?.total ?? 0
    }

    /// El cuadro de roam que toca, o nil si esta quieta o el pack no se mueve.
    /// Las imagenes miran a la derecha; hacia la izquierda se espejan.
    private func roamFrame() -> (sprite: Sprite, time: Double, loops: Bool, mirrored: Bool)? {
        guard let pack = PetTheme.shared.pack, let spec = pack.roam else { return nil }
        if roamPhase.yieldsToStateSprite(pack.spritePaths[mood.rawValue] != nil) { return nil }
        switch roamPhase {
        case .resting:
            return nil
        case .rolling(let d):
            guard let s = cachedSprite(spec.loop) else { return nil }
            return (s, roamAge, true, d < 0)
        case .starting(let d):
            guard let url = spec.start, let s = cachedSprite(url) else { return nil }
            return (s, roamAge, false, d < 0)
        case .stopping(let d):
            // Frenar es el arranque al revés: la cabeza vuelve al frente.
            guard let url = spec.start, let s = cachedSprite(url) else { return nil }
            return (s, s.total - roamAge, false, d < 0)
        }
    }

    /// Dibuja el sprite de roam o el del estado actual. Devuelve false si no hay
    /// ninguno y hay que caer al droide vectorial.
    private func drawSprite(in box: CGRect) -> Bool {
        let frame: (sprite: Sprite, time: Double, loops: Bool, mirrored: Bool)
        let now = CACurrentMediaTime()
        if let r = roamFrame() {
            _ = spriteClock.time(showing: "roam", now: now)
            frame = r
        } else if let url = PetTheme.shared.spriteURL(for: mood), let s = cachedSprite(url) {
            frame = (s, spriteClock.time(showing: url.path, now: now), true, false)
        } else {
            lastSpriteRect = nil
            return false
        }
        let s = frame.sprite
        // Cabe en una caja algo mayor que el vector, conservando proporcion.
        var w = box.width * 1.5, h = box.height * 1.2
        let sz = s.size
        if sz.width > 0 && sz.height > 0 {
            let k = min(w / sz.width, h / sz.height)
            w = sz.width * k
            h = sz.height * k
        }
        let rect = CGRect(x: box.midX - w / 2, y: box.minY, width: w, height: h)
        if frame.mirrored {
            NSGraphicsContext.saveGraphicsState()
            let flip = NSAffineTransform()
            flip.translateX(by: rect.midX, yBy: 0)
            flip.scaleX(by: -1, yBy: 1)
            flip.translateX(by: -rect.midX, yBy: 0)
            flip.concat()
            s.draw(in: rect, at: frame.time, loops: frame.loops)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            s.draw(in: rect, at: frame.time, loops: frame.loops)
        }
        lastSpriteRect = rect
        return true
    }

    /// Caja del droide. El resto de la vista es aire para el salto y los adornos.
    private func bodyRect() -> CGRect {
        let w: CGFloat = 50, h: CGFloat = 64
        return CGRect(x: (bounds.width - w) / 2,
                      y: (bounds.height - h) / 2 - 8,
                      width: w, height: h)
    }

    // MARK: dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Desplazamiento: flotar siempre, saltar al terminar, sacudirse al fallar.
        // La formula vive en PetAnimation para que los renderers la compartan.
        let motion = PetAnimation(mood: mood, phase: phase, age: age, blinking: false)
        let body = renderer()
        // Apoyada en el piso mientras recorre la pantalla (flotar ahi se ve como
        // patinar) o si su cuerpo vectorial no flota: solo sube cuando salta.
        let usesSprite = PetTheme.shared.spriteURL(for: mood) != nil
        let grounded = roamFrame() != nil || (!usesSprite && !body.floats)
        let dy = grounded ? motion.hop : motion.lift
        let box = bodyRect().offsetBy(dx: motion.shake, dy: dy)

        // Sombra en el piso: se achica cuando sube.
        let lift = max(0, dy)
        let shadowW = box.width * (0.66 - lift / 240)
        NSColor.black.withAlphaComponent(max(0, 0.24 - lift / 340)).setFill()
        NSBezierPath(ovalIn: CGRect(x: box.midX - shadowW / 2,
                                    y: bodyRect().minY - 6,
                                    width: shadowW, height: 6)).fill()

        // Sprite propio si existe; si no, el dibujo vectorial que pida el pack.
        if drawSprite(in: box) {
            drawAccessory(body: box)
            return
        }
        let anim = PetAnimation(mood: mood, phase: phase, age: age,
                                blinking: CACurrentMediaTime() < blinkUntil)
        body.draw(box, anim, ctx)
        drawAccessory(body: box)
    }

    // MARK: el cuerpo

    /// El dibujo que pide la mascota activa. Un renderer desconocido cae al
    /// droide: el aviso ya lo dio `PetPack.load` al cargar el paquete.
    private func renderer() -> VectorRenderer {
        guard let raw = PetTheme.shared.pack?.renderer.raw,
              let r = VectorRenderers.named(raw) else { return DroidRenderer.renderer }
        return r
    }

    /// Adorno sobre la cabeza segun el estado: puntos de "pensando", signo de admiracion.
    private func drawAccessory(body: CGRect) {
        switch mood {
        case .working:
            let y = body.maxY + 22
            for i in 0..<3 {
                let a = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 5 - Double(i) * 0.9))
                mood.accent.withAlphaComponent(CGFloat(a)).setFill()
                let x = body.midX - 8 + CGFloat(i) * 8
                NSBezierPath(ovalIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)).fill()
            }
        case .attention:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .heavy),
                .foregroundColor: mood.accent,
            ]
            let s = NSAttributedString(string: "!", attributes: attrs)
            let sz = s.size()
            let bob = CGFloat(sin(phase * 5)) * 2
            s.draw(at: CGPoint(x: body.midX - sz.width / 2 + 9, y: body.maxY + 14 + bob))
        default:
            break
        }
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        dragWindowOrigin = window?.frame.origin ?? .zero
        dragDistance = 0
        mouseDownAt = CACurrentMediaTime()
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let d = CGPoint(x: now.x - dragOrigin.x, y: now.y - dragOrigin.y)
        dragDistance = max(dragDistance, abs(d.x) + abs(d.y))
        onDrag?(CGPoint(x: dragWindowOrigin.x + d.x, y: dragWindowOrigin.y + d.y))
    }

    override func mouseUp(with event: NSEvent) {
        // Un click es un click solo si casi no se movio y fue rapido.
        if dragDistance < 5 && CACurrentMediaTime() - mouseDownAt < 0.5 { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }

    // MARK: hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        hoverArea = a
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
