# Rutas del asistente en Windows. Analogo de Support/Paths.swift.
#
# Todo el estado en disco vive bajo %USERPROFILE%\.mascotuscan, igual que la
# version de macOS usa ~/.mascotuscan. El repo nunca escribe ahi.

import os
import sys
from pathlib import Path

HOME = Path(os.path.expanduser("~")) / ".mascotuscan"
# Los nombres anteriores del producto escribian aqui, del mas reciente al mas
# viejo: LucyGlow en .lucy y cmux-pet en .cmux-pet. Ver ensure_home().
LEGACY_HOMES = [Path(os.path.expanduser("~")) / name for name in (".lucy", ".cmux-pet")]

CONFIG = HOME / "config.json"
SHELL_LOG = HOME / "shell.jsonl"
PID = HOME / "pet.pid"
NOTEBOOK = HOME / "notebook.json"
SPRITES = HOME / "sprites"
VOICES = HOME / "voices"
LOG = HOME / "pet.log"
REMINDER_WAV = HOME / "reminder.wav"
# Misma forma en macOS y Windows: ver docs/reference/versioning.md.
UPDATE = HOME / "update.json"


def migrate_legacy_home(home: Path = HOME, candidates=None):
    """ Mueve a `home` el primer directorio viejo que exista y lo devuelve. Si
    `home` ya existe no toca nada: mezclar dos estados podria pisar el nuevo
    con el viejo. Mismos casos que Support/Paths.swift. """
    if home.exists():
        return None
    for old in (LEGACY_HOMES if candidates is None else candidates):
        if not old.exists():
            continue
        # rename y no shutil.move: si Windows tiene un archivo abierto, move
        # copia y luego borra a medias. Mejor no migrar y decirlo.
        try:
            old.rename(home)
            return old
        except OSError as e:
            print(f"no pude migrar {old} a {home}: {e}", file=sys.stderr)
            return None
    return None


def ensure_home() -> None:
    # Migrar en vez de empezar de cero: nadie deberia perder su configuracion,
    # sus mascotas o sus frases generadas solo porque el producto cambio de
    # nombre.
    migrate_legacy_home()
    HOME.mkdir(parents=True, exist_ok=True)
    VOICES.mkdir(parents=True, exist_ok=True)


def voice_file(pet_id: str) -> Path:
    return VOICES / f"{pet_id}.json"


# Las mascotas incluidas viven en el repo, no en disco del usuario: windows/ y
# pets/ son hermanos. Se resuelve relativo a este archivo para que funcione sin
# importar desde donde se lance.
REPO_ROOT = Path(__file__).resolve().parents[2]
BUNDLED_PETS = REPO_ROOT / "pets"
