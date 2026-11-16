# claude-progress.md

**Leer esto primero.** El agente olvida entre sesiones; el repo no. Arriba va el
estado de hoy y el próximo paso; el detalle de cada sesión anterior queda en el
historial de git de este archivo (`git log -p claude-progress.md`).

---

## Estado verificado

Fecha: **2026-11-16**. `main` en `b431d5c` (#25), `VERSION` = `0.4.0`.

```
make test-windows                         -> Ran 61 tests ... OK
python3 -m unittest discover -s scripts/tests -> Ran 106 tests ... OK
./scripts/test-release-tooling.sh         -> 19 ok, salida 0
./scripts/test-repo-integrity.sh          -> ok version 0.4.0 ..., ok cero emojis
verify en main, corrida 43789379493       -> macos-15: Executed 157 tests, with 0 failures;
                                             El binario responde: mascotuscan 0.4.0
gh release list -L 1                      -> lucy 0.3.0  Latest  v0.3.0
git show v0.3.0:Package.swift             -> name: "lucy"
```

Dos cosas rotas, las dos con arreglo en vuelo:

1. **CI no puede correr en `macos-14`.** En la corrida 43789379493, cada job ahí
   terminó cancelado con `The configuration 'macos-14-arm64-us-default' is not
   supported`. Tres de los cuatro checks obligatorios de `main` corren en ese
   runner, así que ningún PR puede entrar. `release.yml` también compilaba ahí.
2. **La instalación de macOS falla (R12).** `0.4.0` entró a `main` el 2026-09-27
   (#18) y nunca se etiquetó. `install.sh` instala `v0.3.0`, que compila `lucy`,
   y muere en `install.sh:122` buscando `mascotuscan`.

En vuelo:

| PR | Qué | Estado |
|---|---|---|
| #28 | Runners a `macos-15`/`macos-26`; `publicar.yml` + `scripts/tag-release.sh`: CI etiqueta y publica al mergear un `VERSION` sin tag (`docs/adr/0013`); notas de `0.4.0` completas | abierto, todos los checks de CI en verde (corrida 43789896230); `claude/revision` espera aprobación |
| rama `docs/estado-y-readme` | Este archivo, `EXECUTION-PLAN.md`, README con estándares de proyecto abierto, `SECURITY.md` y `CODE_OF_CONDUCT.md` | abierto; sus checks esperan a #28 |
| #26, #27 | La mascota recorre la pantalla (`roam`) | abiertos desde el 2026-09-28; heredan el CI roto hasta actualizarse contra `main` |

## Próximo paso

Configuración de una vez en GitHub, **aplicada el 2026-11-16** con la cuenta del
dueño (comandos en `docs/reference/tags.md`):

```
required_status_checks  -> build y tests (macos-15), build y tests (macos-26),
                           shell e instalador, mascotas y marketplace
environments/release    -> deployment_branch_policy.protected_branches: true
keys                    -> "publicar version (CI)", read_only: false
secret --env release    -> RELEASE_SSH_KEY (la copia local se borró con shred)
rulesets/23606182       -> bypass DeployKey + RepositoryRole 5; reglas y condiciones intactas
private-vulnerability-reporting -> enabled: true; descripción y topics del repo al día
```

1. **Revisar y mergear #28** (poner `claude:revisar` para que lo revise Claude) y
   verificar: `publicar.yml` crea `v0.4.0`, el push con la deploy key dispara
   `release.yml` (hipótesis sin verificar hasta entonces), `gh release view
   v0.4.0` muestra el tarball, y `curl ... | bash` instala.
2. Actualizar contra `main` la rama de docs y los PRs #26 y #27, para que corran
   con los runners nuevos.
3. En la máquina del autor: `lucy update`, y confirmar `~/.mascotuscan`, el
   zshrc con solo el enganche nuevo y `mascotuscan --version` (F2).

Después, en el orden de `EXECUTION-PLAN.md` §En vuelo: `roam`, revisor como
check obligatorio, prueba real del permiso desde la burbuja, rutas que faltan
del harness de issues, paridad de dibujos en Windows.

## Decisiones vigentes que no están en un ADR

- **OpenCode (PR3 de `docs/adr/0008`) queda en espera** por decisión del autor:
  no hay cómo probar el plugin-puente contra una instalación real de OpenCode, y
  el mapeo de eventos no se da por bueno sin esa prueba.
- **Ningún test de Windows instancia `tk.Tk()`.** Es deliberado: la suite cubre
  la lógica pura. Por eso no hay `test_app.py`; el `tick()` que reparte sobre
  `self.sources` no tiene lógica propia.
- **Responder desde la burbuja es solo con clics** (permiso: once/deny; pregunta:
  una opción). Texto libre necesita que el panel tome foco de teclado
  (`canBecomeKey = false` hoy); queda fuera de alcance en `docs/adr/0009`.

## Historial

| Fecha | Qué pasó |
|---|---|
| 2026-07-31 | Prototipo: droide vectorial, burbuja de terminal, cuatro fuentes de eventos, voz generada, seguimiento en vivo. Todo en un archivo de 2195 líneas |
| 2026-07-31 | Diagnóstico de "no llegan las notificaciones": tres causas, la principal el socket de cmux rechazando procesos de launchd (`docs/adr/0001`) |
| 2026-07-31 | Empaquetado: SPM librería + ejecutable, tests, instalador, harness. CI encontró un archivo que el `.gitignore` excluía |
| 2026-07-31 | Pivote a plataforma: pet packs, marketplace, CLI de mascotas, voz por personalidad (`docs/adr/0005`) |
| 2026-08-02 | Comandos `sprite` y `fork`; dibujos `vector:ball` y `vector:sage` (#2, #3) |
| 2026-09-16 | Port de Windows en Python, con `cangrejo` y `llama` como mascotas con sprites (#4) |
| 2026-09-17 | La versión es del producto: `VERSION`, guarda de integridad, release por tag, aviso de versión nueva igual en macOS y Windows (`docs/adr/0006`). Primer release `v0.2.0` |
| 2026-09-17 | Reglas de tags con `check-tag.sh`, firma SSH y ruleset (`docs/reference/tags.md`), obligatorias en `CLAUDE.md` (#7). `v0.2.1` reveló un bug de CI con tags anotados; publicado como `v0.2.2` (#9), con `update` probado de punta a punta |
| 2026-09-17 | Renombrado a LucyGlow (`docs/adr/0007`), release `v0.3.0`. Contrato `EventSource` en los dos runtimes (`docs/adr/0008`, #12 a #14). Responder permiso/pregunta desde la burbuja, plomería y botones (`docs/adr/0009`, #15, #16) |
| 2026-09-27 | Renombrado a MascoTuscan con migración encadenada de `~/.lucy`/`~/.cmux-pet` (`docs/adr/0010`, #17). Versión `0.4.0` preparada (#18), sin etiquetar |
| 2026-09-27 | Harness de issues: Claude evalúa con aprobación, reglas fijas y escaneo de secretos (`docs/adr/0011`, #19) |
| 2026-09-28 | Harness de issues probado en GitHub con #20, #21 y #22 (#23). Respuesta según el tipo de issue y revisor de PRs bloqueante (`docs/adr/0012`, #24). Droide esférico animado (#25). PRs de `roam` abiertos (#26, #27) |
| 2026-11-15 | Diagnóstico del harness tras siete semanas sin actividad: CI roto por el retiro de `macos-14` y `0.4.0` sin publicar. CI publica la versión al mergear y runners nuevos (#28, `docs/adr/0013`). Plan, progreso y README al día |

## Trampas que ya costaron tiempo

No volver a caer en estas. Todas están documentadas con evidencia en
`docs/reference/` y en los ADR.

1. **Un fallo silencioso parece éxito.** La mascota arrancaba y dibujaba, pero no
   recibía nada. Tres hipótesis falsas antes de encontrar el rechazo del socket.
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
    contrato va en `docs/reference/` y cada runtime lo implementa con los mismos
    casos de prueba. Y el gate tiene que cubrir los dos.
11. **`Config` de Windows descarta claves desconocidas.** Una preferencia nueva que
    no esté en `DEFAULTS` se pierde en el siguiente `save()`.
12. **GitHub Actions entrega el ref de un tag apuntando al commit, no al objeto
    tag anotado.** `git fetch --tags --force origin` después del checkout lo
    corrige. Costó publicar dos veces (`v0.2.1` se perdió, `v0.2.2` es la real).
13. **El remote no tenía refspec de fetch** (`remote.origin.fetch` vacío), así que
    `origin/main` no existía en local. Se arregló con
    `git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'`.
14. **`git branch -d` no borra una rama mergeada por squash**: para git no está
    "fully merged". Es `-D`, tras comprobar que el PR entró.
15. **Mover el directorio de estado no alcanza para renombrar.** Fuera del repo
    quedan cosas apuntando al nombre viejo: el `source` en el zshrc y los hooks
    en el `settings.json` de Claude Code. `docs/adr/0010` las cubre.
16. **`git tag -F` limpia el mensaje en modo `strip`** y borra toda línea que
    empiece con `#`: así perdió `v0.3.0` los encabezados `###` de sus notas. Hace
    falta `--cleanup=verbatim` (#28).
17. **Un paso manual que nadie recuerda no ocurre.** `0.4.0` esperó siete semanas
    un `make tag`. Mientras tanto GitHub retiró `macos-14` y el commit de esa
    versión quedó sin poder publicarse. De ahí `docs/adr/0013`.

## Checklist de fin de sesión

Antes de cerrar, sin excepciones:

- [ ] `make verify` verde (en Linux, lo que corre sin Swift y el CI del PR para el resto)
- [ ] Si cambió algo visual: `make render` y **mirar** los PNG
- [ ] Si cambió el formato de pack: actualizar `docs/reference/pet-pack.md`, que es
      el contrato, y revisar que las mascotas incluidas sigan validando
- [ ] Si cambió una decisión durable: ADR nuevo en `docs/adr/` (insert-once)
- [ ] Si cambió el comportamiento de cara al usuario: README y `PRODUCT.md`
- [ ] Si cambió un contrato de `docs/reference/`: los dos runtimes y sus dos tests
- [ ] `EXECUTION-PLAN.md`: mover lo terminado a "Entregado" **con evidencia**
- [ ] Actualizar "Estado verificado" y "Próximo paso" de este archivo
- [ ] Working tree limpio o el pendiente anotado arriba
