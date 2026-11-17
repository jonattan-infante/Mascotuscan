# AGENTS.md

Catálogo de agentes del repo y flujo por feature: cinco agentes, un archivo por
agente en cada feature. Las definiciones que carga Claude Code están en
`.claude/agents/`; este archivo es el mapa. Por qué cinco: `docs/adr/0015`.

Dos reglas estructurales:

- **Maker/checker: quien implementa nunca valida su propio trabajo.** Un modelo es
  el mejor abogado defensor de su propia salida.
- **cmux es un cliente, no el producto.** Ningún agente diseña, implementa ni
  aprueba algo que solo funcione con un cliente sin declararlo en la spec. Hoy
  los clientes son cmux, la shell y los hooks de Claude Code; después vienen
  OpenCode, wmux y los que sigan (`docs/reference/event-source.md`).

## El equipo

| Agente | Rol | Escribe, y nada más | Nunca hace |
|---|---|---|---|
| `pet-product` | qué se construye y cuándo está terminado | `01-spec.md`, `PRODUCT.md`, backlog de `EXECUTION-PLAN.md` | código, arte, controles |
| `pet-ux` | cómo se ve, se lee y habla: estados, burbuja, panel, voz, CLI, guía de packs | `02-ux.md` y su imagen | lógica, cambiar casos |
| `pet-security` | amenazas en las fronteras y si sus controles existen | `03-seguridad.md` | arreglar código |
| `pet-developer` | implementa en Swift y Python con los mismos tests | código, tests, `ARCHITECTURE.md`, `04-entrega.md` | aprobar su trabajo |
| `pet-qa` | intenta refutar que funcione y que se vea bien | `05-qa.md` | arreglar código |

## Flujo por feature

```
idea, issue o fila del backlog
      │
      ▼
pet-product ──► 01-spec.md: casos, Toca, Fuentes
      │         Jonattan firma §Aprobación
      ├── Toca vista o texto ──► pet-ux ─────────► 02-ux.md + imagen
      ├── Toca frontera ───────► pet-security ───► 03-seguridad.md §Antes (casos S)
      ▼
pet-developer ──► código, tests, PR y 04-entrega.md
      │
      ├──► pet-qa ─────────► 05-qa.md: veredicto por caso
      └──► pet-security ───► 03-seguridad.md §Después (si toca frontera)
      │
      ├── rechazado o bloqueado: vuelve a pet-developer con el caso que falla
      ▼
pet-product llena §Aceptación ──► Jonattan mergea: "listo"
```

| Paso | Empieza cuando | Termina cuando |
|---|---|---|
| `pet-product` | hay una idea, un issue o una fila del backlog | cada caso dice cómo se comprueba y Jonattan firmó §Aprobación |
| `pet-ux` | spec aprobada con "Toca: vista o texto" | cada caso visible tiene texto exacto o imagen |
| `pet-security` §Antes | spec aprobada con "Toca: frontera" | cada amenaza tiene control y caso S |
| `pet-developer` | spec aprobada, y UX y seguridad terminados si les tocaba | gate verde, PR abierto, cada caso con test |
| `pet-qa` | hay `04-entrega.md` y PR | veredicto por cada caso |
| `pet-security` §Después | hay `04-entrega.md` y la spec toca frontera | cada control con `archivo:línea` |
| `pet-product` acepta | QA `aprobado` y seguridad sin bloqueantes | §Aceptación llena |
| Jonattan | producto aceptó | `make merge` |

Fronteras que llaman a `pet-security`, lista cerrada: una fuente de eventos nueva
o cambiada; `PetPack.load` y packs de terceros; `install` desde URL o
marketplace; aviso y descarga de versión; escritura en la configuración del
usuario; respuesta a permisos o preguntas de un agente; workflows de CI y sus
prompts. El porqué de cada una está en `.claude/agents/pet-security.md`.

Reglas del ciclo:

- **Jonattan aprueba cada spec** antes de que empiece UX, seguridad o desarrollo
  (decisión del 2026-11-16, al menos para las primeras features).
- Si la feature cambia el orquestador, al menos un caso usa dos `source`
  distintos.
- Lo fuera de alcance vuelve a `pet-product`, que lo lleva al backlog con
  severidad. No se arregla de paso.
- Una spec ambigua o un choque entre UX y spec vuelve a `pet-product`. Nadie
  inventa.
- Cada agente arranca de los archivos de la feature, no del prompt de quien lo
  llama: funcionan igual orquestados o por separado.
- Solo se crean los archivos que tocan: una feature sin vista no tiene `02-ux.md`.
- Una decisión durable no se queda en un artefacto: va a un ADR nuevo.

## Artefactos

Plantillas en `docs/features/_template/`. Si un artefacto no cabe en su tope, la
feature es demasiado grande y `pet-product` la parte.

| Archivo | Dueño | Qué lleva | Tope |
|---|---|---|---|
| `01-spec.md` | `pet-product` | problema, fuera de alcance, Toca, Fuentes, casos, aprobación, aceptación | 60 líneas |
| `02-ux.md` | `pet-ux` | qué ve el usuario por caso, sin el cliente que lo permite, textos exactos, medidas | 40 líneas e imagen |
| `03-seguridad.md` | `pet-security` | §Antes: entrada, abuso, control, caso S · §Después: control en `archivo:línea` | 40 líneas |
| `04-entrega.md` | `pet-developer` | SHA, PR, gate pegado, caso y test por runtime, lo que quedó fuera | 30 líneas y la salida |
| `05-qa.md` | `pet-qa` | veredicto, gate reproducido, caso por fuente, imágenes, hallazgos, refutación | 50 líneas y la salida |

## Los agentes de CI

No son parte del equipo: los dispara GitHub, no una persona, y son la revisión de
lo que llega de afuera.

| Agente | Workflow | Qué hace | Rol del equipo que cubre |
|---|---|---|---|
| `evaluar` y `implementar` | `claude-issues.yml` | diagnostica un issue y, si el error es evidente, lo corrige | `pet-product` y `pet-developer` |
| `revisar` | `claude-revision.yml` | revisa cada PR y puede bloquear el merge | `pet-security` y `pet-qa` |

Que lean las mismas reglas que el equipo es un PR aparte (`EXECUTION-PLAN.md`,
B17). Hasta entonces, sus contratos siguen en `docs/reference/claude-issues.md` y
`docs/reference/claude-revision.md`.

## Roles diferidos a propósito

| Rol | Por qué no existe todavía | Cuándo crearlo |
|---|---|---|
| Curador del marketplace | hoy son 4 mascotas incluidas y los PRs los revisa el dueño | cuando lleguen PRs de mascotas de terceros con regularidad |
| DevOps | CI, `Makefile` y `publicar.yml` alcanzan | si el pipeline necesita alguien que lo opere |
| Orquestador | el flujo vive en los artefactos y en estas tablas | probablemente nunca: un orquestador gordo esconde el flujo |

## Anti-patrones

- **Creerle a un checker sin verificar.** Un revisor también alucina: toda
  corrección se comprueba contra el código antes de aplicarla.
- **Pasar contexto por el prompt** en vez de dejarlo en disco. Si un agente lo
  necesita para trabajar, va en un archivo de la feature.
- **Un solo agente que implementa y aprueba.**
- **Diseñar para cmux y "ver después" los otros clientes.**
- **Copiar toda la plantilla por simetría.** Solo los archivos que van a tener
  contenido.
- **Confiar en que `tools:` limita rutas.** Limita herramientas: que cada agente
  escriba solo su archivo lo sostiene la instrucción. Si se rompe, el siguiente
  paso es un hook `PreToolUse` por agente.
