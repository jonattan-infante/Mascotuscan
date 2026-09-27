# claude-progress.md

**Leer esto primero.** El agente olvida entre sesiones; el repo no.

---

## Estado verificado

Fecha: **2026-09-27** (renombrado a MascoTuscan, ver su sección abajo; lo anterior es del 2026-09-17)

El proyecto es una **plataforma de mascotas con dos runtimes**: macOS en Swift y
Windows en Python (`windows/`). Desde esta sesión la **versión es del producto**
(`VERSION` = `0.2.0`) y **la mascota avisa una vez cuando hay una versión publicada
más nueva**, con el mismo contrato en las dos plataformas
(`docs/reference/versioning.md`, `docs/adr/0006`).

Baseline verde, verificado con comandos en la rama
`feat/versiones-y-aviso-de-actualizacion`:

```
make verify                          -> compila + 84 tests Swift + 8 hooks + 12 instalador
                                        + 15 integridad + 11 mascotas + 51 tests Python
./.build/debug/lucy --version    -> lucy 0.2.0
python3 windows/pet.py --version     -> lucy 0.2.0
./.build/debug/lucy update --check -> "sin versiones publicadas todavía", salida 0
actionlint release.yml               -> limpio
```

Guarda de versión probada en negativo: con `__init__.py` en `0.1.0`,
`test-repo-integrity.sh` dice
`FALLA la version diverge: VERSION=0.2.0 swift=0.2.0 python=0.1.0 changelog=0.2.0`.

El aviso, de punta a punta en la máquina real, con
`LUCY_UPDATE_URL=file://…/latest.json` (`{"tag_name":"v9.9.9"}`):

```
[14:12:23Z] aviso: [info] *dwoo-weep* Reactivada. A vigilar tus procesos.
[14:12:53Z] actualizaciones: hay 9.9.9, corre 0.2.0
[14:12:53Z] aviso: [info] Hay una versión nueva de lucy: 9.9.9. Corre: lucy update
~/.lucy/update.json -> { "announced": "9.9.9", "checkedAt": "2026-09-17T14:12:53Z", "latest": "9.9.9" }
segundo arranque                -> 0 avisos de actualización (ver abajo)
```

Ese primer aviso salió con el texto neutro del programa porque el pack instalado
en `~/.lucy/pets/` era la copia anterior, sin la clase `updateAvailable`.
Tras `./install.sh --from-source` (binario y packs en 0.2.0, máquina del autor),
la misma prueba lo dijo con la voz de la mascota activa:

```
[14:14:53Z] mascota activa: Astro (astro) v1.1.0, renderer vector:droid
[14:15:23Z] actualizaciones: hay 9.9.9, corre 0.2.0
[14:15:23Z] aviso: [info] *bip-bip* Hay una versión nueva de lucy: 9.9.9. Solicito actualización de firmware.
```

La máquina del autor quedó con `lucy 0.2.0` instalado desde esta rama y sin
`update.json` (se borró al terminar la prueba para que la primera consulta real
ocurra sola).

