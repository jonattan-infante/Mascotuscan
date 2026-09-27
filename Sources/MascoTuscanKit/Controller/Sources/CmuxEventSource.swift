// Fuente: stream de eventos de cmux (agentes, notificaciones, foco).

import Foundation

/// Envuelve `cmux events --reconnect`. Dueña de su propia reconexion y de su
/// deteccion de fallo (socket denegado, reinicios rapidos). El orquestador
/// solo recibe NormalizedEvent u onUnavailable: nunca sabe que hay un
/// subproceso ni un JSON crudo detras.
final class CmuxEventSource: EventSource {
    let id = "cmux"

    /// Costura para el dedup de `fetchNotification` sin acoplar la fuente a
    /// PetController. El controller la enchufa a `currentBubble?.mood`.
    var isShowingAttention: () -> Bool = { false }

    private var onEvent: ((NormalizedEvent) -> Void)?
    private var onUnavailable: ((String) -> Void)?
    private var process: Process?
    private var eventCount = 0
    private var fastExits = 0

    func start(onEvent: @escaping (NormalizedEvent) -> Void,
               onUnavailable: @escaping (String) -> Void) {
        self.onEvent = onEvent
        self.onUnavailable = onUnavailable
        killStaleStreams()
        launch()
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// Mata streams de instancias anteriores. Sin esto cada reinicio deja un
    /// `cmux events` huerfano leyendo el socket para siempre.
    private func killStaleStreams() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "cmux events --reconnect --no-heartbeat --no-ack --category agent"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func launch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmuxPath)
        p.arguments = ["events", "--reconnect", "--no-heartbeat", "--no-ack",
                       "--category", "agent", "--category", "notification",
                       "--category", "surface", "--category", "workspace"]
        let pipe = Pipe()
        p.standardOutput = pipe

