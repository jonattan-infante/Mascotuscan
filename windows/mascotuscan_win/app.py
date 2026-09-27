# Orquestador. Analogo del PetController de macOS: conecta las fuentes (aqui,
# el tail de shell.jsonl) con el estado (los seis) y con la vista.
#
# Decide CUANDO hablar; el pet pack decide COMO. Esa separacion es la misma del
# proyecto original y es lo que hace posible reusar los packs astro/gatito tal
# cual.

import os
import random
import sys
import threading
import time
import tkinter as tk

from . import notebook as notebookmod
from . import paths, sound, voice as voicemod, nowplaying, update as updatemod, wording
from . import __version__
from .config import Config
from .events import Tailer
from . import state as statemod
from .state import StateMachine, Mood
from .ui import PetWindow

FRAME_MS = 40                      # ~25 fps: fluido y barato
# Cada cuanto se molesta en mirar el archivo de la libreta. El intervalo de
# cada recordatorio es propio de cada tarea (ver notebook.due_todo_reminders);
# esto solo evita leer el JSON del disco en cada uno de los ticks de 40ms.
TODO_SCAN_SECONDS = 30
# Cada cuanto se plantea consultar si hay version nueva. La consulta real la
# limita update.should_query a una por dia; esto es solo el reloj del tick.
UPDATE_SCAN_SECONDS = 6 * 3600
UPDATE_FIRST_DELAY = 30            # no competir con el saludo al arrancar

# Frases para anunciar lo que suena en Spotify. Encajan con su onda de DJ.
SONG_LINES = [
    "Ahora suena: {t}, de {a}. Buen tema.",
    "Mmm, {a} con {t}. Subele.",
    "Sonando {t}, de {a}. Este me gusta.",
    "{a}: {t}. Perfecto para programar.",
]


