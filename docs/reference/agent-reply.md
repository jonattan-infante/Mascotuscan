# Responder un permiso o una pregunta: el contrato `agent-reply`

Contrato del producto, dirección opuesta a `EventSource`
(`docs/reference/event-source.md`): acá el orquestador **escribe** hacia
cmux en vez de solo escuchar. Decisión y motivos: `docs/adr/0009`.

Fase 1, cmux/macOS-only: responder con un clic un permiso o una pregunta que
Claude dejó pendiente. Sin texto libre — ver "Fuera de alcance" abajo.

## Cómo se correlaciona un aviso con su respuesta

El stream de hooks (`cmux events`) sigue redactando `tool_input`/`context` en
`agent.hook.PermissionRequest` y `agent.hook.AskUserQuestion` — la regla 11 de
`CLAUDE.md` sigue siendo cierta para ese canal, no se toca. Pero ese mismo
payload trae, sin redactar, un id de correlación en un campo mal nombrado:

```json
{"_opencode_request_id": "claude-<uuid>-PermissionRequest-Bash-<epoch>", "_source": "claude", ...}
```

Verificado el 2026-09-17 contra `~/.cmuxterm/events.jsonl` real: el campo
aparece igual con `_source: claude` (no solo `opencode`, pese al nombre) y su
valor es idéntico al `request_id` que trae `cmux rpc feed.list '{}'` para el
mismo ítem. `CmuxEventSource.translate()` lo copia a
`NormalizedEvent.requestId`.

El contenido real (comando exacto, opciones de la pregunta) **no** viaja en
ese payload — sale de `feed.list`, que no redacta nada. `feed.list` devuelve
**todos** los workstreams activos, no solo los de esta mascota: el código
descarta de inmediato todo ítem que no matchee el `requestId` pendiente
(`PetController.extractPendingContent`) y **nunca loguea ni persiste** ese
contenido a disco (ni `pet.log` ni `~/.mascotuscan`).

Formas verificadas de un ítem de `feed.list` (2026-09-17, valores reales
reemplazados por sintéticos):

```json
{"id": "…", "kind": "permissionRequest", "request_id": "claude-…-PermissionRequest-Bash-…",
 "title": "Bash", "tool_input": "{\"command\":\"…\"}", "status": "pending|expired"}

{"id": "…", "kind": "question", "request_id": "claude-…-AskUserQuestion-…",
 "question_multi_select": false,
 "question_options": [{"id": "opt0", "label": "…", "description": "…"}]}
```

⚠️ `status` pasa a `"expired"` si nadie responde — visto ~2 min después de
creado en los casos observados, sin garantía documentada de ese número
exacto. `PetController.sweepExpiredRequests()` usa 90s de margen por las
dudas, pero la fuente de verdad de si expiró es la respuesta del RPC, no el
reloj local.

## Los RPC de respuesta

Ninguno está documentado en `docs/cli-contract.md` ni en `cmux feed --help`.
Se verificó el esquema exacto **sin tocar ningún permiso/pregunta real**:
`cmux rpc <método> '{}'` (o con un `request_id` inventado) devuelve un error
`invalid_params` que el propio cmux redacta con los campos que exige —
seguro de correr porque un `request_id` que no existe no afecta ninguna
sesión real.

```bash
$ cmux rpc feed.permission.reply '{}'
Error: invalid_params: feed.permission.reply requires request_id
$ cmux rpc feed.permission.reply '{"request_id":"x"}'
Error: invalid_params: feed.permission.reply requires mode ∈ once|always|all|bypass|deny
$ cmux rpc feed.permission.reply '{"request_id":"x","mode":"once"}'
{"delivered": true}

$ cmux rpc feed.question.reply '{"request_id":"x"}'
Error: invalid_params: feed.question.reply requires selections: [string]
$ cmux rpc feed.question.reply '{"request_id":"x","selections":["opt0"]}'
{"delivered": true}
```

| Método | Parámetros | Notas |
|---|---|---|
| `feed.permission.reply` | `request_id: string`, `mode: once\|always\|all\|bypass\|deny` | Fase 1 solo ofrece `once`/`deny` desde la burbuja; el resto son los modos reales de permiso de Claude Code, quedan documentados para más adelante |
| `feed.question.reply` | `request_id: string`, `selections: [string]` | Array de `question_options[].id`, incluso para una pregunta de una sola opción |
| `feed.exit_plan.reply` | `request_id: string`, `mode: ultraplan\|bypassPermissions\|autoAccept\|manual\|deny` | Hallazgo de paso, no usado en esta fase — mismo mecanismo, sin pedido |

