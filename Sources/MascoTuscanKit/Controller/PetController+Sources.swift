// Fuente 3: puertos y titulos de workspace, via RPC de cmux.

import AppKit
import Foundation

extension PetController {
    // MARK: supresion por pane

    /// Estas mirando ese pane exacto ahora mismo: no tiene sentido avisarte de lo
    /// que ya ves. Deliberadamente es a nivel de pane y no de workspace: un
    /// workspace tiene muchas pestañas y silenciarlo entero se traga casi todo.
    func userIsWatching(_ surfaceId: String?) -> Bool {
        guard let s = surfaceId, s == focusedSurface else { return false }
        return isCmuxFrontmost()
    }

    // MARK: fuente 3 — puertos y titulos de workspace

    func startPolling() {
        refreshWorkspaces()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshWorkspaces()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func refreshWorkspaces() {
        DispatchQueue.global(qos: .utility).async {
            guard let obj = cmuxJSON(["rpc", "workspace.list", "{}"]),
                  let list = obj["workspaces"] as? [[String: Any]] else { return }

            var titles: [String: String] = [:]
            var ports: [String: Set<Int>] = [:]
            for w in list {
                guard let id = w["id"] as? String else { continue }
                if let t = w["title"] as? String, !t.isEmpty {
                    titles[id] = t
                } else if let t = w["custom_title"] as? String, !t.isEmpty {
                    titles[id] = t
                } else if let d = w["current_directory"] as? String {
                    titles[id] = (d as NSString).lastPathComponent
                }
                let raw = (w["listening_ports"] as? [Any]) ?? []
                var set = Set<Int>()
                for item in raw {
                    if let n = item as? Int { set.insert(n) }
                    else if let d = item as? [String: Any], let n = d["port"] as? Int { set.insert(n) }
                }
                ports[id] = set
            }

            DispatchQueue.main.async {
                self.workspaceTitles = titles
                self.diffPorts(ports)
            }
        }
    }

    func diffPorts(_ fresh: [String: Set<Int>]) {
        defer { knownPorts = fresh }
        guard config.watchPorts else { return }
        guard portsBaselineDone else { portsBaselineDone = true; return }

        for (ws, now) in fresh {
            let before = knownPorts[ws] ?? []
            let label = Wording.at(workspaceLabel(ws))
            for p in now.subtracting(before).sorted() {
                show(Bubble(mood: .info,
                            text: Voice.shared.phrase("portUp", ["port": "\(p)", "where": label])
                                ?? Wording.plain("El puerto \(p) está escuchando\(label)."),
                            workspaceId: ws, sticky: false))
            }
            for p in before.subtracting(now).sorted() {
                show(Bubble(mood: .info,
                            text: Voice.shared.phrase("portDown", ["port": "\(p)", "where": label])
                                ?? Wording.plain("El puerto \(p) se cerró\(label)."),
                            workspaceId: ws, sticky: false))
            }
        }
    }

    func workspaceLabel(_ id: String?) -> String {
        guard let id = id else { return "" }
        return PetController.cleanTitle(workspaceTitles[id] ?? "")
    }

    /// cmux le pone un spinner braille o un asterisco al titulo cuando el
    /// workspace esta activo. Dentro de una frase eso es basura.
    static func cleanTitle(_ t: String) -> String {
        var s = Substring(t)
        while let f = s.unicodeScalars.first {
            let v = f.value
            let isSpinner = (v >= 0x2800 && v <= 0x28FF)   // braille
                || v == 0x2733 || v == 0x2731 || v == 0x002A   // asteriscos
                || f == " "
            if isSpinner { s = s.dropFirst() } else { break }
        }
        return String(s).trimmingCharacters(in: .whitespaces)
    }

}
