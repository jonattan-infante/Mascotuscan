// Figura pequena encapuchada: tunica, capucha con los ojos en sombra y un
// baston. Es un arquetipo de cuento, no un personaje de nadie.
//
// Aporta una silueta organica frente a las dos maquinas: sirve para mascotas con
// voz tranquila o sentenciosa, donde un robot desentonaria.

import AppKit

public enum SageRenderer {

    public static let renderer = VectorRenderer(
        id: "vector:sage",
        title: "Figura encapuchada",
        summary: "Túnica, capucha con los ojos en sombra y un bastón.",
        draw: draw)

    public static func draw(in box: CGRect, anim: PetAnimation, ctx: CGContext) {
        let accent = anim.accent
        let ink = VectorInk.ink

        // La tunica ocupa casi toda la caja: la silueta es lo que identifica.
        let robeW = box.width * 0.74
        let robe = CGRect(x: box.midX - robeW / 2, y: box.minY,
                          width: robeW, height: box.height * 0.78)

        // Respirar: la tunica se ensancha y encoge apenas. Es lo que la separa
        // de un cono quieto.
        let breath = CGFloat(sin(anim.phase * 1.1)) * 1.6

        drawStaff(box: box, robe: robe, anim: anim)

        // --- tunica ---
        let cloth = NSColor(srgbRed: 0.40, green: 0.34, blue: 0.28, alpha: 1)
        let clothDark = NSColor(srgbRed: 0.26, green: 0.21, blue: 0.17, alpha: 1)

        let body = NSBezierPath()
        body.move(to: CGPoint(x: robe.midX - robe.width * 0.20, y: robe.maxY))
        body.curve(to: CGPoint(x: robe.minX - breath, y: robe.minY),
                   controlPoint1: CGPoint(x: robe.midX - robe.width * 0.34, y: robe.midY),
                   controlPoint2: CGPoint(x: robe.minX - breath, y: robe.minY + robe.height * 0.28))
        body.line(to: CGPoint(x: robe.maxX + breath, y: robe.minY))
        body.curve(to: CGPoint(x: robe.midX + robe.width * 0.20, y: robe.maxY),
                   controlPoint1: CGPoint(x: robe.maxX + breath, y: robe.minY + robe.height * 0.28),
                   controlPoint2: CGPoint(x: robe.midX + robe.width * 0.34, y: robe.midY))
        body.close()
        if let g = NSGradient(colors: [cloth, clothDark],
                              atLocations: [0.0, 1.0], colorSpace: .sRGB) {
            g.draw(in: body, angle: -75)
        }
        ink.withAlphaComponent(0.4).setStroke()
        body.lineWidth = 1.2
        body.stroke()

        // Pliegues: dos lineas bastan para que la tela no se vea plana.
        clothDark.withAlphaComponent(0.55).setStroke()
        for dx in [-0.16, 0.14] as [CGFloat] {
            let fold = NSBezierPath()
            fold.move(to: CGPoint(x: robe.midX + robe.width * dx, y: robe.maxY - robe.height * 0.18))
            fold.line(to: CGPoint(x: robe.midX + robe.width * dx * 1.9, y: robe.minY + 3))
            fold.lineWidth = 1.4
            fold.stroke()
        }

        // Cinto en el color del estado.
        accent.withAlphaComponent(0.8).setStroke()
        let belt = NSBezierPath()
        belt.move(to: CGPoint(x: robe.midX - robe.width * 0.30, y: robe.minY + robe.height * 0.46))
        belt.curve(to: CGPoint(x: robe.midX + robe.width * 0.30, y: robe.minY + robe.height * 0.46),
                   controlPoint1: CGPoint(x: robe.midX - robe.width * 0.1, y: robe.minY + robe.height * 0.42),
                   controlPoint2: CGPoint(x: robe.midX + robe.width * 0.1, y: robe.minY + robe.height * 0.42))
        belt.lineWidth = 2.4
        belt.lineCapStyle = .round
        belt.stroke()

        // --- capucha ---
        let hoodR = box.width * 0.235
        let nod = nodOffset(mood: anim.mood, phase: anim.phase, age: anim.age)
        let hood = CGPoint(x: robe.midX + nod.x, y: robe.maxY + hoodR * 0.42 + nod.y)

        let hoodPath = NSBezierPath()
        hoodPath.appendArc(withCenter: hood, radius: hoodR, startAngle: 8, endAngle: 172)
        hoodPath.curve(to: CGPoint(x: hood.x + hoodR * 0.99, y: hood.y - hoodR * 0.14),
                       controlPoint1: CGPoint(x: hood.x - hoodR * 0.72, y: hood.y - hoodR * 0.86),
                       controlPoint2: CGPoint(x: hood.x + hoodR * 0.72, y: hood.y - hoodR * 0.86))
        hoodPath.close()
        if let g = NSGradient(colors: [cloth, clothDark],
                              atLocations: [0.0, 1.0], colorSpace: .sRGB) {
            g.draw(in: hoodPath, angle: -80)
        }
        ink.withAlphaComponent(0.45).setStroke()
        hoodPath.lineWidth = 1.2
        hoodPath.stroke()

        // La sombra de la capucha: el rostro nunca se ve, solo los ojos. Asi la
        // figura no es nadie en particular.
        let shade = NSBezierPath(ovalIn: CGRect(x: hood.x - hoodR * 0.62, y: hood.y - hoodR * 0.62,
                                                width: hoodR * 1.24, height: hoodR * 1.02))
        NSColor(white: 0.06, alpha: 0.92).setFill()
        shade.fill()

        drawEyes(center: hood, radius: hoodR, anim: anim, ctx: ctx)

        let wash = NSBezierPath()
        wash.append(body)
        wash.append(hoodPath)
        VectorInk.moodWash(wash, anim: anim)
    }

