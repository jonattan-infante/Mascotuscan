// Recorrer la pantalla: hasta el borde, vuelta en espejo, y a casa al terminar.
// Es lo que el autor pidio, y cada regla aqui es una de esas decisiones. Ver
// docs/adr/0013.

import XCTest
@testable import MascoTuscanKit

final class RoamTests: XCTestCase {
    let bounds = 0.0...1000.0
    let dt = 1.0 / 30

    private func roamer(at x: Double = 500, start: Double = 1.0) -> Roamer {
        Roamer(x: x, speed: 100, startDuration: start)
    }

    /// Corre hasta que la condicion se cumpla o se acabe el tiempo.
    @discardableResult
    private func run(_ r: inout Roamer, goal: Roamer.Goal, seconds: Double,
                     until done: (Roamer) -> Bool = { _ in false }) -> Bool {
        var t = 0.0
        while t < seconds {
            r.step(dt, goal: goal, bounds: bounds)
            if done(r) { return true }
            t += dt
        }
        return false
    }

    func testArrancaHaciaLaDerechaYNoSeMueveMientrasGira() {
        var r = roamer()
        r.step(dt, goal: .roam, bounds: bounds)
        XCTAssertEqual(r.phase, .starting(direction: 1))
        run(&r, goal: .roam, seconds: 0.9)
        XCTAssertEqual(r.x, 500, "se movio antes de terminar de girar")
        run(&r, goal: .roam, seconds: 0.5)
        XCTAssertEqual(r.phase, .rolling(direction: 1))
        XCTAssertGreaterThan(r.x, 500)
    }

    func testLlegaAlBordeYDaLaVueltaEnEspejo() {
        var r = roamer()
        XCTAssertTrue(run(&r, goal: .roam, seconds: 20) { $0.phase == .stopping(direction: 1) })
        XCTAssertEqual(r.x, bounds.upperBound, "no llego al borde")
        XCTAssertTrue(run(&r, goal: .roam, seconds: 3) { $0.phase == .rolling(direction: -1) })
        run(&r, goal: .roam, seconds: 1)
        XCTAssertLessThan(r.x, bounds.upperBound)
    }

    /// Ida y vuelta: despues del borde derecho llega al izquierdo y vuelve a dar
    /// la vuelta, sin quedarse pegado a ninguno.
    func testVaDeBordeABorde() {
        var r = roamer()
        XCTAssertTrue(run(&r, goal: .roam, seconds: 40) { $0.phase == .stopping(direction: -1) })
        XCTAssertEqual(r.x, bounds.lowerBound)
        XCTAssertTrue(run(&r, goal: .roam, seconds: 3) { $0.phase == .rolling(direction: 1) })
    }

    func testAlTerminarRegresaASuLugar() {
        var r = roamer(at: 300)
        run(&r, goal: .roam, seconds: 8)
        XCTAssertNotEqual(r.x, 300)
        XCTAssertTrue(run(&r, goal: .home, seconds: 30) { $0.phase == .resting })
        XCTAssertEqual(r.x, 300, accuracy: 0.5)
        run(&r, goal: .home, seconds: 2)
        XCTAssertEqual(r.phase, .resting, "en casa tiene que quedarse quieta")
    }

    /// Si al terminar iba en sentido contrario a su casa, frena, da la vuelta y
    /// regresa: no retrocede de espaldas.
    func testParaVolverDaLaVueltaSiIbaAlOtroLado() {
        var r = roamer(at: 300)
        run(&r, goal: .roam, seconds: 4)
        XCTAssertEqual(r.phase, .rolling(direction: 1))
        r.step(dt, goal: .home, bounds: bounds)
        XCTAssertEqual(r.phase, .stopping(direction: 1))
        XCTAssertTrue(run(&r, goal: .home, seconds: 3) { $0.phase == .rolling(direction: -1) })
    }

    func testSeDetieneDondeEstaSiLaVasATocar() {
        var r = roamer()
        run(&r, goal: .roam, seconds: 3)
        let x = r.x
        run(&r, goal: .hold, seconds: 3)
        XCTAssertEqual(r.x, x, "se movio con el mouse encima")
        XCTAssertEqual(r.phase, .resting)
    }

