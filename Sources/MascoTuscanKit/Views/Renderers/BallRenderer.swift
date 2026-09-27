// Droide esferico: cuerpo bola que rueda, cabeza cupula que se apoya encima.
//
// La bola es un arquetipo de droide, no un personaje: geometria propia, sin
// tomar el diseno de nadie. Existe porque el astromecanico era el unico cuerpo
// disponible y toda mascota sin arte terminaba pareciendose a un robot de
// servicio, hablara como hablara.

import AppKit

public enum BallRenderer {

    public static let renderer = VectorRenderer(
        id: "vector:ball",
        title: "Droide esférico",
        summary: "Cuerpo esfera que rueda, cabeza cúpula con lente.",
        draw: draw)

    public static func draw(in box: CGRect, anim: PetAnimation, ctx: CGContext) {
        let accent = anim.accent
        let steel = VectorInk.steel
        let steelDark = VectorInk.steelDark
        let ink = VectorInk.ink

        // La bola ocupa la parte baja; la cupula se apoya y no gira con ella.
        let ballD = min(box.width, box.height * 0.62)
        let ball = CGRect(x: box.midX - ballD / 2, y: box.minY, width: ballD, height: ballD)

        // Rodar: el cuerpo gira segun el animo, la cupula solo se inclina. Es el
        // gesto que distingue a este renderer del astromecanico, que camina.
        let roll = rollAngle(mood: anim.mood, phase: anim.phase)

        drawBall(ball, roll: roll, accent: accent, steel: steel,
                 steelDark: steelDark, ink: ink, anim: anim)

        // --- cupula ---
        let tilt = CGFloat(sin(anim.phase * (anim.mood == .working ? 2.4 : 0.8)))
            * (anim.mood == .working ? 5 : 3)
        let domeR = ballD * 0.34
        let domeCenter = CGPoint(x: ball.midX + tilt * 0.6, y: ball.maxY - domeR * 0.12)

        let dome = NSBezierPath()
        dome.appendArc(withCenter: domeCenter, radius: domeR, startAngle: 0, endAngle: 180)
        dome.close()
        if let g = NSGradient(colors: [steel, .white, steelDark],
                              atLocations: [0.0, 0.4, 1.0], colorSpace: .sRGB) {
            g.draw(in: dome, angle: 0)
        }
        ink.withAlphaComponent(0.5).setStroke()
        dome.lineWidth = 1.2
        dome.stroke()

        // Banda de la cupula, en el color del estado.
        accent.withAlphaComponent(0.75).setStroke()
        let band = NSBezierPath()
        band.appendArc(withCenter: domeCenter, radius: domeR - 3.5,
                       startAngle: 104 - Double(tilt), endAngle: 150 - Double(tilt))
        band.lineWidth = 2.6
        band.lineCapStyle = .round
        band.stroke()

        // La antena es lo unico que sobresale: da silueta y marca el estado.
        let antenna = NSBezierPath()
        let tip = CGPoint(x: domeCenter.x + tilt * 1.4, y: domeCenter.y + domeR + 11)
        antenna.move(to: CGPoint(x: domeCenter.x + tilt * 0.4, y: domeCenter.y + domeR - 2))
        antenna.line(to: tip)
        antenna.lineWidth = 1.6
        antenna.lineCapStyle = .round
        steelDark.setStroke()
        antenna.stroke()
        accent.setFill()
        NSBezierPath(ovalIn: CGRect(x: tip.x - 2, y: tip.y - 2, width: 4, height: 4)).fill()

        // --- lente ---
        VectorInk.glowingLens(
            center: CGPoint(x: domeCenter.x + tilt, y: domeCenter.y + domeR * 0.40),
            outer: domeR * 0.42, inner: domeR * 0.25, anim: anim, ctx: ctx)

        // Lente pequeno al lado: dos ojos desiguales leen como maquina, no como cara.
        steelDark.setFill()
        let small = CGPoint(x: domeCenter.x + tilt + domeR * 0.52, y: domeCenter.y + domeR * 0.24)
        NSBezierPath(ovalIn: CGRect(x: small.x - 3, y: small.y - 3, width: 6, height: 6)).fill()
        ink.setFill()
        NSBezierPath(ovalIn: CGRect(x: small.x - 1.8, y: small.y - 1.8, width: 3.6, height: 3.6)).fill()

        var wash = NSBezierPath(ovalIn: ball)
        wash.append(dome)
        VectorInk.moodWash(wash, anim: anim)
        wash = NSBezierPath()
    }

    /// Cuanto ha rodado el cuerpo. Trabajando rueda de verdad; en reposo apenas
    /// se mece, como algo que se balancea sobre su propio eje.
    static func rollAngle(mood: Mood, phase: Double) -> CGFloat {
        switch mood {
        case .working:   return CGFloat(phase * 1.6)
        case .done:      return CGFloat(sin(phase * 4)) * 0.5
        case .error:     return CGFloat(sin(phase * 12)) * 0.12
        default:         return CGFloat(sin(phase * 0.6)) * 0.22
        }
    }

    /// El cuerpo, con los aros que hacen visible el giro.
    static func drawBall(_ ball: CGRect, roll: CGFloat, accent: NSColor,
                         steel: NSColor, steelDark: NSColor, ink: NSColor,
                         anim: PetAnimation) {
        let path = NSBezierPath(ovalIn: ball)
        if let g = NSGradient(colors: [.white, steel, steelDark],
                              atLocations: [0.0, 0.45, 1.0], colorSpace: .sRGB) {
            g.draw(in: path, angle: -60)
        }

        // Los aros se recortan contra la esfera para que el giro se vea sin que
        // nada se salga del cuerpo.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let r = ball.width / 2
        for i in 0..<3 {
            // Cada aro entra y sale por el borde segun el giro: eso es lo que da
            // la sensacion de rodar.
            let t = (Double(roll) + Double(i) * 2.09).truncatingRemainder(dividingBy: 6.28)
            let x = ball.midX + CGFloat(sin(t)) * r * 0.92
            let squash = abs(CGFloat(cos(t)))
            guard squash > 0.06 else { continue }
            let w = r * 0.62 * squash
            let ringRect = CGRect(x: x - w, y: ball.midY - r * 0.46,
                                  width: w * 2, height: r * 0.92)
            accent.withAlphaComponent(0.85).setStroke()
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 3
            ring.stroke()
            accent.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: ringRect.insetBy(dx: w * 0.45, dy: r * 0.2)).fill()
        }

        // Linea del ecuador: ancla el cuerpo y evita que se lea como un globo.
        steelDark.withAlphaComponent(0.5).setStroke()
        let eq = NSBezierPath(ovalIn: CGRect(x: ball.minX - 2, y: ball.midY - r * 0.20,
                                             width: ball.width + 4, height: r * 0.40))
        eq.lineWidth = 1.2
        eq.stroke()

        NSGraphicsContext.restoreGraphicsState()

        ink.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1.3
        path.stroke()

        // Brillo alto: sin esto la esfera se ve plana.
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: CGRect(x: ball.minX + ball.width * 0.20,
                                    y: ball.minY + ball.height * 0.62,
                                    width: ball.width * 0.22,
                                    height: ball.height * 0.14)).fill()
    }
}
