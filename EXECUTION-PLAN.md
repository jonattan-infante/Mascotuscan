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
| P0.5 | Herramientas de publicación | verde | `./scripts/test-release-tooling.sh` → 30 ok, salida 0 (`main` en `6435f5f`, 2026-11-16) |
| P0.6 | Integridad del repo y la versión es una sola | verde | `./scripts/test-repo-integrity.sh` → `ok version 0.4.0 en VERSION, Paths.swift, __init__.py y CHANGELOG`, `ok cero emojis` |
| P0.7 | CI en GitHub Actions | verde en `main` desde #28 | GitHub ya no acepta `macos-14` (`The configuration 'macos-14-arm64-us-default' is not supported`, corrida 43789379493). #28 pasó a `macos-15`/`macos-26`; `verify` sobre `8813d05`, corrida 43907356423 (2026-11-16) |
| P0.8 | `main` protegido | verde | `gh api .../branches/main/protection/required_status_checks` → `build y tests (macos-15)`, `build y tests (macos-26)`, `shell e instalador`, `mascotas y marketplace` (desde 2026-11-16); push directo → `remote rejected (protected branch hook declined)`, con `enforce_admins: true` |
| P0.9 | Working tree limpio | verde | `git status --short` vacío en `main` |

Un PR abierto antes de #28 hereda `macos-14` en su `ci.yml` y no puede pasar los
checks obligatorios hasta actualizarse contra `main`.

## En vuelo

En orden de prioridad.

| # | Cosa | Estado | Próximo paso concreto |
|---|---|---|---|
| F2 | Migración de la máquina del autor a MascoTuscan (`docs/adr/0010`) | lista para hacer: `v0.4.0` es el último release desde el 2026-11-16 (`gh release list`) | `lucy update`; confirmar `~/.mascotuscan`, que el zshrc tiene solo el enganche nuevo y que `mascotuscan --version` responde |
| F3 | La mascota recorre la pantalla mientras trabaja (`roam`) | PRs #26 y #27 abiertos desde el 2026-09-28; `claude/revision` en `failure` porque nadie aprobó la corrida | actualizarlos contra `main` (heredan los runners nuevos), poner `claude:revisar` y revisar |
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
| Releases publicados por tag | `v0.2.0`, `v0.2.2`, `v0.3.0` y `v0.4.0` con `release.yml` en verde y tarball + sha256 (`gh release list`). `v0.2.1` se perdió por un bug de CI con tags anotados (R11) y se documentó como no publicado |
| CI publica la versión al mergear (`docs/adr/0013`) | #28 (`8813d05`). `publicar.yml` (corrida 43907356448) creó `v0.4.0`: tag anotado sobre `8813d05`, `git tag -v` → `Good "git" signature with ED25519 key SHA256:9eG2Fi…`, con los `###` de las notas intactos. El push con la deploy key disparó `release.yml` (corrida 43907451387; el intento 1 no consiguió runner macOS, el 2 publicó). `sha256sum -c` del tarball ok; `bin/mascotuscan` es `Mach-O 64-bit arm64` |
| Reglas de tags con verificación y protección | `docs/reference/tags.md`; `scripts/check-tag.sh` en el gate y en CI; ruleset `tags de version` (id 23606182) sobre `refs/tags/v*`, bypass del administrador probado en `v0.2.1`/`v0.2.2` |
| Versión y notas propuestas desde los commits | `make next-version` y `make release-notes` (Conventional Commits → Keep a Changelog), en `test-release-tooling.sh` |
| Instalador de macOS clona el último release | `install.sh`: resuelve `tag_name` de `releases/latest` y cae a `main` si no hay, diciéndolo |
| Contrato `EventSource` en macOS y Windows (PR1, PR2 y PR4 de `docs/adr/0008`) | `docs/reference/event-source.md`; `CmuxEventSource`, `ShellHookEventSource`, `FileTailer`; `PetController.ingest(_:)` como único punto que decide. Skeleton de `WmuxEventSource` sin registrar. 35 + 3 + 2 tests nuevos |
| Responder permiso/pregunta: plomería y botones en la burbuja (`docs/adr/0009`) | `docs/reference/agent-reply.md`; `BubbleOption`, `respondToOption`; 21 tests nuevos; `render/burbuja-pendiente-*.png` revisadas a ojo. Falta la prueba real (F5) |
| Renombrado a MascoTuscan con migración encadenada (`docs/adr/0010`) | PR #17 (`0a6bf04`), 6 checks en verde en la corrida 36293399797; migración `~/.lucy`/`~/.cmux-pet` → `~/.mascotuscan` con tests en `test-installer.sh` y `test_install.py`. Versión `0.4.0` preparada en #18 |
| Claude atiende issues dentro de un harness (`docs/adr/0011`) | #19, #23 y #24; probado en GitHub con #20, #21 y #22: aprobación, las tres rutas, caso hostil sin fugas |
| Claude revisa cada PR con un status que bloquea (`docs/adr/0012`) | #24; `claude/revision` corrió en GitHub sobre #25 y #26 |
| Droide esférico animado: quieto mira alrededor, trabajando rueda | #25, 9 tests en `BallRendererTests` |
| La llave de publicación solo se usa desde `main` | #30 (`7b1006b`): el job `etiquetar` exige `refs/heads/main` y fija `actions/checkout` a un commit. Test de firma SSH real; dos mutantes de `tag-release.sh` caen. Tras el merge, `publicar.yml` (corrida 43942127907): `v0.4.0 ya esta publicada: nada que hacer` |
| README con estándares de proyecto abierto, `SECURITY.md` y `CODE_OF_CONDUCT.md` | #29 (`6435f5f`); reporte privado de vulnerabilidades activado; `claude/revision` sin hallazgos en el último commit |

