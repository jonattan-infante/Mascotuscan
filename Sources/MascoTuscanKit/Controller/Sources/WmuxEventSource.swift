// Fuente: wmux (fork de cmux para Windows). Esqueleto, no implementado.
//
// wmux.org confirma un named pipe `\\.\pipe\wmux` con JSON-RPC v2 y hooks de
// Claude Code auto-registrados, pero no documenta metodos RPC, categorias de
// evento ni forma de payload; tampoco hay hoy un entorno Windows real donde
// verificarlo contra `wmux --help` o `github.com/amirlehmam/wmux`.
// Implementar a ciegas viola "Verificar en vez de recordar" (CLAUDE.md).
//
// Por eso NO se registra en `PetController.makeEventSources()`: existir en el
// codigo, sin encenderse, deja el contrato `EventSource` listo para cuando
// haya como verificar el protocolo real. Ver docs/adr/0008.
final class WmuxEventSource: EventSource {
    let id = "wmux"

    func start(onEvent: @escaping (NormalizedEvent) -> Void,
               onUnavailable: @escaping (String) -> Void) {
        onUnavailable("wmux: protocolo no verificado, ver docs/adr/0008")
    }

    func stop() {}
}
