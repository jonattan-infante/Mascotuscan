# Reglas de los tags

Un tag es el acto de publicar una versión. Lo crea CI al mergear el PR que sube
`VERSION`, con el mismo script que corre `make tag` a mano; estas reglas existen
para que los dos caminos produzcan tags idénticos y para que CI rechace los que no
cumplan. La versión en sí (dónde vive el número, cómo se sube) está en
[`versioning.md`](versioning.md); por qué lo hace CI, en
[`docs/adr/0013`](../adr/0013-ci-publica-la-version.md).

## Las reglas

| # | Regla | Quién la exige |
|---|---|---|
| 1 | **Nombre `vX.Y.Z`.** Prefijo `v`, tres números, sin sufijos. Ni `0.3`, ni `v0.3.0-rc1`, ni `release-0.3.0` | `scripts/check-tag.sh`, ruleset de GitHub (`refs/tags/v*`) |
| 2 | **Anotado, nunca ligero.** Un tag ligero es un puntero sin autor, fecha ni mensaje. El anotado es un objeto con todo eso, y se puede firmar | `check-tag.sh` |
| 3 | **Firmado.** Con la llave de quien publica: la del job de CI, o la del dueño si corre `make tag`. Es lo que permite saber que el tag salió de un camino autorizado y no de alguien con acceso al remoto | `check-tag.sh` (presencia); GitHub muestra "Verified" si la llave está registrada |
| 4 | **Mensaje con forma fija.** Primera línea `mascotuscan X.Y.Z` (los ya publicados llevan el nombre de su momento: `cmux-pet` hasta `v0.2.2`, `lucy` en `v0.3.0`; ver `docs/adr/0010`); línea en blanco; después, tal cual, la sección `## [X.Y.Z]` del `CHANGELOG.md`. El tag se explica solo con `git tag -n99 vX.Y.Z` | `check-tag.sh` |
| 5 | **Apunta a un commit de `main`** y ese commit tiene `VERSION` = `X.Y.Z` y la sección del CHANGELOG | `check-tag.sh --on main`, `release.yml` |
| 6 | **Inmutable.** Un tag empujado no se mueve ni se borra. Si salió mal, se sube la versión y se etiqueta de nuevo; la versión perdida se anota en el CHANGELOG como "no publicada" | ruleset de GitHub: sin `update` ni `deletion` en `v*` |
| 7 | **Uno por versión y en orden.** No se etiqueta una versión menor que la última publicada | `check-tag.sh` |
| 8 | **Lo crea `scripts/tag-release.sh`.** Lo corre `publicar.yml` cuando entra a `main` un `VERSION` sin tag; `make tag` es el respaldo manual. Valida todo lo anterior antes de empujar | convención; `CLAUDE.md`; ruleset (solo el administrador y las deploy keys crean `v*`) |

`v0.2.0` se creó antes de estas reglas: es anotado y apunta al commit correcto,
pero no lleva notas en el mensaje ni firma. Por la regla 6 se queda así; las reglas
aplican desde `v0.3.0`.

## Por qué así

Es lo que hacen los repositorios grandes, verificado en sus tags reales por la API
de GitHub el 2026-09-17:

| Proyecto | Tag | Objeto | Firmado | Mensaje |
|---|---|---|---|---|
| git/git | `v2.47.0` | anotado | sí | `Git 2.47` |
| nodejs/node | `v22.11.0` | anotado | sí | `2024-10-29 Node.js v22.11.0 'Jod' (LTS) Release` |
| rust-lang/rust | `1.82.0` | anotado | sí | `1.82.0 release` |
| kubernetes/kubernetes | `v1.31.0` | anotado | no (lo crea un robot) | `Kubernetes official release v1.31.0` |
| golang/go | `go1.23.0` | ligero | no | (ninguno) |

Y lo que dicen sus guías:

- Pro Git, "Tagging": *"It's generally recommended that you create annotated tags so
  you can have all this information"*; un anotado *"contain[s] the tagger name,
  email, and date; ha[s] a tagging message; and can be signed and verified"*.
- Node.js, `doc/contributing/releases.md`: *"Once you have created a tag and pushed
  it to GitHub, you must not delete and re-tag. If you make a mistake after tagging
  then you'll have to version-bump and start again and count that tag/version as
  lost."* El tag se firma con la llave de un releaser autorizado.
- GitHub, rulesets: para tags existen *"Restrict creations"*, *"Restrict updates"*
  y *"Restrict deletions"*, con patrón de nombre.

El mensaje con las notas del CHANGELOG (regla 4) va un paso más allá que
`Git 2.47`: el tag lleva las notas consigo, así que `git tag -n99` las muestra sin
red y sin GitHub. Es lo que hace Node.js con su fecha y tipo de release.

## El flujo, paso a paso

```bash
./scripts/next-version.sh        # propone X.Y.Z a partir de los commits desde el ultimo tag
./scripts/release-notes.sh       # borrador de la seccion del CHANGELOG, para editar
# editar CHANGELOG.md: pegar la seccion, corregir la prosa
./scripts/bump-version.sh X.Y.Z  # VERSION, Swift y Python
make pr && make merge            # al entrar a main, publicar.yml etiqueta y release.yml publica
```

