// translate() contra los payloads reales catalogados en
// docs/reference/cmux-events.md. Puro: no lanza ningun proceso de cmux.

import XCTest
@testable import MascoTuscanKit

final class CmuxEventSourceTests: XCTestCase {
    let src = CmuxEventSource()

    func envelope(_ name: String, payload: [String: Any] = [:], workspaceId: String? = nil) -> [String: Any] {
        var e: [String: Any] = ["seq": 1, "name": name, "category": "agent", "payload": payload]
        if let ws = workspaceId { e["workspace_id"] = ws }
        return e
    }

    func testSessionStart() {
        let e = src.translate(envelope("agent.hook.SessionStart",
                                       payload: ["session_id": "s1", "_source": "claude", "workspace_id": "ws1"]))
        XCTAssertEqual(e?.name, .sessionStart)
        XCTAssertEqual(e?.sessionId, "s1")
        XCTAssertEqual(e?.agent, "Claude")
        XCTAssertEqual(e?.workspaceId, "ws1")
    }

    func testPreToolUseTraeElNombreDeLaHerramienta() {
        let e = src.translate(envelope("agent.hook.PreToolUse",
                                       payload: ["session_id": "s1", "tool_name": "Edit", "workspace_id": "ws1"]))
        XCTAssertEqual(e?.name, .preToolUse)
        XCTAssertEqual(e?.tool, "Edit")
    }

    func testStopYSessionEndSonNombresDistintos() {
        let stop = src.translate(envelope("agent.hook.Stop", payload: ["session_id": "s1"]))
        let end = src.translate(envelope("agent.hook.SessionEnd", payload: ["session_id": "s1"]))
        XCTAssertEqual(stop?.name, .stop)
        XCTAssertEqual(end?.name, .sessionEnd)
    }

    /// El generador de frases ES un Claude Code que la propia mascota lanza.
    func testFiltraSuPropioPpid() {
        let mine = Int(getpid())
        let e = src.translate(envelope("agent.hook.PreToolUse",
                                       payload: ["session_id": "s1", "_ppid": mine]))
        XCTAssertNil(e)
    }

    func testPermissionRequestEsPermiso() {
        let e = src.translate(envelope("agent.hook.PermissionRequest",
                                       payload: ["session_id": "s1", "tool_name": "Bash"]))
        XCTAssertEqual(e?.name, .notification)
        XCTAssertEqual(e?.reason, .permission)
        XCTAssertEqual(e?.tool, "Bash")
    }

    /// Una PermissionRequest cuya herramienta ES "AskUserQuestion" sigue siendo
    /// una pregunta, no un permiso — asi lo distinguia el switch original.
    func testPermissionRequestConHerramientaAskUserQuestionEsPregunta() {
        let e = src.translate(envelope("agent.hook.PermissionRequest",
                                       payload: ["session_id": "s1", "tool_name": "AskUserQuestion"]))
        XCTAssertEqual(e?.reason, .question)
    }

    func testAskUserQuestionEsPregunta() {
        let e = src.translate(envelope("agent.hook.AskUserQuestion", payload: ["session_id": "s1"]))
        XCTAssertEqual(e?.name, .notification)
        XCTAssertEqual(e?.reason, .question)
    }

    /// El campo esta mal nombrado (aparece igual con _source: claude, no solo
    /// opencode) pero es el id que despues pide feed.permission.reply/
    /// feed.question.reply — verificado a mano contra ~/.cmuxterm/events.jsonl
    /// el 2026-09-17. Ver docs/reference/agent-reply.md.
    func testPermissionRequestTraeElRequestIdDeCorrelacion() {
        let e = src.translate(envelope("agent.hook.PermissionRequest",
                                       payload: ["session_id": "s1", "tool_name": "Bash",
                                                 "_opencode_request_id": "claude-s1-PermissionRequest-Bash-123"]))
        XCTAssertEqual(e?.requestId, "claude-s1-PermissionRequest-Bash-123")
    }

    func testAskUserQuestionTraeElRequestIdDeCorrelacion() {
        let e = src.translate(envelope("agent.hook.AskUserQuestion",
                                       payload: ["session_id": "s1",
                                                 "_opencode_request_id": "claude-s1-AskUserQuestion-456"]))
        XCTAssertEqual(e?.requestId, "claude-s1-AskUserQuestion-456")
    }

    func testPermissionRequestSinRequestIdQuedaNil() {
        let e = src.translate(envelope("agent.hook.PermissionRequest",
                                       payload: ["session_id": "s1", "tool_name": "Bash"]))
        XCTAssertNil(e?.requestId)
    }

    func testNotificationGenericaEsGenerica() {
        let e = src.translate(envelope("agent.hook.Notification", payload: ["session_id": "s1"]))
        XCTAssertEqual(e?.name, .notification)
        XCTAssertEqual(e?.reason, .generic)
    }

    func testWorkspacePromptSubmittedTraeElPreview() {
        let e = src.translate(envelope("workspace.prompt.submitted",
                                       payload: ["workspace_id": "ws1", "message_preview": "arreglar el bug"]))
        XCTAssertEqual(e?.name, .workspaceTaskSubmitted)
        XCTAssertEqual(e?.messagePreview, "arreglar el bug")
    }

    func testWorkspacePromptSubmittedSinPreviewNoProduceEvento() {
        let e = src.translate(envelope("workspace.prompt.submitted", payload: ["workspace_id": "ws1"]))
        XCTAssertNil(e)
    }

    func testSurfaceFocusedYSelectedActualizanElMismoCampo() {
        let a = src.translate(["name": "surface.focused", "surface_id": "surf1", "payload": [:] as [String: Any]])
        let b = src.translate(["name": "surface.selected", "surface_id": "surf2", "payload": [:] as [String: Any]])
        XCTAssertEqual(a?.name, .surfaceFocused)
        XCTAssertEqual(a?.surfaceId, "surf1")
        XCTAssertEqual(b?.surfaceId, "surf2")
    }

    func testWorkspaceSelected() {
        let e = src.translate(envelope("workspace.selected", payload: ["workspace_id": "ws9"]))
        XCTAssertEqual(e?.name, .workspaceSelected)
        XCTAssertEqual(e?.workspaceId, "ws9")
    }

    func testEventoSinNombreEsNil() {
        XCTAssertNil(src.translate(["payload": [:] as [String: Any]]))
    }

    func testEventoDesconocidoEsNil() {
        XCTAssertNil(src.translate(envelope("agent.hook.PostToolUse", payload: ["session_id": "s1"])))
    }

    // MARK: agentLabel

    func testAgentLabelConoceLosAgentesFrecuentes() {
        XCTAssertEqual(CmuxEventSource.agentLabel("claude"), "Claude")
        XCTAssertEqual(CmuxEventSource.agentLabel("opencode"), "OpenCode")
        XCTAssertEqual(CmuxEventSource.agentLabel(nil), "El agente")
        XCTAssertEqual(CmuxEventSource.agentLabel("mistral"), "Mistral")
    }
}
