// Orquestador: consume las cuatro fuentes de eventos y decide que mostrar.

import AppKit
import Foundation

public final class PetController: NSObject, NSApplicationDelegate {
    var config = PetConfig.load()
    let panel: PetPanel
    let container = ContainerView()
    let petView = PetView()
    let bubbleView = BubbleView()
    let rosterView = RosterView()
    var hovering = false
    /// El mouse esta sobre la burbuja. No es `hovering`: ese abre el panel de
    /// estado, y pasar por la burbuja no deberia abrirlo.
    var bubbleHovered = false

    let petBox = CGSize(width: 96, height: 108)
    var anchor: CGPoint = .zero

    // Estado de agentes, por session_id.
    var activities: [String: AgentActivity] = [:]
    var workspaceTasks: [String: String] = [:]    // workspaceId -> texto del prompt
    var attentionSessions: Set<String> = []
    var lastDoneAt: [String: Date] = [:]
    var lastAttentionAt: [String: Date] = [:]

    var currentBubble: Bubble?
    var bubbleTimer: Timer?
    var transientMoodTimer: Timer?
    var lastAlertWorkspace: String?
    var lastNarrationAt: Date?
    var lastNarrationText: String?

    var workspaceTitles: [String: String] = [:]
    var focusedSurface: String?
    var selectedWorkspace: String?
    var knownPorts: [String: Set<Int>] = [:]
    var portsBaselineDone = false

