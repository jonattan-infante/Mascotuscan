// Avisos: mostrar, ocultar y narrar el avance.

import AppKit
import Foundation

extension PetController {
    // MARK: burbujas y estado

    /// Estado en reposo: atender gana sobre trabajar, trabajar gana sobre descansar.
    func refreshRestingMood() {
        guard transientMoodTimer == nil else { return }
        petView.mood = restingMood()
        petView.workingCount = activities.count
    }

    func restingMood() -> Mood {
        if !attentionSessions.isEmpty { return .attention }
        if !activities.isEmpty { return .working }
        return .idle
    }

    // MARK: narracion periodica

    /// Cada tanto cuenta en que van, sin esperar a que termine nada. Se calla si
    /// no hay nadie trabajando, si estas viendo una burbuja, o si el ultimo
    /// reporte decia exactamente lo mismo.
    func startNarration() {
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.maybeNarrate()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func maybeNarrate() {
        sweepStaleActivities()
        sweepExpiredRequests()
        guard config.narrateEverySeconds > 0, !config.quiet else { return }
        guard !activities.isEmpty, currentBubble == nil, !hovering else { return }
        if let last = lastNarrationAt,
           Date().timeIntervalSince(last) < config.narrateEverySeconds { return }

        let live = activities.values.sorted { $0.startedAt < $1.startedAt }
        guard let lead = live.first else { return }

        // La plantilla "working" del pack habla de UN agente. Con varios se
        // narra el que lleva más tiempo y se suma el resto con un sufijo neutro:
        // asi la frase sigue siendo la voz de la mascota y no una lista del
        // programa. Antes esto lo componia el programa y un gato acababa
        // diciendo "*whirr*".
        let ws = Wording.at(workspaceLabel(lead.workspaceId))
        let distintos = Set(live.map { "\($0.agent)|\(workspaceLabel($0.workspaceId))|\($0.doing)" })
        let base = Voice.shared.phrase("working", [
            "agent": lead.agent, "doing": lead.doing, "time": lead.elapsed, "where": ws,
        ]) ?? Wording.plain("\(lead.agent) lleva \(lead.elapsed)\(ws) \(lead.doing).")
        let text = base + Wording.andOthers(distintos.count - 1)

        // Si el parte es identico al anterior no aporta nada.
        guard text != lastNarrationText else { return }
        lastNarrationText = text
        lastNarrationAt = Date()
        show(Bubble(mood: .working, text: text,
                    workspaceId: live.first?.workspaceId, sticky: false))
    }

    func show(_ b: Bubble) {
        if let ws = b.workspaceId { lastAlertWorkspace = ws }

        transientMoodTimer?.invalidate()
        petView.mood = b.mood
        if !b.sticky {
            let hold: Double = b.mood == .error ? 4.5 : 3.0
            transientMoodTimer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.transientMoodTimer = nil
                self.petView.mood = self.restingMood()
            }
        } else {
            transientMoodTimer = nil
        }

        guard !config.quiet else {
            plog("silenciado: \(b.text)")
            return
        }

        plog("aviso: [\(b.mood.rawValue)] \(b.text)")
        currentBubble = b
        bubbleView.bubble = b
        layout()

        bubbleTimer?.invalidate()
        if !b.sticky {
            // El reloj arranca cuando termina de escribir, no antes: un mensaje
            // largo no puede desaparecer a medio teclear.
            let typing = Double(b.text.count) / BubbleView.charsPerSecond
            let ttl = typing + (b.mood == .error ? 9 : 6)
            bubbleTimer = Timer.scheduledTimer(withTimeInterval: ttl, repeats: false) { [weak self] _ in
                self?.hideBubble()
            }
        } else {
            // Incluso lo pegajoso caduca: un aviso de hace media hora ya no sirve.
            bubbleTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                self?.hideBubble()
            }
        }
    }

    func hideBubble() {
        bubbleTimer?.invalidate()
        bubbleTimer = nil
        currentBubble = nil
        bubbleView.bubble = nil
        layout()
    }

    func greet() {
        let nombre = PetTheme.shared.name
        show(Bubble(mood: .info,
                    text: Voice.shared.phrase("greeting", [:])
                        ?? Wording.plain("\(nombre) en línea, vigilando tus agentes, comandos y puertos."),
                    workspaceId: nil, sticky: false))
    }

}
