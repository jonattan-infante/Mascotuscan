// Recorrer la pantalla: el controlador decide a donde quiere ir la mascota y
// mueve la ventana; como se mueve lo decide `Roamer` (Model/Roam.swift). Ver
// docs/adr/0013.

import AppKit

extension PetController {
    /// Se llama al activar una mascota. Si la anterior andaba lejos de su lugar,
    /// la nueva hereda ese lugar; si la nueva no se mueve, vuelve ahi de una.
    func setupRoam() {
        let home = roamer.map { CGFloat($0.home) } ?? anchor.x
        guard let spec = PetTheme.shared.pack?.roam else {
            roamer = nil
            petView.roamPhase = .resting
            if anchor.x != home {
                anchor.x = home
                layout()
            }
            return
        }
        roamer = Roamer(x: Double(anchor.x), home: Double(home), speed: spec.speed,
                        startDuration: petView.roamStartDuration())
    }

    /// Quieta si la vas a tocar o si te necesita: no se le puede hacer clic a
    /// una burbuja que se va. Quieta tambien mientras celebra que algo termino:
    /// ese gesto no se ve rodando. Sin trabajo, a su lugar.
    func roamGoal() -> Roamer.Goal {
        if hovering || !attentionSessions.isEmpty || currentBubble?.options.isEmpty == false {
            return .hold
        }
        if petView.mood == .done { return .hold }
        return activities.isEmpty ? .home : .roam
    }

    /// De borde a borde de la pantalla en la que esta, con el mismo margen que
    /// `clamp`: nunca se sale de la vista.
    func roamBounds() -> ClosedRange<Double> {
        let center = CGPoint(x: anchor.x + petBox.width / 2, y: anchor.y + petBox.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return Double(anchor.x)...Double(anchor.x) }
        let lo = Double(vf.minX + 4)
        return lo...max(lo, Double(vf.maxX - petBox.width - 4))
    }

    func stepRoam(_ dt: Double) {
        guard var r = roamer else { return }
        // Tras dormir la maquina el primer dt puede ser de minutos: sin tope, la
        // mascota apareceria de golpe en el otro extremo.
        r.step(min(dt, 0.1), goal: roamGoal(), bounds: roamBounds())
        roamer = r
        petView.roamPhase = r.phase
        petView.roamAge = r.phaseAge
        let x = CGFloat(r.x)
        if abs(x - anchor.x) > 0.01 {
            anchor.x = x
            layout()
        }
    }
}
