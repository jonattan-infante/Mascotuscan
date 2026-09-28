# EXECUTION-PLAN.md

Plan maestro. **Un estado solo avanza con evidencia**: un comando que se pueda
correr, un archivo que se pueda abrir, o una salida pegada. Sin evidencia, el
estado es "por verificar".

Última revisión: **2026-09-27**

## P0 — Baseline

| # | Cosa | Estado | Evidencia |
|---|---|---|---|
| P0.1 | El paquete compila | verde | `swift build` → `Build complete!` |
| P0.2 | Tests de lógica pura | verde | `swift test` → 52 tests, 0 fallos |
| P0.3 | Tests de hooks de zsh | verde | `./scripts/test-shell-hooks.sh` → 8 ok, salida 0 |
| P0.3b | Tests del instalador | verde | `./scripts/test-installer.sh` → 12 ok, salida 0 |
| P0.3c | Integridad del repo | verde | `./scripts/test-repo-integrity.sh` → 13 ok, salida 0 |
| P0.3d | Mascotas y marketplace | verde | `./scripts/test-pet-packs.sh` → 11 ok, salida 0. Probado que detecta: pack roto, versión desincronizada e id duplicado |
| P0.3e | Port de Windows | verde | `make test-windows` → 51 tests, 0 fallos (2026-09-17); job `port de Windows` en CI, en `windows-latest` |
| P0.3f | La versión es una sola | verde | `./scripts/test-repo-integrity.sh` → `ok version 0.2.0 en VERSION, Paths.swift, __init__.py y CHANGELOG`; probado en negativo: con `__init__.py` en 0.1.0 dice `FALLA la version diverge` |
| P0.8 | `main` protegido | verde | push directo → `remote rejected (protected branch hook declined)`, verificado con `enforce_admins: true` |
| P0.7 | CI en GitHub Actions | verde | 5 jobs en verde el 2026-07-31: build en macos-14 y macos-15, shell, mascotas, vista previa |
| P0.4 | El binario arranca y responde | verde | `./.build/debug/lucy --version` → `lucy 0.2.0`; `python3 windows/pet.py --version` → `lucy 0.2.0` |
| P0.5 | El dibujo se puede revisar sin pantalla | verde | `make render` → 6 PNG de estado + `todos.png` + `panel.png` |
| P0.6 | Working tree limpio | verde | repo recién creado, primer commit |

## Entregado — no re-trabajar

