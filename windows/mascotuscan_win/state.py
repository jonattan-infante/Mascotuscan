# Los seis estados y la maquina que los resuelve. Puerto de Model/Mood.swift y
# de la parte del PetController que correlaciona sesiones y decide el estado.
#
# El vocabulario es del sistema, no de la mascota: un pack cambia colores e
# imagenes, nunca inventa un estado. Aqui, cada sesion de Claude Code es un
# "agente"; el estado global es la prioridad mas alta entre todas las sesiones.

from dataclasses import dataclass, field
from typing import Optional


class Mood:
    IDLE = "idle"
    WORKING = "working"
    DONE = "done"
    ERROR = "error"
    ATTENTION = "attention"
    INFO = "info"
    ALL = [IDLE, WORKING, DONE, ERROR, ATTENTION, INFO]


# Paleta por defecto (rgb 0..1), identica a Mood.defaultAccent en Swift.
DEFAULT_ACCENT = {
    Mood.IDLE:      (0.42, 0.62, 0.98),
    Mood.WORKING:   (0.98, 0.72, 0.24),
    Mood.DONE:      (0.30, 0.80, 0.50),
    Mood.ERROR:     (0.94, 0.36, 0.36),
    Mood.ATTENTION: (0.98, 0.55, 0.20),
    Mood.INFO:      (0.55, 0.60, 0.98),
}


def rgb_to_hex(rgb) -> str:
    r, g, b = rgb
    return "#%02X%02X%02X" % (int(r * 255), int(g * 255), int(b * 255))


def blend(rgb, fraction, other=(0.0, 0.0, 0.0)):
    """ Mezcla 'fraction' de 'other' sobre 'rgb'. Igual que NSColor.blended. """
    return tuple(rgb[i] * (1 - fraction) + other[i] * fraction for i in range(3))


# Ventanas de tiempo (segundos). Deciden cuando un estado decae.
ACTIVE_WINDOW = 180.0   # tras la ULTIMA HERRAMIENTA: cubre las pausas largas de pensamiento entre herramientas (Stop cierra antes)
PROMPT_WINDOW = 60.0    # tras un prompt SIN herramientas todavia: respuesta solo de texto o Stop que no llego
DONE_SHOW = 6.0         # cuanto se muestra "listo" tras terminar
ERROR_SHOW = 8.0        # cuanto se muestra "fallo" tras un error
INFO_SHOW = 5.0         # cuanto se muestra "info" tras una notificacion
GHOST_AFTER = 600.0     # sin senal en 10 min, la sesion se barre


@dataclass
class Session:
    session_id: str
    workspace: str = ""
    # Quien la anuncia ("Claude", "OpenCode", ...): la pone la fuente en el
    # primer evento de la sesion. Ver docs/reference/event-source.md.
    agent: str = "Claude"
    last_tool: str = ""
    steps: int = 0
    started_ts: float = 0.0
    last_ts: float = 0.0
    last_tool_ts: float = -1e9      # ultimo PreToolUse/PostToolUse
    prompt_ts: float = -1e9         # ultimo UserPromptSubmit
    stopped: bool = False
    attention: bool = False
    error_ts: float = -1e9
    done_ts: float = -1e9
    info_ts: float = -1e9

    def active(self, now: float) -> bool:
        # "Trabajando" lo sostienen las herramientas; un prompt solo lo sostiene
        # un rato corto. Asi, si el Stop no llega (respuesta solo de texto,
        # hook caido), la mascota vuelve sola al reposo.
        if self.stopped:
            return False
        return ((now - self.last_tool_ts) < ACTIVE_WINDOW
                or (now - self.prompt_ts) < PROMPT_WINDOW)


@dataclass
class Announcement:
    kind: str
    vars: dict = field(default_factory=dict)
    session_id: str = ""
    workspace: str = ""


