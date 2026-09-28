// Droide esferico: cuerpo bola que rueda, cabeza cupula que se apoya encima.
//
// La bola es un arquetipo de droide, no un personaje: geometria propia, sin
// tomar el diseno de nadie. Existe porque el astromecanico era el unico cuerpo
// disponible y toda mascota sin arte terminaba pareciendose a un robot de
// servicio, hablara como hablara.
//
// Dos movimientos lo definen, y cada uno tiene que leerse solo:
//   quieto   el cuerpo no se mueve; la cabeza mira alrededor, con pausas.
//   rodando  el cuerpo gira hacia quien mira, con los paneles barridos, y la
//            cabeza se queda arriba equilibrandose.

import AppKit

public enum BallRenderer {

    public static let renderer = VectorRenderer(
        id: "vector:ball",
        title: "Droide esférico",
        summary: "Cuerpo esfera que rueda, cabeza cúpula que mira alrededor.",
        floats: false,
        draw: draw)

    public static func draw(in box: CGRect, anim: PetAnimation, ctx: CGContext) {
        let now = pose(for: anim)
        let ballD = min(box.width, box.height * 0.62)
        let ball = CGRect(x: box.midX - ballD / 2, y: box.minY, width: ballD, height: ballD)

        drawDust(under: ball, anim: anim)
        drawBody(ball, pose: now, anim: anim)
        drawHead(on: ball, pose: now, anim: anim, ctx: ctx)
    }

    // MARK: - Movimiento

    /// Lo que se mueve en un instante. Vive aparte del dibujo para poder probar
    /// el movimiento sin mirar pixeles.
    struct Pose {
        /// Giro del cuerpo hacia quien mira, en radianes.
        var roll = 0.0
        /// Balanceo del cuerpo de lado a lado, en radianes.
        var rock = 0.0
        /// Hacia donde mira la cabeza: 0 de frente, positivo a la derecha.
        var yaw = 0.0
        /// Inclinacion de la cabeza, en radianes; positivo hacia la derecha.
        var tilt = 0.0
        /// Rebote de la cabeza sobre el cuerpo, en puntos.
        var bob = 0.0
        /// Copias del cuerpo que forman el barrido. 1 es nitido.
        var blurSamples = 1
    }

    /// Cuanto gira la cabeza en reposo: un poco, sin darse la vuelta.
    static let idleYawLimit = 0.5
    /// Radianes por segundo al rodar: lo justo para que los paneles se barran.
    static let rollSpeed = 6.0

    static func pose(for anim: PetAnimation) -> Pose {
        var p = Pose()
        switch anim.mood {
        case .idle, .info:
            p.yaw = lookAround(anim.phase)
            p.tilt = p.yaw * 0.14
        case .working:
            p.roll = anim.phase * rollSpeed
            p.yaw = sin(anim.phase * 0.9) * 0.08
            p.tilt = sin(anim.phase * 3.1) * 0.06
            p.bob = abs(sin(anim.phase * rollSpeed)) * 0.9
            p.blurSamples = 8
        case .done:
            // Un meneo de alegria que se apaga, encima del salto comun.
            let decay = max(0, 1 - anim.age / 1.4)
            p.rock = sin(anim.age * 10) * 0.35 * decay
            p.tilt = -p.rock * 0.5
        case .error:
            // La cabeza dice que no; el cuerpo ya se sacude con PetAnimation.shake.
            let decay = max(0, 1 - anim.age / 1.2)
            p.yaw = sin(anim.age * 16) * 0.45 * decay
        case .attention:
            // Mira de frente y se mece: tiene que moverse mas que en reposo.
            p.rock = sin(anim.phase * 5) * 0.18
            p.tilt = sin(anim.phase * 5) * 0.10
            p.bob = (0.5 + 0.5 * sin(anim.phase * 10)) * 1.2
        }
        return p
    }

    /// Mirar alrededor con pausas: al frente, a un lado, al frente, al otro.
    /// Las pausas son las que lo hacen parecer atento y no un pendulo.
    static func lookAround(_ t: Double) -> Double {
        let cycle = 8.0
        let keys: [(at: Double, yaw: Double)] = [
            (0.0, 0), (2.2, 0), (2.7, 0.42), (4.0, 0.42), (4.5, 0),
            (5.4, 0), (5.9, -0.30), (7.4, -0.30), (8.0, 0),
        ]
        var u = t.truncatingRemainder(dividingBy: cycle)
        if u < 0 { u += cycle }
        for (a, b) in zip(keys, keys.dropFirst()) where u <= b.at {
            let k = (u - a.at) / (b.at - a.at)
            return a.yaw + (b.yaw - a.yaw) * k * k * (3 - 2 * k)
        }
        return 0
    }

