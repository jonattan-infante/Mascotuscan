// Modo --render: dibuja cada estado a PNG sin abrir ventana.

import AppKit

public func renderShowcase(to dir: URL) {
    let moods: [Mood] = [.idle, .working, .done, .error, .attention, .info]
    let size = CGSize(width: 96, height: 108)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    var frames: [NSImage] = []
    for m in moods {
        let view = PetView(frame: CGRect(origin: .zero, size: size))
        view.mood = m
        view.tick(m == .done ? 0.22 : 0.9)   // avanza a un instante representativo

        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            rep.draw(in: CGRect(origin: .zero, size: size))
        }
        canvas.unlockFocus()
        frames.append(canvas)

        if let tiff = canvas.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("\(m.rawValue).png"))
        }
    }

    // Tira horizontal con los seis estados, para compararlos de un vistazo.
    let stripSize = CGSize(width: size.width * CGFloat(frames.count), height: size.height)
    let strip = NSImage(size: stripSize)
    strip.lockFocus()
    for (i, f) in frames.enumerated() {
        f.draw(at: CGPoint(x: CGFloat(i) * size.width, y: 0),
               from: .zero, operation: .sourceOver, fraction: 1)
    }
    strip.unlockFocus()
    if let tiff = strip.tiffRepresentation,
       let bmp = NSBitmapImageRep(data: tiff),
       let png = bmp.representation(using: .png, properties: [:]) {
        try? png.write(to: dir.appendingPathComponent("todos.png"))
    }
    // Burbujas con las frases REALES de la mascota activa, rellenadas con datos
    // de ejemplo. Asi `--render` es la vista previa de quien esta creando una
    // mascota: se ve como habla, no un texto de muestra ajeno.
    let nombre = PetTheme.shared.name
    let samples: [(Mood, String)] = [
        (.done, Voice.shared.phrase("commandDone", [
            "cmd": "./gradlew build", "time": "1 min 34 s", "where": " en Fineract",
        ]) ?? Wording.plain("./gradlew build terminó en 1 min 34 s en Fineract.")),
        (.error, Voice.shared.phrase("commandError", [
            "cmd": "npm run test:e2e", "code": "1", "where": " en Backend",
        ]) ?? Wording.plain("npm run test:e2e falló con código 1 en Backend.")),
        (.attention, Voice.shared.phrase("attention", [
            "agent": "Claude", "what": "un permiso para usar Bash", "where": " en DB Connect",
        ]) ?? Wording.plain("Claude necesita un permiso para usar Bash en DB Connect.")),
        (.working, Voice.shared.phrase("working", [
            "agent": "Claude", "doing": "editando archivos", "time": "4 min",
            "where": " en Fineract",
        ]) ?? Wording.plain("Claude lleva 4 min en Fineract editando archivos.")),
        (.info, Voice.shared.phrase("greeting", [:])
            ?? Wording.plain("\(nombre) en línea, vigilando tus agentes, comandos y puertos.")),
    ]
    for (i, sample) in samples.enumerated() {
        let b = Bubble(mood: sample.0, text: sample.1, workspaceId: nil, sticky: false)
        let bs = BubbleView.size(for: b)
        for (j, frac) in [0.35, 1.0].enumerated() {
            let view = BubbleView(frame: CGRect(origin: .zero, size: bs))
            view.bubble = b
            view.debugReveal = frac
            let canvas = NSImage(size: CGSize(width: bs.width + 20, height: bs.height + 20))
            canvas.lockFocus()
            NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: canvas.size)).fill()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                rep.draw(in: CGRect(x: 10, y: 10, width: bs.width, height: bs.height))
            }
            canvas.unlockFocus()
            if let tiff = canvas.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("burbuja-\(i)-\(j).png"))
            }
        }
    }

    // Burbujas con botones: permiso y pregunta pendientes (docs/adr/0009).
    // Solo con debugReveal=1: las opciones no se pintan a mitad de escritura.
    let pending: [Bubble] = [
        Bubble(mood: .attention,
              text: "Claude pide permiso para Bash en Fineract:\nrm -rf build/",
              workspaceId: nil, sticky: true, requestId: "r1",
              options: [BubbleOption(id: "once", label: "Sí"), BubbleOption(id: "deny", label: "No")]),
        Bubble(mood: .attention, text: "Claude pregunta en Backend:", workspaceId: nil, sticky: true,
              requestId: "r2",
              options: [BubbleOption(id: "opt0", label: "Los mismos créditos de antes"),
                        BubbleOption(id: "opt1", label: "Una lista nueva"),
                        BubbleOption(id: "opt2", label: "Otra cosa, dejame explicar")]),
    ]
    for (i, b) in pending.enumerated() {
        let bs = BubbleView.size(for: b)
        let view = BubbleView(frame: CGRect(origin: .zero, size: bs))
        view.bubble = b
        view.debugReveal = 1.0
        let canvas = NSImage(size: CGSize(width: bs.width + 20, height: bs.height + 20))
        canvas.lockFocus()
        NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: canvas.size)).fill()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            rep.draw(in: CGRect(x: 10, y: 10, width: bs.width, height: bs.height))
        }
        canvas.unlockFocus()
        if let tiff = canvas.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("burbuja-pendiente-\(i).png"))
        }
    }

    // Panel de estado en vivo.
    let accent = Mood.working.accent
    let rosterLines: [(String, NSColor?)] = [
        ("2 unidades trabajando", accent),
        ("", nil),
        ("Claude · Fineract · 4 min", accent),
        ("  corriendo comandos · 23 pasos", nil),
        ("  \u{201C}repetir los movimientos del corte 23\u{201D}", nil),
        ("", nil),
        ("Codex · Backend · 40 s", accent),
        ("  editando archivos · 3 pasos", nil),
        ("  \u{201C}arreglar el null pointer del score\u{201D}", nil),
    ]
    let rh = RosterView.height(for: rosterLines)
    let rv = RosterView(frame: CGRect(x: 0, y: 0, width: RosterView.width, height: rh))
    rv.lines = rosterLines
    rv.accent = accent
    let rcanvas = NSImage(size: CGSize(width: RosterView.width + 20, height: rh + 20))
    rcanvas.lockFocus()
    NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: rcanvas.size)).fill()
    if let rep = rv.bitmapImageRepForCachingDisplay(in: rv.bounds) {
        rv.cacheDisplay(in: rv.bounds, to: rep)
        rep.draw(in: CGRect(x: 10, y: 10, width: RosterView.width, height: rh))
    }
    rcanvas.unlockFocus()
    if let tiff = rcanvas.tiffRepresentation,
       let bmp = NSBitmapImageRep(data: tiff),
       let png = bmp.representation(using: .png, properties: [:]) {
        try? png.write(to: dir.appendingPathComponent("panel.png"))
    }

    print("render en \(dir.path)")
}
