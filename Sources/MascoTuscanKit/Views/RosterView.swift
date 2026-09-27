// Panel de estado en vivo de los agentes.

import AppKit

final class RosterView: NSView {
    var lines: [(String, NSColor?)] = [] { didSet { needsDisplay = true } }
    var accent: NSColor = .systemBlue

    static let width: CGFloat = 300
    static let padding: CGFloat = 12
    static let lineHeight: CGFloat = 15

    override var isFlipped: Bool { true }

    private static func font(_ bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 11, weight: bold ? .semibold : .regular)
    }

    static func height(for lines: [(String, NSColor?)]) -> CGFloat {
        // Las lineas largas envuelven: hay que contar cuantas ocupan de verdad.
        let inner = width - padding * 2
        var total: CGFloat = 0
        for (text, _) in lines {
            if text.isEmpty { total += lineHeight * 0.5; continue }
            let s = NSAttributedString(string: text, attributes: [.font: font()])
            let r = s.boundingRect(with: CGSize(width: inner, height: 200),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading])
            total += max(lineHeight, ceil(r.height))
        }
        return total + padding * 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // no roba el mouse

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)

        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 12,
                      color: NSColor.black.withAlphaComponent(0.42).cgColor)
        let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor(srgbRed: 0.075, green: 0.085, blue: 0.11, alpha: 0.97).setFill()
        path.fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        accent.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        let inner = RosterView.width - RosterView.padding * 2
        var y = box.minY + RosterView.padding
        for (text, color) in lines {
            if text.isEmpty { y += RosterView.lineHeight * 0.5; continue }
            let bold = color != nil
            let attrs: [NSAttributedString.Key: Any] = [
                .font: RosterView.font(bold),
                .foregroundColor: color ?? NSColor(srgbRed: 0.72, green: 0.76, blue: 0.82, alpha: 1),
            ]
            let s = NSAttributedString(string: text, attributes: attrs)
            let h = max(RosterView.lineHeight,
                        ceil(s.boundingRect(with: CGSize(width: inner, height: 200),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
            s.draw(with: CGRect(x: box.minX + RosterView.padding, y: y, width: inner, height: h),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
            y += h
        }
    }
}
