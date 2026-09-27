// Un permiso o una pregunta de Claude que sigue esperando respuesta. Ver
// docs/reference/agent-reply.md.

import Foundation

struct PendingRequest {
    enum Kind: Equatable {
        case permission
        case question
    }

    var requestId: String
    var kind: Kind
    var sessionId: String
    var workspaceId: String?
    var tool: String?
    var createdAt = Date()
}