## Riesgos

| # | Riesgo | Impacto | Mitigación actual |
|---|---|---|---|
| R1 | Si se cierra el pane que lanzó la mascota, el proceso queda hijo de launchd; un respawn del stream sería rechazado por el socket | pierde eventos en silencio | `--reconnect` mantiene la conexión original; `noteStreamExit` avisa en pantalla si el stream muere dos veces seguidas. **Sin verificar en la práctica** ⚠️ 2026-07-31 |
| R2 | El formato de eventos de cmux puede cambiar entre versiones | la mascota deja de reportar | `docs/reference/cmux-events.md` documenta lo verificado con fecha y versión; el fallo es visible, no silencioso |
| R3 | La generación de voz consume cuota del usuario | molestia | una llamada cada 7 días; se puede apagar borrando `voice.json` y no regenerando |
| R5 | Un pack del marketplace trae arte de un personaje con dueño | problema legal para el autor y para el índice | regla explícita en `docs/marketplace.md`, revisión en el PR, y se quita del índice al detectarlo. **Depende de revisión humana** ⚠️ 2026-07-31 |
| R6 | Un pack malicioso apunta sprites fuera de su carpeta | leer archivos del usuario | `..` prohibido en rutas, cubierto por test. Un pack no ejecuta código: solo aporta texto e imágenes |
| R7 | El registro crece y el `git clone --depth 1` por install se vuelve costoso | instalación lenta | hoy son 2 entradas (`registry.json`); si crece, cachear o servir tarballs |
| R8 | `release.yml` falla en un tag | no hay release y nadie recibe el aviso; el instalador sigue en la última publicada | ocurrió en `v0.2.1` (R11) y en `v0.4.0`, por falta de runner (R16). Si el tag salió bien, `gh run rerun <id> --failed` publica sobre el mismo tag (`docs/reference/tags.md`) |
| R9 | La burbuja de actualización en Tk (Windows) no se ha visto en una máquina Windows real | el aviso podría no mostrarse aunque la lógica esté probada | la lógica pura tiene 17 tests y `Checker` está probado con `file://`; falta `--selftest` con `MASCOTUSCAN_UPDATE_URL` en Windows ⚠️ 2026-09-17 |
| R10 | El bypass del ruleset de tags no aplica al dueño y `make tag` no puede empujar | el tag queda en local; nada publicado | verificado con `v0.2.1` y `v0.2.2`: GitHub reporta "Bypassed rule violations" |
| R11 | GitHub Actions entrega el ref de un tag apuntando al commit, no al objeto tag anotado | `check-tag.sh` en CI rechaza cualquier tag real como "ligero" | `git fetch --tags --force origin` tras el checkout; documentado en `release.yml` y en el CHANGELOG de `0.2.2` |
| R12 | `install.sh` de `main` clona el último release, que compila `lucy` y no `mascotuscan` | `curl ... \| bash` falla con "no encuentro el binario compilado" | **cerrado el 2026-11-16**: el último release es `v0.4.0` (`releases/latest` → `tag_name: v0.4.0`) y su `Package.swift` declara `name: "mascotuscan"`. Falta verlo en una Mac real (F2) |
| R13 | Un issue hostil (prompt injection) engaña a Claude en el harness de issues | un diagnóstico o un parche que no corresponde | Claude no tiene comandos, red ni escritura; la guardia y el escaneo de secretos son código con tests; `evaluar` y todo cambio estructural esperan aprobación; ningún PR se mergea solo |
| R14 | Un PR hostil engaña a Claude para que apruebe, o un falso positivo bloquea un PR correcto | un merge sin revisión real, o un PR frenado | el status lo decide el harness; una credencial agregada bloquea aunque Claude apruebe; el código del PR nunca se ejecuta; los PRs sensibles y los forks esperan aprobación. Ante un falso positivo, `claude:revision-anulada` |
| R15 | Se filtra la llave de publicación de CI (`RELEASE_SSH_KEY`) | alguien crea tags `v*` o empuja ramas sin protección | vive en el environment `release`, que solo acepta ramas protegidas, y con #30 el job además exige `main`; `main` le exige PR y checks como a cualquiera. Se revoca borrando la deploy key (`gh repo deploy-key delete`) |
| R16 | GitHub retira un runner que usa CI | checks obligatorios que nunca llegan a correr: ningún PR entra, ningún release sale | pasó con `macos-14` (P0.7). Variante: la imagen existe pero no hay capacidad. El job de macOS de `v0.4.0` terminó con `The job was not acquired by Runner of type hosted even after multiple attempts`, y se reintentó. Revisar los avisos de retiro de imágenes de GitHub antes de cada release |
| R17 | GitHub bloquea por defecto `pull_request_target` en repos públicos desde el 2026-12-02 | la revisión de Claude termina en `startup_failure` y ningún PR se revisa | pasó en el corte de prueba del 2026-11-16 (corridas 43910799064 y 43911158599). Política de Actions 14840: permite `pull_request_target` y `workflow_dispatch` solo a `claude-revision.yml` (`docs/reference/claude-revision.md` §Configuración) |

## Backlog

Ordenado por valor sobre esfuerzo. El valor es una estimación; lo ajusta el dueño.

| # | Cosa | Por qué | Valor (estimado) | Esfuerzo |
|---|---|---|---|---|
| B16 | Bajar de 5 a 2 los jobs macOS por PR: juntar `shell e instalador` y `mascotas y marketplace` con el build, y `vista previa` solo con una etiqueta | el plan Free permite 5 jobs macOS a la vez; el 2026-11-16 GitHub canceló siete por falta de runner y cada PR necesitó reintentos (R16). Cambia los nombres de los checks obligatorios | alto | bajo |
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