    // MARK: - Geometria del cuerpo

    struct Vec {
        var x, y, z: Double

        static func * (v: Vec, k: Double) -> Vec { Vec(x: v.x * k, y: v.y * k, z: v.z * k) }
        static func + (a: Vec, b: Vec) -> Vec { Vec(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }

        var normalized: Vec { self * (1 / (x * x + y * y + z * z).squareRoot()) }

        func cross(_ o: Vec) -> Vec {
            Vec(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
        }

        /// El punto como lo deja el cuerpo: primero rueda sobre el eje x (la
        /// cara de arriba viene hacia quien mira) y despues se mece sobre el z.
        func turned(roll: Double, rock: Double) -> Vec {
            let y1 = y * cos(roll) - z * sin(roll)
            let z1 = y * sin(roll) + z * cos(roll)
            return Vec(x: x * cos(rock) - y1 * sin(rock),
                       y: x * sin(rock) + y1 * cos(rock),
                       z: z1)
        }
    }

    /// Los paneles, en las caras de un tetraedro: en reposo queda uno grande al
    /// frente y los otros asoman por el borde. Cuatro se leen a este tamano;
    /// mas serian ruido.
    static let panels: [Vec] = {
        let front = Vec(x: -0.2, y: 0.05, z: 1).normalized
        let side = Vec(x: 0, y: 1, z: 0).cross(front).normalized
        let up = front.cross(side)
        let spread = acos(-1.0 / 3)
        let rest = [-30.0, 90, 210].map { deg -> Vec in
            let a = deg * .pi / 180
            return front * cos(spread) + (side * cos(a) + up * sin(a)) * sin(spread)
        }
        return [front] + rest
    }()

    /// Radio angular de un panel. Los paneles no se tocan: el tetraedro los
    /// separa 109 grados.
    static let panelRadius = 0.68

    /// El contorno visible de un panel, en el disco unidad. Los puntos que
    /// quedan detras se aplastan contra el borde de la esfera, que es donde el
    /// ojo los pierde: un panel que se esconde no atraviesa el cuerpo. nil si
    /// el panel entero esta del otro lado.
    static func outline(of center: Vec, radius: Double, roll: Double, rock: Double,
                        steps: Int = 40) -> [CGPoint]? {
        let helper = abs(center.y) < 0.9 ? Vec(x: 0, y: 1, z: 0) : Vec(x: 1, y: 0, z: 0)
        let u = helper.cross(center).normalized
        let w = center.cross(u)
        var points: [CGPoint] = []
        var anyVisible = false
        for i in 0..<steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let p = (center * cos(radius) + (u * cos(t) + w * sin(t)) * sin(radius))
                .turned(roll: roll, rock: rock)
            if p.z >= 0 {
                anyVisible = true
                points.append(CGPoint(x: p.x, y: p.y))
            } else {
                let n = (p.x * p.x + p.y * p.y).squareRoot()
                if n > 1e-6 { points.append(CGPoint(x: p.x / n, y: p.y / n)) }
            }
        }
        return anyVisible ? points : nil
    }

    // MARK: - Dibujo

