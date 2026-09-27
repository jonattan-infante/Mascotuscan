# Fuente de eventos del port: el archivo shell.jsonl que escriben los hooks de
# Claude Code. Analogo del tail de shell.jsonl en PetController+Sources (macOS),
# pero aqui es la fuente PRINCIPAL, no una secundaria: no hay cmux.
#
# Un archivo plano y no un socket, por la misma razon que en el proyecto
# original: un append nunca bloquea al que escribe. El precio es un poll, que es
# gratis. Ver ARCHITECTURE.md del repo.

import json
from pathlib import Path
from typing import Optional


def parse_line(line: str) -> Optional[dict]:
    """ Una linea JSON del hook -> evento normalizado, o None si no sirve. """
    line = line.strip()
    if not line:
        return None
    try:
        raw = json.loads(line)
    except (ValueError, TypeError):
        return None
    if not isinstance(raw, dict):
        return None
    return normalize(raw)


# Nombres de evento de Claude Code que entendemos. Cualquier otro se ignora en
# silencio (mejor que adivinar).
KNOWN = {
    "SessionStart", "SessionEnd", "UserPromptSubmit",
    "PreToolUse", "PostToolUse", "Notification",
    "Stop", "SubagentStop",
}


def normalize(raw: dict) -> Optional[dict]:
    """ Acepta tanto la forma cruda del hook de Claude Code como la forma
    compacta que escribe mascotuscan-hook.ps1. Devuelve el esquema interno. """
    event = raw.get("event") or raw.get("hook_event_name") or ""
    if event not in KNOWN:
        return None

    ev = {
        "ts": _num(raw.get("ts"), 0.0),
        "event": event,
        "session": str(raw.get("session") or raw.get("session_id") or "?"),
        "workspace": raw.get("workspace") or "",
        "cwd": raw.get("cwd") or "",
        "tool": raw.get("tool") or raw.get("tool_name") or "",
        "cmd": raw.get("cmd") or "",
        "message": raw.get("message") or "",
        "ok": raw.get("ok", True),
        "exit": raw.get("exit"),
        "pid": raw.get("pid"),
        # Hoy solo hay una fuente de hooks de Claude Code, asi que es constante.
        # Ver docs/reference/event-source.md: cada fuente pone su propio agente.
        "agent": "Claude",
    }

    # Si viene la forma cruda, extraer lo util de sus sub-objetos.
    ti = raw.get("tool_input")
    if isinstance(ti, dict) and not ev["cmd"]:
        ev["cmd"] = ti.get("command") or ""
    tr = raw.get("tool_response")
    if isinstance(tr, dict):
        # Mejor esfuerzo: Claude Code marca error con is_error o interrupted.
        if tr.get("is_error") or tr.get("interrupted"):
            ev["ok"] = False
    return ev


def _num(v, default):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


class Tailer:
    """ Sigue un archivo de texto y entrega solo las lineas nuevas en cada
    lectura, ya normalizadas por `parse`.

    Arranca al final del archivo: no reproduce el historial al abrir. Tolera que
    el archivo aun no exista, que rote (se trunque) o que crezca. Sin hilos: el
    caller llama read_new() desde su propio timer.

    `parse` es inyectable para poder reusar esta clase con otra fuente que
    escriba lineas en su propio formato (p.ej. el plugin-puente de OpenCode,
    ver docs/reference/event-source.md) sin duplicar la logica de tailing.
    """

    def __init__(self, path: Path, parse=parse_line):
        self.path = Path(path)
        self._parse = parse
        self._pos = 0
        self._inode = None
        self._seek_end()

    def _seek_end(self) -> None:
        try:
            st = self.path.stat()
            self._pos = st.st_size
            self._inode = getattr(st, "st_ino", None)
        except FileNotFoundError:
            self._pos = 0
            self._inode = None

    def read_new(self) -> list:
        try:
            st = self.path.stat()
        except FileNotFoundError:
            self._pos = 0
            return []

        # Truncado o reemplazado: reiniciar desde el principio.
        if st.st_size < self._pos or (
                self._inode is not None
                and getattr(st, "st_ino", None) != self._inode):
            self._pos = 0
            self._inode = getattr(st, "st_ino", None)

        events = []
        try:
            with self.path.open("r", encoding="utf-8", errors="replace") as f:
                f.seek(self._pos)
                for line in f:
                    ev = self._parse(line)
                    if ev is not None:
                        events.append(ev)
                self._pos = f.tell()
        except OSError:
            return events
        return events
