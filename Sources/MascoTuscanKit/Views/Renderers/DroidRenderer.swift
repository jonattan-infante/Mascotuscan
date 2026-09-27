// El droide astromecanico: cupula con lente, torso con paneles y tres patas.
// Es el dibujo original del proyecto y el que usan las mascotas incluidas.

import AppKit

public enum DroidRenderer {

    public static let renderer = VectorRenderer(
        id: "vector:droid",
        title: "Droide astromecánico",
        summary: "Cúpula con lente, torso con paneles y luces, tres patas.",
        draw: draw)

    public static func draw(in box: CGRect, anim: PetAnimation, ctx: CGContext) {
        let mood = anim.mood
        let phase = anim.phase
        let accent = anim.accent
        let steel = VectorInk.steel
        let steelDark = VectorInk.steelDark
        let ink = VectorInk.ink
        let sway = domeSway(mood: mood, phase: phase)

        let domeH = box.width * 0.42
        let torso = CGRect(x: box.minX + 7, y: box.minY + 11,
                           width: box.width - 14, height: box.height - domeH - 14)

        /// Pata: caña inclinada hacia afuera y pie plano. Se dibuja antes del
        /// torso para que el torso le tape el arranque.
        func drawLeg(topX: CGFloat, botX: CGFloat, top: CGFloat, thickness: CGFloat) {
            let stem = NSBezierPath()
            stem.move(to: CGPoint(x: topX, y: top))
            stem.line(to: CGPoint(x: botX, y: box.minY + 6))
            stem.lineWidth = thickness
            stem.lineCapStyle = .round
            steelDark.setStroke()
            stem.stroke()

            // Ranura central: sin esto la caña se ve como un palo plano.
            let groove = NSBezierPath()
            groove.move(to: CGPoint(x: topX, y: top - 2))
            groove.line(to: CGPoint(x: botX, y: box.minY + 7))
            groove.lineWidth = max(1.5, thickness - 5)
            groove.lineCapStyle = .round
            ink.withAlphaComponent(0.45).setStroke()
            groove.stroke()

            let foot = CGRect(x: botX - thickness / 2 - 2.5, y: box.minY,
                              width: thickness + 5, height: 6)
            ink.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: foot, xRadius: 2.5, yRadius: 2.5).fill()
            steelDark.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: CGRect(x: foot.minX + 1, y: foot.maxY - 2.5,
                                             width: foot.width - 2, height: 2.5),
                         xRadius: 1, yRadius: 1).fill()
        }

        drawLeg(topX: torso.minX + 3, botX: box.minX + 4, top: torso.maxY - 5, thickness: 7)
        drawLeg(topX: torso.maxX - 3, botX: box.maxX - 4, top: torso.maxY - 5, thickness: 7)

        // --- torso ---
        let torsoPath = NSBezierPath(roundedRect: torso, xRadius: 6, yRadius: 6)
        if let g = NSGradient(colors: [steel, NSColor.white, steelDark],
                              atLocations: [0.0, 0.35, 1.0],
                              colorSpace: .sRGB) {
            g.draw(in: torsoPath, angle: 0)
        }
        ink.withAlphaComponent(0.55).setStroke()
        torsoPath.lineWidth = 1.2
        torsoPath.stroke()

        // Banda central y rejilla: lo que hace que se lea como droide y no como caja.
        ink.withAlphaComponent(0.75).setFill()
        NSBezierPath(rect: CGRect(x: torso.minX, y: torso.midY + 3,
                                  width: torso.width, height: 4)).fill()
        steelDark.withAlphaComponent(0.9).setFill()
        for i in 0..<4 {
            NSBezierPath(rect: CGRect(x: torso.minX + 4 + CGFloat(i) * 7.5,
                                      y: torso.minY + 4, width: 4, height: 5)).fill()
        }

        // Panel de color: el unico elemento del torso que cambia con el estado.
        let panel = CGRect(x: torso.minX + 4, y: torso.midY - 11, width: 12, height: 11)
        accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 2, yRadius: 2).fill()
        ink.withAlphaComponent(0.5).setStroke()
        let panelPath = NSBezierPath(roundedRect: panel, xRadius: 2, yRadius: 2)
        panelPath.lineWidth = 1
        panelPath.stroke()

        // Panel gris de al lado.
        steelDark.setFill()
        NSBezierPath(roundedRect: CGRect(x: torso.maxX - 16, y: torso.midY - 10,
                                         width: 12, height: 9),
                     xRadius: 2, yRadius: 2).fill()

        // Luces de estado: parpadean en secuencia solo mientras trabaja.
        let lights: [NSColor] = [
            NSColor(srgbRed: 0.95, green: 0.35, blue: 0.35, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.78, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 0.40, green: 0.80, blue: 0.95, alpha: 1),
        ]
        for (i, c) in lights.enumerated() {
            let on: CGFloat = mood == .working
                ? CGFloat(0.25 + 0.75 * (0.5 + 0.5 * sin(phase * 6 - Double(i) * 1.1)))
                : 0.5
            c.withAlphaComponent(on).setFill()
            let lx = torso.minX + 5 + CGFloat(i) * 6
            NSBezierPath(ovalIn: CGRect(x: lx, y: torso.maxY - 8, width: 3.4, height: 3.4)).fill()
        }

        // --- tercera pata, al frente y por delante del torso ---
        let centerFoot = CGRect(x: box.midX - 7, y: box.minY, width: 14, height: 6)
        steelDark.setFill()
        NSBezierPath(roundedRect: CGRect(x: box.midX - 3, y: box.minY + 3,
                                         width: 6, height: torso.minY - box.minY),
                     xRadius: 2.5, yRadius: 2.5).fill()
        ink.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: centerFoot, xRadius: 2.5, yRadius: 2.5).fill()
        steelDark.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: CGRect(x: centerFoot.minX + 1, y: centerFoot.maxY - 2.5,
                                         width: centerFoot.width - 2, height: 2.5),
                     xRadius: 1, yRadius: 1).fill()

        // --- cupula ---

        let domeCenter = CGPoint(x: box.midX + sway * 0.35, y: torso.maxY)
        let domeR = torso.width / 2 + 1
        let dome = NSBezierPath()
        dome.appendArc(withCenter: domeCenter, radius: domeR, startAngle: 0, endAngle: 180)
        dome.close()
        if let g = NSGradient(colors: [steel, NSColor.white, steelDark],
                              atLocations: [0.0, 0.4, 1.0],
                              colorSpace: .sRGB) {
            g.draw(in: dome, angle: 0)
        }
        ink.withAlphaComponent(0.55).setStroke()
        dome.lineWidth = 1.2
        dome.stroke()

        // Franjas de la cupula, giran con ella.
        accent.withAlphaComponent(0.7).setStroke()
        let stripe = NSBezierPath()
        stripe.appendArc(withCenter: domeCenter, radius: domeR - 5,
                         startAngle: 118 - Double(sway), endAngle: 152 - Double(sway))
        stripe.lineWidth = 3
        stripe.lineCapStyle = .round
        stripe.stroke()

        // --- lente ---
        let dim = anim.blinking
        let lens = CGPoint(x: domeCenter.x + sway, y: domeCenter.y + domeR * 0.42)
        let outerR: CGFloat = 8.5
        ink.setFill()
        NSBezierPath(ovalIn: CGRect(x: lens.x - outerR, y: lens.y - outerR,
                                    width: outerR * 2, height: outerR * 2)).fill()
        steelDark.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: lens.x - outerR, y: lens.y - outerR,
                                               width: outerR * 2, height: outerR * 2))
        ring.lineWidth = 1.4
        ring.stroke()

        // El ojo late cuando hay algo que atender y se apaga al parpadear.
        var glow: CGFloat = dim ? 0.25 : 1.0
        if mood == .attention { glow *= CGFloat(0.65 + 0.35 * (0.5 + 0.5 * sin(phase * 6))) }
        if mood == .error { glow *= CGFloat(0.4 + 0.6 * (sin(phase * 14) > 0 ? 1.0 : 0.35)) }
        let innerR: CGFloat = 5
        ctx.setShadow(offset: .zero, blur: 10, color: accent.withAlphaComponent(0.9 * glow).cgColor)
        accent.withAlphaComponent(glow).setFill()
        NSBezierPath(ovalIn: CGRect(x: lens.x - innerR, y: lens.y - innerR,
                                    width: innerR * 2, height: innerR * 2)).fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        NSColor.white.withAlphaComponent(0.85 * glow).setFill()
        NSBezierPath(ovalIn: CGRect(x: lens.x - 3.2, y: lens.y + 0.6,
                                    width: 2.4, height: 2.4)).fill()

        // Tinte de estado sobre todo el droide, sutil, para que el color se lea de lejos.
        if mood == .error || mood == .attention || mood == .done {
            accent.withAlphaComponent(0.10).setFill()
            let wash = NSBezierPath(roundedRect: torso, xRadius: 6, yRadius: 6)
            wash.append(dome)
            wash.fill()
        }
    }

    /// Cuanto gira la cupula. En reposo mira alrededor despacio; trabajando, rapido.
    static func domeSway(mood: Mood, phase: Double) -> CGFloat {
        switch mood {
        case .working:   return CGFloat(sin(phase * 2.6)) * 6
        case .attention: return CGFloat(sin(phase * 5.0)) * 3
        case .error:     return CGFloat(sin(phase * 1.2)) * 2
        default:         return CGFloat(sin(phase * 0.7)) * 5
        }
    }
}