    /// Al reanudar sigue hacia donde iba, no vuelve a empezar hacia la derecha.
    func testAlReanudarSigueHaciaDondeIba() {
        var r = roamer()
        run(&r, goal: .roam, seconds: 20) { $0.phase == .rolling(direction: -1) }
        // Lejos del borde: pegada a el, el borde decidiria la direccion y no la memoria.
        run(&r, goal: .roam, seconds: 2)
        XCTAssertLessThan(r.x, bounds.upperBound - 50)
        run(&r, goal: .hold, seconds: 3)
        XCTAssertTrue(run(&r, goal: .roam, seconds: 3) { $0.phase == .rolling(direction: -1) })
    }

    /// Frenar a medio giro arranca la frenada desde ese mismo cuadro: la cabeza
    /// no salta.
    func testFrenarAMedioGiroEmpiezaDondeIba() {
        var r = roamer(start: 1.0)
        run(&r, goal: .roam, seconds: 0.3)
        let girado = r.phaseAge
        r.step(dt, goal: .hold, bounds: bounds)
        XCTAssertEqual(r.phase, .stopping(direction: 1))
        XCTAssertEqual(r.phaseAge, 1.0 - girado - dt, accuracy: dt)
    }

    func testSinGiroDeArranqueAvanzaEnSeguida() {
        var r = roamer(start: 0)
        run(&r, goal: .roam, seconds: 0.2)
        XCTAssertGreaterThan(r.x, 500)
    }

    func testSiLaArrastrasEseEsSuNuevoLugar() {
        var r = roamer(at: 300)
        run(&r, goal: .roam, seconds: 5)
        r.place(at: 700)
        XCTAssertEqual(r.home, 700)
        XCTAssertEqual(r.phase, .resting)
        run(&r, goal: .roam, seconds: 5)
        XCTAssertTrue(run(&r, goal: .home, seconds: 30) { $0.phase == .resting })
        XCTAssertEqual(r.x, 700, accuracy: 0.5)
    }

    /// Si la pantalla cambio y su lugar quedo afuera, vuelve al punto mas
    /// cercano que si se ve.
    func testSuLugarFueraDeLaPantallaSeAjustaAlBorde() {
        var r = Roamer(x: 500, home: 5000, speed: 100, startDuration: 0.5)
        XCTAssertTrue(run(&r, goal: .home, seconds: 30) { $0.phase == .resting && $0.x != 500 })
        XCTAssertEqual(r.x, bounds.upperBound)
    }

    func testNuncaSeSaleDeLaPantalla() {
        var r = roamer(at: 10)
        let goals: [Roamer.Goal] = [.roam, .hold, .roam, .home, .roam]
        for (i, g) in goals.enumerated() {
            var t = 0.0
            while t < Double(7 + i * 3) {
                r.step(dt, goal: g, bounds: bounds)
                XCTAssertTrue(bounds.contains(r.x), "x=\(r.x) fuera de la pantalla")
                t += dt
            }
        }
    }

    /// El arranque es suave: el primer tramo avanza menos que a velocidad plena.
    func testArrancaSinSaltar() {
        var r = roamer(start: 0)
        r.step(dt, goal: .roam, bounds: bounds)
        r.step(dt, goal: .roam, bounds: bounds)
        XCTAssertEqual(r.phase, .rolling(direction: 1))
        let x0 = r.x
        r.step(dt, goal: .roam, bounds: bounds)
        XCTAssertLessThan(r.x - x0, 100 * dt)
        XCTAssertGreaterThan(r.x - x0, 0)
    }
}

/// Celebrar al terminar: la mascota se detiene y se ve el gesto del estado,
/// que ademas empieza desde su primer cuadro.
final class CelebrarAlTerminarTests: XCTestCase {
    func testFrenandoGanaLaImagenPropiaDelEstado() {
        XCTAssertTrue(Roamer.Phase.stopping(direction: 1).yieldsToStateSprite(true))
        XCTAssertTrue(Roamer.Phase.stopping(direction: -1).yieldsToStateSprite(true))
    }

