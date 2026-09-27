# Punto de entrada de la mascota de Windows.
#
#   python pet.py              arranca la mascota flotante
#   python pet.py --selftest   prueba de humo sin bloquear: alimenta eventos
#                              sinteticos, verifica los estados y sale
#   python pet.py --version    imprime la version del producto
#
# La logica vive en el paquete mascotuscan_win para que sea testeable; este archivo
# solo arranca (como main.swift en macOS).

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# Antes de tkinter: --version tiene que responder aunque falte la UI.
if "--version" in sys.argv:
    from mascotuscan_win import __version__
    print(f"mascotuscan {__version__}")
    raise SystemExit(0)

import tkinter as tk  # noqa: E402

from mascotuscan_win.app import App          # noqa: E402
from mascotuscan_win.config import Config    # noqa: E402
from mascotuscan_win.state import Mood        # noqa: E402
from mascotuscan_win.events import Tailer     # noqa: E402


def selftest() -> int:
    """ Construye la ventana real, le mete una secuencia de eventos por un
    archivo temporal y verifica que los estados y la burbuja responden. Prueba
    el pipeline completo (tail -> estado -> voz -> dibujo) sin abrir mainloop. """
    import json
    import tempfile

    tmp = Path(tempfile.mkdtemp()) / "shell.jsonl"
    tmp.write_text("", encoding="utf-8")

    root = tk.Tk()
    app = App(root, config=Config(), tailer=Tailer(tmp))

    def emit(ev):
        with tmp.open("a", encoding="utf-8") as f:
            f.write(json.dumps(ev) + "\n")

    def frame(now):
        mood = app.tick(now=now)
        root.update()      # fuerza el dibujo real en el canvas
        return mood

    checks = []
    t = 1000.0

    frame(t)  # arranque: saludo

    # Cada estado se prueba limpio. Se ordena para que las ventanas de tiempo no
    # se pisen: error > done por prioridad, asi que 'done' se verifica antes de
    # que exista cualquier error.
    emit({"event": "PreToolUse", "session": "a", "cwd": "C:/code/Fineract", "tool": "Bash"})
    checks.append(("working", frame(t + 1)))

    emit({"event": "Stop", "session": "a", "cwd": "C:/code/Fineract"})
    checks.append(("done", frame(t + 2)))

    emit({"event": "Notification", "session": "b", "cwd": "C:/code/Backend",
          "message": "Claude needs permission to run Bash"})
    checks.append(("attention", frame(t + 3)))

    emit({"event": "UserPromptSubmit", "session": "b"})   # respondiste: se limpia
    emit({"event": "PostToolUse", "session": "b", "cwd": "C:/code/Backend",
          "tool": "Bash", "ok": False, "exit": 1, "cmd": "npm test"})
    checks.append(("error", frame(t + 4)))

    # Hover: el roster debe listar sesiones sin reventar.
    app.window._hovering = True
    app.window.set_roster(app.sm.roster(t + 4))
    app.window.render(t + 4)
    root.update()

    idle = frame(t + 1000)   # todo decae a reposo
    checks.append(("idle", idle))

    root.destroy()

    ok = True
    for expected, got in checks:
        status = "ok" if got == expected else "FALLO"
        if got != expected:
            ok = False
        print(f"  [{status}] esperado={expected:10s} obtuvo={got}")
    print("selftest:", "OK" if ok else "FALLO")
    return 0 if ok else 1


def _make_dpi_aware() -> None:
    # Sin esto, Tk puede reportar un tamano de pantalla escalado/erroneo al
    # arrancar y la ventana termina fuera de vista (bug de la mascota que se iba
    # a la esquina superior). Marcar el proceso DPI-aware lo estabiliza.
    import ctypes
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    _make_dpi_aware()
    root = tk.Tk()
    App(root).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
