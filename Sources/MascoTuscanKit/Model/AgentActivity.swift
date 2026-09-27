// Lo que sabemos de un agente vivo.

import Foundation

struct AgentActivity {
    var agent: String
    var workspaceId: String?
    var startedAt: Date
    var lastSeen: Date
    var currentTool: String?
    var toolCount: Int = 0

    var elapsed: String { compactDuration(Date().timeIntervalSince(startedAt)) }
    var doing: String { Wording.activity(currentTool) }
}

