# Instalador de mascotuscan para Windows.
#
# Registra los hooks de Claude Code que alimentan a la mascota y prepara
# %USERPROFILE%\.mascotuscan. Idempotente: correrlo dos veces no duplica nada.
#
#   python install.py            # instalar los hooks en ~/.claude/settings.json
#   python install.py --uninstall
#   python install.py --update     # mover el checkout a la ultima version publicada
#   python install.py --settings <ruta>   # para pruebas
#
# El instalador va en Python (no en PowerShell) porque Python ya es requisito de
# la mascota y el merge de settings.json es mas seguro asi. El hook en si
# (mascotuscan-hook.ps1) si es PowerShell: lo ejecuta Claude Code en cada evento.

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from mascotuscan_win import paths

HERE = Path(__file__).resolve().parent
HOOK = HERE / "hooks" / "mascotuscan-hook.ps1"

# Todos los eventos que la mascota entiende. Los de herramienta llevan matcher "".
TOOL_EVENTS = ["PreToolUse", "PostToolUse"]
PLAIN_EVENTS = ["SessionStart", "SessionEnd", "UserPromptSubmit",
                "Notification", "Stop", "SubagentStop"]
ALL_EVENTS = TOOL_EVENTS + PLAIN_EVENTS

MARK = "mascotuscan-hook.ps1"   # firma para reconocer nuestros hooks al desinstalar
# El hook se llamo asi con los nombres anteriores del producto. Una instalacion
# vieja los dejo registrados apuntando a un archivo que ya no existe: se quitan
# igual que los actuales, y nunca se registran de nuevo.
LEGACY_MARKS = ("lucy-hook.ps1", "cmux-pet-hook.ps1")


def hook_command(hook_path: Path) -> str:
    return ('powershell -NoProfile -ExecutionPolicy Bypass -File '
            f'"{hook_path}"')


def _is_ours(command: str) -> bool:
    return any(m in command for m in (MARK, *LEGACY_MARKS))


def _has_our_hook(entries) -> bool:
    for entry in entries or []:
        for h in entry.get("hooks", []):
            if MARK in str(h.get("command", "")):
                return True
    return False


def _strip_our_hooks(entries):
    out = []
    for entry in entries or []:
        kept = [h for h in entry.get("hooks", []) if not _is_ours(str(h.get("command", "")))]
        if kept:
            e = dict(entry)
            e["hooks"] = kept
            out.append(e)
    return out


def merge(settings: dict, hook_path: Path, uninstall: bool = False) -> dict:
    """ Devuelve settings con nuestros hooks agregados (o quitados). Idempotente:
    no duplica, y respeta cualquier hook ajeno que ya exista. """
    settings = dict(settings or {})
    hooks = dict(settings.get("hooks") or {})
    cmd = hook_command(hook_path)

    for event in ALL_EVENTS:
        entries = list(hooks.get(event) or [])
        entries = _strip_our_hooks(entries)   # siempre limpiamos los nuestros primero
        if not uninstall:
            spec = {"type": "command", "command": cmd}
            if event in TOOL_EVENTS:
                entries.append({"matcher": "", "hooks": [spec]})
            else:
                entries.append({"hooks": [spec]})
        if entries:
            hooks[event] = entries
        else:
            hooks.pop(event, None)

    if hooks:
        settings["hooks"] = hooks
    else:
        settings.pop("hooks", None)
    return settings


def _git(*args, cwd: Path):
    return subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True)


def update_checkout(repo_root: Path, tag: str) -> int:
    """ Mueve el checkout al tag publicado. La mascota corre desde el checkout,
    asi que esto ES la actualizacion en Windows. No toca un arbol con cambios
    locales: pisarle trabajo a alguien es peor que no actualizar. """
    if not (repo_root / ".git").exists():
        print("este mascotuscan no es un clon de git, asi que no puedo moverlo solo.")
        print(f"  descarga la version: https://github.com/jonattan-infante/mascotuscan/releases/tag/{tag}")
        return 1
    dirty = _git("status", "--porcelain", cwd=repo_root)
    if dirty.returncode != 0:
        print(f"error: git no responde en {repo_root}: {dirty.stderr.strip()}", file=sys.stderr)
        return 1
    if dirty.stdout.strip():
        print("error: hay cambios sin commit en el checkout; guardalos o descartalos y vuelve a correr.",
              file=sys.stderr)
        return 1
    fetch = _git("fetch", "--tags", "--quiet", "origin", cwd=repo_root)
    if fetch.returncode != 0:
        print(f"error: no pude traer los tags: {fetch.stderr.strip()}", file=sys.stderr)
        return 1
    co = _git("checkout", "--quiet", tag, cwd=repo_root)
    if co.returncode != 0:
        print(f"error: no pude cambiar a {tag}: {co.stderr.strip()}", file=sys.stderr)
        return 1
    print(f"checkout en {tag}")
    return 0