**`v0.2.2` está publicado, con release real.** El primer intento (`v0.2.1`) reveló
un bug genuino en `release.yml`: GitHub Actions entrega el ref de un tag
apuntando al commit que señala, no al objeto tag anotado, así que
`check-tag.sh` en CI decía "es un tag ligero" para un tag que localmente es
anotado y firmado. Reproducido con un remoto de prueba y corregido con
`git fetch --tags --force origin` justo después del checkout (PR #9).

`v0.2.1` se documentó como no publicado en el CHANGELOG y se quedó en GitHub
sin borrarse, siguiendo la regla de inmutabilidad que este mismo repo exige.
`v0.2.2` corrió los tres jobs de `release.yml` en verde:

```
el tag dice lo mismo que el repo: success
binario de macOS: success
publicar el release: success
gh release view v0.2.2 -> draft=false prerelease=false
assets: lucy-0.2.2-macos-arm64.tar.gz, lucy-0.2.2-macos-arm64.tar.gz.sha256
```

Y el ciclo completo, de punta a punta en la máquina del autor:

```
lucy --version              -> lucy 0.2.0  (instalado antes de publicar)
lucy update --check         -> Hay una versión nueva: 0.2.2
lucy update                 -> clona v0.2.2 del release real
lucy --version              -> lucy 0.2.2
lucy update --check         -> Estás en la última versión publicada.
```

El bypass de administrador del ruleset de tags también quedó probado dos veces
(GitHub reporta "Bypassed rule violations" en cada push de tag).

Rama `docs/reglas-de-tags-para-agentes-ia` (PR #7) llevó las reglas de tags a
`CLAUDE.md` como sección obligatoria para cualquier agente de IA, no solo un
punto entre otros veinte.

## Refactor de fuentes de eventos (PR1 de 4, `docs/adr/0008`)

`PetController+Events.swift`/`+Sources.swift` estaban cableadas directo a cmux
y a `shell.jsonl`, sin ninguna interfaz común y sin un solo test. Rama
`refactor/event-source-contract`: protocolo `EventSource` +
`NormalizedEvent` (`docs/reference/event-source.md`), `CmuxEventSource` y
`ShellHookEventSource` como adapters, `PetController.ingest(_:)` como único
punto que decide mood y texto. Cero cambio de comportamiento observable.

```
make verify   -> compila + 119 tests Swift (35 nuevos: CmuxEventSourceTests,
                 FileTailerTests, ShellHookEventSourceTests,
                 PetControllerIngestTests) + 8 hooks + 14 instalador +
                 15 integridad + 11 mascotas + 19 release-tooling + 51 Python
```

PR2 (Windows) también entregado, mismo contrato: `Tailer(path, parse=...)`
con default retrocompatible, `App(sources=[...])` reemplaza `tailer=`, y
`state.py:Session.agent` reemplaza la constante `_agent()` que devolvía
siempre `"Claude"`.

```
cd windows && python3 -m unittest discover -s tests -p "test_*.py"
  -> 54 tests, 0 fallos (51 + 3 nuevos)
```

Decisión tomada en PR2, no en el plan original: **no se agregó
`test_app.py`**. Verificado que ningún test de `windows/tests/` instancia
`tk.Tk()` (es deliberado en este runtime); crear uno solo para el `tick()`
de tres líneas que reparte sobre `self.sources` habría sido la primera
dependencia de Tk en la suite, para una lógica ya cubierta por
`test_events.py`/`test_state.py`.

PR4 (skeleton de `WmuxEventSource`) también entregado: `start()` llama
`onUnavailable("wmux: protocolo no verificado, ver docs/adr/0008")` y nunca
`onEvent`; no está en `makeEventSources()`. `WmuxEventSourceTests` (2 casos)
fija ese contrato en código.

Decisión explícita del autor: **PR3 (OpenCode) queda en espera**, sin
implementar — no hay cómo probar el plugin-puente contra una instalación
real de OpenCode, y el mapeo de eventos no se da por bueno sin esa prueba
(ver docs/reference/event-source.md).

## Responder permiso/pregunta desde la burbuja (PR1 de 2, `docs/adr/0009`)

Pedido del autor: que la mascota deje de ser pasiva — responder un permiso o
una pregunta de Claude desde la burbuja, con el contenido real, sin ir a la
terminal. Investigación con comandos reales contra el cmux instalado:
`cmux capabilities` confirmó un RPC de escritura sin usar
(`feed.permission.reply`, `feed.question.reply`, `workspace.prompt_submit`,
entre otros); el esquema exacto de los dos primeros se verificó **sin tocar
ningún permiso/pregunta real** (`cmux rpc feed.permission.reply '{}'` revela
los campos que exige vía su propio error de validación). Todo documentado
con evidencia en `docs/reference/agent-reply.md`.

Hallazgo que definió el alcance: `BubbleView` no tiene ningún control
interactivo hoy y `PetPanel` no puede tomar foco de teclado
(`canBecomeKey = false`) — esta fase se limita a responder con clics
(permiso: `mode` once/deny; pregunta: elegir una `question_options`), no a
texto libre. Eso queda para una decisión aparte (ver "Fuera de alcance" en
el ADR).

PR1 (plomería, sin UI todavía) entregado en `feat/responder-permiso-pregunta`:

```
make verify   -> compila + 132 tests Swift (10 nuevos) + 8 hooks + 14 instalador
                 + 15 integridad + 11 mascotas + 19 release-tooling + 54 Python
```

`NormalizedEvent.requestId` (extraído de `_opencode_request_id`, verificado
contra `~/.cmuxterm/events.jsonl` real), `PetController.pendingRequests` +
`sweepExpiredRequests()`, y en `PetController+Actions.swift`:
`fetchPendingContent` (puro vía `PetController.extractPendingContent`,
testeado con fixtures literales de `feed.list`), `replyPermission`,
`replyQuestion`.

PR2 (botones en la burbuja) también entregado:

```
make verify   -> compila + 143 tests Swift (11 nuevos) + 8 hooks + 14 instalador
                 + 15 integridad + 11 mascotas + 19 release-tooling + 54 Python
make render   -> burbuja-pendiente-0.png (permiso, Sí/No), burbuja-pendiente-1.png
                 (pregunta, 3 opciones largas) — revisadas a ojo, se ven y miden bien
```

`BubbleView` gana su primer control interactivo (antes: cero `NSButton`/
`NSTextField` en todo el árbol de vistas): cada opción es su propia línea
clicable, con el mismo motor de `docs/adr/0003`. Los botones solo aparecen
una vez que termina de "escribir", y el alto ya está reservado desde
`size(for:)` — no hay salto en pantalla. `PetController.fetchPendingContent`
es una costura de test, mismo patrón que `isCmuxFrontmost`.

⚠️ Pendiente, documentado en `docs/reference/agent-reply.md`: confirmar con
un permiso/pregunta real (workspace descartable) que un clic en la burbuja
efectivamente mueve al agente, no solo que el RPC devuelve `delivered: true`
contra un id inventado. No se cierra la fase sin esa prueba.

## Renombrado a MascoTuscan (`docs/adr/0010`)

Pedido del autor: el proyecto se llama `mascotuscan`. Decidido con él: cambio
completo como en `docs/adr/0007`, comando `mascotuscan`, marca `MascoTuscan`.
Rama `claude/awesome-newton-f3bluk`. Los nombres viejos que quedan en el repo son
a propósito: la migración, sus tests, los ADR 0001-0009, el CHANGELOG publicado
y la evidencia pegada en este archivo y en `EXECUTION-PLAN.md`.

Además del reemplazo de nombres, arregla lo que el renombrado anterior dejó
suelto: el `source ~/.lucy/...` del zshrc (ahora `install.sh` lo reemplaza), los
hooks de Claude Code con el nombre viejo en Windows (`install.py` los reconoce),
la migración que fallaba en silencio y la mascota vieja corriendo sobre el
directorio que se mueve.

Verificado en Linux (sesión en la nube, sin Swift ni PowerShell):

```
make test-windows            -> 61 tests, 0 fallos (54 + 7 nuevos)
test-installer.sh            -> 24 ok (14 + 10 nuevos), con /usr/bin/sed -i '' cambiado
                                a sed -i en una copia: el script es para BSD
  mismo, con LEGACY_NAMES=() -> 5 FALLA (quita el enganche viejo, migra...)
test-shell-hooks.sh          -> 8 ok (zsh instalado con apt)
test-repo-integrity.sh       -> ok, CLAUDE.md en 190 lineas
test-release-tooling.sh      -> 19 ok ('mascotuscan X.Y.Z' como primera linea del tag)
python3 windows/pet.py --version -> mascotuscan 0.3.0
install.py con HOME falso    -> "migrado .../.lucy -> .../.mascotuscan", hook
                                lucy-hook.ps1 reemplazado, hook ajeno intacto
```

⚠️ 2026-09-27: **Swift sin compilar.** `download.swift.org` está bloqueado por la
red de la sesión. El renombrado de Swift es mecánico (módulo, target, una
constante), pero `PetPaths.migrateLegacyHome` y `PathsTests.swift` (5 casos,
los mismos que `test_paths.py`) solo los va a correr CI. `test-pet-packs.sh` y
`make render` tampoco corrieron.

## Próximo paso

**Renombrado (F5 en `EXECUTION-PLAN.md`), en este orden:**

1. Renombrar el repositorio en GitHub a `mascotuscan` (Settings > General)
   **antes** de mergear: el código nuevo apunta a `jonattan-infante/mascotuscan`.
   GitHub redirige la URL vieja, así que las instalaciones de `lucy` siguen
   encontrando releases.
2. Que CI compile y corra los tests de Swift; después, `make merge`.
3. Publicar una versión apenas entre (`make next-version`, `bump-version.sh`,
   CHANGELOG, `make tag`). Hasta entonces `curl ... | bash` falla (R12).
4. En la máquina del autor: `lucy update`, y confirmar que `~/.lucy` pasó a
   `~/.mascotuscan`, que el zshrc tiene solo el enganche nuevo y que
   `mascotuscan --version` responde. Si `~/.lucy/bin` está en el `PATH`, cambiarlo.

Después, lo que ya estaba pendiente:


Verificación de punta a punta pendiente de arriba (F4 en
`EXECUTION-PLAN.md`): provocar un permiso/una pregunta reales, clic en la
burbuja, confirmar en el pane que el agente recibió la respuesta. Sin eso, o
si se prefiere, retomar F1/F2 del backlog o F3 (OpenCode) cuando haya cómo
verificarlo.

Pendiente de antes, sin resolver en esta sesión: **registrar la llave como
signing key en GitHub** (B14), para que los tags aparezcan "Verified" en vez
de "Unverified" (siguen siendo válidos sin esto; es solo la insignia visual):

```
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add ~/.ssh/id_ed25519_github.pub --type signing --title "firma de tags"
```

Después: probar `python pet.py --selftest` con `MASCOTUSCAN_UPDATE_URL` en una máquina
Windows real (R9), y marcar el job `port de Windows` como check obligatorio (B13).

## Historial

| Fecha | Qué pasó |
|---|---|
| 2026-07-31 | Prototipo: droide vectorial, burbuja de terminal, cuatro fuentes de eventos, voz generada, seguimiento en vivo. Todo en un archivo de 2195 líneas |
| 2026-07-31 | Diagnóstico de "no llegan las notificaciones": tres causas, la principal el socket de cmux rechazando procesos de launchd (`docs/adr/0001`) |
| 2026-07-31 | Empaquetado: SPM librería + ejecutable, 20 archivos, tests, instalador, harness. CI encontró un archivo que el `.gitignore` excluía |
| 2026-07-31 | Pivote a plataforma: pet packs, marketplace, CLI de mascotas, voz por personalidad (`docs/adr/0005`) |
| 2026-08-02 | Comandos `sprite` y `fork`; renderers `vector:ball` y `vector:sage`; port de Windows en Python (PRs #2, #3, #4) |
| 2026-09-17 | La versión es del producto: `VERSION`, guarda de integridad, release por tag, instalador al último release, y aviso de versión nueva con el mismo contrato en macOS y Windows (`docs/adr/0006`) |
| 2026-09-17 | Primer release: `v0.2.0`. README reescrito. Reglas de tags con `check-tag.sh`, `next-version`, `release-notes`, firma SSH y ruleset en GitHub (`docs/reference/tags.md`) |
| 2026-09-17 | Reglas de tags obligatorias en `CLAUDE.md` para cualquier agente de IA (PR #7). Primer tag bajo las reglas (`v0.2.1`) reveló un bug real de CI con tags anotados; corregido y publicado como `v0.2.2` (PR #9), con el ciclo de `lucy update` probado de punta a punta contra el release real |
| 2026-09-27 | Renombrado de LucyGlow a MascoTuscan, comando `mascotuscan` (`docs/adr/0010`). Migración encadenada `~/.lucy`/`~/.cmux-pet`, y reemplazo de los enganches viejos en el zshrc y en los hooks de Claude Code |

## Trampas que ya costaron tiempo

No volver a caer en estas. Todas están documentadas con evidencia en
`docs/reference/` y en los ADR.

1. **Un fallo silencioso parece éxito.** El asistente arrancaba y dibujaba, pero
   no recibía nada. Tres hipótesis falsas antes de encontrar el rechazo del socket.
   Ahora el rechazo, y la falta de mascota, se muestran en pantalla.
2. **Medir con `boundingRect` y dibujar con `draw(with:)`** corta la última línea.
   Ver `docs/adr/0003`.
3. **Un patrón de `.gitignore` sin barra inicial aplica a cualquier nivel.**
   `render/` excluyó `Sources/LucyGlowKit/Render/`. Lo cubre
   `scripts/test-repo-integrity.sh`.
4. **`pkill -f <patrón>` mata el propio shell** si el patrón aparece en su línea de
   comandos. Pasó dos veces.
5. **Un test que depende del entorno pasa en local y falla en CI.** `pgrep` sin
   coincidencias devuelve 1 y con `pipefail` mata el script.
6. **`#"..."#` se cierra en el `"#"` de un color hex.** Para JSON con colores en un
   test, hace falta `##"..."##`.
7. **Los hooks de cmux llegan duplicados** (`received` y `completed`).
8. **El texto de las notificaciones y de `tool_input` viene redactado.**
9. **`NSImageView` como subvista no aparece en `cacheDisplay`**, así que
   `--render` salía vacío con sprites. Se cambió a dibujo directo, que además
   permitió animar GIF con el mismo reloj.
10. **Una funcionalidad que solo existe en un runtime no es del producto.** El
    aviso de actualización se pidió "global, sin depender de la plataforma": el
    contrato va en `docs/reference/` y cada runtime lo implementa con los mismos
    casos de prueba. Y el gate tiene que cubrir los dos: hasta esta sesión los
    tests de Windows no corrían ni en `make verify` ni en CI.
11. **`Config` de Windows descarta claves desconocidas.** Una preferencia nueva que
    no esté en `DEFAULTS` se pierde en el siguiente `save()`.
12. **GitHub Actions entrega el ref de un tag apuntando al commit, no al
    objeto tag anotado.** Un `check-tag.sh` que pasa en local puede fallar en
    CI por esto solo. `git fetch --tags --force origin` después del checkout
    lo corrige. Costó publicar dos veces (`v0.2.1` se perdió, `v0.2.2` es la
    real).
13. **El remote no tenía refspec de fetch** (`remote.origin.fetch` vacío), así que
    `origin/main` no existía en local y `git fetch` solo movía `FETCH_HEAD`. Se
    arregló con `git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'`.
    `make tag` depende de `origin/main`.
14. **`git branch -d` no borra una rama mergeada por squash**: para git no está
    "fully merged". Es `-D`, tras comprobar que el PR entró.
15. **Mover el directorio de estado no alcanza para renombrar.** Fuera del repo
    quedan cosas apuntando al nombre viejo: el `source` en el zshrc y los hooks
    en el `settings.json` de Claude Code. El renombrado de `docs/adr/0007` no
    las tocó; `docs/adr/0010` sí.

## Checklist de fin de sesión

Antes de cerrar, sin excepciones:

- [ ] `make verify` verde
- [ ] Si cambió algo visual: `make render` y **mirar** los PNG
- [ ] Si cambió el formato de pack: actualizar `docs/reference/pet-pack.md`, que es
      el contrato, y revisar que las dos mascotas incluidas sigan validando
- [ ] Si cambió una decisión durable: ADR nuevo en `docs/adr/` (insert-once)
- [ ] Si cambió el comportamiento de cara al usuario: README y `PRODUCT.md`
- [ ] Si cambió un contrato de `docs/reference/`: los dos runtimes y sus dos tests
- [ ] `EXECUTION-PLAN.md`: mover lo terminado a "Entregado" **con evidencia**
- [ ] Actualizar "Estado verificado" y "Próximo paso" de este archivo
- [ ] Working tree limpio o el pendiente anotado arriba
