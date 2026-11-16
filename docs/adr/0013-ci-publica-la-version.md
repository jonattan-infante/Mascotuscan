# ADR 0013 — CI publica la versión al mergear su PR

- **Estado:** aceptada
- **Fecha:** 2026-11-15
- **Decide:** quién crea el tag de una versión, sobre qué commit y con qué llave

## Contexto

Pedido del autor: que CI publique la versión nueva.

Hasta ahora (`docs/adr/0006`, `docs/reference/tags.md`) publicar tenía dos pasos
humanos: mergear el PR que sube `VERSION` y, después, correr `make tag` desde una
máquina con la llave de firma. El segundo se olvidó. `0.4.0` entró a `main` el
2026-09-27 (#18) y el 2026-11-15 seguía sin tag:

```
$ cat VERSION                 -> 0.4.0
$ gh release list -L 1        -> lucy 0.3.0  Latest  v0.3.0
$ git show v0.3.0:Package.swift | grep -m1 'name:'   -> name: "lucy",
```

En esas siete semanas `install.sh` de `main` instalaba `v0.3.0`, que compila
`lucy`, y moría buscando `mascotuscan` (riesgo R12 de `EXECUTION-PLAN.md`).

Y el tag ya no podía ir sobre ese commit. GitHub dejó de aceptar el runner
`macos-14` (anotación de cada job de la corrida 43789379493, 2026-11-15:
`The configuration 'macos-14-arm64-us-default' is not supported`), y el
`release.yml` de `a076385` compila en `macos-14`: un tag ahí no habría tenido
release nunca, y los tags no se mueven. Tres de los cuatro checks obligatorios de
`main` corrían en ese runner, así que tampoco podía entrar ningún PR.

`tags.md` §Automatizar ya fijaba cómo tenía que ser el día que se montara: el job
usa su propia llave y entra al bypass del ruleset, sin tocar las reglas.

Al escribir los tests del script apareció además un bug del flujo manual:
`git tag -F` limpia el mensaje en modo `strip` y borra las líneas que empiezan con
`#`, así que el mensaje de `v0.3.0` perdió los encabezados `### Incompatible` de
sus notas (`git cat-file tag v0.3.0`), contra la regla 4 de `tags.md`.

## Decisión

- **Publicar es mergear.** `.github/workflows/publicar.yml` corre en cada push a
  `main`. Si `VERSION` ya tiene tag, no hace nada; si no, corre
  `scripts/tag-release.sh --push` y `release.yml` publica el release al ver el tag.
- **Un solo camino para crear el tag.** `scripts/tag-release.sh` compone el
  mensaje (con `--cleanup=verbatim`), firma, corre `check-tag.sh` y solo entonces
  empuja. Lo usan CI y `make tag`, que queda como respaldo manual. Las ocho reglas
  de `tags.md` no cambian.
- **El tag apunta al commit que disparó el workflow** (`$GITHUB_SHA`), como
  `make tag` apuntaba a la punta de `main`. Si otro merge entra mientras tanto,
  no viaja con notas que no lo mencionan.
- **Los runners pasan a `macos-15` y `macos-26`**, en `ci.yml` y en
  `release.yml`, en el mismo PR. Así el primer tag que crea CI, el de `0.4.0`,
  cae en un commit cuyo `release.yml` puede correr.
- **La llave es del job.** Una SSH ed25519 generada para esto, registrada como
  deploy key con escritura y guardada como secreto `RELEASE_SSH_KEY` en el
  environment `release`, que solo acepta ramas protegidas. La misma llave empuja
  y firma.
- **El ruleset `tags de version` suma el bypass para deploy keys**, junto al del
  administrador.
- **Las notas las sigue escribiendo una persona** en el PR de versión. CI no las
  genera.

## Alternativas descartadas

- **`GITHUB_TOKEN` con bypass para la app de GitHub Actions.** Un tag empujado
  con ese token no dispara otros workflows, así que `release.yml` no correría. Y
  el bypass valdría para cualquier job con `contents: write`: el harness de issues
  tiene uno.
- **Un token personal (PAT).** Da acceso a la cuenta, no a este repositorio; si se
  filtra, el daño no queda acotado a crear tags aquí.
- **Release del todo automático** (versión y notas generadas desde los commits).
  `tags.md` prefiere que una persona lea las notas antes de publicar. Se puede
  sumar después (B15) sin tocar nada de esto: solo abriría el PR de versión.
- **Llamar `release.yml` como workflow reutilizable desde `publicar.yml`.** Serían
  dos caminos para publicar un release. El tag empujado con la llave ya dispara
  `release.yml`.
- **Etiquetar el último commit que tocó `VERSION`** en vez del que disparó el
  workflow. Ata las notas al contenido con más fuerza, pero para `0.4.0` ese
  commit es `a076385`, con `macos-14`: el release nunca saldría. Habría que
  saltar a `0.5.0` y dejar `0.4.0` como versión perdida sin haberla intentado.

## Consecuencias

- **A favor:** sacar una versión no depende de recordar un paso ni de tener la
  llave de firma en una máquina concreta.
- **A favor:** CI y `make tag` producen el mismo tag, con el mismo script y los
  mismos tests (`scripts/test-release-tooling.sh`).
- **En contra:** la firma prueba que el tag salió del job, no de una persona. La
  autorización pasa a ser el merge a `main`, que exige PR y los checks
  obligatorios. Es el modelo de `kubernetes/kubernetes` en la tabla de `tags.md`.
- **En contra:** la llave puede empujar a ramas sin protección y crear tags `v*`.
  `main` le exige PR y checks como a cualquiera; el secreto solo lo lee un job que
  corre desde `main`.
- **En contra:** mientras la llave no se registre como *signing key* de una
  cuenta, GitHub muestra los tags como "Unverified", igual que hoy los del autor
  (B14). Siguen firmados y `check-tag.sh` lo comprueba.
- **Regla derivada:** `scripts/tag-release.sh` es sensible para el revisor de PRs
  y prohibido para el harness de issues, igual que `check-tag.sh`.
