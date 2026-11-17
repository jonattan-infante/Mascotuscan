# ADR 0015 — Un equipo de cinco agentes, un archivo por agente

- **Estado:** aceptada
- **Fecha:** 2026-11-16
- **Decide:** qué agentes trabajan una feature, en qué orden, qué entrega cada
  uno y quién la da por terminada

## Contexto

`AGENTS.md` describía tres agentes (`pet-maker`, `pet-checker`,
`pet-visual-checker`) y postergaba a propósito Producto y Seguridad ("Tres, no
nueve"). Al 2026-11-16:

- Ninguno existía como agente de Claude Code: no había `.claude/agents/`.
- Ninguna feature había pasado por el flujo: `docs/features/` solo tenía
  `_template/`.
- sea-battle, otro repo del autor, trabaja con cuatro agentes y artefactos por
  paso; su QA dejó 25 reportes en `docs/game/qa/`.
- El revisor de PRs de CI (`docs/adr/0012`) ya hace trabajo de seguridad y de
  QA, pero solo cuando el código existe.

El autor pidió cinco agentes (producto, UX, desarrollo, QA y seguridad), con un
flujo definido y artefactos concisos para iterar el ciclo de vida, y fijó un
principio: **cmux es solo un cliente**; la mascota tiene que funcionar con muchos
más, incluido Claude Code nativo.

Preguntado, decidió (2026-11-16):

1. Los agentes de CI se quedan, y se alinean con el equipo en un PR aparte.
2. Él aprueba cada spec antes de que se empiece a trabajar, al menos en las
   primeras features.
3. La feature piloto es Claude Code nativo en macOS, sin cmux.

## Decisión

**Cinco agentes en `.claude/agents/`, cada uno dueño de un solo archivo por
feature** en `docs/features/FEAT-XXX/`, con tope de líneas:

| Archivo | Dueño | Tope |
|---|---|---|
| `01-spec.md` | `pet-product` | 60 |
| `02-ux.md` e imagen | `pet-ux` | 40 |
| `03-seguridad.md` | `pet-security` | 40 |
| `04-entrega.md` | `pet-developer` | 30 y la salida del gate |
| `05-qa.md` | `pet-qa` | 50 y la salida del gate |

**La spec enruta, no un orquestador.** "Toca: vista o texto" llama a `pet-ux`;
"Toca: frontera", de una lista cerrada, llama a `pet-security`, que trabaja antes
del código (amenazas y casos S) y después (dónde está cada control).

**La spec declara sus fuentes de eventos.** Si cambia el orquestador, un caso usa
al menos dos `source` distintos; QA prueba con cada fuente declarada. Así el
principio "cmux es un cliente" se comprueba en cada feature, no solo se enuncia.

**Terminado** es QA `aprobado`, seguridad sin bloqueantes y producto aceptando
contra la spec. "Listo" lo declara el autor al mergear.

El flujo, las fronteras y las reglas del ciclo viven en `AGENTS.md`.

## Alternativas descartadas

- **Seguir con tres.** El rol de producto lo hacía el autor sin plantilla, y no
  rodó ninguna feature; seguridad quedaba en manos del revisor de CI, que llega
  cuando el código ya está escrito. Un control diseñado antes cuesta menos que un
  hallazgo que bloquea después.
- **Seguridad en todas las features.** En una sin frontera solo agrega ceremonia,
  y el revisor de CI igual mira cada PR.
- **Un orquestador que llame a los demás.** Esconde el flujo en un prompt; aquí
  vive en archivos que se pueden leer y en una tabla.
- **Borrar los agentes de CI.** Son la única revisión de los PRs de terceros y ya
  encontraron fallas reales: `roam` sin validar en Windows, en la revisión de #26
  (corrida 43949845781).

## Consecuencias

- Una feature cuesta como mínimo tres archivos (spec, entrega y QA) y una firma
  del autor. Es el precio de que nada avance sin evidencia.
- `tools:` restringe herramientas, no rutas: que cada agente escriba solo su
  archivo lo sostiene la instrucción. Si se rompe, el paso siguiente es un hook
  `PreToolUse` por agente.
- En Linux no hay Swift: desarrollo y QA dependen del CI del PR para el gate de
  macOS y del artefacto `vista-previa` para las imágenes.
- `PRODUCT.md` deja de describir el producto alrededor de cmux y lleva una matriz
  de clientes con evidencia.
- Los agentes de CI quedan fuera del equipo hasta alinearlos (`EXECUTION-PLAN.md`,
  B17).