def stop_running_pet(home: Path = paths.HOME) -> None:
    """ La mascota vieja sigue en memoria con el codigo viejo. Se le pide salir
    por su pid; el hook SessionStart arranca la nueva en la proxima sesion. """
    pid_file = home / "pet.pid"
    try:
        pid = int(pid_file.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return
    try:
        if os.name == "nt":
            # taskkill /F no le deja a la mascota borrar su pid.pid, asi que uno
            # viejo es comun y Windows reusa los pid: solo si es un python.
            if not _is_python_process(pid):
                return
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
        else:
            os.kill(pid, 15)
        pid_file.unlink(missing_ok=True)
        print("mascota anterior detenida; arranca sola en tu proxima sesion de Claude Code")
    except OSError:
        pass


def _is_python_process(pid: int) -> bool:
    out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    return out.strip().strip('"').lower().startswith("python")


def default_settings_path() -> Path:
    return Path(os.path.expanduser("~")) / ".claude" / "settings.json"


def load_settings(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            print(f"aviso: {path} no es JSON valido; se respalda y se recrea",
                  file=sys.stderr)
            path.replace(path.with_suffix(".json.bak"))
    return {}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Instala los hooks de mascotuscan para Claude Code")
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("--update", action="store_true",
                    help="mover este checkout a la ultima version publicada")
    ap.add_argument("--settings", default=None, help="ruta a settings.json (default ~/.claude)")
    args = ap.parse_args(argv)

    if not HOOK.exists():
        print(f"error: no encuentro el hook en {HOOK}", file=sys.stderr)
        return 1

    if args.update:
        sys.path.insert(0, str(HERE))
        from mascotuscan_win import update as updatemod, __version__
        current = updatemod.parse(__version__)
        latest, problem = updatemod.fetch_latest()
        print(f"mascotuscan {__version__}")
        if problem:
            print(f"  {problem}")
            return 1
        if current and latest <= current:
            print("estas en la ultima version publicada.")
            return 0
        print(f"hay una version nueva: {updatemod.fmt(latest)}")
        code = update_checkout(HERE.parent, "v" + updatemod.fmt(latest))
        if code != 0:
            return code
        stop_running_pet()
        # Los hooks apuntan a una ruta absoluta que no cambio, pero una version
        # nueva puede traer eventos nuevos: se re-registran, es idempotente.

    settings_path = Path(args.settings) if args.settings else default_settings_path()
    settings_path.parent.mkdir(parents=True, exist_ok=True)

    settings = load_settings(settings_path)
    updated = merge(settings, HOOK, uninstall=args.uninstall)
    settings_path.write_text(json.dumps(updated, indent=2, ensure_ascii=False),
                             encoding="utf-8")

    # Preparar el estado en disco de la mascota. Si viene de un nombre anterior
    # del producto, se migra en vez de empezar de cero. La mascota vieja corre
    # desde ese directorio y Windows no deja moverlo con archivos abiertos: se
    # detiene primero. Si aun asi falla, crear el directorio nuevo dejaria el
    # viejo huerfano para siempre, asi que se para y se dice.
    legacy = next((d for d in paths.LEGACY_HOMES if d.exists()), None)
    if legacy is not None and not paths.HOME.exists():
        stop_running_pet(legacy)
        if paths.migrate_legacy_home() is None:
            print(f"error: no pude mover {legacy} a {paths.HOME}. "
                  "Cierra la mascota y vuelve a correr esto.", file=sys.stderr)
            return 1
        print(f"migrado {legacy} -> {paths.HOME}")
    paths.VOICES.mkdir(parents=True, exist_ok=True)

    if args.uninstall:
        print(f"listo: hooks de mascotuscan quitados de {settings_path}")
        return 0

    if args.update:
        print(f"listo: actualizado y hooks al dia en {settings_path}")
        return 0

    print(f"listo: hooks de mascotuscan instalados en {settings_path}")
    print("")
    print("La mascota arranca sola en tu proxima sesion de Claude Code.")
    print("Para lanzarla ahora mismo:")
    print(f"    python \"{HERE / 'pet.py'}\"")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