    /// Sin imagen propia (solo `default`), se ve la frenada; y mientras arranca o
    /// rueda, manda el movimiento aunque el estado tenga imagen.
    func testElMovimientoManda() {
        XCTAssertFalse(Roamer.Phase.stopping(direction: 1).yieldsToStateSprite(false))
        XCTAssertFalse(Roamer.Phase.rolling(direction: 1).yieldsToStateSprite(true))
        XCTAssertFalse(Roamer.Phase.starting(direction: 1).yieldsToStateSprite(true))
    }

    func testAlTerminarUnTrabajoSeDetiene() {
        let pc = PetController()
        pc.config = PetConfig()
        pc.petView.mood = .done
        XCTAssertEqual(pc.roamGoal(), .hold)
        pc.petView.mood = .idle
        XCTAssertEqual(pc.roamGoal(), .home)
    }

    func testCadaImagenEmpiezaEnSuPrimerCuadro() {
        var clock = SpriteClock()
        XCTAssertEqual(clock.time(showing: "quieto", now: 100), 0)
        XCTAssertEqual(clock.time(showing: "quieto", now: 103), 3)
        XCTAssertEqual(clock.time(showing: "flamita", now: 104), 0, "no empezo desde el principio")
        XCTAssertEqual(clock.time(showing: "flamita", now: 105.5), 1.5)
        XCTAssertEqual(clock.time(showing: "quieto", now: 107), 0, "volver a una imagen la reinicia")
    }
}

/// Quieta solo si la vas a tocar. Medido el 2026-09-28 en `pet.log`: Claude Code
/// avisa `attention` 60 s despues de cada turno que queda sin respuesta, y esa
/// sesion sigue en `attention` hasta que le vuelvas a escribir. Si eso la
/// detenia, con varias sesiones abiertas no volvia a rodar.
final class QuietaSoloSiLaVasATocarTests: XCTestCase {
    func makeController() -> PetController {
        let pc = PetController()
        pc.config = PetConfig()
        pc.ingest(NormalizedEvent(source: "t", name: .sessionStart, sessionId: "trabaja", agent: "Claude"))
        return pc
    }

    func testUnAgenteEsperandoRespuestaNoLaDetiene() {
        let pc = makeController()
        pc.ingest(NormalizedEvent(source: "t", name: .notification, sessionId: "espera",
                                  agent: "Claude", reason: .generic))
        XCTAssertTrue(pc.attentionSessions.contains("espera"))
        XCTAssertEqual(pc.roamGoal(), .roam)
    }

    func testConElMouseSobreLaBurbujaSeDetiene() {
        let pc = makeController()
        pc.ingest(NormalizedEvent(source: "t", name: .notification, sessionId: "espera",
                                  agent: "Claude", reason: .generic))
        pc.bubbleHovered = true
        XCTAssertEqual(pc.roamGoal(), .hold)
        pc.bubbleHovered = false
        XCTAssertEqual(pc.roamGoal(), .roam)
    }

    /// Una burbuja que se esconde con el mouse encima no avisa que salio: ese
    /// dato viejo no puede dejar quieta a la mascota con la burbuja siguiente.
    func testElMouseViejoNoFrenaLaBurbujaSiguiente() {
        let pc = makeController()
        pc.ingest(NormalizedEvent(source: "t", name: .notification, sessionId: "espera",
                                  agent: "Claude", reason: .generic))
        pc.bubbleHovered = true
        pc.hideBubble()
        pc.ingest(NormalizedEvent(source: "t", name: .notification, sessionId: "otra",
                                  agent: "Claude", reason: .generic))
        XCTAssertNotNil(pc.currentBubble)
        XCTAssertEqual(pc.roamGoal(), .roam)
    }

    func testConElMouseSobreLaMascotaSeDetiene() {
        let pc = makeController()
        pc.hovering = true
        XCTAssertEqual(pc.roamGoal(), .hold)
    }
}
