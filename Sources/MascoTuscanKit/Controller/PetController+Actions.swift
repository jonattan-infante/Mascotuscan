// Acciones del usuario: click, menu y sus comandos.

import AppKit
import Foundation

/// Los modos que entiende `feed.permission.reply`, verificados a mano contra
/// el propio error de validacion del RPC (2026-09-17):
/// `cmux rpc feed.permission.reply '{}'` -> "requires mode ∈ once|always|all|bypass|deny".
/// Ver docs/reference/agent-reply.md.
enum PermissionReplyMode: String {
    case once, always, all, bypass, deny
}

/// Una opcion de `question_options`, tal como la sirve `feed.list`.
struct QuestionOption: Equatable {
    var id: String
    var label: String
    var description: String
}

/// El contenido real de un permiso o pregunta pendiente. Sale de `feed.list`,
/// nunca del stream de hooks (que sigue redactado — regla 11 de CLAUDE.md
/// sigue aplicando a ese canal). No se persiste ni se loguea.
enum PendingRequestContent: Equatable {
    case permission(tool: String, toolInput: String)
    case question(options: [QuestionOption])
}

extension PetController {
    // MARK: acciones

    func jumpToLastAlert() {
        let ws = currentBubble?.workspaceId ?? lastAlertWorkspace
        hideBubble()
        attentionSessions.removeAll()
        refreshRestingMood()
        guard let ws = ws else { activateCmux(); return }
        cmuxFire(["select-workspace", "--workspace", ws])
        activateCmux()
    }

    func activateCmux() {
        let url = URL(fileURLWithPath: "/Applications/cmux.app")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }

