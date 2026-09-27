// Contrato compartido con Windows: docs/reference/event-source.md.

import Foundation

/// Evento ya traducido del formato crudo de una fuente al vocabulario comun
/// del programa. Ninguna fuente decide mood ni compone texto: eso es del
/// orquestador (PetController.ingest). Ver docs/reference/event-source.md.
struct NormalizedEvent {
    enum Name: Equatable {
        case sessionStart, sessionEnd, userPromptSubmit
        case preToolUse, postToolUse
        case stop, subagentStop
        case notification
        case shellCommand
        case surfaceFocused, workspaceSelected, workspaceTaskSubmitted, notificationCreated
    }

    enum Reason: Equatable {
        case permission, question, generic
    }

    let source: String
    let name: Name
    var sessionId: String?
    var workspaceId: String?
    var surfaceId: String?
    var agent: String?
    var tool: String?
    var exitCode: Int?
    var command: String?
    var seconds: Double?
    var messagePreview: String?
    /// Id de correlacion para responder un permiso o una pregunta pendiente
    /// (`feed.permission.reply`/`feed.question.reply`). Ver
    /// docs/reference/agent-reply.md.
    var requestId: String?
    var reason: Reason = .generic
    var occurredAt = Date()
}

/// Una fuente de eventos: dueña de su transporte y de su reconexion propia,
/// traduce el protocolo crudo a NormalizedEvent y nunca decide mood ni compone
/// texto de burbuja — eso es siempre del orquestador. Ver
/// docs/reference/event-source.md.
protocol EventSource: AnyObject {
    /// Para el log y para el aviso "no me deja escuchar a <id>". P.ej. "cmux".
    var id: String { get }

    /// Nunca bloquea: la conexion real ocurre en segundo plano. `onUnavailable`
    /// se llama cuando la fuente no puede operar (transporte ausente, permiso
    /// denegado, reconexion fallida repetida); el orquestador decide si avisa.
    func start(onEvent: @escaping (NormalizedEvent) -> Void,
               onUnavailable: @escaping (String) -> Void)

    func stop()
}
