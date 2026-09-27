# Lee que esta sonando en Windows (Spotify, navegador, cualquier reproductor) via
# la sesion de medios del sistema (SMTC). No necesita cuenta ni claves.
#
# Es OPCIONAL: depende del paquete winrt. Si no esta, todo cae con gracia y la
# mascota sigue funcionando sin musica.
#
#   pip install winrt-Windows.Media.Control winrt-Windows.Foundation
#
# La consulta es asincrona y algo lenta, asi que corre en un hilo de fondo y deja
# el ultimo resultado en .latest; el pet solo lo lee.

import threading
import time

try:
    import asyncio
    from winrt.windows.media.control import (
        GlobalSystemMediaTransportControlsSessionManager as _Manager)
    _AVAILABLE = True
except Exception:
    _AVAILABLE = False


def available() -> bool:
    return _AVAILABLE


# Estados de reproduccion de SMTC.
_PLAYING = 4


async def _read():
    mgr = await _Manager.request_async()
    s = mgr.get_current_session()
    if s is None:
        return None
    info = await s.try_get_media_properties_async()
    pb = s.get_playback_info()
    app = (s.source_app_user_model_id or "")
    return {
        "title": (info.title or "").strip(),
        "artist": (info.artist or "").strip(),
        "playing": int(pb.playback_status) == _PLAYING,
        "spotify": "spotify" in app.lower(),
    }


class Poller:
    """ Hilo de fondo que refresca .latest cada `interval` segundos. """

    def __init__(self, interval: float = 4.0):
        self.interval = interval
        self.latest = None
        self._stop = threading.Event()
        self._thread = None

    def start(self):
        if not _AVAILABLE or self._thread:
            return
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()

    def _run(self):
        while not self._stop.is_set():
            try:
                self.latest = asyncio.run(_read())
            except Exception:
                self.latest = None
            self._stop.wait(self.interval)
