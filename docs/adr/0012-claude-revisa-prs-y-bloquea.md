# ADR 0012 — Claude revisa cada PR y un status con reglas fijas bloquea el merge

- **Estado:** aceptada
- **Fecha:** 2026-09-28
- **Decide:** cómo un agente revisa seguridad y calidad de cada PR hacia `main` y
  cómo esa revisión bloquea el merge

## Contexto

Pedido del autor: un agente evaluador de PRs que revise seguridad y calidad de
código, y que sea bloqueante para aceptar un PR.

Lo que ya existía (`docs/adr/0011`): un harness en el que Claude solo produce
datos y un script con tests decide qué se publica; dos environments con el token
de la suscripción (`claude`, con aprobación, y `claude-auto`, sin ella, los dos
solo desde `main`); y un escaneo de secretos antes de publicar nada.

Lo que cambia con un PR respecto de un issue:

- El PR trae **código** de un tercero, no solo texto. Para que un fork use el
  token de Claude hace falta `pull_request_target`, que corre con secretos; el
  error clásico con ese evento es ejecutar el código del PR.
- El PR puede traer **instrucciones para agentes** (`CLAUDE.md`, `.claude/`) que
  Claude Code cargaría solas si estuvieran en el workspace.
- La revisión decide un **merge**: un PR que convenza a Claude de aprobarlo no
  puede convertir eso en un check verde.

## Decisión

Un workflow de tres jobs (`docs/reference/claude-revision.md`):

- **El status lo pone el harness.** Claude devuelve hallazgos con severidad.
  `scripts/revision-harness.py` valida que el veredicto coincida con ellos, suma
  los hallazgos que no dependen de un modelo (credenciales en las líneas
  agregadas) y pone `claude/revision` en `failure` si hay alguno `critica` o
  `alta`. Ese status es un check obligatorio de `main`.
- **El código del PR se lee, nunca se ejecuta.** El workflow, el prompt, el
  esquema, los `settings` y el harness salen de `main`. El PR se baja a
  `claude-pr/` sin credenciales; de él solo corre `git diff` sin drivers. Sus
  instrucciones para agentes se renombran y sus enlaces simbólicos se quitan.
- **Aprobación donde hay riesgo.** Un PR de un fork, o uno que toca las reglas
  de Claude, las instrucciones de los agentes o la publicación, espera la
  aprobación del dueño antes de que Claude lo lea. El resto corre solo.
- **Salida de emergencia auditable.** El dueño puede anular la revisión de un
  commit con una etiqueta; queda escrito quién y en qué commit, y el commit
  siguiente se revisa de nuevo.

## Alternativas descartadas

- **Una review de GitHub de Claude con "Request changes".** Para que bloquee,
  `main` tendría que exigir reviews aprobadas, y el dueño no puede aprobar sus
  propios PRs. Además la decisión quedaría en el modelo. Un status de un script
  con tests es lo que la protección de `main` ya sabe exigir.
- **`pull_request` en vez de `pull_request_target`.** No tiene secretos en un PR
  de un fork, y en uno del repo correría el workflow del propio PR: el PR podría
  cambiar las reglas que lo revisan.
- **El job del action como check obligatorio.** En `workflow_dispatch` ese check
  queda en el commit de `main`, no en el del PR, y un job que espera aprobación
  o se salta no dice por qué. Un status explícito en el SHA del PR es el mismo
  venga de donde venga la revisión, y distingue "espera aprobación", "falló" y
  "bloqueado".
- **Comentarios en línea por hallazgo.** Se apilan en cada push y no se pueden
  actualizar como uno solo. Un comentario único que se reemplaza deja el estado
  actual siempre arriba, y el run guarda el historial.
- **Pedir aprobación para todo PR.** El autor de una rama del repo ya puede
  escribir en él; sumarle un clic por PR no protege nada que no proteja ya el
  permiso de escritura.

## Consecuencias

- **A favor:** que un PR se pueda mergear lo decide código con tests. Un PR
  hostil puede engañar a Claude, pero no ocultar una credencial agregada ni
  convertir un hallazgo grave en un veredicto verde.
- **A favor:** los PRs que abre el harness de issues pasan por el mismo revisor.
- **En contra:** cada PR consume la suscripción del autor, y un PR sensible pide
  un clic antes de poder mergearse.
- **En contra:** un falso positivo bloquea hasta que el dueño lo anula o lo
  corrige con otro commit.
- **Regla derivada:** el harness compartido (`scripts/harness_comun.py`) y el
  revisor no se modifican desde un issue, y un PR que los toca es sensible. Un
  test comprueba que todo lo que el harness de issues prohíbe es sensible para
  el revisor, salvo `CHANGELOG.md`, que cambia en cada versión.
