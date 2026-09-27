// Fuente 5: la version publicada. La mascota avisa una vez cuando hay una mas
// nueva que la que corre. Contrato en docs/reference/versioning.md.

import AppKit
import Foundation

extension PetController {
    /// Primer disparo a los 30 s de arrancar, para no competir con el saludo ni
    /// con la conexion a cmux; despues cada 6 h de reloj. La consulta real la
    /// limita `UpdateCheck.shouldQuery` a una por dia.
    func startUpdateCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.maybeCheckForUpdate()
        }
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.maybeCheckForUpdate()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func maybeCheckForUpdate() {
        guard config.checkUpdates else { return }
        let state = UpdateState.load()
        guard UpdateCheck.shouldQuery(state: state) else { return }
        guard let current = Semver(mascoTuscanVersion) else { return }

        UpdateCheck.fetchLatest { latest, problem in
            DispatchQueue.main.async {
                if let problem = problem { plog("actualizaciones: \(problem)") }
                let (announce, next) = UpdateCheck.decide(current: current, latest: latest,
                                                          state: UpdateState.load())
                next.save()
                if let latest = latest, latest > current { self.availableUpdate = latest }
                if let v = announce { self.announceUpdate(v) }
            }
        }
    }

    func announceUpdate(_ v: Semver) {
        plog("actualizaciones: hay \(v), corre \(mascoTuscanVersion)")
        show(Bubble(mood: .info,
                    text: Voice.shared.phrase("updateAvailable", ["version": v.description])
                        ?? Wording.plain("Hay una versión nueva de MascoTuscan: \(v). Corre: mascotuscan update"),
                    workspaceId: nil, sticky: false))
    }

    /// Desde el menu: reinstala con el mismo instalador que usa la terminal. Este
    /// proceso hereda el entorno del shell que lo arranco dentro de cmux, asi
    /// que el instalador puede relanzar la mascota nueva con acceso al socket.
    @objc func runUpdate() {
        let target = availableUpdate.map { "v\($0)" } ?? "la última versión"
        show(Bubble(mood: .working,
                    text: "Actualizando a \(target). Compila un minuto y vuelvo sola.",
                    workspaceId: nil, sticky: true))
        guard let bin = Bundle.main.executableURL ?? URL(string: CommandLine.arguments[0]) else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            // nohup: el instalador mata a este proceso a mitad de camino y el
            // hijo tiene que sobrevivirlo para terminar y relanzar.
            p.arguments = ["-c", "nohup \"\(bin.path)\" update >> \"\(PetPaths.home.path)/pet.log\" 2>&1 &"]
            try? p.run()
            p.waitUntilExit()
        }
    }
}
