# Claude revisa PRs: el revisor bloqueante

Contrato de cómo Claude revisa un PR y cuándo lo bloquea. Lo implementan
`.github/workflows/claude-revision.yml` (el orden y los permisos),
`scripts/revision-harness.py` (las reglas) y `.github/claude/revisar.md` con
`revision.schema.json` (lo que se le pide a Claude). Comparte con el harness de
issues el escaneo de secretos y la limpieza de texto (`scripts/harness_comun.py`).
La decisión y sus alternativas están en `docs/adr/0012`.

**Principio:** Claude revisa; las reglas deciden. El status `claude/revision`, que
es lo que bloquea el merge, lo pone un script con reglas fijas a partir de los
hallazgos, nunca el modelo. Claude no tiene con qué escribir en el repo ni en
GitHub, y el código del PR se lee pero nunca se ejecuta.

## Flujo

```
PR hacia main ──► preparar ────────────► revisar ─────────────────► publicar
(abierto, push,   sin Claude ni secretos  Claude, solo lectura       sin Claude
 listo, etiqueta) status pendiente        fork o sensible: espera    comentario y
                  etiquetas               tu aprobación              status en el commit
```

Un PR que abre el harness de issues se revisa igual: su job `publicar` pide la
revisión con `workflow_dispatch`, porque un PR abierto con el token del workflow
no dispara `pull_request_target`.

Cada commit nuevo cancela la revisión en curso y empieza otra. Un borrador no se
revisa: queda con el status pendiente hasta que lo marcas listo.

## Qué bloquea

| Severidad | Cuándo, según `revisar.md` | Bloquea |
|---|---|---|
| `critica` | se puede explotar o destruye algo: código de terceros con secretos, una credencial expuesta, un paquete que escribe fuera de su carpeta, datos del usuario borrados, un intento de manipular la revisión | **sí** |
| `alta` | rompe un flujo principal, pierde trabajo del usuario, viola un límite duro de `CLAUDE.md` o abre una debilidad de seguridad concreta | **sí** |
| `media` | caso borde, falta el test de un cambio, documentación desactualizada | no |
| `baja` | estilo, nombres, una mejora menor | no |

`decidir` pone `failure` si hay al menos un hallazgo `critica` o `alta`, de Claude
o del harness, y `success` si no. Los hallazgos del harness no dependen de un
modelo: toda línea que el PR agrega y tiene forma de credencial es `critica`, y
bloquea aunque Claude haya aprobado.

`validar_revision` rechaza la respuesta de Claude, y la revisión falla, si:

- falta o sobra un campo, o un valor está fuera de su lista;
- una ruta sale del repo (absoluta o con `..`);
- el veredicto no coincide con los hallazgos: `bloquear` sin uno grave, o
  `aprobar`/`cambios` con uno grave. Un PR que convenza a Claude de aprobar no
  borra lo que Claude encontró.

## Cuándo espera tu aprobación

`revisar` corre en el environment `claude` (espera tu aprobación) si el PR:

- **viene de un fork**, incluido uno borrado, o
- **es sensible**: toca `.github/`, `.claude/`, cualquier `CLAUDE.md`,
  `CLAUDE.local.md` o `AGENTS.md`, `VERSION`, los dos harness y sus tests
  (`scripts/harness_comun.py`, `issue-harness.py`, `revision-harness.py`,
  `scripts/tests/`, `test-issue-harness.sh`) o los scripts de publicación.
  Un archivo renombrado cuenta por sus dos nombres.

Si no, corre en `claude-auto` sin esperar: el autor de una rama del repo ya tiene
permiso de escritura.

Que un PR sea sensible se decide dos veces: en `preparar`, con la lista de la API
(si la API no alcanza a listar todos los archivos, cuenta como sensible), y en
`revisar`, con `git diff --name-only` sobre el commit exacto, antes de que corra
Claude. Si la segunda dice sensible y la corrida no esperó tu aprobación, falla.

Aprobar la corrida no aprueba el PR: solo deja que Claude lo revise.

## El código del PR se lee, nunca se ejecuta

`pull_request_target` corre el workflow de `main` con acceso a los secretos, así
que en `revisar`:

- la raíz del workspace es `main`, con sus reglas, su prompt y su esquema; el
  harness se copia fuera del workspace antes de que corra Claude y se ejecuta
  desde ahí;