    /// La cabeza asiente o niega segun el estado. Es el gesto que reemplaza a la
    /// cara, que aqui esta siempre en sombra.
    static func nodOffset(mood: Mood, phase: Double, age: Double) -> CGPoint {
        switch mood {
        case .working:
            return CGPoint(x: CGFloat(sin(phase * 1.9)) * 2.2, y: 0)
        case .done:
            // Un asentimiento corto al terminar, y se detiene.
            return CGPoint(x: 0, y: CGFloat(sin(age * 6)) * 2.4 * CGFloat(max(0, 1 - age / 1.2)))
        case .error:
            // Negar con la cabeza.
            return CGPoint(x: CGFloat(sin(age * 9)) * 3 * CGFloat(max(0, 1 - age / 1.4)), y: 0)
        case .attention:
            return CGPoint(x: 0, y: CGFloat(sin(phase * 5)) * 1.4)
        default:
            return CGPoint(x: CGFloat(sin(phase * 0.5)) * 1.6, y: 0)
        }
    }

    /// Dos ojos en la sombra. No hay lente ni maquina: brillan, no se encienden.
    static func drawEyes(center: CGPoint, radius: CGFloat, anim: PetAnimation, ctx: CGContext) {
        let y = center.y - radius * 0.06
        let dx = radius * 0.30
        var glow: CGFloat = anim.blinking ? 0.12 : 1
        if anim.mood == .attention {
            glow *= CGFloat(0.6 + 0.4 * (0.5 + 0.5 * sin(anim.phase * 6)))
        }

        for x in [center.x - dx, center.x + dx] {
            ctx.setShadow(offset: .zero, blur: 7,
                          color: anim.accent.withAlphaComponent(0.85 * glow).cgColor)
            anim.accent.withAlphaComponent(glow).setFill()
            if anim.blinking {
                // Parpadear es cerrar: una linea, no un ovalo tenue.
                let l = NSBezierPath()
                l.move(to: CGPoint(x: x - radius * 0.16, y: y))
                l.line(to: CGPoint(x: x + radius * 0.16, y: y))
                l.lineWidth = 1.6
                l.lineCapStyle = .round
                anim.accent.withAlphaComponent(0.5).setStroke()
                l.stroke()
            } else {
                NSBezierPath(ovalIn: CGRect(x: x - radius * 0.15, y: y - radius * 0.10,
                                            width: radius * 0.30, height: radius * 0.20)).fill()
            }
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
    }

    /// El baston, apoyado en el piso. Se inclina un poco al fallar.
    static func drawStaff(box: CGRect, robe: CGRect, anim: PetAnimation) {
        let wood = NSColor(srgbRed: 0.44, green: 0.32, blue: 0.20, alpha: 1)
        let lean = anim.mood == .error
            ? CGFloat(sin(anim.age * 8)) * 2 * CGFloat(max(0, 1 - anim.age / 1.2)) : 0

        let staff = NSBezierPath()
        let bottom = CGPoint(x: robe.minX - 3, y: box.minY + 1)
        let top = CGPoint(x: robe.minX + 1 + lean, y: robe.maxY + box.height * 0.06)
        staff.move(to: bottom)
        staff.curve(to: top,
                    controlPoint1: CGPoint(x: bottom.x - 2, y: robe.midY),
                    controlPoint2: CGPoint(x: top.x - 3, y: robe.maxY * 0.9))
        staff.lineWidth = 2.4
        staff.lineCapStyle = .round
        wood.setStroke()
        staff.stroke()
    }
}