| Cosa | Evidencia |
|---|---|
| Droide vectorial con 6 estados distinguibles | `make render`, revisado a ojo en `render/todos.png` |
| Sprites propios del usuario, con GIF animado | probado sustituyendo `default.png`: el vector desaparece y escala bien |
| Burbuja estilo terminal con escritura letra por letra | `render/burbuja-*.png` en dos avances de escritura |
| Voz generada por Claude Code local, sin API key | `~/.lucy/voice.json`, 64 plantillas, log: `voz cargada: agentDone=8 …` |
| Respaldo estático cuando no hay `voice.json` | primera narración del log usó `Droid`, antes de que terminara la generación |
| Seguimiento en vivo: panel al hover, narración, línea de menú | log: `aviso: [working] *whirr* 3 unidades trabajando: …` |
| Comandos de shell largos y fallos | log: `*bzzzt* npm run build falló con código 1 en Fineract` |
| Puertos que suben y bajan | diff contra `listening_ports` de `cmux rpc workspace.list` |
| Texto real de notificaciones vía RPC | probado con `cmux notify`: la burbuja mostró título y cuerpo |
| Click salta al workspace del aviso | `cmux select-workspace --workspace <uuid>` → `OK workspace:2` |
| Arranque por shell con acceso al socket | ver `docs/adr/0001`; probado: 1 instancia tras abrir dos shells |
| Fallos de socket visibles en pantalla | `noteStreamError` / `noteStreamExit` con burbuja pegajosa |
| Deduplicación de hooks duplicados (`received` + `completed`) | log antes: 2 avisos por evento; después: 1 |
| Barrida de sesiones fantasma a los 10 min | `sweepStaleActivities()`, traza `barrida: N sesión(es) sin señal` |
| Formato de pet pack con validación en la frontera | 21 tests en `PetPackTests`: rutas con `..`, colores, sprites, semver, schema |
| Marketplace: índice JSON, `search` e `install` desde registro, git o ruta local | `registry.json` + 9 tests en `RegistryTests`, dos de ellos validan el registro publicado |
| Dos mascotas incluidas que solo difieren en personalidad | mismo aviso: astro dice "*bzzzt* … Algo no cuadra", gatito dice "… No fui yo" |
| Voz por mascota generada desde `persona.md` | `~/.lucy/voices/gatito.json`, 64 plantillas con voz felina, sin tocar código |
| CLI de mascotas: list, use, info, install, uninstall, new, validate, voice, search | probados a mano sobre la máquina real; salida pegada en claude-progress |
| Cambio de mascota en caliente desde el menú | `switchPet` reactiva tema y voz sin reiniciar el proceso |
| Instalador y desinstalador probados de punta a punta | `./install.sh --from-source` sobre la máquina real: 1 instancia, aviso real entregado. Desinstalación cubierta por 12 casos en sandbox |
| Versión del producto con fuente única y guarda | `VERSION` + `scripts/bump-version.sh`; la integridad compara cuatro sitios y falla en negativo (P0.3f) |
| Aviso de versión nueva, mismo contrato en macOS y Windows | `docs/reference/versioning.md`; 14 tests en `UpdateTests.swift` y 17 en `test_update.py` con los mismos casos; punta a punta con `LUCY_UPDATE_URL=file://…` en la máquina real: `aviso: [info] … 9.9.9` una sola vez, `update.json` con `announced` (ver claude-progress) |
| `lucy update [--check]` y `python install.py --update` | tras publicar `v0.2.0`: `update --check` → `Estás en la última versión publicada`, salida 0. `--update` en Windows solo probado por lectura ⚠️ 2026-09-17 |
| Primer release publicado por tag | `make tag` → `v0.2.0`; run 35236336097 de `release.yml`: `el tag dice lo mismo que el repo`, `binario de macOS`, `publicar el release` en verde; release con `lucy-0.2.0-macos-arm64.tar.gz` y `.sha256` |
| Reglas de tags con verificación y protección | `docs/reference/tags.md`; `scripts/check-tag.sh` (19 casos en `test-release-tooling.sh`, en el gate y en CI); `release.yml` lo exige con `--on origin/main`; ruleset `tags de version` (id 23606182) sobre `refs/tags/v*`, bypass de administrador probado en `v0.2.1`/`v0.2.2` |
| Reglas de tags obligatorias en `CLAUDE.md` para cualquier agente de IA | sección propia con cinco prohibiciones (PR #7); 174 líneas, dentro del límite de 200 |
| `v0.2.2` publicado con release real | run de `release.yml` en verde: `el tag dice lo mismo que el repo`, `binario de macOS`, `publicar el release`; `gh release view v0.2.2` → `draft=false prerelease=false`, assets con tarball y sha256 |
| `lucy update` de punta a punta contra un release real | máquina del autor: `0.2.0` instalado → `update --check` decía "Hay una versión nueva: 0.2.2" → `lucy update` clonó el release y quedó en `lucy 0.2.2` → `update --check` dice "Estás en la última versión publicada" |
| Versión y notas propuestas desde los commits | `make next-version` y `make release-notes` (Conventional Commits → Keep a Changelog), probados en el mismo test |
| Instalador de macOS clona el último release | `install.sh`: resuelve `tag_name` de `releases/latest`, cae a `main` y lo dice; `bash -n` ok. **Sin release publicado aún, la rama `main` es lo que instala** ⚠️ 2026-09-17 |
| Contrato `EventSource` (PR1 de 4): cmux y shell detrás de un adapter, con la cobertura que faltaba | `docs/reference/event-source.md`, `docs/adr/0008`; `CmuxEventSource`/`ShellHookEventSource`/`FileTailer` nuevos; `PetController.ingest(_:)` reemplaza `handleCmuxEvent`/`handleShellEvent`. Cero cambio de comportamiento observable. 35 tests nuevos (`CmuxEventSourceTests` 15, `FileTailerTests` 3, `ShellHookEventSourceTests` 3, `PetControllerIngestTests` 14) — antes de este PR, `PetController`/`+Events`/`+Sources` no tenían ningún test. `make verify` → 119 tests Swift + 51 Python, todo verde |
| `EventSource` en Windows (PR2 de 4): `Tailer` con parser inyectable y campo `agent` | `Tailer(path, parse=...)`, default `parse_line`; `App.__init__(sources=[...])` reemplaza `tailer=`; `state.py:Session.agent` reemplaza la constante `_agent()`. 3 tests nuevos (`test_parse_is_injectable`, dos en `test_state.py`) — sin `test_app.py`: ningún test de este runtime toca `tk.Tk()` y el `tick()` que reparte sobre `sources` no tiene lógica propia. `make test-windows` → 54 tests, 0 fallos |
| Skeleton de `WmuxEventSource` (PR4 de 4) | `start()` llama `onUnavailable` y nunca `onEvent`; no está en `makeEventSources()`. 2 tests (`WmuxEventSourceTests`): avisa no-disponible sin emitir eventos, y no aparece en la lista por defecto. Decisión explícita: OpenCode (PR3) queda pendiente porque no hay cómo probar el plugin contra una instalación real |
| Responder permiso/pregunta (PR1 de 2, `docs/adr/0009`): plomería sin UI | `docs/reference/agent-reply.md`; `NormalizedEvent.requestId` extraído de `_opencode_request_id` en `CmuxEventSource.translate()`; `PetController.pendingRequests` poblado en `ingest(_:)`, con barrida (`sweepExpiredRequests`); `PetController+Actions.swift`: `fetchPendingContent`/`replyPermission`/`replyQuestion`. Esquema real de `feed.permission.reply`/`feed.question.reply` verificado a mano contra el propio error de validación del RPC (sin tocar ningún permiso/pregunta real). 10 tests nuevos. `make verify` → 132 tests Swift + 54 Python, todo verde. Sin cambio visible todavía: la burbuja no muestra botones hasta PR2 |
| Responder permiso/pregunta (PR2 de 2, `docs/adr/0009`): botones en la burbuja | `BubbleView` gana sus primeras sub-regiones clicables (`BubbleOption`, una línea por opción, mismo motor de `docs/adr/0003`); `PetController.respondToOption`/`showPendingRequest`; costura de test `fetchPendingContent` (mismo patrón que `isCmuxFrontmost`). 11 tests nuevos (`BubbleViewTests` 3, `summarizeToolInput` 3, wiring en `PetControllerIngestTests` 5). `make render` → `burbuja-pendiente-0.png`/`-1.png`, revisadas a ojo. `make verify` → 143 tests Swift + 54 Python, todo verde. ⚠️ Falta la verificación de punta a punta contra un permiso/pregunta real (ver `docs/reference/agent-reply.md`) |
| Renombrado a MascoTuscan, comando `mascotuscan` (`docs/adr/0010`), con migración encadenada `~/.lucy` y `~/.cmux-pet` → `~/.mascotuscan` | en Linux, 2026-09-27: `make test-windows` → 61 tests (7 nuevos: `test_paths.py` y hooks con nombre anterior en `test_install.py`); `test-installer.sh` → 24 ok con `sed` de GNU en lugar del de BSD (10 nuevos: migra `~/.lucy`, quita su enganche del zshrc, un solo backup con el original) y 5 de ellos fallan si se vacía `LEGACY_NAMES`; `test-shell-hooks.sh` → 8 ok; `test-repo-integrity.sh` → ok; `test-release-tooling.sh` → 19 ok; `install.py` sobre un `HOME` falso con `.lucy` y el hook viejo registrado → migrado, hook reemplazado, el ajeno intacto. Swift en CI (run 36293399797 del PR #17, 6 checks en verde): 148 tests con los 5 de `PathsTests`, `mascotuscan 0.3.0` en release, `test-installer.sh` 24 ok con el `sed` de BSD. Mergeado como `0a6bf04` |

## En vuelo

| # | Cosa | Estado | Próximo paso concreto |
|---|---|---|---|
| F1 | Mascotas con arte propio | el renderer `sprites` funciona, pero ningún pack incluido lo usa | hacer un pack de ejemplo con sprites, aunque sean formas simples, para que se vea el camino |
| F2 | Más renderers integrados | hay `vector:droid`, `vector:ball` y `vector:sage` | portar `ball` y `sage` al Canvas de Windows |
| F3 | OpenCode sobre el contrato `EventSource` (PR3 de `docs/adr/0008`) | PR1, PR2 y PR4 (wmux) entregados; PR3 en espera de poder probar el plugin contra una instalación real de OpenCode | escribir `bridges/opencode/mascotuscan-bridge.js` y los dos adapters cuando haya cómo verificarlo |
| F5 | Renombrado a MascoTuscan (`docs/adr/0010`): pasos fuera del repo | repo renombrado a `Mascotuscan`; PR #17 mergeado con CI en verde; versión `0.4.0` preparada en su PR | mergear el PR de `0.4.0` y `make tag`; en la máquina del autor, `lucy update` y confirmar `~/.mascotuscan`, el zshrc y `mascotuscan --version` ⚠️ 2026-09-27 |
| F6 | Claude atiende issues dentro de un harness (`docs/adr/0011`, `docs/reference/claude-issues.md`) | en `main` desde #19 y probado en GitHub el 2026-09-28 con #20, #21 y #22: aprobación, las tres rutas, caso hostil sin fugas, token de solo lectura sin intentos de escritura (detalle en `docs/reference/claude-issues.md` §Verificado en GitHub). Tres mejoras de esas corridas en la rama siguiente | probar un error evidente real para ver el PR y el CI por `workflow_dispatch`, y un rechazo de `implementar` ⚠️ 2026-09-28 |
| F4 | Responder permiso/pregunta desde la burbuja (`docs/adr/0009`): verificación real pendiente | PR1 y PR2 entregados (plomería + botones), `make verify` en verde | probar a mano contra un permiso/pregunta real (workspace descartable): clic en la burbuja, confirmar en el pane que el agente siguió con esa respuesta |


## Riesgos

| # | Riesgo | Impacto | Mitigación actual |
|---|---|---|---|
| R1 | Si se cierra el pane que lanzó el asistente, el proceso queda hijo de launchd; un respawn del stream sería rechazado por el socket | pierde eventos en silencio | `--reconnect` mantiene la conexión original; `noteStreamExit` avisa en pantalla si el stream muere dos veces seguidas. **Sin verificar en la práctica** ⚠️ 2026-07-31 |
| R2 | El formato de eventos de cmux puede cambiar entre versiones | el asistente deja de reportar | `docs/reference/cmux-events.md` documenta lo verificado con fecha y versión; el fallo es visible, no silencioso |
| R3 | La generación de voz consume cuota del usuario | molestia | una llamada cada 7 días; se puede apagar borrando `voice.json` y no regenerando |
| R5 | Un pack del marketplace trae arte de un personaje con dueño | problema legal para el autor y para el índice | regla explícita en `docs/marketplace.md`, revisión en el PR, y se quita del índice al detectarlo. **Depende de revisión humana** ⚠️ 2026-07-31 |
| R6 | Un pack malicioso apunta sprites fuera de su carpeta | leer archivos del usuario | `..` prohibido en rutas, cubierto por test. Un pack no ejecuta código: solo aporta texto e imágenes |
| R7 | El registro crece y el `git clone --depth 1` por install se vuelve costoso | instalación lenta | hoy son 2 entradas; si crece, cachear o servir tarballs (B11) |
| R8 | `release.yml` falla en un tag | no hay release y nadie recibe el aviso; el instalador sigue en la última publicada | ocurrió de verdad en `v0.2.1`: `check-tag.sh` en CI daba "tag ligero" por un artefacto de checkout de GitHub Actions (R11). Corregido y verificado en `v0.2.2` |
| R10 | El bypass del ruleset de tags no aplica al dueño y `make tag` no puede empujar | el tag queda en local; nada publicado | verificado con `v0.2.1` y `v0.2.2`: GitHub reporta "Bypassed rule violations", el bypass del rol administrador funciona |
| R11 | GitHub Actions entrega el ref de un tag apuntando al commit, no al objeto tag anotado | `check-tag.sh` en CI rechaza cualquier tag real como "ligero" | `git fetch --tags --force origin` tras el checkout, antes de verificar; documentado en `release.yml` y en el CHANGELOG de `0.2.2` |
| R12 | Entre el merge del renombrado y el primer release con el nombre nuevo, `install.sh` de `main` clona el último release, que compila `lucy` y no `mascotuscan` | `curl ... \| bash` falla con "no encuentro el binario compilado" | falla visible, no silenciosa; `lucy update` no reinstala mientras no haya versión más nueva. Publicar justo después del merge (F5) |
| R13 | Un issue hostil (prompt injection) engaña a Claude en el harness de issues | un diagnóstico o un parche que no corresponde | Claude no tiene comandos, red ni escritura; la guardia y el escaneo de secretos son código con tests; `evaluar` y todo cambio estructural esperan aprobación; ningún PR se mergea solo |
| R9 | La burbuja de actualización en Tk (Windows) no se ha visto en una máquina Windows real | el aviso podría no mostrarse aunque la lógica esté probada | la lógica pura tiene 17 tests y `Checker` está probado con `file://`; falta `--selftest` con `LUCY_UPDATE_URL` en Windows ⚠️ 2026-09-17 |

## Backlog

Ordenado por relación valor/esfuerzo, no por antojo.

| # | Cosa | Por qué | Esfuerzo |
|---|---|---|---|
| B10 | Más renderers integrados (`vector:gato`, `vector:blob`) | hoy un pack sin arte solo puede verse como droide, aunque hable como gato | medio |
| B11 | Página del marketplace con capturas de cada mascota | el índice JSON no deja ver cómo se ven; una galería sí | medio |
| B1 | Sonido opcional por estado | un aviso visual en la esquina se pierde si miras otra pantalla | bajo |
| B2 | Click derecho en el panel de estado → saltar a ese agente | el panel ya sabe el workspace de cada uno | bajo |
| B3 | Recarga en caliente de `config.json` | hoy hay que reiniciar para cambiar `narrateEverySeconds` | bajo |
| B5 | Soporte de otros shells (bash, fish) | hoy solo zsh; bash necesita `trap DEBUG` + `PROMPT_COMMAND` | medio |
| B6 | Migrar a concurrencia estricta de Swift 6 | hoy el paquete fija `swiftLanguageVersions: [.v5]` | medio |
| B7 | Avisos comentados por el modelo con los datos reales | más gracia, pero cuesta latencia; ver `docs/adr/0002` | medio |
| B8 | Fórmula de Homebrew | `brew install` es lo que espera la gente; el release ya adjunta el tarball con su sha256 | medio |
| B12 | Que el instalador de macOS use el tarball del release en vez de compilar | instalar sin Xcode; depende de firmar (B9) | medio |
| B13 | Marcar el job `port de Windows` como check obligatorio en `main` | hoy son cuatro checks obligatorios; se cambia en Settings > Branches | bajo |
| B14 | Registrar la llave SSH como signing key en GitHub | hoy los tags firmados se verían "Unverified"; `gh ssh-key add --type signing` necesita el scope `admin:ssh_signing_key` | bajo |
| B15 | Job que publique solo (`next-version` + `release-notes` + PR + `make tag` con llave propia) | hoy las notas las reescribe una persona; ver `docs/reference/tags.md` §Automatizar | medio |
| B9 | Empaquetar como `.app` firmada | necesario si algún día se distribuye fuera de GitHub | alto |
