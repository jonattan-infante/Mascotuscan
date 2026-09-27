# Comprobacion de actualizaciones. Implementacion en Python del contrato de
# docs/reference/versioning.md; Sources/MascoTuscanKit/Model/Update.swift es la
# misma logica en Swift y los dos comparten los casos de prueba.
#
# La decision es pura y esta separada de la red a proposito: lo que se prueba
# es "dado este estado y esta version remota, hablo o me callo".

import json
import os
import re
import threading
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from . import paths

DEFAULT_ENDPOINT = "https://api.github.com/repos/jonattan-infante/mascotuscan/releases/latest"
MIN_INTERVAL = 24 * 3600      # una consulta real por dia como maximo

_SEMVER = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def endpoint() -> str:
    # MASCOTUSCAN_UPDATE_URL reemplaza el endpoint para probar sin publicar nada
    # (acepta file://).
    return os.environ.get("MASCOTUSCAN_UPDATE_URL") or DEFAULT_ENDPOINT


def parse(raw) -> Optional[tuple]:
    """ 'v0.2.0' -> (0, 2, 0). None si no es X.Y.Z: un prerelease no es una
    version publicada para el usuario y no se compara. """
    if not isinstance(raw, str):
        return None
    m = _SEMVER.match(raw.strip())
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def fmt(v: tuple) -> str:
    return ".".join(str(x) for x in v)


def parse_latest(data: bytes) -> Optional[tuple]:
    """ Saca la version de la respuesta de GitHub (tag_name). """
    try:
        obj = json.loads(data)
    except (ValueError, TypeError):
        return None
    if not isinstance(obj, dict):
        return None
    return parse(obj.get("tag_name"))


# --- estado en disco ------------------------------------------------------

def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _from_iso(s) -> Optional[datetime]:
    if not isinstance(s, str):
        return None
    try:
        return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


class UpdateState:
    """ Lo que se recuerda entre arranques. Misma forma que en macOS para que
    un mismo ~/.mascotuscan sirva a las dos plataformas. """

    def __init__(self, checked_at: Optional[datetime] = None,
                 latest: Optional[str] = None, announced: Optional[str] = None):
        self.checked_at = checked_at
        self.latest = latest
        self.announced = announced

    def __eq__(self, other):
        return (isinstance(other, UpdateState)
                and (self.checked_at, self.latest, self.announced)
                == (other.checked_at, other.latest, other.announced))

    @classmethod
    def load(cls, path: Path = None) -> "UpdateState":
        # Un archivo corrupto o ausente es un estado vacio, no un fallo.
        path = path or paths.UPDATE
        try:
            obj = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return cls()
        if not isinstance(obj, dict):
            return cls()
        return cls(_from_iso(obj.get("checkedAt")),
                   obj.get("latest") if isinstance(obj.get("latest"), str) else None,
                   obj.get("announced") if isinstance(obj.get("announced"), str) else None)

    def save(self, path: Path = None) -> None:
        path = path or paths.UPDATE
        obj = {}
        if self.checked_at:
            obj["checkedAt"] = _iso(self.checked_at)
        if self.latest:
            obj["latest"] = self.latest
        if self.announced:
            obj["announced"] = self.announced
        try:
            path.write_text(json.dumps(obj, indent=2, sort_keys=True), encoding="utf-8")
        except OSError:
            pass


# --- decision ---------------------------------------------------------------

def should_query(state: UpdateState, now: datetime = None) -> bool:
    now = now or datetime.now(timezone.utc)
    if state.checked_at is None:
        return True
    return (now - state.checked_at).total_seconds() >= MIN_INTERVAL


def decide(current: tuple, latest: Optional[tuple], state: UpdateState,
           now: datetime = None):
    """ La regla de silencio: se habla una sola vez por version nueva.
    Devuelve (version_a_anunciar | None, estado_nuevo). """
    now = now or datetime.now(timezone.utc)
    nxt = UpdateState(now, fmt(latest) if latest else None, state.announced)
    if latest is None or latest <= current:
        return None, nxt
    done = parse(state.announced) if state.announced else None
    if done is not None and done >= latest:
        return None, nxt
    nxt.announced = fmt(latest)
    return latest, nxt


# --- red --------------------------------------------------------------------

def fetch_latest(timeout: float = 10.0):
    """ Bloquea: llamar desde un hilo. Devuelve (version | None, problema | None). """
    from . import __version__
    req = urllib.request.Request(endpoint(), headers={
        "User-Agent": f"mascotuscan/{__version__}",
        "Accept": "application/vnd.github+json",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None, "sin versiones publicadas todavia"
        return None, f"GitHub respondio {e.code}"
    except Exception as e:      # sin red, DNS, timeout: todos son "hoy no"
        return None, f"sin red: {e}"
    v = parse_latest(data)
    if v is None:
        return None, "la respuesta no traia una version"
    return v, None


class Checker:
    """ Hilo de fondo con el patron de nowplaying.Poller: consulta una vez y
    deja el resultado en .result; el tick de Tk solo lo lee. """

    def __init__(self):
        self.result = None          # (version | None, problema | None)
        self._thread = None

    @property
    def busy(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self):
        if self.busy:
            return
        self.result = None
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self):
        self.result = fetch_latest()

    def take(self):
        """ Devuelve el resultado una sola vez, o None si no hay nada nuevo. """
        r = self.result
        if r is not None:
            self.result = None
        return r
