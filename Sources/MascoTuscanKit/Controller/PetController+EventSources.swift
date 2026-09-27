// Orquesta las fuentes de eventos: arranca, para, e ingiere lo que producen.
// Ninguna fuente decide mood ni compone texto — eso es todo de aqui. Ver
// docs/reference/event-source.md y docs/adr/0008.

import AppKit
import Foundation

extension PetController {
    // MARK: arranque y parada

    /// Que fuentes existen hoy. Agregar una nueva (OpenCode, wmux) es agregar
    /// una linea aca, sin tocar `ingest` salvo que traiga un evento nuevo.
    func makeEventSources() -> [EventSource] {
        let cmux = CmuxEventSource()
        cmux.isShowingAttention = { [weak self] in self?.currentBubble?.mood == .attention }
        return [ShellHookEventSource(), cmux]
    }

    func startEventSources() {
        startEventSources(makeEventSources())
    }

    /// Separado de `startEventSources()` para poder inyectar fuentes falsas
    /// desde los tests sin lanzar ningun proceso real.
    func startEventSources(_ list: [EventSource]) {
        sources = list
        guard !sources.isEmpty else {
            show(Bubble(mood: .error,
                        text: Wording.plain("No tengo ninguna fuente de eventos activa."),
                        workspaceId: nil, sticky: true))
            return
        }
        for s in sources {
            s.start(
                onEvent: { [weak self] ev in
                    DispatchQueue.main.async { self?.ingest(ev) }
                },
                onUnavailable: { [weak self] msg in
                    DispatchQueue.main.async { self?.noteSourceUnavailable(s.id, msg) }
                })
        }
    }

    /// Cierre ordenado: launchd manda SIGTERM y las fuentes deben morir con nosotros.
    public func shutdown() {
        for s in sources { s.stop() }
        try? fm.removeItem(at: pidURL)
    }

    /// Una fuente que no puede operar se avisa una sola vez, sin importar
    /// cuantas veces vuelva a fallar (generaliza el `warnedAboutSocket` de antes).
    func noteSourceUnavailable(_ id: String, _ msg: String) {
        guard !warnedSources.contains(id) else { return }
        warnedSources.insert(id)
        show(Bubble(mood: .error, text: msg, workspaceId: nil, sticky: true))
    }

    // MARK: ingesta — el unico lugar que decide mood y compone texto

    func ingest(_ e: NormalizedEvent) {
        switch e.name {
        case .sessionStart, .userPromptSubmit:
            touchActivity(e.sessionId ?? "anon", agent: e.agent ?? "El agente",
                         wsId: e.workspaceId, tool: nil)
            if let s = e.sessionId { attentionSessions.remove(s) }
            refreshRestingMood()

        case .preToolUse:
            touchActivity(e.sessionId ?? "anon", agent: e.agent ?? "El agente",
                         wsId: e.workspaceId, tool: e.tool)
            if let s = e.sessionId { attentionSessions.remove(s) }
            refreshRestingMood()

        case .postToolUse, .subagentStop:
            // cmux no las emite hoy (ver docs/reference/cmux-events.md); quedan
            // reservadas para fuentes de hooks directos (OpenCode, Windows).
            break

        case .workspaceTaskSubmitted:
            if let ws = e.workspaceId, let preview = e.messagePreview {
                workspaceTasks[ws] = preview
            }

        case .stop, .sessionEnd:
            guard let session = e.sessionId else { return }
            let wasRunning = activities.removeValue(forKey: session) != nil
            attentionSessions.remove(session)
            refreshRestingMood()
            guard wasRunning else { return }
            // Evita dos avisos por la misma sesion si llegan Stop y SessionEnd juntos.
            if let last = lastDoneAt[session], Date().timeIntervalSince(last) < 3 { return }
            lastDoneAt[session] = Date()
            let agent = e.agent ?? "El agente"
            show(Bubble(mood: .done,
                        text: Voice.shared.phrase("agentDone", [
                            "agent": agent, "where": Wording.at(workspaceLabel(e.workspaceId)),
                        ]) ?? Wording.plain("\(agent) terminó su turno\(Wording.at(workspaceLabel(e.workspaceId)))."),
                        workspaceId: e.workspaceId, sticky: false))

        case .notification:
            guard let session = e.sessionId else { return }
            attentionSessions.insert(session)
            refreshRestingMood()
            // Cada hook llega dos veces (phase received y completed).
            if let last = lastAttentionAt[session], Date().timeIntervalSince(last) < 3 { return }
            lastAttentionAt[session] = Date()
            let agent = e.agent ?? "El agente"
            let ws = Wording.at(workspaceLabel(e.workspaceId))
            // {what} es un sustantivo: las plantillas lo enchufan tras
            // "necesita ayuda con" o "está atascado en". El respaldo cambia
            // segun el motivo porque "una decisión tuya" no es "un permiso".
            let what: String
            let fallback: String
            switch e.reason {
            case .question:
                what = "una pregunta"
                fallback = "\(agent) necesita \(what)\(ws)."
            case .permission:
                what = "un permiso" + (e.tool.map { " para usar \($0)" } ?? "")
                fallback = "\(agent) necesita \(what)\(ws)."
            case .generic:
                what = "una decisión tuya"
                fallback = "\(agent) dejó de trabajar\(ws)."
            }
            show(Bubble(mood: .attention,
                        text: Voice.shared.phrase("attention", [
                            "agent": agent, "what": what, "where": ws,
                        ]) ?? Wording.plain(fallback),
                        workspaceId: e.workspaceId, sticky: true))

            // Solo permiso/pregunta se pueden responder; una notificacion
            // generica no tiene con que RPC contestarse.
            if let rid = e.requestId, e.reason == .permission || e.reason == .question {
                pendingRequests[rid] = PendingRequest(requestId: rid,
                                                      kind: e.reason == .permission ? .permission : .question,
                                                      sessionId: session, workspaceId: e.workspaceId,
                                                      tool: e.tool)
                // El contenido real llega aparte (feed.list, sin redactar): la
                // burbuja de arriba ya avisó con el texto generico: si esto
                // tarda o falla, el usuario no se queda sin nada.
                fetchPendingContent(rid) { [weak self] content in
                    guard let self = self, let content = content, self.pendingRequests[rid] != nil else { return }
                    self.showPendingRequest(rid, content: content, agent: agent, ws: ws)
                }
            }

        case .shellCommand:
            if !config.notifyWhileWatching && userIsWatching(e.surfaceId) {
                plog("suprimido (mirando el pane): \(e.command ?? "")")
                return
            }
            let status = e.exitCode ?? 0
            let seconds = e.seconds ?? 0
            let command = truncate(e.command ?? "", 56)
            let ws = Wording.at(workspaceLabel(e.workspaceId))
            if status != 0 {
                show(Bubble(mood: .error,
                            text: Voice.shared.phrase("commandError", [
                                "cmd": command, "code": "\(status)", "where": ws,
                            ]) ?? Wording.plain("\(command) falló con código \(status)\(ws)."),
                            workspaceId: e.workspaceId, sticky: false))
            } else {
                show(Bubble(mood: .done,
                            text: Voice.shared.phrase("commandDone", [
                                "cmd": command, "time": humanDuration(seconds), "where": ws,
                            ]) ?? Wording.plain("\(command) terminó en \(humanDuration(seconds))\(ws)."),
                            workspaceId: e.workspaceId, sticky: false))
            }

        case .surfaceFocused:
            focusedSurface = e.surfaceId

        case .workspaceSelected:
            selectedWorkspace = e.workspaceId

        case .notificationCreated:
            show(Bubble(mood: .info, text: Wording.plain(e.messagePreview ?? ""),
                        workspaceId: e.workspaceId, sticky: false))
        }
    }

