# EXECUTION-PLAN.md

Plan maestro y hoja de ruta. **Un estado solo avanza con evidencia**: un comando
que se pueda correr, un archivo que se pueda abrir, o una salida pegada. Sin
evidencia, el estado es "por verificar".

Última revisión: **2026-11-16**

Cómo leerlo: **P0** dice si se puede trabajar; **En vuelo** es lo que sigue, en
orden de prioridad; **Entregado** no se re-trabaja; **Backlog** es lo que viene
después, ordenado por valor sobre esfuerzo.

## P0 — Baseline

| # | Cosa | Estado | Evidencia (2026-11-15) |
|---|---|---|---|
| P0.1 | Compila y pasan los tests de Swift | verde en `macos-15` | corrida 43789379493 de `verify` sobre `main` (`b431d5c`): `Executed 157 tests, with 0 failures`, `swift build -c release` ok |
| P0.2 | El binario arranca y responde | verde | misma corrida, paso "El binario responde": `mascotuscan 0.4.0` |
| P0.3 | Port de Windows | verde | `make test-windows` → `Ran 61 tests ... OK`; job `port de Windows` en verde en la corrida 43789379493 |
| P0.4 | Harness de issues y revisor de PRs | verde | `python3 -m unittest discover -s scripts/tests` → `Ran 106 tests ... OK` |
| P0.5 | Herramientas de publicación | verde | `./scripts/test-release-tooling.sh` → 19 ok, salida 0 |
| P0.6 | Integridad del repo y la versión es una sola | verde | `./scripts/test-repo-integrity.sh` → `ok version 0.4.0 en VERSION, Paths.swift, __init__.py y CHANGELOG`, `ok cero emojis` |
| P0.7 | CI en GitHub Actions | **rojo en `main`**, verde en #28 | GitHub ya no acepta `macos-14`: cada job ahí termina con `The configuration 'macos-14-arm64-us-default' is not supported` (corrida 43789379493). En #28, con `macos-15`/`macos-26`, todos los jobs en verde (corrida 43789896230). Se cierra al mergear #28 (F1) |
| P0.8 | `main` protegido | verde | `gh api .../branches/main/protection/required_status_checks` → `build y tests (macos-15)`, `build y tests (macos-26)`, `shell e instalador`, `mascotas y marketplace` (desde 2026-11-16); push directo → `remote rejected (protected branch hook declined)`, con `enforce_admins: true` |
| P0.9 | Working tree limpio | verde | `git status --short` vacío en `main` |

Hasta que entre #28, un PR basado en `main` no puede pasar los checks obligatorios:
su `ci.yml` todavía pide `macos-14`. Al entrar #28, cada PR abierto se actualiza
contra `main`.

## En vuelo

En orden de prioridad. El primero bloquea a los demás.