class App:
    def __init__(self, root: tk.Tk, config: Config = None, sources: list = None):
        paths.ensure_home()
        self.root = root
        self.config = config or Config.load()
        statemod.set_workspace_aliases(self.config.get("workspaceAliases"))
        self.sm = StateMachine()
        # Cada fuente cumple el contrato de docs/reference/event-source.md:
        # read_new() -> list[dict] de eventos ya normalizados. Agregar una
        # fuente nueva (OpenCode, ...) es sumarla a esta lista.
        self.sources = sources if sources is not None else [Tailer(paths.SHELL_LOG)]

        self.pack = self._load_pack(self.config["activePet"])
        self.voice = voicemod.Voice(self.pack)

        self.last_cwd = None
        self._last_narrate = 0.0
        self._notebook = None
        self._last_todo_scan = 0.0
        self._started_at = time.time()
        self._last_update_scan = None
        self._update_checker = updatemod.Checker()
        self.available_update = None    # tupla semver, para el menu

        # Spotify (opcional): lee que suena en Windows y lo anuncia al cambiar.
        self._np = nowplaying.Poller()
        self._np_last = None
        if self.config.get("spotify", True):
            self._np.start()

        self.window = PetWindow(
            root, self.pack,
            on_click=self._on_click,
            on_menu={
                "items": self._menu_items(),
                "moved": self._on_moved,
            })
        self.window.anim_divisor = self.config.get("animSlowdown", 1)
        self.window.sprite_h = self.config.get("spriteHeight", 220)
        self.window.place_bottom_right(self.config.get("position"))

        # Saludo al arrancar.
        greet = self.voice.phrase("greeting", {})
        if greet and not self.config["quiet"]:
            self.window.show_bubble(greet, time.time(), seconds=5.0)

    # --- ciclo de vida ------------------------------------------------------

    def run(self):
        self._write_pid()
        self._schedule()
        try:
            self.root.mainloop()
        finally:
            self._clear_pid()

    def _schedule(self):
        self.tick()
        self.root.after(FRAME_MS, self._schedule)

    def tick(self, now=None):
        if now is None:
            now = time.time()
        for src in self.sources:
            for ev in src.read_new():
                self._handle(ev, now)
        self._maybe_narrate(now)
        self._maybe_song(now)
        self._maybe_todo_reminder(now)
        self._maybe_update(now)
        mood = self.sm.mood(now)
        self.window.set_mood(mood)
        self.window.set_roster(self.sm.roster(now))
        self.window.render(now)
        return mood

    # --- eventos ------------------------------------------------------------

    def _handle(self, ev, now):
        ann = self.sm.ingest(ev, now)
        if ev.get("cwd"):
            self.last_cwd = ev["cwd"]
        if ann and not self.config["quiet"]:
            text = self.voice.phrase(ann.kind, ann.vars)
            if text:
                self.window.show_bubble(text, now)

    def _maybe_narrate(self, now):
        every = self.config.get("narrateEverySeconds", 150) or 0
        if every <= 0 or self.config["quiet"]:
            return
        if now - self._last_narrate < every:
            return
        ann = self.sm.working_narration(now)
        if ann:
            self._last_narrate = now
            text = self.voice.phrase(ann.kind, ann.vars)
            if text:
                self.window.show_bubble(text, now)

    def _maybe_todo_reminder(self, now):
        # Cada tarea de la lista trae su propio intervalo y su propio on/off
        # (se configuran desde la libreta, click en el textito de "cada Xh"
        # junto a cada renglon). Aqui solo se pregunta cuales ya se cumplieron.
        if self.config["quiet"]:
            return
        if now - self._last_todo_scan < TODO_SCAN_SECONDS:
            return
        self._last_todo_scan = now
        notebook_open = self._notebook is not None and self._notebook.win.winfo_exists()
        if notebook_open:
            # Sobre el mismo objeto en memoria de la ventana abierta: si
            # leyeramos/escribieramos el archivo aparte, el siguiente guardado
            # de la libreta (con su copia vieja) pisaria el last_reminded y el
            # aviso saldria de nuevo enseguida en vez de respetar el intervalo.
            due, changed = notebookmod.scan_due_items(self._notebook.pages, now)
            if changed:
                self._notebook.save()
        else:
            due = notebookmod.due_todo_reminders(now)
        if not due:
            return
        self._play_reminder_sound()
        self.window.show_bubble(self._todo_reminder_phrase(due), now, seconds=10.0)

    def _maybe_update(self, now):
        # Fuente extra: la version publicada. Contrato en docs/reference/versioning.md.
        # Primero se recoge lo que haya traido el hilo; despues se decide si
        # lanzar otra consulta.
        result = self._update_checker.take()
        if result is not None:
            latest, problem = result
            current = updatemod.parse(__version__)
            announce, state = updatemod.decide(current, latest, updatemod.UpdateState.load())
            state.save()
            if latest and current and latest > current:
                self.available_update = latest
                self.window.on_menu["items"] = self._menu_items()
            if announce and not self.config["quiet"]:
                text = (self.voice.phrase("updateAvailable", {"version": updatemod.fmt(announce)})
                        or wording.update_available(updatemod.fmt(announce)))
                self.window.show_bubble(text, now, seconds=10.0)
        if not self.config.get("checkUpdates", True):
            return
        if now - self._started_at < UPDATE_FIRST_DELAY:
            return
        if self._last_update_scan is not None and now - self._last_update_scan < UPDATE_SCAN_SECONDS:
            return
        self._last_update_scan = now
        if updatemod.should_query(updatemod.UpdateState.load()):
            self._update_checker.start()

    def _play_reminder_sound(self):
        # Campanita suave sintetizada (ver sound.py). Antes eran dos Beep() de
        # onda cuadrada que aturdian; Catalina pidio algo tranquilo.
        sound.play_reminder()

    def _todo_reminder_phrase(self, due):
        if len(due) == 1:
            return f"Che, todavia te falta: {due[0]}."
        preview = ", ".join(due[:3])
        extra = f" y {len(due) - 3} mas" if len(due) > 3 else ""
        return f"Recordatorio: te quedan {len(due)} pendientes ({preview}{extra})."

    def _maybe_song(self, now):
        # Anuncia la cancion de Spotify solo cuando cambia (para no ser pesada).
        if self.config["quiet"]:
            return
        np = self._np.latest
        if not np or not np.get("playing") or not np.get("title"):
            return
        key = (np["title"], np["artist"])
        if key == self._np_last:
            return
        self._np_last = key
        text = random.choice(SONG_LINES).format(t=np["title"],
                                                a=np["artist"] or "alguien")
        self.window.show_bubble(text, now, seconds=7.0)

    # --- acciones de la vista ----------------------------------------------

    def _on_click(self):
        # Click en la mascota: si la libreta ya esta abierta, la cierra
        # (guardando primero); si no, la abre. Un solo click hace las dos cosas.
        if self._notebook is not None and self._notebook.win.winfo_exists():
            self._notebook._on_close()
            self._notebook = None
        else:
            self._notebook = notebookmod.NotebookWindow(self.root)

    def _on_moved(self, x, y):
        self.config["position"] = [x, y]
        self.config.save()

    def _installed_pets(self):
        # Se descubren escaneando pets/: soltar una carpeta con pet.json basta,
        # sin tocar codigo. Por eso los packs locales (no versionados) aparecen.
        out = []
        if paths.BUNDLED_PETS.exists():
            for d in sorted(paths.BUNDLED_PETS.iterdir()):
                if (d / "pet.json").exists():
                    out.append(d.name)
        return out or ["astro"]

    def _menu_items(self):
        items = []
        for pid in self._installed_pets():
            mark = "  (activa)" if pid == self.config["activePet"] else ""
            items.append((f"Mascota: {pid}{mark}",
                          lambda p=pid: self._use_pet(p)))
        items.append(("-", None))
        cur = self.config.get("animSlowdown", 1)
        for label, val in (("Baile: normal", 1), ("Baile: lento", 3), ("Baile: quieto", 0)):
            mark = "  *" if val == cur else ""
            items.append((label + mark, lambda v=val: self._set_dance(v)))
        items.append(("-", None))
        if nowplaying.available():
            sp_label = "Spotify: si" if self.config.get("spotify", True) else "Spotify: no"
            items.append((sp_label, self._toggle_spotify))
        quiet_label = "Reactivar avisos" if self.config["quiet"] else "Silenciar avisos"
        items.append((quiet_label, self._toggle_quiet))
        items.append(("-", None))
        if self.available_update:
            items.append((f"Actualizar a v{updatemod.fmt(self.available_update)}",
                          self._run_update))
        items.append((f"mascotuscan v{__version__}", None))
        items.append(("Salir", self._quit))
        return items

    def _run_update(self):
        # El instalador mueve el checkout al tag publicado y esta mascota se
        # apaga; el hook SessionStart arranca la nueva.
        import subprocess
        self.window.show_bubble("Actualizando. Cierro y vuelvo con la version nueva.",
                                time.time(), seconds=8.0)
        subprocess.Popen([sys.executable, str(paths.REPO_ROOT / "windows" / "install.py"),
                          "--update"], creationflags=getattr(subprocess, "DETACHED_PROCESS", 0))

    def _toggle_spotify(self):
        on = not self.config.get("spotify", True)
        self.config["spotify"] = on
        self.config.save()
        if on:
            self._np.start()
        else:
            self._np.stop()
        self.window.on_menu["items"] = self._menu_items()

    def _set_dance(self, value):
        self.config["animSlowdown"] = value
        self.config.save()
        self.window.anim_divisor = value
        self.window.on_menu["items"] = self._menu_items()

    def _use_pet(self, pid):
        if pid == self.config["activePet"]:
            return
        self.config["activePet"] = pid
        self.config.save()
        self.pack = self._load_pack(pid)
        self.voice = voicemod.Voice(self.pack)
        self.window.set_pack(self.pack)
        self.window.on_menu["items"] = self._menu_items()

    def _toggle_quiet(self):
        self.config["quiet"] = not self.config["quiet"]
        self.config.save()
        self.window.on_menu["items"] = self._menu_items()

    def _quit(self):
        self._np.stop()
        self.root.destroy()

    # --- soporte ------------------------------------------------------------

    def _load_pack(self, pet_id):
        d = paths.BUNDLED_PETS / pet_id
        if not (d / "pet.json").exists():
            d = paths.BUNDLED_PETS / "astro"
        return voicemod.load_pack(d)

    def _write_pid(self):
        try:
            paths.PID.write_text(str(os.getpid()), encoding="utf-8")
        except OSError:
            pass

    def _clear_pid(self):
        try:
            paths.PID.unlink()
        except OSError:
            pass
