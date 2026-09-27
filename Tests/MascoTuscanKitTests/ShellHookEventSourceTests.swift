// translate() contra el dict que escribe shell/pet.zsh.

import XCTest
@testable import MascoTuscanKit

final class ShellHookEventSourceTests: XCTestCase {
    let src = ShellHookEventSource(url: FileManager.default.temporaryDirectory
        .appendingPathComponent("shell-hook-tests-\(UUID().uuidString).jsonl"))

    func testComandoOk() {
        let e = src.translate(["kind": "command", "status": 0, "seconds": 1.5,
                               "command": "npm test", "cwd": "/tmp", "workspace": "ws1", "surface": "surf1"])
        XCTAssertEqual(e?.name, .shellCommand)
        XCTAssertEqual(e?.exitCode, 0)
        XCTAssertEqual(e?.command, "npm test")
        XCTAssertEqual(e?.workspaceId, "ws1")
        XCTAssertEqual(e?.surfaceId, "surf1")
        XCTAssertEqual(e?.seconds, 1.5)
    }

    func testComandoQueFalla() {
        let e = src.translate(["kind": "command", "status": 1, "command": "make build"])
        XCTAssertEqual(e?.exitCode, 1)
    }

    func testIgnoraLoQueNoEsUnComando() {
        XCTAssertNil(src.translate(["kind": "otro"]))
        XCTAssertNil(src.translate([:]))
    }
}