    func showMenu(_ event: NSEvent) {
        let menu = NSMenu()

        let quiet = NSMenuItem(title: config.quiet ? "Reactivar avisos" : "Silenciar avisos",
                               action: #selector(toggleQuiet), keyEquivalent: "")
        quiet.target = self
        menu.addItem(quiet)

        let ports = NSMenuItem(title: config.watchPorts ? "Dejar de vigilar puertos" : "Vigilar puertos",
                               action: #selector(togglePorts), keyEquivalent: "")
        ports.target = self
        menu.addItem(ports)

        menu.addItem(.separator())

        let jump = NSMenuItem(title: "Ir al último aviso", action: #selector(menuJump), keyEquivalent: "")
        jump.target = self
        jump.isEnabled = lastAlertWorkspace != nil
        menu.addItem(jump)

        let reset = NSMenuItem(title: "Reiniciar posición", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        // Cambiar de mascota sin salir a la terminal: es la accion central del
        // producto ahora que hay un marketplace.
        let installed = PetLibrary.installed()
        let activeID = PetTheme.shared.pack?.id
        if installed.count > 1 {
            let switcher = NSMenuItem(title: "Cambiar de mascota", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for p in installed {
                let item = NSMenuItem(title: "\(p.name)  (\(p.id))",
                                      action: #selector(switchPet(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.id
                item.state = p.id == activeID ? .on : .off
                sub.addItem(item)
            }
            switcher.submenu = sub
            menu.addItem(switcher)
        }

        let voice = NSMenuItem(title: "Reescribir sus frases", action: #selector(regenerateVoice),
                               keyEquivalent: "")
        voice.target = self
        menu.addItem(voice)

        let reload = NSMenuItem(title: "Recargar la mascota", action: #selector(reloadPet),
                                keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let openFolder = NSMenuItem(title: "Abrir su carpeta",
                                    action: #selector(openPetFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        if let v = availableUpdate {
            let upd = NSMenuItem(title: "Actualizar a v\(v)", action: #selector(runUpdate),
                                 keyEquivalent: "")
            upd.target = self
            menu.addItem(upd)
        }

        let petLine = NSMenuItem(title: PetTheme.shared.pack.map { "\($0.name) v\($0.version)" }
                                    ?? "sin mascota instalada",
                                 action: nil, keyEquivalent: "")
        petLine.isEnabled = false
        menu.addItem(petLine)

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let versionLine = NSMenuItem(title: "mascotuscan v\(mascoTuscanVersion)", action: nil, keyEquivalent: "")
        versionLine.isEnabled = false
        menu.addItem(versionLine)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: petView)
    }

    func statusLine() -> String {
        let live = activities.values.sorted { $0.startedAt < $1.startedAt }
        if live.isEmpty { return "Sin agentes activos" }
        return live.map { a in
            let ws = workspaceLabel(a.workspaceId)
            return "\(a.agent)\(ws.isEmpty ? "" : " · \(ws)") · \(a.doing) · \(a.elapsed)"
        }.joined(separator: "   |   ")
    }

    @objc func toggleQuiet() {
        config.quiet.toggle()
        config.save()
        if config.quiet { hideBubble() }
    }

    @objc func togglePorts() {
        config.watchPorts.toggle()
        config.save()
    }

    @objc func menuJump() { jumpToLastAlert() }

    /// Relee el paquete de la mascota activa desde el disco: sirve mientras
    /// alguien esta creando la suya y quiere ver los cambios sin reiniciar.
    @objc func reloadPet() {
        activateConfiguredPet()
        layout()
        show(Bubble(mood: .info,
                    text: Voice.shared.phrase("greeting", [:])
                        ?? "\(PetTheme.shared.name) recargada.",
                    workspaceId: nil, sticky: false))
    }

    /// Cambia de mascota en caliente, sin reiniciar el proceso.
    @objc func switchPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        config.activePet = id
        config.save()
        activateConfiguredPet()
        layout()
        show(Bubble(mood: .info,
                    text: Voice.shared.phrase("greeting", [:])
                        ?? "Ahora soy \(PetTheme.shared.name).",
                    workspaceId: nil, sticky: false))
    }

    @objc func regenerateVoice() {
        show(Bubble(mood: .working,
                    text: "Escribiendo frases nuevas con Claude Code. Tarda como un minuto.",
                    workspaceId: nil, sticky: false))
        Voice.shared.regenerate("me lo pediste") { [weak self] ok, detail in
            guard let self = self else { return }
            self.show(Bubble(mood: ok ? .done : .error,
                             text: ok
                                ? (Voice.shared.phrase("greeting", [:]) ?? "Frases nuevas cargadas.")
                                : "No pude escribir frases nuevas: \(detail). Sigo con las de antes.",
                             workspaceId: nil, sticky: false))
        }
    }

    /// Abre la carpeta del paquete de la mascota activa, que es donde estan sus
    /// sprites y su personalidad.
    @objc func openPetFolder() {
        guard let pack = PetTheme.shared.pack else {
            NSWorkspace.shared.open(PetLibrary.petsDir)
            return
        }
        NSWorkspace.shared.open(pack.root)
    }

    @objc func resetPosition() {
        config.x = nil
        config.y = nil
        config.save()
        restoreAnchor()
        settle()
    }

    @objc func quitApp() {
        try? fm.removeItem(at: pidURL)
        NSApp.terminate(nil)
    }

    // MARK: responder un permiso o una pregunta — ver docs/reference/agent-reply.md

    /// Puro y testeable: de la lista de items de `feed.list`, el contenido del
    /// que matchea `requestId`, o nil si no esta (ya resuelto, expirado, o el
    /// feed no lo trae). `feed.list` devuelve TODOS los workstreams activos,
    /// no solo los de esta mascota: el llamador descarta el resto de
    /// inmediato, nunca los loguea ni los persiste.
    static func extractPendingContent(_ items: [[String: Any]], requestId: String) -> PendingRequestContent? {
        guard let item = items.first(where: { ($0["request_id"] as? String) == requestId }) else { return nil }
        switch item["kind"] as? String {
        case "permissionRequest":
            return .permission(tool: (item["title"] as? String) ?? "?",
                               toolInput: (item["tool_input"] as? String) ?? "")
        case "question":
            let raw = (item["question_options"] as? [[String: Any]]) ?? []
            let options = raw.compactMap { o -> QuestionOption? in
                guard let id = o["id"] as? String, let label = o["label"] as? String else { return nil }
                return QuestionOption(id: id, label: label, description: (o["description"] as? String) ?? "")
            }
            return .question(options: options)
        default:
            return nil
        }
    }

    /// Implementacion real de la costura `fetchPendingContent`: busca el
    /// contenido en el feed de cmux. Los tests la reemplazan por una version
    /// sincrona, sin lanzar ningun proceso.
    static func fetchPendingContentDefault(_ requestId: String, _ completion: @escaping (PendingRequestContent?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let items = (cmuxJSON(["rpc", "feed.list", "{}"])?["items"] as? [[String: Any]]) ?? []
            let content = PetController.extractPendingContent(items, requestId: requestId)
            DispatchQueue.main.async { completion(content) }
        }
    }

    /// Del `tool_input` crudo (JSON, sin redactar) de un permiso, el comando
    /// si la herramienta es Bash-like; si no se puede parsear o no trae
    /// `command`, devuelve el JSON tal cual (mejor mostrar algo que nada).
    static func summarizeToolInput(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return raw }
        return (obj["command"] as? String) ?? raw
    }

    /// Arma la burbuja con el contenido real y los botones. Nunca se muestra
    /// si el pendiente ya se resolvio o expiro mientras se pedia el contenido
    /// (lo llama el caller solo si `pendingRequests[requestId]` sigue ahi).
    func showPendingRequest(_ requestId: String, content: PendingRequestContent, agent: String, ws: String) {
        let text: String
        let options: [BubbleOption]
        switch content {
        case .permission(let tool, let toolInput):
            text = "\(agent) pide permiso para \(tool)\(ws):\n\(truncate(PetController.summarizeToolInput(toolInput), 140))"
            options = [BubbleOption(id: PermissionReplyMode.once.rawValue, label: "Sí"),
                       BubbleOption(id: PermissionReplyMode.deny.rawValue, label: "No")]
        case .question(let opts):
            guard !opts.isEmpty else { return }
            text = "\(agent) pregunta\(ws):"
            options = opts.map { BubbleOption(id: $0.id, label: $0.label) }
        }
        show(Bubble(mood: .attention, text: text, workspaceId: nil, sticky: true,
                   requestId: requestId, options: options))
    }

    /// Un clic en una de las opciones de la burbuja. `currentBubble.requestId`
    /// dice cual, `pendingRequests[..].kind` dice con que RPC responder.
    func respondToOption(_ optionId: String) {
        guard let rid = currentBubble?.requestId, let pending = pendingRequests[rid] else { return }
        hideBubble()
        let onResult: (Bool) -> Void = { [weak self] ok in
            guard let self = self, !ok else { return }
            // Nunca en silencio (regla 16): si ya expiro, se dice en pantalla.
            self.show(Bubble(mood: .error,
                             text: "No pude enviar la respuesta: puede que ya haya expirado. Respondé desde la terminal.",
                             workspaceId: nil, sticky: false))
        }
        switch pending.kind {
        case .permission:
            guard let mode = PermissionReplyMode(rawValue: optionId) else { return }
            replyPermission(requestId: rid, mode: mode, onResult: onResult)
        case .question:
            replyQuestion(requestId: rid, selections: [optionId], onResult: onResult)
        }
    }

    /// Responde un permiso. `mode` y `request_id` son los unicos campos que
    /// exige el RPC (verificado a mano). Un fallo nunca es silencioso (regla
    /// 16): quien llama decide que avisar con `onResult(false)`.
    func replyPermission(requestId: String, mode: PermissionReplyMode, onResult: @escaping (Bool) -> Void) {
        let params = cmuxParams(["request_id": requestId, "mode": mode.rawValue])
        DispatchQueue.global(qos: .utility).async {
            let ok = (cmuxJSON(["rpc", "feed.permission.reply", params])?["delivered"] as? Bool) ?? false
            DispatchQueue.main.async {
                if ok { self.pendingRequests.removeValue(forKey: requestId) }
                onResult(ok)
            }
        }
    }

    /// Responde una pregunta. `selections` es un array de ids de
    /// `question_options` incluso para una pregunta de una sola opcion
    /// (verificado a mano: `feed.question.reply` exige `selections: [string]`).
    func replyQuestion(requestId: String, selections: [String], onResult: @escaping (Bool) -> Void) {
        let params = cmuxParams(["request_id": requestId, "selections": selections])
        DispatchQueue.global(qos: .utility).async {
            let ok = (cmuxJSON(["rpc", "feed.question.reply", params])?["delivered"] as? Bool) ?? false
            DispatchQueue.main.async {
                if ok { self.pendingRequests.removeValue(forKey: requestId) }
                onResult(ok)
            }
        }
    }
}