        // El stderr del CLI es la unica pista cuando el socket rechaza la conexion.
        let errPipe = Pipe()
        p.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let d = handle.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            let msg = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !msg.isEmpty else { return }
            DispatchQueue.main.async { self?.noteStreamError(msg) }
        }

        let startedAt = Date()

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                guard !lineData.isEmpty else { continue }
                guard let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
                else {
                    plog("linea no parseable (\(lineData.count) bytes)")
                    continue
                }
                DispatchQueue.main.async {
                    self.eventCount += 1
                    if self.eventCount <= 25 {
                        plog("evento #\(self.eventCount): \(obj["name"] as? String ?? "?")")
                    }
                    if let ev = self.translate(obj) {
                        self.onEvent?(ev)
                    }
                }
            }
        }

        p.terminationHandler = { [weak self] proc in
            let lived = Date().timeIntervalSince(startedAt)
            DispatchQueue.main.async {
                self?.noteStreamExit(code: proc.terminationStatus, lived: lived)
            }
            // --reconnect cubre caidas del socket; esto cubre que muera el proceso entero.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.launch() }
        }

        do {
            try p.run()
            plog("stream de eventos conectado (pid \(p.processIdentifier))")
        } catch {
            plog("no pude iniciar cmux events: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.launch() }
            return
        }
        process = p
    }

    /// El CLI escribio en stderr. Si es un rechazo del socket hay que decirlo:
    /// callado, el asistente parece funcionar y no avisa de nada.
    private func noteStreamError(_ msg: String) {
        plog("error del stream: \(msg)")
        let denied = msg.contains("Broken pipe") || msg.lowercased().contains("permission")
            || msg.lowercased().contains("denied") || msg.contains("errno 32")
        guard denied else { return }
        onUnavailable?(Wording.plain("No me deja escuchar a cmux: rechaza el control externo. Revisa socketControlMode en cmux.json."))
    }

    /// Un stream que muere en menos de dos segundos, dos veces seguidas, no es
    /// una caida transitoria: es acceso denegado.
    private func noteStreamExit(code: Int32, lived: Double) {
        plog("stream terminado (código \(code)) tras \(String(format: "%.1f", lived)) s")
        if lived < 2 {
            fastExits += 1
        } else {
            fastExits = 0
        }
        guard fastExits >= 2 else { return }
        onUnavailable?(Wording.plain("El canal de eventos de cmux se me muere al arrancar. Revisa ~/.mascotuscan/pet.log."))
    }

    static func agentLabel(_ source: String?) -> String {
        switch (source ?? "").lowercased() {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "opencode": return "OpenCode"
        case "cursor": return "Cursor"
        case "amp": return "Amp"
        case "copilot": return "Copilot"
        case "": return "El agente"
        default: return (source ?? "").capitalized
        }
    }

    /// Puro y testeable: JSON crudo de `cmux events` -> NormalizedEvent, o nil
    /// si el nombre no se entiende. Ver docs/reference/cmux-events.md para el
    /// catalogo de payloads reales.
    func translate(_ e: [String: Any]) -> NormalizedEvent? {
        guard let name = e["name"] as? String else { return nil }
        let payload = e["payload"] as? [String: Any] ?? [:]

        // El generador de frases ES un Claude Code que lanzamos nosotros. Sin
        // este filtro el asistente se anunciaría a sí mismo en bucle.
        if let ppid = payload["_ppid"] as? Int, ppid == Int(getpid()) { return nil }

        let wsId = (payload["workspace_id"] as? String) ?? (e["workspace_id"] as? String)
        let session = (payload["session_id"] as? String) ?? "anon"
        let agent = Self.agentLabel(payload["_source"] as? String)

        switch name {
        case "agent.hook.SessionStart", "agent.hook.UserPromptSubmit":
            return NormalizedEvent(source: id,
                                   name: name.hasSuffix("SessionStart") ? .sessionStart : .userPromptSubmit,
                                   sessionId: session, workspaceId: wsId, agent: agent)

        case "agent.hook.PreToolUse":
            return NormalizedEvent(source: id, name: .preToolUse, sessionId: session,
                                   workspaceId: wsId, agent: agent,
                                   tool: payload["tool_name"] as? String)

        case "workspace.prompt.submitted":
            // El texto del prompt es lo unico que dice en QUE trabaja el agente.
            guard let preview = payload["message_preview"] as? String, !preview.isEmpty else { return nil }
            return NormalizedEvent(source: id, name: .workspaceTaskSubmitted,
                                   workspaceId: wsId, messagePreview: truncate(preview, 120))

        case "agent.hook.Stop", "agent.hook.SessionEnd":
            return NormalizedEvent(source: id,
                                   name: name.hasSuffix("Stop") ? .stop : .sessionEnd,
                                   sessionId: session, workspaceId: wsId, agent: agent)

        case "agent.hook.PermissionRequest":
            let tool = payload["tool_name"] as? String
            return NormalizedEvent(source: id, name: .notification, sessionId: session,
                                   workspaceId: wsId, agent: agent, tool: tool,
                                   requestId: payload["_opencode_request_id"] as? String,
                                   reason: tool == "AskUserQuestion" ? .question : .permission)

        case "agent.hook.AskUserQuestion":
            return NormalizedEvent(source: id, name: .notification, sessionId: session,
                                   workspaceId: wsId, agent: agent,
                                   requestId: payload["_opencode_request_id"] as? String,
                                   reason: .question)

        case "agent.hook.Notification":
            return NormalizedEvent(source: id, name: .notification, sessionId: session,
                                   workspaceId: wsId, agent: agent, reason: .generic)

        case "surface.focused", "surface.selected":
            let sid = (e["surface_id"] as? String) ?? (payload["surface_id"] as? String)
            return NormalizedEvent(source: id, name: .surfaceFocused, surfaceId: sid)

        case "workspace.selected":
            let selected = (payload["workspace_id"] as? String) ?? wsId
            return NormalizedEvent(source: id, name: .workspaceSelected, workspaceId: selected)

        case "notification.created":
            // El stream trae el texto redactado; el contenido real se pide por
            // rpc, asincrono: no hay NormalizedEvent sincrono que devolver aqui.
            if let nid = payload["notification_id"] as? String { fetchNotification(nid) }
            return nil

        default:
            return nil
        }
    }

    func fetchNotification(_ id: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self,
                  let obj = cmuxJSON(["rpc", "notification.list", "{}"]),
                  let list = obj["notifications"] as? [[String: Any]],
                  let n = list.first(where: { ($0["id"] as? String) == id })
            else { return }
            let title = (n["title"] as? String) ?? "cmux"
            let subtitle = (n["subtitle"] as? String) ?? ""
            let body = (n["body"] as? String) ?? ""
            let wsId = n["workspace_id"] as? String
            let wsTitle = (n["tab_title"] as? String) ?? ""

            // Los avisos de agente ya los cubre el stream de hooks: no duplicar.
            let known = ["claude code", "codex", "gemini", "opencode"]
            if known.contains(title.lowercased()) && self.isShowingAttention() { return }

            // Todo en una frase: "<titulo> — <subtitulo>: <cuerpo> (en <workspace>)".
            let head = subtitle.isEmpty ? title : "\(title) — \(subtitle)"
            var sentence = truncate(head, 60)
            if !body.isEmpty { sentence += ": " + truncate(body, 110) }
            sentence += Wording.at(wsTitle) + "."

            DispatchQueue.main.async {
                self.onEvent?(NormalizedEvent(source: self.id, name: .notificationCreated,
                                              workspaceId: wsId, messagePreview: sentence))
            }
        }
    }
}