    /// Polvo que levanta al rodar, a los dos lados de la base. Sin esto, rodar
    /// en el mismo sitio se lee como girar en el aire.
    static func drawDust(under ball: CGRect, anim: PetAnimation) {
        guard anim.mood == .working else { return }
        let r = ball.width / 2
        for side in [-1.0, 1.0] {
            for k in 0..<4 {
                var u = (anim.phase / 0.7 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
                if u < 0 { u += 1 }
                let x = ball.midX + CGFloat(side) * (r * 0.55 + CGFloat(u) * 11)
                let y = ball.minY + 1 + CGFloat(u * 6 - u * u * 4)
                let d = CGFloat(1.4 + u * 2.2)
                VectorInk.steelDark.withAlphaComponent(CGFloat(0.4 * (1 - u))).setFill()
                NSBezierPath(ovalIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
            }
        }
    }

    static func drawBody(_ ball: CGRect, pose: Pose, anim: PetAnimation) {
        let accent = anim.accent
        let path = NSBezierPath(ovalIn: ball)
        if let g = NSGradient(colors: [.white, VectorInk.steel, VectorInk.steelDark],
                              atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB) {
            g.draw(in: path, relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
        }

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let r = ball.width / 2
        func shape(_ pts: [CGPoint]) -> NSBezierPath {
            let bp = NSBezierPath()
            for (i, p) in pts.enumerated() {
                let q = CGPoint(x: ball.midX + p.x * r, y: ball.midY + p.y * r)
                if i == 0 { bp.move(to: q) } else { bp.line(to: q) }
            }
            bp.close()
            return bp
        }

        // Barrido: el cuerpo se dibuja varias veces un poco atras en el giro.
        // Con una sola copia, rodar rapido se ve como saltar de cuadro en cuadro.
        let copies = max(1, pose.blurSamples)
        let alpha: CGFloat = copies == 1 ? 1 : 0.4
        let inner = (VectorInk.steel.blended(withFraction: 0.18, of: accent) ?? VectorInk.steel)
        for k in (0..<copies).reversed() {
            let roll = pose.roll - Double(k) * 0.045
            for c in panels {
                guard let ring = outline(of: c, radius: panelRadius, roll: roll, rock: pose.rock)
                else { continue }
                accent.withAlphaComponent(0.92 * alpha).setFill()
                shape(ring).fill()
                if let disc = outline(of: c, radius: panelRadius * 0.62, roll: roll, rock: pose.rock) {
                    inner.withAlphaComponent(alpha).setFill()
                    shape(disc).fill()
                }
                if let hub = outline(of: c, radius: panelRadius * 0.2, roll: roll, rock: pose.rock) {
                    accent.withAlphaComponent(0.6 * alpha).setFill()
                    shape(hub).fill()
                }
            }
        }

        // Remaches entre paneles: solo nitidos, barridos serian manchas.
        if copies == 1 {
            VectorInk.ink.withAlphaComponent(0.35).setFill()
            for b in panels {
                let p = (b * -1).turned(roll: pose.roll, rock: pose.rock)
                guard p.z > 0.25 else { continue }
                let q = CGPoint(x: ball.midX + p.x * r, y: ball.midY + p.y * r)
                NSBezierPath(ovalIn: CGRect(x: q.x - 0.9, y: q.y - 0.9, width: 1.8, height: 1.8)).fill()
            }
        }

        // Oscurecer el borde es lo que hace que los paneles se vean pegados a
        // una esfera y no a un disco.
        if let shade = NSGradient(colors: [NSColor.white.withAlphaComponent(0.30),
                                           NSColor.white.withAlphaComponent(0),
                                           NSColor.black.withAlphaComponent(0.24)],
                                  atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB) {
            shade.draw(in: path, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
        }
        NSGraphicsContext.restoreGraphicsState()

        VectorInk.ink.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1.3
        path.stroke()
        VectorInk.moodWash(path, anim: anim)
    }

    static func drawHead(on ball: CGRect, pose: Pose, anim: PetAnimation, ctx: CGContext) {
        let accent = anim.accent
        let steel = VectorInk.steel
        let steelDark = VectorInk.steelDark
        let ink = VectorInk.ink
        let rx = ball.width * 0.34
        let ry = rx * 0.9
        let collarH = rx * 0.24

        ctx.saveGState()
        defer { ctx.restoreGState() }
        // La cabeza se corre un poco hacia donde mira, como si rodara sobre el cuerpo.
        ctx.translateBy(x: ball.midX + CGFloat(pose.yaw) * rx * 0.18,
                        y: ball.maxY - rx * 0.12 + CGFloat(pose.bob))
        ctx.rotate(by: CGFloat(-pose.tilt))

        // Cuello: la junta oscura sobre la que gira la cabeza.
        let collar = NSBezierPath(roundedRect: CGRect(x: -rx * 0.9, y: -collarH * 0.5,
                                                      width: rx * 1.8, height: collarH),
                                  xRadius: collarH / 2, yRadius: collarH / 2)
        if let g = NSGradient(colors: [ink, steelDark, ink],
                              atLocations: [0.0, 0.45, 1.0], colorSpace: .sRGB) {
            g.draw(in: collar, angle: 0)
        }

        let y0 = collarH * 0.5 - 0.5
        let k: CGFloat = 0.5523
        let dome = NSBezierPath()
        dome.move(to: CGPoint(x: -rx, y: y0))
        dome.curve(to: CGPoint(x: 0, y: y0 + ry),
                   controlPoint1: CGPoint(x: -rx, y: y0 + k * ry),
                   controlPoint2: CGPoint(x: -k * rx, y: y0 + ry))
        dome.curve(to: CGPoint(x: rx, y: y0),
                   controlPoint1: CGPoint(x: k * rx, y: y0 + ry),
                   controlPoint2: CGPoint(x: rx, y: y0 + k * ry))
        dome.close()
        if let g = NSGradient(colors: [steel, .white, steelDark],
                              atLocations: [0.0, 0.4, 1.0], colorSpace: .sRGB) {
            g.draw(in: dome, angle: 0)
        }

        // Lo pintado en la cupula gira con ella: cada pieza tiene un azimut fijo
        // y se ve segun hacia donde mira la cabeza. `facing` <= 0 es la espalda.
        func spot(_ azimuth: Double, _ h: Double) -> (p: CGPoint, facing: Double) {
            let a = azimuth + pose.yaw
            let ring = (1 - h * h).squareRoot()
            return (CGPoint(x: CGFloat(sin(a) * ring) * rx, y: y0 + CGFloat(h) * ry), cos(a))
        }

        NSGraphicsContext.saveGraphicsState()
        dome.addClip()

        steelDark.withAlphaComponent(0.55).setFill()
        NSBezierPath(rect: CGRect(x: -rx, y: y0 + ry * 0.82, width: rx * 2, height: ry)).fill()

        func stripe(_ h: Double, from: Double, to: Double, width: CGFloat) {
            let path = NSBezierPath()
            var drawing = false
            for i in 0...16 {
                let s = spot(from + (to - from) * Double(i) / 16, h)
                if s.facing > 0 {
                    if drawing { path.line(to: s.p) } else { path.move(to: s.p) }
                    drawing = true
                } else {
                    drawing = false
                }
            }
            path.lineWidth = width
            accent.withAlphaComponent(0.85).setStroke()
            path.stroke()
        }
        // La franja alta se corta donde va el lente; la baja rodea la cupula.
        stripe(0.70, from: -1.3, to: -0.62, width: 1.6)
        stripe(0.70, from: 0.22, to: 1.3, width: 1.6)
        stripe(0.10, from: -1.5, to: 1.5, width: 1.2)

        let eye = spot(-0.22, 0.45)
        if eye.facing > 0.05 {
            ctx.saveGState()
            ctx.translateBy(x: eye.p.x, y: eye.p.y)
            ctx.scaleBy(x: CGFloat(eye.facing), y: 1)
            VectorInk.glowingLens(center: .zero, outer: rx * 0.34, inner: rx * 0.2,
                                  anim: anim, ctx: ctx)
            ctx.restoreGState()
        }

        // Lente pequeno: dos ojos desiguales leen como maquina, no como cara.
        let aux = spot(0.62, 0.30)
        if aux.facing > 0.05 {
            ctx.saveGState()
            ctx.translateBy(x: aux.p.x, y: aux.p.y)
            ctx.scaleBy(x: CGFloat(aux.facing), y: 1)
            let o = rx * 0.17, i = rx * 0.11
            steelDark.setFill()
            NSBezierPath(ovalIn: CGRect(x: -o, y: -o, width: o * 2, height: o * 2)).fill()
            ink.setFill()
            NSBezierPath(ovalIn: CGRect(x: -i, y: -i, width: i * 2, height: i * 2)).fill()
            NSColor.white.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: CGRect(x: -i * 0.6, y: i * 0.1, width: i * 0.6, height: i * 0.6)).fill()
            ctx.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()

        ink.withAlphaComponent(0.5).setStroke()
        dome.lineWidth = 1.2
        dome.stroke()
        VectorInk.moodWash(dome, anim: anim)

        // Antenas: una larga y una corta. Se quedan un poco atras del gesto de
        // la cabeza, que es lo que les da peso.
        let lag = -CGFloat(pose.tilt) * 3
            + (anim.mood == .working ? CGFloat(sin(anim.phase * 13)) * 0.8 : 0)
        for (azimuth, length) in [(0.45, rx * 0.75), (0.15, rx * 0.45)] {
            let base = spot(azimuth, 0.93).p
            let tip = CGPoint(x: base.x + lag, y: base.y + length)
            let stem = NSBezierPath()
            stem.move(to: base)
            stem.line(to: tip)
            stem.lineWidth = 1.2
            stem.lineCapStyle = .round
            steelDark.setStroke()
            stem.stroke()
            if length > rx * 0.5 {
                accent.setFill()
                NSBezierPath(ovalIn: CGRect(x: tip.x - 1.8, y: tip.y - 1.8, width: 3.6, height: 3.6)).fill()
            }
        }
    }
}