⚠️ **Lo que falta verificar**: `{"delivered": true}` contra un `request_id`
inventado confirma que el JSON es válido, no que un agente real lo recibió.
Falta una prueba de punta a punta contra un permiso/pregunta real (workspace
descartable, no una sesión de trabajo) que confirme que el agente sigue con
la respuesta — pendiente de hacerse antes de considerar la fase 1 cerrada
del todo. Ver `docs/adr/0009`.

## La burbuja (PR2)

`BubbleView` gana su primer control interactivo (antes: cero `NSButton`/
`NSTextField` en todo el árbol de vistas). Cada `BubbleOption` de
`Bubble.options` se dibuja como su propia línea (`"  › <label>"`), con el
mismo motor de `docs/adr/0003` (nunca `boundingRect` + `draw(with:)`
mezclados) — no hay pills ni flow-wrap: una lista vertical es lo que entra en
los 272px de ancho fijo, y sirve igual para dos botones (permiso) que para
varias opciones largas (pregunta). Los botones solo se pintan y se pueden
clicar una vez que termina de "escribir" (`revealed(b) >= b.text.count`):
aparecer a mitad de camino es ruido, y el alto ya está reservado desde
`size(for:)` — no hay salto en pantalla. `mouseUp` primero busca si el clic
cayó en un `optionRect`; si no, cae al comportamiento de siempre (saltar al
workspace del aviso).

`PetController.respondToOption(_:)` mapea el `id` clicado a
`replyPermission`/`replyQuestion` según `pendingRequests[requestId].kind`. Un
fallo del RPC muestra una burbuja de error (regla 16) en vez de quedar mudo.

`PetController.fetchPendingContent` es una costura de test (mismo patrón que
`isCmuxFrontmost`/`CmuxEventSource.isShowingAttention`): en producción hace
el RPC real; los tests la reemplazan por una versión síncrona sin lanzar
`cmux`.

## Reparto de responsabilidad

| | Le toca al orquestador | Nunca |
|---|---|---|
| Guardar el pendiente | `PetController.ingest` cuando `reason` es `.permission`/`.question` y hay `requestId` | — |
| Buscar el contenido real | `fetchPendingContent` → `feed.list`, filtra por `requestId`, descarta el resto | loguear o persistir lo que no matchea |
| Responder | `replyPermission`/`replyQuestion` → `cmuxJSON` (nunca `cmuxFire`: un fallo se tiene que poder ver, regla 16) | responder en silencio si el RPC falla |
| Expirar | `sweepExpiredRequests`, ~90s de margen | asumir que el RPC de responder siempre va a funcionar |

## Fuera de alcance de esta fase

- **Texto libre / `workspace.prompt_submit`** (reenviar un mensaje nuevo, no
  responder uno pendiente): `PetPanel` fija `canBecomeKey = false` /
  `canBecomeMain = false` (`Chrome.swift`) — no puede tomar foco de teclado
  tal como está armado. Un campo de texto real requiere decidir antes cómo
  el panel aceptaría teclado sin romper que la mascota nunca interrumpe al
  usuario. Queda para una decisión aparte.
- **Windows**: sin RPC equivalente documentado (los hooks ahí son de una
  sola vía). Esta funcionalidad queda cmux-only, misma asimetría que
  `ShellCommand` en `docs/reference/event-source.md`.
- `feed.exit_plan.reply`: mismo mecanismo, no pedido en esta fase.

## Para verificar

`CmuxEventSourceTests.swift` prueba que `translate()` copia
`_opencode_request_id` a `requestId` (payloads sintéticos, sin lanzar cmux).
`PendingRequestContentTests.swift` prueba `extractPendingContent` y
`summarizeToolInput` contra fixtures literales — puro, sin proceso.
`PetControllerIngestTests.swift` prueba que un `.notification` con
`reason: .permission`/`.question` y `requestId` queda en `pendingRequests`,
que la burbuja se enriquece con botones cuando `fetchPendingContent` (con la
costura de test) trae contenido, y que un pendiente ya resuelto no se pisa
con botones tardíos. `BubbleViewTests.swift` prueba que `size(for:)` crece
con las opciones. `replyPermission`/`replyQuestion` lanzan `cmux` de verdad:
no hay unit test para eso, mismo criterio que el resto de `CmuxCLI.swift` —
se verifican a mano (ver arriba).

⚠️ **Verificación de punta a punta pendiente** (real, no contra un
`request_id` inventado): provocar un permiso y una pregunta reales en un
workspace descartable, hacer clic en un botón desde la burbuja de verdad, y
confirmar en el pane de cmux que el agente siguió con esa respuesta. `make
render` ya confirmó que la burbuja se ve y mide bien
(`render/burbuja-pendiente-0.png`, `-1.png`), pero eso no reemplaza probar el
RPC contra un pendiente vivo.
