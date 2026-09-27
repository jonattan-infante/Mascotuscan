// Fija en codigo que wmux es "no implementado todavia", en vez de dejarlo
// como un comentario que se puede desincronizar. Ver docs/adr/0008.

import XCTest
@testable import MascoTuscanKit

final class WmuxEventSourceTests: XCTestCase {
    func testAvisaNoDisponibleYNuncaEmiteEventos() {
        let src = WmuxEventSource()
        var unavailableMsg: String?
        var eventFired = false

        src.start(onEvent: { _ in eventFired = true },
                 onUnavailable: { msg in unavailableMsg = msg })

        XCTAssertNotNil(unavailableMsg)
        XCTAssertFalse(eventFired)
    }

    func testNoEstaRegistradaPorDefecto() {
        let pc = PetController()
        let ids = pc.makeEventSources().map { $0.id }
        XCTAssertFalse(ids.contains("wmux"),
                       "wmux no se enciende hasta verificar su protocolo real")
    }
}
