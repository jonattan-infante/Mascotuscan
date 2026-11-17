# FEAT-XXX — <título>

> La escribe `pet-product`. Máximo 60 líneas. Copiar a `docs/features/FEAT-XXX/`
> solo los archivos de la plantilla que esta feature va a usar.

- Estado: `borrador` / `aprobada` / `aceptada`

## Problema

Qué le pasa hoy al usuario, en términos de lo que ve, no de lo que falta en el
código.

## Fuera de alcance

Lo que explícitamente no se hace. Esta sección evita que la feature crezca sola.

## Toca

- [ ] vista o texto: `pet-ux` escribe `02-ux.md`
- [ ] frontera (lista en `AGENTS.md`): `pet-security` escribe `03-seguridad.md`

## Fuentes

- [ ] todas: cambia el orquestador; un caso usa al menos dos `source` distintos
- [ ] cmux · [ ] hooks de Claude Code · [ ] shell · [ ] OpenCode · [ ] otra:

Si aplica a una sola, por qué.

## Casos verificables

Cada caso tiene que poder fallar. Los casos de seguridad (S1, S2...) están en
`03-seguridad.md`.

| # | Dado | Cuando | Entonces | Cómo se comprueba |
|---|---|---|---|---|
| C1 | | | | test o comando concreto |

## Preguntas abiertas para Jonattan

## Aprobación

Sin esta firma no empieza nadie.

- Aprobada por Jonattan el:

## Aceptación

La llena `pet-product` cuando `05-qa.md` dice `aprobado` y seguridad no bloquea.

| Caso | Evidencia en `05-qa.md` | ¿Cumple? |
|---|---|---|
| C1 | | sí / no |
