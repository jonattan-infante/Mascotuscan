// Burbuja estilo terminal con texto que se escribe letra por letra.

import AppKit

final class BubbleView: NSView {
    var bubble: Bubble? {
        didSet {
            revealStart = CACurrentMediaTime()
            needsDisplay = true
        }
    }
    var onClick: (() -> Void)?
    /// Se dispara con el `id` de la opcion clicada (ver `Bubble.options`).
    var onOption: ((String) -> Void)?

    static let width: CGFloat = 272
    static let padding: CGFloat = 12
    static let charsPerSecond: Double = 45
    private static let optionSpacing: CGFloat = 6
    private static let prompt = "› "
    private static let cursor = "\u{2588}"

    private var revealStart: CFTimeInterval = 0
    /// Solo para el modo --render: congela el avance de la escritura.
    var debugReveal: Double?
    /// Rects de las opciones dibujadas en el ultimo `draw(_:)`, en coordenadas
    /// locales (la vista esta `isFlipped`). `mouseUp` las usa para saber si el
    /// clic fue sobre un boton o sobre el resto de la burbuja.
    private var optionRects: [(CGRect, String)] = []

    private static func font() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    }

    private static func inkAttrs() -> [NSAttributedString.Key: Any] {
        [.font: font(),
         .foregroundColor: NSColor(srgbRed: 0.87, green: 0.90, blue: 0.94, alpha: 1)]
    }

    private static func optionAttrs(_ mood: Mood) -> [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: mood.accent]
    }

    private static func optionLine(_ o: BubbleOption) -> String { "  › " + o.label }

    /// Vista volteada: el motor de layout dibuja de arriba hacia abajo, y asi
    /// medir y dibujar usan exactamente el mismo sistema de coordenadas.
    override var isFlipped: Bool { true }

    /// Un unico camino de layout para medir Y para dibujar. Medir con
    /// `boundingRect` y dibujar con `draw(with:)` daba envoltura distinta y
    /// recortaba la ultima linea.
    private static func layoutText(_ s: NSAttributedString, width w: CGFloat)
        -> (NSTextStorage, NSLayoutManager, NSTextContainer, CGFloat) {
        let storage = NSTextStorage(attributedString: s)
        let container = NSTextContainer(size: CGSize(width: w, height: 100_000))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return (storage, layout, container, ceil(layout.usedRect(for: container).height))
    }

    static func textHeight(_ s: NSAttributedString, width w: CGFloat) -> CGFloat {
        layoutText(s, width: w).3
    }

    /// La caja se mide con el texto COMPLETO. Si se midiera con lo revelado,
    /// la tarjeta crecería mientras escribe y saltaría en pantalla. Las
    /// opciones (si hay) ya suman su alto desde el arranque, por la misma
    /// razon: no pueden aparecer y hacer saltar la tarjeta despues.
    static func size(for b: Bubble) -> CGSize {
        let inner = width - padding * 2
        let s = NSAttributedString(string: prompt + b.text + cursor, attributes: inkAttrs())
        var h = textHeight(s, width: inner)
        if !b.options.isEmpty { h += optionsBlockHeight(b.options, mood: b.mood, width: inner) }
        return CGSize(width: width, height: h + padding * 2)
    }

    private static func optionsBlockHeight(_ options: [BubbleOption], mood: Mood, width w: CGFloat) -> CGFloat {
        options.reduce(CGFloat(0)) { acc, o in
            let s = NSAttributedString(string: optionLine(o), attributes: optionAttrs(mood))
            return acc + optionSpacing + textHeight(s, width: w)
        }
    }

    /// Cuantos caracteres se ven ya.
    private func revealed(_ b: Bubble) -> Int {
        if let f = debugReveal { return Int(Double(b.text.count) * f) }
        let elapsed = CACurrentMediaTime() - revealStart
        return min(b.text.count, max(0, Int(elapsed * BubbleView.charsPerSecond)))
    }

    var isTyping: Bool {
        guard let b = bubble else { return false }
        return revealed(b) < b.text.count
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bubble != nil else { return nil }
        let p = convert(point, from: superview)
        return bounds.contains(p) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let b = bubble, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)

        // Tarjeta oscura: es una terminal, se queda oscura en tema claro tambien.
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 12,
                      color: NSColor.black.withAlphaComponent(0.42).cgColor)
        let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor(srgbRed: 0.075, green: 0.085, blue: 0.11, alpha: 0.97).setFill()
        path.fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        b.mood.accent.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Un solo parrafo: prompt en color de estado, texto en gris claro,
        // cursor de bloque al final.
        let n = revealed(b)
        let shown = String(b.text.prefix(n))
        let line = NSMutableAttributedString(string: BubbleView.prompt,
                                             attributes: [.font: BubbleView.font(),
                                                          .foregroundColor: b.mood.accent])
        line.append(NSAttributedString(string: shown, attributes: BubbleView.inkAttrs()))

        // Mientras escribe el cursor esta fijo; al terminar, parpadea.
        let typing = n < b.text.count
        let blink = CACurrentMediaTime().truncatingRemainder(dividingBy: 1.0) < 0.55
        if typing || blink {
            line.append(NSAttributedString(
                string: BubbleView.cursor,
                attributes: [.font: BubbleView.font(),
                             .foregroundColor: b.mood.accent.withAlphaComponent(0.9)]))
        }

        let inner = BubbleView.width - BubbleView.padding * 2
        let (storage, layout, container, textH) = BubbleView.layoutText(line, width: inner)
        layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container),
                          at: CGPoint(x: box.minX + BubbleView.padding,
                                      y: box.minY + BubbleView.padding))
        _ = storage   // el layout manager no retiene el storage

        // Las opciones solo se pintan (y se pueden clicar) una vez terminada
        // la escritura: aparecer a mitad de camino es ruido, y el alto ya
        // esta reservado desde size(for:) asi que no hay salto al llegar.
        optionRects = []
        if !b.options.isEmpty, n >= b.text.count {
            var y = box.minY + BubbleView.padding + textH + BubbleView.optionSpacing
            for o in b.options {
                let optString = NSAttributedString(string: BubbleView.optionLine(o),
                                                   attributes: BubbleView.optionAttrs(b.mood))
                let (oStorage, oLayout, oContainer, oH) = BubbleView.layoutText(optString, width: inner)
                let rect = CGRect(x: box.minX + BubbleView.padding, y: y, width: inner, height: oH)
                optionRects.append((rect, o.id))
                oLayout.drawGlyphs(forGlyphRange: oLayout.glyphRange(for: oContainer),
                                   at: CGPoint(x: rect.minX, y: rect.minY))
                _ = oStorage
                y += oH + BubbleView.optionSpacing
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = optionRects.first(where: { $0.0.contains(p) }) {
            onOption?(hit.1)
            return
        }
        onClick?()
    }
}