    // MARK: actividad de agentes

    /// Registra o refresca lo que esta haciendo un agente. El turno arranca en
    /// la primera senal y conserva su hora de inicio en las siguientes.
    func touchActivity(_ session: String, agent: String, wsId: String?, tool: String?) {
        if var a = activities[session] {
            if let t = tool {
                a.currentTool = t
                a.toolCount += 1
            }
            if a.workspaceId == nil { a.workspaceId = wsId }
            a.lastSeen = Date()
            activities[session] = a
        } else {
            var a = AgentActivity(agent: agent, workspaceId: wsId, startedAt: Date(),
                                  lastSeen: Date(), currentTool: tool)
            if tool != nil { a.toolCount = 1 }
            activities[session] = a
        }
    }

    /// Un Stop puede perderse (agente matado, cmux reiniciado, hook fallido). Sin
    /// esta barrida el panel acumula fantasmas que nunca se van.
    func sweepStaleActivities() {
        let cutoff = Date().addingTimeInterval(-600)
        let dead = activities.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        guard !dead.isEmpty else { return }
        for k in dead {
            activities.removeValue(forKey: k)
            attentionSessions.remove(k)
        }
        plog("barrida: \(dead.count) sesión(es) sin señal por 10 min")
        refreshRestingMood()
    }

    /// Un permiso/pregunta sin responder deja de ofrecerse pasado un margen:
    /// cmux los expira solo (~2 min observado, sin número garantizado por
    /// verificar — docs/reference/agent-reply.md), y un botón que ya no sirve
    /// es peor que no mostrarlo.
    func sweepExpiredRequests() {
        let cutoff = Date().addingTimeInterval(-90)
        let dead = pendingRequests.filter { $0.value.createdAt < cutoff }.map { $0.key }
        for k in dead { pendingRequests.removeValue(forKey: k) }
    }

    /// Las lineas del panel de estado. Vacio si no hay nada corriendo.
    func rosterLines() -> [(String, NSColor?)] {
        let live = activities.values.sorted { $0.startedAt < $1.startedAt }
        guard !live.isEmpty else { return [] }

        let accent = Mood.working.accent
        var out: [(String, NSColor?)] = []
        out.append((live.count == 1 ? "1 unidad trabajando" : "\(live.count) unidades trabajando", accent))

        for a in live {
            out.append(("", nil))
            let ws = workspaceLabel(a.workspaceId)
            out.append(("\(a.agent)\(ws.isEmpty ? "" : " · \(ws)") · \(a.elapsed)", accent))
            out.append(("  \(a.doing)\(a.toolCount > 0 ? " · \(a.toolCount) pasos" : "")", nil))
            if let ws = a.workspaceId, let task = workspaceTasks[ws] {
                out.append(("  \u{201C}\(truncate(task, 96))\u{201D}", nil))
            }
        }
        return out
    }
}
