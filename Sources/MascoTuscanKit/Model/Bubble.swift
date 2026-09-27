// Un aviso en pantalla.

import Foundation

struct Bubble {
    var mood: Mood
    var text: String
    var workspaceId: String?
    var sticky: Bool
    var createdAt: Date = Date()
    /// Si no es nil, ademas de texto la burbuja ofrece botones para responder
    /// un permiso o una pregunta pendiente. Ver docs/reference/agent-reply.md.
    var requestId: String? = nil
    var options: [BubbleOption] = []
}

/// Un boton clicable dentro de una burbuja pendiente de respuesta. `id` es lo
/// que se manda al RPC (un `mode` de permiso o el id de una `question_option`).
struct BubbleOption {
    var id: String
    var label: String
}

/// La voz del droide. Un pitido segun el animo, la frase, y a veces un cierre.
/// Todo en un parrafo: el asistente habla como una unidad astromecanica, no
