# CLAUDE.md — router del repositorio

MascoTuscan: plataforma de mascotas de escritorio para tus agentes de IA. El
programa decide **cuándo** hablar; un paquete instalable decide **cómo se ve y
cómo habla**. En macOS observa [cmux](https://cmux.com) y está en Swift, sin
dependencias; en Windows observa Claude Code directamente.

## Antes de empezar una sesión

1. Leer `claude-progress.md` — estado verificado y próximo paso.
2. Leer `EXECUTION-PLAN.md` — qué está en vuelo y qué ya se entregó (no re-trabajar).
3. Según la tarea, leer **una** de estas y no todas:
   - toco el formato de paquete → `docs/reference/pet-pack.md` (es el contrato)
   - toco el marketplace → `docs/marketplace.md`
   - toco el dibujo o la animación → `ARCHITECTURE.md` §Vistas
   - toco una fuente de eventos (cmux, hooks, o agrego una nueva) →
     `docs/reference/event-source.md` (es el contrato) + `docs/reference/cmux-events.md`
   - toco cómo se responde un permiso o una pregunta → `docs/reference/agent-reply.md`
     (es el contrato) + `docs/adr/0009`
   - toco los textos o la voz → `docs/adr/0002` y `docs/adr/0005`
   - decido si avisar o callar → `docs/adr/0004`
   - toco la versión, el release o el aviso de actualización → `docs/reference/versioning.md`
     (es el contrato: se implementa en Swift y en Python con los mismos tests)
   - voy a publicar o toco cómo se crean los tags → `docs/reference/tags.md`
4. Al cerrar: actualizar `claude-progress.md` con la checklist del final de ese archivo.

## Comandos

```bash
make verify     # el gate: build + tests Swift + hooks de zsh + instalador + integridad
make render     # dibuja cada estado de la mascota activa a PNG en ./render
make run        # arranca en primer plano
make install    # instala en ~/.mascotuscan, con las mascotas incluidas
make log        # sigue ~/.mascotuscan/pet.log
make tag        # publica la versión de VERSION: tag anotado y firmado + release por CI, solo desde main
make next-version   # propone X.Y.Z desde los commits (Conventional Commits)
make release-notes  # borrador de la sección del CHANGELOG
```

Comandos de mascota (el producto, no el build):

```bash
mascotuscan list                     # instaladas, con la activa marcada
mascotuscan use <id>                 # cambiar de mascota
mascotuscan search [texto]           # buscar en el marketplace
mascotuscan install <id|url|ruta>    # instalar; --use la activa, --force reemplaza
mascotuscan new <id> [--sprites]     # crear un paquete nuevo, ya válido
mascotuscan fork <origen> <nuevo>    # copia editable de una mascota existente
mascotuscan sprite <id> <estado> <f> # ponerle imagen; --dir <carpeta>, --clear
mascotuscan validate <ruta>          # revisar un paquete y explicar cada fallo
mascotuscan voice [<id>]             # que Claude Code le escriba las frases
mascotuscan info <id>
mascotuscan uninstall <id>
mascotuscan update [--check]         # reinstalar la última publicada; --check solo compara
```

`make verify` es el juez. Si pasa, el cambio es candidato; si no pasa, no existe.

## Límites duros

1. **Un pack nunca inventa un estado.** Los seis (`idle`, `working`, `done`,
   `error`, `attention`, `info`) son del programa: el orquestador no sabría cuándo
   usar uno nuevo. Ver `docs/adr/0005`.
2. **`PetPack.load` es la frontera del sistema.** Lo escribe un tercero: nada de
   rutas con `..`, colores sin validar ni sprites que no existan.
3. **Nunca editar un pack marcado `.bundled`.** Se reemplaza al actualizar y el
   trabajo del usuario se perdería sin aviso: primero `fork`. Todo cambio al
   manifiesto se revalida y se revierte si dejaría el paquete inválido.
4. **Las frases generadas van a `~/.mascotuscan/voices/<id>.json`, nunca dentro del
   pack.** Actualizar un pack no puede borrarlas.
5. **El prompt se compone**: personalidad del pack + contrato del programa. No
   meter personalidad en el código ni contrato en el pack.
6. **Toda mascota tiene respaldo.** `phrases.json` o las frases de `Scaffold`. La
   mascota no puede quedar muda.
7. **Nunca `boundingRect` + `draw(with:)` en la misma vista.** Divergen y cortan
   texto. Usar `layoutText(...)`. Ver `docs/adr/0003`.
8. **Nunca suprimir avisos por workspace.** Solo por pane exacto. Ver `docs/adr/0004`.
9. **Nunca llamar a un modelo en el camino de un aviso.** Ver `docs/adr/0002`.
10. **Nunca asumir que el texto de una notificación viene en el evento.** Llega
   redactado; se pide por `cmux rpc notification.list`.
11. **Nunca usar `tool_input` de los hooks.** Viene redactado. Solo hay `tool_name`.
12. **Nunca invocar el `claude` del PATH para generar la voz.** Es el envoltorio
    de cmux e inyecta hooks: la mascota se anunciaría a sí misma en bucle. Usar el
    binario real y filtrar eventos por `_ppid`.
13. **Nunca depender de launchd para el arranque.** El socket de cmux rechaza
    procesos que no descienden de cmux. Ver `docs/adr/0001`.
14. **Nunca bloquear el hilo principal con `cmuxJSON`.** Es sincrónico: va en
    `DispatchQueue.global`.
15. **Nunca escribir al disco del usuario desde el repo.** Todo el estado vive en
    `~/.mascotuscan`.
16. **Nunca dejar que un fallo sea silencioso.** Sin mascota instalada, sin socket
    o sin frases, se dice en pantalla.
17. **Nunca arte de personajes con dueño**, ni en los packs incluidos ni aceptado
    en el marketplace.
18. **Cero emojis** en código, mensajes, commits y documentación.
19. **Nunca crear carpetas de feature vacías** por simetría con la plantilla.
20. **Nunca cambiar la versión a mano.** `VERSION` es la fuente única y
    `scripts/bump-version.sh` propaga a Swift y Python; la integridad falla si
    divergen. Una funcionalidad del producto se define una vez en
    `docs/reference/` y se implementa en los dos runtimes con los mismos tests.
    Ver `docs/adr/0006`.
21. **Los tags siguen las reglas de `docs/reference/tags.md`, sin excepciones.**
    Ver la sección siguiente: es obligatoria para cualquier agente de IA que
    trabaje en este repo, no solo para Claude Code.
22. **Una fuente de eventos (`EventSource`) nunca decide mood ni compone
    texto.** Traduce su transporte a `NormalizedEvent`; el orquestador decide
    todo lo demás. Ver `docs/reference/event-source.md` y `docs/adr/0008`.
23. **El contenido de `feed.list` (permiso/pregunta pendiente) nunca se
    loguea ni se persiste.** Trae todos los workstreams activos, no solo los
    de esta mascota; se descarta todo lo que no matchee el `requestId`
    pendiente apenas se filtra. Ver `docs/reference/agent-reply.md` y
    `docs/adr/0009`.

## Reglas de tags — obligatorio para cualquier agente de IA

Publicar una versión es crear un tag, y un tag mal creado no se puede deshacer:
GitHub ya rechaza moverlo o borrarlo. Por eso estas reglas no son una preferencia
de estilo: son lo único que impide que un agente deje el historial de versiones
roto sin poder arreglarlo. El porqué de cada una está en
[`docs/reference/tags.md`](docs/reference/tags.md); esto es el qué.

- **Nunca `git tag` a mano.** Siempre `make tag`. Compone el mensaje, firma con
  SSH, corre `scripts/check-tag.sh` y solo entonces empuja.
- **Nunca mover, forzar ni borrar un tag ya empujado**, así el ruleset de GitHub
  lo permita por el rol de quien opera. Si un tag salió mal, se sube la versión
  y se etiqueta de nuevo (`scripts/bump-version.sh` + `make tag`); el tag viejo
  se queda y se documenta como perdido.
- **Nunca etiquetar fuera de `main` al día**, con cambios sin commit, o antes de
  que `VERSION` y su sección del `CHANGELOG.md` estén mergeados en `main`.
- **Nunca escribir a mano el mensaje del tag.** Sale de
  `scripts/changelog-section.sh`. Si no hay notas para la versión, se escriben
  en el CHANGELOG antes de etiquetar; no se inventan en el mensaje del tag.
- **Si `scripts/check-tag.sh` falla, el tag queda solo en local, sin empujar.**
  Se corrige la causa que reporta y se repite `make tag`. Nunca `--force`, ni
  editar el script o el ruleset para pasarlo por alto.

## Verificar en vez de recordar

Este repo se construyó depurando cuatro hipótesis falsas seguidas, y CI encontró
un archivo que el `.gitignore` excluía. La regla que salió de ahí: **una afirmación
sin comando que la respalde no entra a un documento.** Si no se pudo verificar, se
marca con ⚠️ y fecha.

Para lo visual, `make render` es la forma de verificar: escribe un PNG por estado
de la mascota activa, sin abrir ventana. No hace falta pedirle capturas al usuario.

Para un paquete, `mascotuscan validate` explica cada fallo. Úsalo antes de afirmar
que un pack está bien.

## Mapa del código

| Ruta | Qué vive ahí |
|---|---|
| `Sources/mascotuscan/main.swift` | arranque, señales, `--render`, despacho de subcomandos |
| `Sources/MascoTuscanKit/Model/PetPack.swift` | el formato de paquete y su validación |
| `Sources/MascoTuscanKit/Model/PetLibrary.swift` | instaladas, activa, instalar, quitar |
| `Sources/MascoTuscanKit/Model/Mood.swift` | los seis estados y `PetTheme` |
| `Sources/MascoTuscanKit/Model/Update.swift` | semver, estado y regla de silencio del aviso de versión |
| `Sources/MascoTuscanKit/CLI/` | subcomandos, scaffolding y registro del marketplace |
| `Sources/MascoTuscanKit/Voice/` | frases de la mascota activa y composición del prompt |
| `Sources/MascoTuscanKit/Views/` | renderer vectorial, sprites, burbuja, panel de estado |
| `Sources/MascoTuscanKit/Controller/EventSource.swift` | contrato `EventSource` y `NormalizedEvent` |
| `Sources/MascoTuscanKit/Controller/Sources/` | adapters: `CmuxEventSource`, `ShellHookEventSource`, `WmuxEventSource` (esqueleto) |
| `Sources/MascoTuscanKit/Controller/` | orquestador: ingiere eventos normalizados, decide mood y texto |
| `Sources/MascoTuscanKit/Controller/PetController+Actions.swift` | acciones hacia cmux: saltar de workspace, responder permiso/pregunta |
| `Sources/MascoTuscanKit/Model/PendingRequest.swift` | un permiso/pregunta sin responder, por `requestId` |
| `Sources/MascoTuscanKit/Support/` | rutas, puente con el CLI de cmux, tailer de archivos, formateo |
| `pets/` | mascotas incluidas: `astro`, `gatito`, `cangrejo` y `llama` |
| `windows/` | port para Windows en Python: mismos packs, mismo contrato de voz y de versión |
| `VERSION` | la versión del producto; `CHANGELOG.md` lleva sus notas |
| `registry.json` | el índice del marketplace |
| `shell/pet.zsh` | hooks `preexec`/`precmd` y autoarranque |
| `docs/adr/` | decisiones durables. Insert-once: no se editan |
| `docs/reference/` | contratos: formato de paquete, eventos de cmux, versionado y tags |

## Convenciones

- **Este repo es personal: siempre la cuenta `jonattan-infante`.** La cuenta
  activa de `gh` es estado global que otra sesión voltea, así que no se confía en
  ella: usar `make pr` y `make merge`, que piden el token de esa cuenta
  explícitamente. El remote ya está pinneado a `github-personal`.
- **`main` está protegido**: nada entra sin PR y sin los cuatro checks en verde.
  Ni el dueño puede empujar directo. Flujo: rama, `make pr`, `make merge`.
- Commits: Conventional Commits, imperativo y minúsculas
  (`feat(packs): validar rutas de sprites`).
- Ramas: `<tipo>/<descripcion-corta-en-kebab>`.
- Comentarios: explican **por qué**, nunca qué. Si el comentario parafrasea la
  línea siguiente, se borra.
- Español en documentación, comentarios y textos de usuario; inglés en
  identificadores de código.
