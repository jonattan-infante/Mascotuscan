# Texto que produce el PROGRAMA, no la mascota. Puerto de Voice/Wording.swift.
#
# Nada de aqui tiene personalidad, a proposito: la personalidad vive en el pack.
# Esto son piezas neutras que las plantillas del pack rellenan.

# Traduce la herramienta a lo que el agente esta haciendo de verdad. En Windows
# los hooks de Claude Code SI traen el nombre real de la herramienta (a
# diferencia de cmux, que lo redacta), asi que el verbo es fiable.
_ACTIVITY = {
    "Bash": "corriendo comandos",
    "BashOutput": "corriendo comandos",
    "KillShell": "corriendo comandos",
    "Edit": "editando archivos",
    "Write": "editando archivos",
    "MultiEdit": "editando archivos",
    "NotebookEdit": "editando archivos",
    "Read": "leyendo codigo",
    "Grep": "buscando en el codigo",
    "Glob": "buscando en el codigo",
    "WebFetch": "consultando la web",
    "WebSearch": "consultando la web",
    "Task": "delegando a subagentes",
    "Agent": "delegando a subagentes",
    "Skill": "usando una skill",
    "AskUserQuestion": "esperando tu respuesta",
    "TodoWrite": "organizando el plan",
    "TaskCreate": "organizando el plan",
    "TaskUpdate": "organizando el plan",
    "Artifact": "publicando un artifact",
    "": "arrancando",
}


def activity(tool: str) -> str:
    tool = tool or ""
    if tool in _ACTIVITY:
        return _ACTIVITY[tool]
    return f"usando {tool}"


def at(workspace: str) -> str:
    """ ' en Fineract' o cadena vacia. Trae la preposicion incluida. """
    return f" en {workspace}" if workspace else ""


def and_others(count: int) -> str:
    if count <= 0:
        return ""
    return " Y otro mas." if count == 1 else f" Y otros {count} mas."


def update_available(version: str) -> str:
    """ Ultimo recurso cuando el pack no trae frase para la clase. """
    return f"Hay una version nueva de MascoTuscan: {version}. Corre: python install.py --update"


def fmt_duration(seconds: float) -> str:
    """ '1 min 34 s', '12 s', '2 h 3 min'. Duracion ya formateada para {time}. """
    s = int(round(seconds))
    if s < 60:
        return f"{s} s"
    if s < 3600:
        m, r = divmod(s, 60)
        return f"{m} min {r} s" if r else f"{m} min"
    h, r = divmod(s, 3600)
    m = r // 60
    return f"{h} h {m} min" if m else f"{h} h"
