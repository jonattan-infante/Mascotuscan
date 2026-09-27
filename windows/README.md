# MascoTuscan para Windows

Una mascota flotante que te cuenta qué está haciendo **Claude Code** en Windows.

cmux solo existe en macOS, así que en Windows no hay `cmux events` que traducir.
Este port mantiene la misma idea del proyecto (el programa decide **cuándo**
hablar; el pet pack decide **cómo se ve y cómo habla**) pero cambia la fuente:
en vez de cmux, observa a **Claude Code** a través de sus *hooks*.

```
Claude Code hooks (PowerShell)
        │  cada evento -> una linea JSON
        ▼
%USERPROFILE%\.mascotuscan\shell.jsonl
        │  tail
        ▼
   la mascota (tkinter)  ->  uno de seis estados  ->  pet pack (astro / gatito)
```

Windows 10/11 · Python 3 (viene tkinter) · sin dependencias que instalar.

## Qué reusa del proyecto y qué cambia

| Contrato del proyecto | En Windows |
|---|---|
| Los seis estados (`idle`, `working`, `done`, `error`, `attention`, `info`) | idénticos: el vocabulario es del sistema |
| El pet pack (`pet.json`, `phrases.json`, `persona.md`) | se cargan **los mismos** `pets/astro` y `pets/gatito` del repo |
| Las plantillas con marcadores (`{agent}`, `{cmd}`, `{where}`...) | idénticas; la voz sale del pack, no del código |
| Fuente de eventos: cmux (`events` + `rpc`) | **Claude Code hooks** escribiendo `shell.jsonl` |
| Estado en disco bajo `~/.mascotuscan` | `%USERPROFILE%\.mascotuscan` |
| UI en AppKit (`NSPanel`, `NSView`) | tkinter (`Canvas`, `-transparentcolor`) |
| Arranque desde el shell (no launchd) | autoarranque desde el hook `SessionStart` |
| Aviso de versión nueva (`docs/reference/versioning.md`) | idéntico: mismo endpoint, mismo `update.json`, mismos casos de prueba |

Una diferencia a favor de Windows: los hooks de Claude Code **sí** entregan
`tool_input`, así que el aviso de un comando que falla puede mostrar el comando
real. En cmux ese campo viene redactado.

## Instalar

Necesitas Python 3 (tkinter viene incluido en el instalador oficial de Windows)
y Claude Code.

```powershell
python install.py
```

Eso registra los hooks en `~\.claude\settings.json` (respetando los que ya
tengas) y prepara `%USERPROFILE%\.mascotuscan`. La mascota arranca sola en tu
próxima sesión de Claude Code, en la esquina inferior derecha.

Para lanzarla ahora mismo, sin esperar:

```powershell
python pet.py
```

Para quitar los hooks:

```powershell
python install.py --uninstall
```

## Actualizar

La mascota avisa una vez cuando hay una versión publicada más nueva que la que
corre (el contrato es el mismo que en macOS: `docs/reference/versioning.md`).
Como en Windows corre desde este checkout, actualizar es moverlo al tag publicado:

```powershell
python install.py --update     # git fetch + checkout vX.Y.Z, re-registra hooks
python pet.py --version        # que version corre
```

`--update` se niega si hay cambios sin commit en el checkout. La comprobación se
apaga con `"checkUpdates": false` en `config.json`.

**Si venías de LucyGlow**: el `--update` de esa versión corre con su código
viejo y vuelve a registrar `lucy-hook.ps1`, que ya no existe. Corre
`python install.py` una vez más: reemplaza los hooks por `mascotuscan-hook.ps1`,
detiene la mascota vieja y mueve `%USERPROFILE%\.lucy` a
`%USERPROFILE%\.mascotuscan`. Ver `docs/adr/0010`.

## Qué hace

- **Avisa cuando Claude termina** su turno (`Stop`), y en qué workspace.
- **Se pone en alerta** cuando pide permiso o hace una pregunta (`Notification`)
  y se queda así hasta que respondes.
- **Avisa de un comando que falla** (`PostToolUse` con error), con el comando real.
- **Te dice en qué va**: pasa el mouse por encima y ves cada sesión, qué está
  haciendo y cuántos pasos lleva.
- **Un click** abre en el Explorador la carpeta del último aviso.
- **Click derecho**: cambiar de mascota, silenciar avisos, salir.
- **Arrastrar**: la mueves; recuerda la posición.

Cada sesión de Claude Code cuenta como un "agente": si corres varias en
paralelo, el estado global es la prioridad más alta entre todas
(`attention > error > working > done > info > idle`).

## Elegir mascota

Vienen las dos incluidas del repo. Click derecho sobre la mascota para cambiar,
o edita `%USERPROFILE%\.mascotuscan\config.json`:

```json
{
  "activePet": "gatito",
  "quiet": false,
  "narrateEverySeconds": 150,
  "position": null,
  "checkUpdates": true
}
```

## Cómo está hecho

Todo el código está en `mascotuscan_win/`, dividido igual que el proyecto macOS:

| Archivo | Qué vive ahí | Equivalente macOS |
|---|---|---|
| `paths.py` | rutas bajo `%USERPROFILE%\.mascotuscan` | `Support/Paths.swift` |
| `wording.py` | texto neutro del programa (verbo por herramienta) | `Voice/Wording.swift` |
| `events.py` | parseo de `shell.jsonl` y tail sin bloquear | `PetController+Sources.swift` |
| `state.py` | los seis estados y la máquina que los resuelve | `Model/Mood.swift` + Controller |
| `voice.py` | carga del pet pack y relleno de plantillas | `Voice/Voice.swift` + `Model/PetPack.swift` |
| `config.py` | `config.json` | `Model/Config.swift` |
| `update.py` | versión publicada, regla de silencio, estado `update.json` | `Model/Update.swift` |
| `ui.py` | ventana flotante, droide vectorial, burbuja, roster | `Views/` |
| `app.py` | orquestador: conecta fuente, estado y vista | `Controller/PetController.swift` |
| `hooks/mascotuscan-hook.ps1` | el hook que Claude Code ejecuta en cada evento | `shell/pet.zsh` |
| `install.py` | registra los hooks en `settings.json` | `install.sh` |

## Verificar

Sin dependencias externas: solo la stdlib de Python.

```powershell
python -m unittest discover -s tests -p "test_*.py"   # logica pura
python pet.py --selftest                              # pipeline completo + dibujo real
```

`--selftest` construye la ventana de verdad, le mete una secuencia de eventos por
un `shell.jsonl` temporal y verifica que los seis estados responden y que el
canvas dibuja sin errores. Es el análogo de `make render`: no hace falta pedir
capturas.

## Límites conocidos de este port

- El renderer vectorial es una adaptación a `Canvas`: colores planos en vez de los
  gradientes de AppKit. Se ve fiel, pero no idéntico.
- Renderers soportados: `vector:droid`, `vector:llama` y `sprites` (PNG y GIF
  animado, con `tkinter` puro, respetando la transparencia). `vector:ball` y
  `vector:sage` aún no están portados.
- El click abre la carpeta en el Explorador; no trae la terminal al frente (en
  cmux eso lo hace el `rpc`, que aquí no existe).
- La detección de "comando falló" es de mejor esfuerzo: depende de lo que Claude
  Code ponga en `tool_response`.