`scripts/tag-release.sh` toma el commit que disparó `publicar.yml` (con
`make tag`, la punta de `origin/main`), lee su `VERSION` y compone el mensaje con
la sección del CHANGELOG de ese commit, sin limpiarlo
(`--cleanup=verbatim`: el modo por defecto de `git tag -F` borra los encabezados
`###`, y así perdió los suyos `v0.3.0`). Después firma, corre `check-tag.sh` y solo
entonces empuja. Si algo falla, borra el tag local (nunca llegó al remoto), explica
qué y el job queda en rojo. Si la versión ya tiene tag, no hace nada.

Si CI no pudo, el respaldo es el mismo script a mano, desde `main` al día y sin
cambios: `make tag`. Para reintentar en CI sin otro merge, `publicar.yml` también
corre con `workflow_dispatch`.

### Cómo se decide la versión

`next-version.sh` lee los commits desde el último tag y aplica Conventional Commits:

| En los commits | Salto | Ejemplo |
|---|---|---|
| `tipo!:` o `BREAKING CHANGE:` en el cuerpo | major (mientras la versión sea `0.x`, minor) | `0.2.0` → `0.3.0`; `1.4.2` → `2.0.0` |
| algún `feat:` | minor | `0.2.0` → `0.3.0` |
| solo `fix:`, `perf:`, `refactor:`, `docs:`, `chore:`... | patch | `0.2.0` → `0.2.1` |
| ningún commit | nada que publicar | salida 1 |

Es una propuesta: quien publica puede subir más si el cambio lo merece. Nunca menos.

### Cómo se redactan las notas

`release-notes.sh` agrupa los commits por tipo en las secciones de
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/):

| Tipo de commit | Sección |
|---|---|
| `tipo!:` | Incompatible |
| `feat` | Agregado |
| `refactor`, `perf`, `revert` | Cambiado |
| `fix` | Corregido |
| `docs` | Documentación |
| `chore`, `ci`, `test`, `build` | no salen: no le cambian nada al usuario |

Es un borrador. Las notas se escriben para quien usa el programa, no para quien lo
programa: se reescriben en prosa, se juntan los commits que cuentan una sola cosa,
y se quita lo que no se nota desde fuera.

## Firmar: configuración de una vez

### La llave de CI

Una llave SSH ed25519 propia del job, que empuja y firma. Vive en el environment
`release`, que solo acepta ramas protegidas, así que ni un PR ni otra rama la leen.
Se genera y se registra una vez, y la copia local se borra:

```bash
repo=repos/jonattan-infante/mascotuscan
gh api -X PUT "$repo/environments/release" --input - <<< \
  '{"deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}'
ssh-keygen -t ed25519 -N '' -C mascotuscan-release -f ./release_key
gh repo deploy-key add ./release_key.pub --allow-write --title "publicar version (CI)"
gh secret set RELEASE_SSH_KEY --env release < ./release_key
rm ./release_key ./release_key.pub
```

Si el secreto falta, `publicar.yml` falla en rojo diciendo cuál, solo cuando hay
una versión por publicar.

### La llave del dueño, para `make tag`

Con la llave SSH del perfil personal, solo en este repositorio:

```bash
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519_github.pub
git config tag.gpgsign true
git tag -s prueba -m prueba && git cat-file tag prueba | grep -c 'SSH SIGNATURE' && git tag -d prueba
```

Para que GitHub muestre el tag como **Verified**, la misma llave pública tiene que
estar registrada en la cuenta como *signing key* (Settings > SSH and GPG keys >
New SSH key > Key type: Signing Key). Con `gh`:

```bash
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add ~/.ssh/id_ed25519_github.pub --type signing --title "firma de tags"
```

Sin ese registro el tag sigue firmado y válido; GitHub solo lo marca "Unverified".

## Protección en GitHub

Un ruleset sobre `refs/tags/v*` con `creation`, `update` y `deletion` restringidos
(creado el 2026-09-17, id `23606182`) y dos bypass: el rol de administrador del
repositorio, que corre `make tag`, y las deploy keys, que es como empuja
`publicar.yml`. Nadie más crea, mueve ni borra un tag de versión: ni un
colaborador, ni el `GITHUB_TOKEN` de un workflow. Para quien tiene bypass la regla
6 es convención, no candado. El bypass del administrador se comprobó en los push
de `v0.2.1` y `v0.2.2`: GitHub reportó "Bypassed rule violations".

```bash
gh api repos/jonattan-infante/mascotuscan/rulesets/23606182 --jq '.bypass_actors'
```

El bypass de las deploy keys se agrega una vez:

```bash
gh api -X PUT repos/jonattan-infante/mascotuscan/rulesets/23606182 --input - <<< \
  '{"bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"},{"actor_id":null,"actor_type":"DeployKey","bypass_mode":"always"}]}'
```

## Qué está automatizado y qué no

Automatizado (`docs/adr/0013`): al entrar a `main` un `VERSION` sin tag, el tag,
su verificación y el release.

Sin automatizar, a propósito: proponer la versión y redactar las notas. Las
notas generadas de commits son un borrador, no una redacción, y se prefiere que
una persona las lea antes de publicar. Si algún día se monta (B15), el job solo
tiene que abrir el PR de versión: `next-version.sh`, `release-notes.sh`,
`bump-version.sh` y `make pr`. El resto ya ocurre al mergearlo.
