// Punto de entrada. Deliberadamente delgado: despacha subcomandos, modo
// --render, y si no hay ninguno, arranca la mascota. Toda la logica vive en
// MascoTuscanKit para que sea testeable.

import AppKit
import MascoTuscanKit
import Foundation

// Los DispatchSource de senales mueren si nadie los retiene.
var signalSources: [DispatchSourceSignal] = []

PetPaths.ensureHome()
PetLibrary.ensureDirs()

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--version") {
    print("mascotuscan \(mascoTuscanVersion)")
    exit(0)
}

// `mascotuscan --render <dir>` escribe un PNG por estado sin abrir ventana. Es como
// se revisa una mascota desde CI o desde un agente.
if let i = args.firstIndex(of: "--render") {
    _ = NSApplication.shared
    let out = i + 1 < args.count
        ? URL(fileURLWithPath: args[i + 1])
        : PetPaths.home.appendingPathComponent("render")
    // El render usa la mascota activa: asi se revisa la que el usuario ve.
    if let pack = PetLibrary.active(config: PetConfig.load()) {
        PetTheme.shared.activate(pack)
        Voice.shared.activate(pack)
    }
    renderShowcase(to: out)
    exit(0)
}

// Subcomandos: list, use, install, new, validate, voice, search...
if let code = PetCommands.run(args) {
    exit(code)
}

takeOverPidFile()

let app = NSApplication.shared
let controller = PetController()
app.delegate = controller

// launchd o un reinicio manual mandan SIGTERM: hay que llevarse al hijo por delante.
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        controller.shutdown()
        exit(0)
    }
    src.resume()
    signalSources.append(src)
}

app.run()