| # | Cosa | Estado | Próximo paso concreto |
|---|---|---|---|
| F1 | **Publicar `0.4.0` y que CI publique cada versión** (`docs/adr/0013`) | PR #28 abierto y en verde: runners a `macos-15`/`macos-26`, `publicar.yml` y `scripts/tag-release.sh`. `VERSION` dice `0.4.0` desde el 2026-09-27 (#18), pero el último release es `v0.3.0` (`gh release list`); mientras tanto `curl ... \| bash` falla (R12). Configuración de una vez aplicada el 2026-11-16: checks obligatorios con `macos-26`, environment `release` (`protected_branches: true`), deploy key `publicar version (CI)` con escritura, secreto `RELEASE_SSH_KEY` en el environment y bypass `DeployKey` en el ruleset 23606182 | revisar y mergear #28; confirmar que `publicar.yml` crea `v0.4.0`, que el push con la deploy key dispara `release.yml` y `gh release view v0.4.0` |
| F2 | Migración de la máquina del autor a MascoTuscan (`docs/adr/0010`) | depende de F1: `lucy update` solo migra cuando existe un release `mascotuscan` | `lucy update`; confirmar `~/.mascotuscan`, que el zshrc tiene solo el enganche nuevo y que `mascotuscan --version` responde |
| F3 | La mascota recorre la pantalla mientras trabaja (`roam`) | PRs #26 y #27 abiertos desde el 2026-09-28; `claude/revision` en `failure` porque nadie aprobó la corrida | tras F1, actualizarlos contra `main` (heredan los runners nuevos), poner `claude:revisar` y revisar |
| F4 | Revisor de PRs como check obligatorio (`docs/adr/0012`) | en `main` desde #24; ya corrió en GitHub sobre #25 y #26 (`gh run list -w "claude revisa PRs"`). `claude/revision` no está entre los checks obligatorios | agregarlo en *Settings > Branches* y verificar los cuatro puntos de `docs/reference/claude-revision.md` §Sin verificar todavía |
| F5 | Responder permiso/pregunta desde la burbuja: prueba real (`docs/adr/0009`) | código y botones en `main` (#15, #16); probado contra el RPC, no contra un permiso real ⚠️ 2026-09-27 | en un workspace descartable, provocar un permiso, hacer clic en la burbuja y confirmar en el pane que el agente siguió con esa respuesta |
| F6 | Harness de issues: las rutas que faltan (`docs/adr/0011`) | probado en GitHub con #20, #21 y #22 (§Verificado en GitHub de `docs/reference/claude-issues.md`) | un error evidente real que termine en PR con CI, y un rechazo de `implementar` ⚠️ 2026-09-28 |
| F7 | Paridad de dibujos en Windows | `windows/README.md`: "`vector:ball` y `vector:sage` aún no están portados" | portar los dos al Canvas de Tk |
| F8 | OpenCode sobre el contrato `EventSource` (PR3 de `docs/adr/0008`) | **en espera**: no hay cómo probar el plugin contra una instalación real de OpenCode | escribir `bridges/opencode/mascotuscan-bridge.js` y los dos adapters cuando haya cómo verificarlo |

## Entregado — no re-trabajar

Los nombres viejos (`lucy`, `~/.lucy`) en la evidencia son a propósito: es lo que
decía la salida en ese momento.

| Cosa | Evidencia |
|---|---|
| Droide vectorial con 6 estados distinguibles | `make render`, revisado a ojo en `render/todos.png` |
| Sprites propios del usuario, con GIF animado | probado sustituyendo `default.png`: el vector desaparece y escala bien |
| Mascotas incluidas con arte propio | `cangrejo` y `llama` con `"renderer": "sprites"` en su `pet.json`, desde #4 (2026-09-16) |
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
| Mascotas que solo difieren en personalidad | mismo aviso: astro dice "*bzzzt* … Algo no cuadra", gatito dice "… No fui yo" |
| Voz por mascota generada desde `persona.md` | `~/.lucy/voices/gatito.json`, 64 plantillas con voz felina, sin tocar código |
| CLI de mascotas: list, use, info, install, uninstall, new, validate, voice, search | probados a mano sobre la máquina real; salida pegada en el historial de `claude-progress.md` |
| Comandos `sprite` y `fork`; dibujos `vector:ball` y `vector:sage` | PRs #2 y #3 |
| Cambio de mascota en caliente desde el menú | `switchPet` reactiva tema y voz sin reiniciar el proceso |
| Instalador y desinstalador probados de punta a punta | `./install.sh --from-source` sobre la máquina real: 1 instancia, aviso real entregado. Desinstalación cubierta por casos en sandbox (`test-installer.sh`) |
| Versión del producto con fuente única y guarda | `VERSION` + `scripts/bump-version.sh`; la integridad compara cuatro sitios y falla en negativo |
| Aviso de versión nueva, mismo contrato en macOS y Windows | `docs/reference/versioning.md`; 14 tests en `UpdateTests.swift` y 17 en `test_update.py` con los mismos casos; punta a punta con `LUCY_UPDATE_URL=file://…`: un solo aviso, `update.json` con `announced` |
| `update [--check]` en macOS contra un release real | máquina del autor: `0.2.0` → `update --check` decía "Hay una versión nueva: 0.2.2" → `update` → `0.2.2` → "Estás en la última versión publicada". `python install.py --update` en Windows solo probado por lectura ⚠️ 2026-09-17 |
| Releases publicados por tag | `v0.2.0`, `v0.2.2` y `v0.3.0` con `release.yml` en verde y tarball + sha256 (`gh release list`). `v0.2.1` se perdió por un bug de CI con tags anotados (R11) y se documentó como no publicado |
| Reglas de tags con verificación y protección | `docs/reference/tags.md`; `scripts/check-tag.sh` en el gate y en CI; ruleset `tags de version` (id 23606182) sobre `refs/tags/v*`, bypass del administrador probado en `v0.2.1`/`v0.2.2` |
| Versión y notas propuestas desde los commits | `make next-version` y `make release-notes` (Conventional Commits → Keep a Changelog), en `test-release-tooling.sh` |
| Instalador de macOS clona el último release | `install.sh`: resuelve `tag_name` de `releases/latest` y cae a `main` si no hay, diciéndolo |
| Contrato `EventSource` en macOS y Windows (PR1, PR2 y PR4 de `docs/adr/0008`) | `docs/reference/event-source.md`; `CmuxEventSource`, `ShellHookEventSource`, `FileTailer`; `PetController.ingest(_:)` como único punto que decide. Skeleton de `WmuxEventSource` sin registrar. 35 + 3 + 2 tests nuevos |
| Responder permiso/pregunta: plomería y botones en la burbuja (`docs/adr/0009`) | `docs/reference/agent-reply.md`; `BubbleOption`, `respondToOption`; 21 tests nuevos; `render/burbuja-pendiente-*.png` revisadas a ojo. Falta la prueba real (F5) |
| Renombrado a MascoTuscan con migración encadenada (`docs/adr/0010`) | PR #17 (`0a6bf04`), 6 checks en verde en la corrida 36293399797; migración `~/.lucy`/`~/.cmux-pet` → `~/.mascotuscan` con tests en `test-installer.sh` y `test_install.py`. Versión `0.4.0` preparada en #18 |
| Claude atiende issues dentro de un harness (`docs/adr/0011`) | #19, #23 y #24; probado en GitHub con #20, #21 y #22: aprobación, las tres rutas, caso hostil sin fugas |
| Claude revisa cada PR con un status que bloquea (`docs/adr/0012`) | #24; `claude/revision` corrió en GitHub sobre #25 y #26 |
| Droide esférico animado: quieto mira alrededor, trabajando rueda | #25, 9 tests en `BallRendererTests` |

## Riesgos

| # | Riesgo | Impacto | Mitigación actual |
|---|---|---|---|
| R1 | Si se cierra el pane que lanzó la mascota, el proceso queda hijo de launchd; un respawn del stream sería rechazado por el socket | pierde eventos en silencio | `--reconnect` mantiene la conexión original; `noteStreamExit` avisa en pantalla si el stream muere dos veces seguidas. **Sin verificar en la práctica** ⚠️ 2026-07-31 |
| R2 | El formato de eventos de cmux puede cambiar entre versiones | la mascota deja de reportar | `docs/reference/cmux-events.md` documenta lo verificado con fecha y versión; el fallo es visible, no silencioso |
| R3 | La generación de voz consume cuota del usuario | molestia | una llamada cada 7 días; se puede apagar borrando `voice.json` y no regenerando |
| R5 | Un pack del marketplace trae arte de un personaje con dueño | problema legal para el autor y para el índice | regla explícita en `docs/marketplace.md`, revisión en el PR, y se quita del índice al detectarlo. **Depende de revisión humana** ⚠️ 2026-07-31 |
| R6 | Un pack malicioso apunta sprites fuera de su carpeta | leer archivos del usuario | `..` prohibido en rutas, cubierto por test. Un pack no ejecuta código: solo aporta texto e imágenes |
| R7 | El registro crece y el `git clone --depth 1` por install se vuelve costoso | instalación lenta | hoy son 2 entradas (`registry.json`); si crece, cachear o servir tarballs |
| R8 | `release.yml` falla en un tag | no hay release y nadie recibe el aviso; el instalador sigue en la última publicada | ocurrió en `v0.2.1` (R11). Pasa también si su runner deja de existir: el `release.yml` del commit de `0.4.0` usa `macos-14` (ver R16) |
| R9 | La burbuja de actualización en Tk (Windows) no se ha visto en una máquina Windows real | el aviso podría no mostrarse aunque la lógica esté probada | la lógica pura tiene 17 tests y `Checker` está probado con `file://`; falta `--selftest` con `MASCOTUSCAN_UPDATE_URL` en Windows ⚠️ 2026-09-17 |
| R10 | El bypass del ruleset de tags no aplica al dueño y `make tag` no puede empujar | el tag queda en local; nada publicado | verificado con `v0.2.1` y `v0.2.2`: GitHub reporta "Bypassed rule violations" |
| R11 | GitHub Actions entrega el ref de un tag apuntando al commit, no al objeto tag anotado | `check-tag.sh` en CI rechaza cualquier tag real como "ligero" | `git fetch --tags --force origin` tras el checkout; documentado en `release.yml` y en el CHANGELOG de `0.2.2` |
| R12 | `install.sh` de `main` clona el último release, que compila `lucy` y no `mascotuscan` | `curl ... \| bash` falla con "no encuentro el binario compilado" | **ocurriendo desde el 2026-09-27**: `v0.3.0` es el último release y su `Package.swift` declara `name: "lucy"`. Se cierra con F1 |
| R13 | Un issue hostil (prompt injection) engaña a Claude en el harness de issues | un diagnóstico o un parche que no corresponde | Claude no tiene comandos, red ni escritura; la guardia y el escaneo de secretos son código con tests; `evaluar` y todo cambio estructural esperan aprobación; ningún PR se mergea solo |
| R14 | Un PR hostil engaña a Claude para que apruebe, o un falso positivo bloquea un PR correcto | un merge sin revisión real, o un PR frenado | el status lo decide el harness; una credencial agregada bloquea aunque Claude apruebe; el código del PR nunca se ejecuta; los PRs sensibles y los forks esperan aprobación. Ante un falso positivo, `claude:revision-anulada` |
| R15 | Se filtra la llave de publicación de CI (`RELEASE_SSH_KEY`) | alguien crea tags `v*` o empuja ramas sin protección | vive en el environment `release`, que solo acepta ramas protegidas; `main` le exige PR y checks como a cualquiera. Se revoca borrando la deploy key (`gh repo deploy-key delete`) |
| R16 | GitHub retira un runner que usa CI | checks obligatorios que nunca llegan a correr: ningún PR entra, ningún release sale | pasó con `macos-14` (P0.7). Revisar los avisos de retiro de imágenes de GitHub antes de cada release |

## Backlog

Ordenado por valor sobre esfuerzo. El valor es una estimación; lo ajusta el dueño.

| # | Cosa | Por qué | Valor (estimado) | Esfuerzo |
|---|---|---|---|---|
| B8 | Fórmula de Homebrew | `brew install` es lo que espera la gente en macOS; el release ya adjunta el tarball con su sha256 | alto | medio |
| B3 | Recarga en caliente de `config.json` | hoy hay que reiniciar para cambiar `narrateEverySeconds` | medio | bajo |
| B2 | Click derecho en el panel de estado → saltar a ese agente | el panel ya sabe el workspace de cada uno | medio | bajo |
| B1 | Sonido opcional por estado | un aviso visual en la esquina se pierde si miras otra pantalla | medio | bajo |
| B13 | Marcar el job `port de Windows` como check obligatorio en `main` | hoy un PR puede romper Windows y entrar igual | medio | bajo |
| B14 | Registrar como *signing key* la llave del autor y la de CI | hoy los tags se ven "Unverified" en GitHub; siguen firmados | bajo | bajo |
| B11 | Página del marketplace con capturas de cada mascota | el índice JSON no deja ver cómo se ven; una galería sí | medio | medio |
| B10 | Más dibujos integrados (`vector:gato`, `vector:blob`) | hoy un pack sin arte solo puede verse como droide, esfera o figura encapuchada | medio | medio |
| B5 | Soporte de otros shells (bash, fish) | hoy solo zsh; bash necesita `trap DEBUG` + `PROMPT_COMMAND` | medio | medio |
| B12 | Que el instalador de macOS use el tarball del release en vez de compilar | instalar sin Xcode; depende de firmar el binario (B9) | alto | medio, bloqueado por B9 |
| B15 | Abrir solo el PR de versión (`next-version` + `release-notes` + `bump-version`) | lo demás ya lo hace CI (`docs/adr/0013`); las notas generadas siguen siendo un borrador que alguien tiene que reescribir | bajo | medio |
| B6 | Migrar a concurrencia estricta de Swift 6 | hoy el paquete fija `swiftLanguageVersions: [.v5]` | bajo | medio |
| B7 | Avisos comentados por el modelo con los datos reales | más gracia, pero cuesta latencia; ver `docs/adr/0002` | bajo | medio |
| B9 | Empaquetar como `.app` firmada | necesario para B12 y si algún día se distribuye fuera de GitHub | medio | alto |
