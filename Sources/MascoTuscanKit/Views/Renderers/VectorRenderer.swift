// Los dibujos vectoriales integrados.
//
// Existen para que una mascota pueda tener cuerpo sin que su autor tenga que
// dibujar nada: elige un renderer, pone sus colores, y ya se ve distinta. Antes
// solo habia el droide astromecanico, asi que un pack que hablaba como gato se
// veia igual que uno que hablaba como robot.
//
// Un renderer NO sabe de estados de agentes ni de eventos: recibe una caja, un
// animo y un reloj, y dibuja. Toda la logica de cuando cambiar de animo vive en
// el controlador.

import AppKit

/// Lo que el renderer necesita saber del momento actual.
public struct PetAnimation {
    public let mood: Mood
    /// Reloj continuo en segundos. Sirve para oscilaciones y parpadeos.
    public let phase: Double
    /// Segundos desde que se entro al animo actual. Las animaciones de una sola
    /// vez (el salto al terminar, la sacudida al fallar) decaen con esto.
    public let age: Double
    public let blinking: Bool

    public var accent: NSColor { mood.accent }

    public init(mood: Mood, phase: Double, age: Double, blinking: Bool) {
        self.mood = mood
        self.phase = phase
        self.age = age
        self.blinking = blinking
    }

    /// Cuanto sube el cuerpo: flota siempre, salta al terminar.
    public var lift: CGFloat {
        var dy = sin(phase * (mood == .working ? 3.2 : 1.6)) * (mood == .working ? 3 : 2)
        if mood == .done {
            dy += abs(sin(age * 7)) * 15 * max(0, 1 - age / 1.4)
        }
        return CGFloat(dy)
    }

    /// Cuanto se sacude de lado: solo al fallar, y decae rapido.
    public var shake: CGFloat {
        guard mood == .error else { return 0 }
        return CGFloat(sin(age * 34) * 5 * max(0, 1 - age / 0.9))
    }
}

/// Un dibujo integrado, como valor.
///
/// Se modela con una estructura y no con un protocolo de miembros estaticos: un
/// arreglo de metatipos de protocolo (`[VectorRenderer.Type]`) hace crashear al
/// compilador de Swift 6.2.3 al emitir el modulo. Datos en vez de metatipos
/// tambien es mas simple de registrar y de probar.
public struct VectorRenderer {
    /// El valor que se escribe en `pet.json`, por ejemplo "vector:droid".
    public let id: String
    /// Nombre para mostrar.
    public let title: String
    /// Una linea sobre como se ve.
    public let summary: String
    public let draw: (CGRect, PetAnimation, CGContext) -> Void

    public init(id: String, title: String, summary: String,
                draw: @escaping (CGRect, PetAnimation, CGContext) -> Void) {
        self.id = id
        self.title = title
        self.summary = summary
        self.draw = draw
    }
}

public enum VectorRenderers {
    /// Todos los dibujos integrados. Agregar uno es agregarlo aqui: la
    /// validacion, la ayuda del CLI y el formato lo toman de esta lista.
    public static let all: [VectorRenderer] = [
        DroidRenderer.renderer,
        BallRenderer.renderer,
        SageRenderer.renderer,
    ]

    public static func named(_ id: String) -> VectorRenderer? {
        all.first { $0.id == id }
    }

    public static var ids: [String] { all.map(\.id) }
}

// MARK: - Piezas compartidas

enum VectorInk {
    static let steel = NSColor(srgbRed: 0.86, green: 0.88, blue: 0.91, alpha: 1)
    static let steelDark = NSColor(srgbRed: 0.62, green: 0.65, blue: 0.70, alpha: 1)
    static let ink = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)

    /// Un ojo o lente que brilla: se apaga al parpadear, late al pedir atencion,
    /// y titila al fallar. Es el elemento que mas comunica el estado.
    static func glowingLens(center: CGPoint, outer: CGFloat, inner: CGFloat,
                            anim: PetAnimation, ctx: CGContext) {
        ink.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - outer, y: center.y - outer,
                                    width: outer * 2, height: outer * 2)).fill()
        steelDark.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - outer, y: center.y - outer,
                                               width: outer * 2, height: outer * 2))
        ring.lineWidth = 1.4
        ring.stroke()

        var glow: CGFloat = anim.blinking ? 0.25 : 1.0
        if anim.mood == .attention {
            glow *= CGFloat(0.65 + 0.35 * (0.5 + 0.5 * sin(anim.phase * 6)))
        }
        if anim.mood == .error {
            glow *= CGFloat(0.4 + 0.6 * (sin(anim.phase * 14) > 0 ? 1.0 : 0.35))
        }

        ctx.setShadow(offset: .zero, blur: 10,
                      color: anim.accent.withAlphaComponent(0.9 * glow).cgColor)
        anim.accent.withAlphaComponent(glow).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - inner, y: center.y - inner,
                                    width: inner * 2, height: inner * 2)).fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        NSColor.white.withAlphaComponent(0.85 * glow).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - inner * 0.64, y: center.y + inner * 0.12,
                                    width: inner * 0.48, height: inner * 0.48)).fill()
    }

    /// Tinte del estado sobre una silueta, para que el color se lea de lejos sin
    /// tener que distinguir la cara.
    static func moodWash(_ path: NSBezierPath, anim: PetAnimation) {
        guard anim.mood == .error || anim.mood == .attention || anim.mood == .done else { return }
        anim.accent.withAlphaComponent(0.10).setFill()
        path.fill()
    }
}