- el PR se baja a `claude-pr/` sin credenciales, y de él solo corre `git diff`
  sin drivers ni textconv. Después se borra su `.git/`;
- sus `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` y `.claude/` se renombran con
  `.pr`, para que Claude Code no los cargue como instrucciones;
- sus enlaces simbólicos se reemplazan por un texto que dice a dónde apuntaban:
  uno podría apuntar a `/proc/self/environ`;
- los `settings` de Claude se pasan en línea, leídos de `main` antes de que la
  action corra.

Claude tiene `Read`, `Grep` y `Glob`, y nada más. Las mismas negaciones de
`.github/claude/settings.json` que en el harness de issues.

## Jobs, permisos y secretos

| Job | Corre Claude | Tu token de Claude | Token del workflow | Aprobación |
|---|---|---|---|---|
| `preparar` | no | no | contents y pull-requests: read; issues y statuses: write | no |
| `revisar` | sí: Read, Grep, Glob | sí (`claude` o `claude-auto`) | contents y pull-requests: read | **si es fork o sensible** |
| `publicar` | no | no | contents: read; issues, pull-requests y statuses: write | no |

## Secretos

Lo mismo que en `docs/reference/claude-issues.md` §Secretos, más:

- **El registro trae código ajeno.** `ejecucion-revisar.json`, `cambios.diff` y
  `pr.md` contienen el PR. Si tienen el valor exacto de un token nuestro, el run
  falla y no se sube nada. Si solo tienen algo con forma de credencial (del
  propio PR), la revisión se publica sin ellos, y el comentario lo dice.
- **Lo que escribe Claude** (`revision.json`, `comentario.md`) y los hallazgos
  del harness pasan el escaneo completo; si algo aparece, no se publica nada.
- **Ningún hallazgo repite la credencial**: dice archivo, línea y regla.

## Qué ves en el PR

- **Un solo comentario** que se actualiza en cada commit: el del bot que empieza
  con `<!-- claude-revision -->`. Dice si bloquea, el resumen de Claude, los
  hallazgos por severidad con enlace a las líneas en ese commit, y el run.
- **El status `claude/revision`** en el commit del PR: pendiente mientras revisa
  o espera tu aprobación; `success` o `failure` según `decidir`; `failure` si
  nadie aprobó la corrida; `error` si la revisión falló.

## Etiquetas

| Etiqueta | Quién | Qué hace |
|---|---|---|
| `claude:revisar` | quien puede poner etiquetas | revisa el commit actual otra vez; se quita sola |
| `claude:revision-anulada` | **solo quien administra el repo** | pone `claude/revision` en `success` para el commit actual y lo deja escrito en el comentario, con quién y en qué commit. Es la salida ante un falso positivo. Un commit nuevo la quita y se revisa de nuevo. Si la pone alguien sin administración, no cuenta y se revisa de nuevo |

## Auditoría

| Dónde | Qué queda |
|---|---|
| El PR | el comentario de la revisión o de la anulación, con el commit y el run |
| El commit | el status `claude/revision` con su descripción y enlace al run |
| Settings > Environments | quién aprobó o rechazó cada revisión que lo pidió |
| Artefacto `revision`, 90 días | `revision.json`, `deterministas.json`, `comentario.md` y, si pasaron el escaneo, `pr.md`, `cambios.diff` y `ejecucion-revisar.json` (la conversación completa de Claude) |

## Configuración, una vez

Después de mergear el workflow:

1. Los environments `claude` y `claude-auto` son los del harness de issues
   (`docs/reference/claude-issues.md` §Configuración). No hace falta otro.
2. **Settings > Branches > la regla de `main`**: en *Require status checks to
   pass*, agrega `claude/revision`. GitHub solo lo ofrece después de verlo una
   vez: abre un PR cualquiera y espera su primera revisión.

## Sin verificar todavía

⚠️ 2026-09-28, nada de esto corrió todavía en GitHub:

- que `claude-code-action@v1` acepte el evento `pull_request_target` en modo
  automatización sin intentar escribir ni cambiar de rama el workspace;
- que acepte un `workflow_dispatch` pedido por `github-actions[bot]` con
  `allowed_bots: github-actions`;
- que `actions/checkout` con `fetch-depth: 0` y un SHA deje `origin/main` para el
  diff, también para un PR de un fork;
- que un environment con revisores rechazado deje el job en `failure`, que es lo
  que `publicar` usa para decir que nadie aprobó.
