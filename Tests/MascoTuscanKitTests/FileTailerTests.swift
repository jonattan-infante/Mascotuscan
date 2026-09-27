// Mismos casos que windows/tests/test_events.py::TailerTests: si se agrega
// uno aca, va alla tambien (docs/reference/event-source.md).

import XCTest
@testable import MascoTuscanKit

final class FileTailerTests: XCTestCase {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tailer-tests-\(UUID().uuidString).jsonl")
    }

    func testSoloLeeLineasNuevas() throws {
        let url = tempURL()
        try "vieja\n".write(to: url, atomically: true, encoding: .utf8)
        let t = FileTailer(url: url)
        XCTAssertEqual(t.readNewLines().count, 0, "no debe reproducir lo que ya estaba al arrancar")

        let fh = try FileHandle(forWritingTo: url)
        fh.seekToEndOfFile()
        fh.write("nueva1\nnueva2\n".data(using: .utf8)!)
        try fh.close()

        let lines = t.readNewLines().compactMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(lines, ["nueva1", "nueva2"])
    }

    func testArchivoInexistenteNoRompe() {
        let url = tempURL()
        let t = FileTailer(url: url)
        XCTAssertEqual(t.readNewLines(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "debe crear el archivo")
    }

    func testTruncadoReiniciaElOffset() throws {
        let url = tempURL()
        try "unaLineaLarga\n".write(to: url, atomically: true, encoding: .utf8)
        let t = FileTailer(url: url)
        _ = t.readNewLines()

        try "corta\n".write(to: url, atomically: true, encoding: .utf8)
        let lines = t.readNewLines().compactMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(lines, ["corta"])
    }
}
