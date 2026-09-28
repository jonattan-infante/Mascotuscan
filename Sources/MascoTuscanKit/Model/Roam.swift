// Recorrer la pantalla: mientras hay trabajo, la mascota rueda hasta el borde,
// da la vuelta en espejo y sigue; al terminar vuelve a su lugar. Solo si su
// paquete lo declara (bloque `roam` de pet.json). Ver docs/adr/0011 y
// docs/reference/pet-pack.md.
//
// Es un modelo puro: recibe el tiempo, a donde quiere ir y los bordes, y dice
// donde esta y en que fase. La ventana y el dibujo solo lo leen, asi el
// comportamiento se prueba sin abrir una pantalla.

import Foundation

/// Lo que un paquete declara para moverse. Las rutas ya estan resueltas y
/// validadas por `PetPack.load`.
public struct RoamSpec: Equatable {
    /// Se reproduce una vez antes de avanzar, sin moverse (por ejemplo, girar la
    /// cabeza hacia donde va). Al revés, es la frenada. Opcional.
    public let start: URL?
    /// En bucle mientras avanza, dibujado mirando a la derecha: hacia la
    /// izquierda el programa lo espeja.
    public let loop: URL
    /// Puntos por segundo.
    public let speed: Double

    /// Mas rapido cruzaria una pantalla en un par de segundos: ya no se lee
    /// como alguien que pasea sino como un parpadeo.
    public static let speedRange: ClosedRange<Double> = 10...400
}

public struct Roamer: Equatable {
    /// Lo que el controlador quiere en este momento.
    public enum Goal: Equatable {
        /// Hay trabajo: recorrer la pantalla de borde a borde.
        case roam
        /// Quedarse donde esta: alguien le va a hacer clic o lo necesita.
        case hold
        /// No hay trabajo: volver a su lugar y quedarse ahi.
        case home
    }

    public enum Phase: Equatable {
        case resting
        /// Reproduce `start` hacia adelante, sin moverse.
        case starting(direction: Int)
        case rolling(direction: Int)
        /// Reproduce `start` al revés, sin moverse.
        case stopping(direction: Int)
    }

    /// Posicion horizontal del ancla de la mascota, en puntos de pantalla.
    public private(set) var x: Double
    /// Su lugar: a donde vuelve al terminar. Solo cambia si la arrastras.
    public private(set) var home: Double
    public private(set) var phase: Phase = .resting
    /// Segundos dentro de la fase actual. El dibujo lo usa para saber que
    /// cuadro de `start` o de `loop` mostrar.
    public private(set) var phaseAge: Double = 0

    public let speed: Double
    /// Lo que dura `start`. 0 si el paquete no lo trae: arranca y frena en seco.
    public let startDuration: Double
    /// Hacia donde iba la ultima vez: si se detuvo a medio camino, sigue igual.
    private var lastDirection = 1

    /// Llegar a velocidad plena de golpe se ve como un salto de la ventana.
    static let rampSeconds = 0.4

    public init(x: Double, home: Double? = nil, speed: Double, startDuration: Double) {
        self.x = x
        self.home = home ?? x
        self.speed = speed
        self.startDuration = max(0, startDuration)
    }

    /// La mascota se movio sin rodar: la arrastraste. Ese es su nuevo lugar.
    public mutating func place(at x: Double) {
        self.x = x
        home = x
        enter(.resting)
    }

    public mutating func step(_ dt: Double, goal: Goal, bounds: ClosedRange<Double>) {
        phaseAge += dt
        x = x.clamped(to: bounds)
        let target = home.clamped(to: bounds)

        switch phase {
        case .resting:
            if let d = departure(goal: goal, target: target, bounds: bounds) {
                enter(.starting(direction: d))
            }

        case .starting(let d):
            if keepsGoing(d, goal: goal, target: target) == false {
                // Frenar desde el cuadro en que iba, no desde el final del giro.
                let done = min(phaseAge, startDuration)
                enter(.stopping(direction: d))
                phaseAge = startDuration - done
            } else if phaseAge >= startDuration {
                enter(.rolling(direction: d))
            }

        case .rolling(let d):
            guard keepsGoing(d, goal: goal, target: target) else {
                enter(.stopping(direction: d))
                return
            }
            let ramp = min(1, phaseAge / Self.rampSeconds)
            x += Double(d) * speed * ramp * dt
            switch goal {
            case .home:
                if (d > 0 && x >= target) || (d < 0 && x <= target) {
                    x = target
                    enter(.stopping(direction: d))
                }
            default:
                // Solo cuenta el borde hacia el que va: recien salido del otro,
                // todavia esta pegado a el.
                if (d > 0 && x >= bounds.upperBound) || (d < 0 && x <= bounds.lowerBound) {
                    x = x.clamped(to: bounds)
                    enter(.stopping(direction: d))
                }
            }

        case .stopping:
            guard phaseAge >= startDuration else { return }
            // Encadenar sin pasar por reposo: un solo cuadro quieto entre frenar
            // y volver a arrancar se ve como un parpadeo.
            if let d = departure(goal: goal, target: target, bounds: bounds) {
                enter(.starting(direction: d))
            } else {
                enter(.resting)
            }
        }
    }

    /// Hacia donde arrancar desde quieto, o nil si no hay que moverse.
    private mutating func departure(goal: Goal, target: Double,
                                    bounds: ClosedRange<Double>) -> Int? {
        switch goal {
        case .hold:
            return nil
        case .home:
            guard abs(target - x) > 0.5 else {
                x = target
                return nil
            }
            return target > x ? 1 : -1
        case .roam:
            if x >= bounds.upperBound - 0.5 { return -1 }
            if x <= bounds.lowerBound + 0.5 { return 1 }
            return lastDirection
        }
    }

    /// Si la direccion en curso sigue sirviendo para lo que se quiere ahora.
    private func keepsGoing(_ d: Int, goal: Goal, target: Double) -> Bool {
        switch goal {
        case .hold: return false
        case .roam: return true
        case .home: return abs(target - x) > 0.5 && (target > x ? 1 : -1) == d
        }
    }

    private mutating func enter(_ p: Phase) {
        guard p != phase else { return }
        phase = p
        phaseAge = 0
        switch p {
        case .starting(let d), .rolling(let d): lastDirection = d
        default: break
        }
    }
}

extension Roamer.Phase {
    /// Frenando, un estado con imagen propia gana sobre la frenada: al terminar
    /// un trabajo se ve el gesto de ese estado en cuanto se detiene, no la
    /// cabeza volviendo al frente. Arrancando o rodando, manda el movimiento.
    public func yieldsToStateSprite(_ stateHasOwnSprite: Bool) -> Bool {
        guard stateHasOwnSprite, case .stopping = self else { return false }
        return true
    }
}

extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}