    var sources: [EventSource] = []
    var warnedSources: Set<String> = []
    /// Permisos/preguntas sin resolver, por requestId. Ver docs/reference/agent-reply.md.
    var pendingRequests: [String: PendingRequest] = [:]
    /// Costura de test: como se busca el contenido real de un pendiente. En
    /// produccion, RPC feed.list (PetController.fetchPendingContentDefault).
    var fetchPendingContent: (String, @escaping (PendingRequestContent?) -> Void) -> Void
        = PetController.fetchPendingContentDefault
    /// Costura de test: quien mira la terminal ahora mismo. En produccion, cmux.
    var isCmuxFrontmost: () -> Bool = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.cmuxterm.app"
    }
    /// Version publicada mas nueva que la que corre, si se supo. Para el menu.
    var availableUpdate: Semver?
    var saveWorkItem: DispatchWorkItem?
    /// Solo existe si el paquete activo declara `roam`. Ver PetController+Roam.
    var roamer: Roamer?

    public override init() {
        panel = PetPanel(contentRect: CGRect(origin: .zero, size: petBox),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
    }

    // MARK: ciclo de vida

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        restoreAnchor()
        layout()
        panel.orderFrontRegardless()

        startAnimation()
        startEventSources()
        startPolling()
        startNarration()
        startUpdateCheck()

        activateConfiguredPet()

        greet()
    }

    /// Pone en pie la mascota configurada: su tema para el dibujo y su voz para
    /// los avisos. Si no hay ninguna instalada, lo dice en pantalla en vez de
    /// quedarse muda y parecer que funciona.
    func activateConfiguredPet() {
        PetLibrary.ensureDirs()
        guard let pack = PetLibrary.active(config: config) else {
            plog("no hay ninguna mascota instalada")
            show(Bubble(mood: .error,
                        text: "No tengo ninguna mascota instalada. Corre: mascotuscan install astro",
                        workspaceId: nil, sticky: true))
            return
        }
        PetTheme.shared.activate(pack)
        Voice.shared.activate(pack)
        petView.reloadSprites()
        setupRoam()
        plog("mascota activa: \(pack.name) (\(pack.id)) v\(pack.version), renderer \(pack.renderer.raw)")

        // Sin frases generadas se usa el respaldo del pack; se piden en segundo
        // plano para que la proxima vez suene distinto.
        if !Voice.shared.hasGenerated {
            Voice.shared.regenerate("primera vez para \(pack.id)")
        } else if let d = Voice.shared.ageInDays, d > 7 {
            Voice.shared.regenerate("frases de hace \(Int(d)) días")
        }
    }

    func setupPanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = container

        container.addSubview(bubbleView)
        container.addSubview(rosterView)
        container.addSubview(petView)

        petView.onClick = { [weak self] in self?.jumpToLastAlert() }
        petView.onDrag = { [weak self] origin in self?.moveTo(origin) }
        petView.onMenu = { [weak self] ev in self?.showMenu(ev) }
        petView.onHover = { [weak self] inside in self?.setHover(inside) }
        bubbleView.onClick = { [weak self] in self?.jumpToLastAlert() }
        bubbleView.onOption = { [weak self] id in self?.respondToOption(id) }
        bubbleView.onHover = { [weak self] inside in self?.bubbleHovered = inside }
    }

    func restoreAnchor() {
        guard let screen = NSScreen.main else { return }
        if let x = config.x, let y = config.y {
            anchor = CGPoint(x: x, y: y)
        } else {
            let vf = screen.visibleFrame
            anchor = CGPoint(x: vf.maxX - petBox.width - 24, y: vf.minY + 24)
        }
        anchor = clamp(anchor)
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: p.x + petBox.width / 2,
                                                                       y: p.y + petBox.height / 2)) }
            ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return p }
        return CGPoint(x: min(max(p.x, vf.minX + 4), vf.maxX - petBox.width - 4),
                       y: min(max(p.y, vf.minY + 4), vf.maxY - petBox.height - 4))
    }

    // MARK: layout

    func layout() {
        var frame = CGRect(origin: anchor, size: petBox)

        // El hover manda: mientras miras al droide quieres el estado, no el aviso.
        let roster = hovering ? rosterLines() : []
        let showRoster = !roster.isEmpty
        if showRoster { rosterView.lines = roster; rosterView.accent = Mood.working.accent }

        var cardSize: CGSize? = nil
        if showRoster {
            cardSize = CGSize(width: RosterView.width, height: RosterView.height(for: roster))
        } else if let b = currentBubble, !config.quiet {
            cardSize = BubbleView.size(for: b)
        }

        var cardFrame: CGRect? = nil
        if let size = cardSize {
            let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
            let vf = screen?.visibleFrame ?? .zero
            let fitsLeft = anchor.x - size.width - 10 >= vf.minX
            let bx = fitsLeft ? anchor.x - size.width - 6 : anchor.x + petBox.width + 6
            var by = anchor.y + petBox.height / 2 - size.height / 2
            by = min(max(by, vf.minY + 4), vf.maxY - size.height - 4)
            cardFrame = CGRect(x: bx, y: by, width: size.width, height: size.height)
            frame = frame.union(cardFrame!)
        }

        frame = frame.insetBy(dx: -14, dy: -14)
        panel.setFrame(frame, display: true)

        petView.frame = CGRect(origin: CGPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY),
                               size: petBox)

        bubbleView.isHidden = true
        rosterView.isHidden = true
        if let cf = cardFrame {
            let local = CGRect(origin: CGPoint(x: cf.minX - frame.minX, y: cf.minY - frame.minY),
                               size: cf.size)
            if showRoster {
                rosterView.isHidden = false
                rosterView.frame = local
            } else {
                bubbleView.isHidden = false
                bubbleView.frame = local
            }
        }
    }

    func setHover(_ inside: Bool) {
        guard hovering != inside else { return }
        hovering = inside
        layout()
    }

    func moveTo(_ origin: CGPoint) {
        // origin es la esquina de la ventana; el ancla es la del personaje dentro de ella.
        let delta = CGPoint(x: origin.x - panel.frame.minX, y: origin.y - panel.frame.minY)
        anchor = clamp(CGPoint(x: anchor.x + delta.x, y: anchor.y + delta.y))
        roamer?.place(at: Double(anchor.x))
        layout()
        scheduleSave()
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.config.x = self.anchor.x
            self.config.y = self.anchor.y
            self.config.save()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    // MARK: animacion

    func startAnimation() {
        var last = CACurrentMediaTime()
        // 30 fps cuando pasa algo, 10 fps en reposo: la vista es de 96 px, el costo es marginal.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            let dt = now - last
            let resting = self.petView.mood == .idle && self.currentBubble == nil
                && (self.roamer?.phase ?? .resting) == .resting
            if resting && dt < 0.1 { return }
            last = now
            self.stepRoam(dt)
            self.petView.tick(dt)
            // La burbuja escribe letra por letra: necesita redibujarse igual de seguido.
            if self.currentBubble != nil { self.bubbleView.needsDisplay = true }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

}
