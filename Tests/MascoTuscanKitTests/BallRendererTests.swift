// El droide esferico se define por dos movimientos: quieto y rodando. Si se
// mezclan (el cuerpo que se mece en reposo, la cabeza que gira al rodar), deja
// de leerse cual es cual. Aqui se fija el movimiento; como se ve, en `make render`.

import XCTest
@testable import MascoTuscanKit

final class BallRendererTests: XCTestCase {
    private func pose(_ mood: Mood, _ t: Double) -> BallRenderer.Pose {
        BallRenderer.pose(for: PetAnimation(mood: mood, phase: t, age: t, blinking: false))
    }

    func testQuietoElCuerpoNoSeMueve() {
        for mood in [Mood.idle, .info] {
            for t in stride(from: 0.0, through: 20, by: 0.37) {
                let p = pose(mood, t)
                XCTAssertEqual(p.roll, 0, "\(mood.rawValue) rueda en t=\(t)")
                XCTAssertEqual(p.rock, 0, "\(mood.rawValue) se mece en t=\(t)")
                XCTAssertEqual(p.blurSamples, 1)
            }
        }
    }

    /// La cabeza gira hacia los dos lados, sin pasar del limite, y se detiene:
    /// sin pausas seria un pendulo.
    func testQuietoLaCabezaGiraUnPocoConPausas() {
        let yaws = stride(from: 0.0, to: 8, by: 0.05).map { pose(.idle, $0).yaw }
        XCTAssertLessThanOrEqual(yaws.map(abs).max() ?? 0, BallRenderer.idleYawLimit)
        XCTAssertGreaterThan(yaws.max() ?? 0, 0.3, "no mira a la derecha")
        XCTAssertLessThan(yaws.min() ?? 0, -0.2, "no mira a la izquierda")

        XCTAssertEqual(BallRenderer.lookAround(0.5), BallRenderer.lookAround(2.0))
        XCTAssertEqual(BallRenderer.lookAround(3.0), BallRenderer.lookAround(3.8))
    }

    func testMirarAlrededorEsContinuoYSeRepite() {
        var prev = BallRenderer.lookAround(0)
        for t in stride(from: 0.01, through: 16, by: 0.01) {
            let y = BallRenderer.lookAround(t)
            XCTAssertLessThan(abs(y - prev), 0.02, "salto de la cabeza en t=\(t)")
            prev = y
        }
        XCTAssertEqual(BallRenderer.lookAround(1.3), BallRenderer.lookAround(9.3), accuracy: 1e-9)
    }

    func testRodandoElCuerpoAvanzaSiempreYSeBarre() {
        var prev = pose(.working, 0).roll
        for t in stride(from: 0.04, through: 10, by: 0.04) {
            let p = pose(.working, t)
            XCTAssertGreaterThan(p.roll, prev, "el cuerpo retrocede en t=\(t)")
            XCTAssertGreaterThan(p.blurSamples, 1)
            prev = p.roll
        }
    }

    /// Rodando la cabeza mira al frente: si girara como en reposo, las dos
    /// animaciones se confundirian.
    func testRodandoLaCabezaMiraAlFrente() {
        for t in stride(from: 0.0, through: 10, by: 0.1) {
            XCTAssertLessThan(abs(pose(.working, t).yaw), 0.1)
        }
    }

    /// Era el defecto del dibujo anterior: los aros de atras se pintaban como
    /// si estuvieran adelante y aparecian y desaparecian al rodar.
    func testUnPanelDeAtrasNoSeDibuja() {
        let atras = BallRenderer.Vec(x: 0, y: 0, z: -1)
        XCTAssertNil(BallRenderer.outline(of: atras, radius: BallRenderer.panelRadius,
                                          roll: 0, rock: 0))
        let adelante = BallRenderer.Vec(x: 0, y: 0, z: 1)
        XCTAssertNotNil(BallRenderer.outline(of: adelante, radius: BallRenderer.panelRadius,
                                             roll: 0, rock: 0))
    }

    func testNingunPanelSeSaleDeLaEsfera() {
        for roll in stride(from: 0.0, to: 2 * .pi, by: 0.13) {
            for rock in [-0.3, 0, 0.3] {
                for c in BallRenderer.panels {
                    guard let pts = BallRenderer.outline(of: c, radius: BallRenderer.panelRadius,
                                                         roll: roll, rock: rock) else { continue }
                    for p in pts {
                        XCTAssertLessThanOrEqual(p.x * p.x + p.y * p.y, 1 + 1e-9)
                    }
                }
            }
        }
    }

    /// Los paneles no se tocan: si se solaparan, el cuerpo se veria como una
    /// mancha al rodar.
    func testLosPanelesNoSeSolapan() {
        let ps = BallRenderer.panels
        for i in ps.indices {
            for j in ps.indices where j > i {
                let dot = ps[i].x * ps[j].x + ps[i].y * ps[j].y + ps[i].z * ps[j].z
                XCTAssertGreaterThan(acos(max(-1, min(1, dot))), 2 * BallRenderer.panelRadius)
            }
        }
    }

    /// Una bola se apoya en el piso: no flota en reposo, pero salta al terminar.
    func testLaBolaNoFlotaPeroSalta() {
        XCTAssertFalse(BallRenderer.renderer.floats)
        XCTAssertTrue(DroidRenderer.renderer.floats)
        for mood in Mood.allCases where mood != .done {
            XCTAssertEqual(PetAnimation(mood: mood, phase: 1.1, age: 0.2, blinking: false).hop, 0)
        }
        XCTAssertGreaterThan(PetAnimation(mood: .done, phase: 0, age: 0.2, blinking: false).hop, 0)
    }
}
