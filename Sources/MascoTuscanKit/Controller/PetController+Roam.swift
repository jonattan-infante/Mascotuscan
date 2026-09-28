// Recorrer la pantalla: el controlador decide a donde quiere ir la mascota y
// mueve la ventana; como se mueve lo decide `Roamer` (Model/Roam.swift). Ver
// docs/adr/0013.

import AppKit

extension PetController {
    /// Se llama al activar una mascota. Si la anterior andaba lejos de su lugar,
    /// la nueva hereda ese lugar; si la nueva no se mueve, vuelve ahi de una.
    func setupRoam() {
        let home = roamer.map { CGFloat($0.home) } ?? anchor.x
        let spec = PetTheme.shared.pack?.roam
        let loopLoads = spec.map { petView.loadsSprite($0.loop) } ?? false
        if let spec = spec, !loopLoads {
            // Sin la imagen en bucle se veria deslizandose por la pantalla: mejor
            // quieta, y dicho donde se ve.
            let file = spec.loop.lastPathComponent
            plog("roam: no pude abrir \(file); la mascota no se mueve")
            // Despues del saludo del arranque, que la taparia enseguida.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.show(Bubble(mood: .error,
                                  text: "No pude abrir \(file), la imagen para recorrer la pantalla. Me quedo en mi lugar.",
                                  workspaceId: nil, sticky: false))
            }
        }
        guard let spec = spec, loopLoads else {
            roamer = nil
            petView.roamPhase = .resting
            // Su lugar puede haber quedado en otra pantalla que ya no esta.
            let place = clamp(CGPoint(x: home, y: anchor.y))
            if place != anchor {
                anchor = place
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
