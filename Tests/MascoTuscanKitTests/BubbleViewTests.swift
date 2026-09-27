// size(for:) es puro (no lanza ventana): mide con el mismo motor de
// docs/adr/0003. Cubre que las opciones (docs/adr/0009) sumen su alto desde
// el arranque, para no saltar en pantalla cuando llegan.

import XCTest
@testable import MascoTuscanKit

final class BubbleViewTests: XCTestCase {
    func testUnaBurbujaConOpcionesEsMasAltaQueSinOpciones() {
        let sinOpciones = Bubble(mood: .attention, text: "Claude pide permiso", workspaceId: nil, sticky: true)
        let conOpciones = Bubble(mood: .attention, text: "Claude pide permiso", workspaceId: nil, sticky: true,
                                 requestId: "r1",
                                 options: [BubbleOption(id: "once", label: "Sí"), BubbleOption(id: "deny", label: "No")])
        let h1 = BubbleView.size(for: sinOpciones).height
        let h2 = BubbleView.size(for: conOpciones).height
        XCTAssertGreaterThan(h2, h1)
    }

    func testMasOpcionesSonMasAlto() {
        let unaOpcion = Bubble(mood: .attention, text: "¿Seguro?", workspaceId: nil, sticky: true,
                               requestId: "r1", options: [BubbleOption(id: "a", label: "Sí")])
        let dosOpciones = Bubble(mood: .attention, text: "¿Seguro?", workspaceId: nil, sticky: true,
                                 requestId: "r1",
                                 options: [BubbleOption(id: "a", label: "Sí"), BubbleOption(id: "b", label: "No")])
        XCTAssertGreaterThan(BubbleView.size(for: dosOpciones).height, BubbleView.size(for: unaOpcion).height)
    }

    func testElAnchoNoCambiaConOpciones() {
        let b = Bubble(mood: .attention, text: "hola", workspaceId: nil, sticky: true,
                       requestId: "r1", options: [BubbleOption(id: "a", label: "Sí")])
        XCTAssertEqual(BubbleView.size(for: b).width, BubbleView.width)
    }
}
