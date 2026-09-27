// PetController.extractPendingContent(_:requestId:) contra fixtures literales
// con la forma real de `cmux rpc feed.list '{}'` (verificada a mano el
// 2026-09-17, valores sinteticos aqui). Puro: no lanza ningun proceso.
// Ver docs/reference/agent-reply.md.

import XCTest
@testable import MascoTuscanKit

final class PendingRequestContentTests: XCTestCase {
    func testEncuentraUnPermisoPorRequestId() {
        let items: [[String: Any]] = [
            ["id": "item-1", "kind": "toolUse", "request_id": "otro"],
            ["id": "item-2", "kind": "permissionRequest", "request_id": "claude-s1-PermissionRequest-Bash-1",
             "title": "Bash", "tool_input": "{\"command\":\"ls -la\"}", "status": "pending"],
        ]
        let content = PetController.extractPendingContent(items, requestId: "claude-s1-PermissionRequest-Bash-1")
        XCTAssertEqual(content, .permission(tool: "Bash", toolInput: "{\"command\":\"ls -la\"}"))
    }

    func testEncuentraUnaPreguntaConSusOpciones() {
        let items: [[String: Any]] = [
            ["id": "item-3", "kind": "question", "request_id": "claude-s1-AskUserQuestion-1",
             "question_multi_select": false,
             "question_options": [
                ["id": "opt0", "label": "Sí", "description": "Continuar como está"],
                ["id": "opt1", "label": "No", "description": "Cambiar de enfoque"],
             ] as [[String: Any]]],
        ]
        let content = PetController.extractPendingContent(items, requestId: "claude-s1-AskUserQuestion-1")
        XCTAssertEqual(content, .question(options: [
            QuestionOption(id: "opt0", label: "Sí", description: "Continuar como está"),
            QuestionOption(id: "opt1", label: "No", description: "Cambiar de enfoque"),
        ]))
    }

    func testSinMatchDevuelveNil() {
        let items: [[String: Any]] = [
            ["id": "item-1", "kind": "permissionRequest", "request_id": "otro-request"],
        ]
        XCTAssertNil(PetController.extractPendingContent(items, requestId: "no-existe"))
    }

    func testFeedVacioDevuelveNil() {
        XCTAssertNil(PetController.extractPendingContent([], requestId: "cualquiera"))
    }

    // MARK: summarizeToolInput

    func testSacaElComandoDeUnToolInputDeBash() {
        XCTAssertEqual(PetController.summarizeToolInput("{\"command\":\"ls -la\"}"), "ls -la")
    }

    func testSinCampoCommandDevuelveElJsonTalCual() {
        let raw = "{\"file_path\":\"a.txt\"}"
        XCTAssertEqual(PetController.summarizeToolInput(raw), raw)
    }

    func testJsonInvalidoDevuelveElTextoTalCual() {
        XCTAssertEqual(PetController.summarizeToolInput("no es json"), "no es json")
    }
}
