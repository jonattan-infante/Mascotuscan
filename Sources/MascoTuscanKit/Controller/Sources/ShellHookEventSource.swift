// Fuente: comandos de shell, via el archivo que escribe shell/pet.zsh.

import Foundation

/// Tailea `~/.mascotuscan/shell.jsonl`. Mismo id que usa el port de Windows para su
/// fuente principal de hooks (docs/reference/event-source.md): en macOS es
/// una fuente secundaria (cmux ya cubre agentes); en Windows es la unica.
final class ShellHookEventSource: EventSource {
    let id = "claude-hooks-file"

    private let tailer: FileTailer
    private var timer: Timer?

    init(url: URL = shellLogURL) {
        tailer = FileTailer(url: url)
    }

    func start(onEvent: @escaping (NormalizedEvent) -> Void,
               onUnavailable: @escaping (String) -> Void) {
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for line in self.tailer.readNewLines() {
                guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let ev = self.translate(obj) else { continue }
                onEvent(ev)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Puro y testeable: dict crudo de `shell/pet.zsh` -> NormalizedEvent, o
    /// nil si no es un evento de comando.
    func translate(_ e: [String: Any]) -> NormalizedEvent? {
        guard (e["kind"] as? String) == "command" else { return nil }
        return NormalizedEvent(source: id, name: .shellCommand,
                               workspaceId: e["workspace"] as? String,
                               surfaceId: e["surface"] as? String,
                               exitCode: e["status"] as? Int,
                               command: e["command"] as? String,
                               seconds: e["seconds"] as? Double)
    }
}