class StateMachine:
    """ Ingiere eventos normalizados y expone el estado global y el roster.

    Decisiones deliberadas, heredadas del proyecto:
    - La atencion persiste hasta que la sesion vuelve a actuar (el humano
      respondio) o termina. Nunca se limpia sola.
    - El estado global es la prioridad mas alta entre sesiones:
      attention > error > working > done > info > idle.
    """

    def __init__(self):
        self.sessions: dict = {}

    # --- ingesta -----------------------------------------------------------

    def _session(self, sid: str, now: float, cwd: str = "", agent: str = "Claude") -> Session:
        s = self.sessions.get(sid)
        if s is None:
            ws = _basename(cwd)
            s = Session(session_id=sid, workspace=ws, agent=agent, started_ts=now, last_ts=now)
            self.sessions[sid] = s
        elif cwd and not s.workspace:
            s.workspace = _basename(cwd)
        return s

    def ingest(self, ev: dict, now: float) -> Optional[Announcement]:
        etype = ev.get("event", "")
        sid = ev.get("session", "") or "?"
        s = self._session(sid, now, ev.get("workspace") or ev.get("cwd", ""),
                          ev.get("agent") or "Claude")
        s.last_ts = now

        if etype == "SessionStart":
            s.stopped = False
            s.info_ts = now
            return None

        if etype == "SessionEnd":
            self.sessions.pop(sid, None)
            return None

        if etype == "UserPromptSubmit":
            # El humano respondio: se acabo la espera y se reanuda el trabajo.
            s.stopped = False
            s.attention = False
            s.prompt_ts = now
            return None

        if etype == "PreToolUse":
            s.stopped = False
            s.attention = False
            s.last_tool_ts = now
            s.last_tool = ev.get("tool", "") or s.last_tool
            s.steps += 1
            return None

        if etype == "PostToolUse":
            s.last_tool_ts = now
            s.last_tool = ev.get("tool", "") or s.last_tool
            if ev.get("ok", True) is False:
                s.error_ts = now
                return Announcement(
                    kind="commandError",
                    vars={
                        "cmd": _short_cmd(ev.get("cmd", "") or s.last_tool),
                        "code": str(ev.get("exit", 1)),
                        "where": _at(s.workspace),
                    },
                    session_id=sid, workspace=s.workspace)
            return None

        if etype == "Notification":
            if _is_idle_notice(ev.get("message", "")):
                # "Claude is waiting for your input": Claude Code lo manda un
                # minuto despues de terminar el turno. No es un pedido; la
                # sesion ya esta en reposo y asi debe verse.
                return None
            s.attention = True
            return Announcement(
                kind="attention",
                vars={
                    "agent": s.agent,
                    "what": _what(ev.get("message", "")),
                    "where": _at(s.workspace),
                },
                session_id=sid, workspace=s.workspace)

        if etype in ("Stop", "SubagentStop"):
            s.stopped = True
            s.attention = False
            s.done_ts = now
            return Announcement(
                kind="agentDone",
                vars={"agent": s.agent, "where": _at(s.workspace)},
                session_id=sid, workspace=s.workspace)

        return None

    # --- estado ------------------------------------------------------------

    def prune(self, now: float) -> None:
        dead = [sid for sid, s in self.sessions.items()
                if now - s.last_ts > GHOST_AFTER]
        for sid in dead:
            self.sessions.pop(sid, None)

    def mood(self, now: float) -> str:
        self.prune(now)
        ss = self.sessions.values()
        if not ss:
            return Mood.IDLE
        if any(s.attention for s in ss):
            return Mood.ATTENTION
        if any(now - s.error_ts < ERROR_SHOW for s in ss):
            return Mood.ERROR
        if any(s.active(now) for s in ss):
            return Mood.WORKING
        if any(now - s.done_ts < DONE_SHOW for s in ss):
            return Mood.DONE
        if any(now - s.info_ts < INFO_SHOW for s in ss):
            return Mood.INFO
        return Mood.IDLE

    def roster(self, now: float) -> list:
        """ Una linea por sesion viva, la mas reciente primero. """
        self.prune(now)
        rows = []
        for s in sorted(self.sessions.values(), key=lambda x: -x.last_ts):
            rows.append({
                "workspace": s.workspace or s.session_id[:8],
                "doing": _activity(s.last_tool) if s.active(now)
                         else ("esperandote" if s.attention else "en reposo"),
                "steps": s.steps,
                "attention": s.attention,
                "age": now - s.started_ts,
            })
        return rows

    def working_narration(self, now: float) -> Optional[Announcement]:
        """ El agente mas activo, para la narracion periodica de 'working'. """
        live = [s for s in self.sessions.values() if s.active(now)]
        if not live:
            return None
        s = max(live, key=lambda x: x.last_ts)
        return Announcement(
            kind="working",
            vars={
                "agent": s.agent,
                "doing": _activity(s.last_tool),
                "time": _fmt(now - s.started_ts),
                "where": _at(s.workspace),
            },
            session_id=s.session_id, workspace=s.workspace)


# --- helpers (se importan tarde para evitar ciclos en tests) ----------------

# Alias de visualizacion: nombres de carpeta -> como se muestran en el roster y
# en las burbujas (p.ej. la carpeta home del usuario, corta). Vienen de la
# config del usuario (workspaceAliases), no del repo.
_WS_ALIASES = {}


def set_workspace_aliases(aliases) -> None:
    _WS_ALIASES.clear()
    if isinstance(aliases, dict):
        _WS_ALIASES.update({str(k): str(v) for k, v in aliases.items()})


def _basename(path: str) -> str:
    if not path:
        return ""
    path = path.replace("\\", "/").rstrip("/")
    name = path.rsplit("/", 1)[-1] if "/" in path else path
    return _WS_ALIASES.get(name, name)


def _is_idle_notice(message: str) -> bool:
    m = (message or "").lower()
    return "waiting for your input" in m or "idle" in m


def _what(message: str) -> str:
    m = (message or "").lower()
    if "permiss" in m or "permit" in m or "allow" in m or "approve" in m:
        return "un permiso"
    if "?" in (message or "") or "question" in m or "input" in m:
        return "una respuesta"
    return "atencion"


def _short_cmd(cmd: str) -> str:
    cmd = (cmd or "").strip().replace("\n", " ")
    return cmd if len(cmd) <= 48 else cmd[:45] + "..."


# Estos delegan en wording.py; se importan aqui para mantener state.py sin
# dependencias de nivel superior en los tests que solo tocan la maquina.
from . import wording as _w  # noqa: E402

_at = _w.at
_activity = _w.activity
_fmt = _w.fmt_duration
