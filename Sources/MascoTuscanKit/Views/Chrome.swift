// Contenedor transparente y panel flotante.

import AppKit

final class ContainerView: NSView {
    override var isFlipped: Bool { false }
    /// Devuelve nil en las zonas transparentes para que el click pase a la app de abajo.
    override func hitTest(_ point: NSPoint) -> NSView? {
        for v in subviews.reversed() {
            if let hit = v.hitTest(point) { return hit }
        }
        return nil
    }
}

/// Panel flotante que nunca toma el foco del teclado: el asistente no debe
/// robarle la escritura a la terminal.
public final class PetPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
