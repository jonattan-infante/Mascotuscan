# Reglas de los tags

Un tag es el acto de publicar una versión. Estas reglas existen para que cualquier
persona, o cualquier automatización, cree tags idénticos a los que crea `make tag`,
y para que CI rechace los que no cumplan. La versión en sí (dónde vive el número,
cómo se sube) está en [`versioning.md`](versioning.md).

## Las reglas

| # | Regla | Quién la exige |
|---|---|---|
| 1 | **Nombre `vX.Y.Z`.** Prefijo `v`, tres números, sin sufijos. Ni `0.3`, ni `v0.3.0-rc1`, ni `release-0.3.0` | `scripts/check-tag.sh`, ruleset de GitHub (`refs/tags/v*`) |
| 2 | **Anotado, nunca ligero.** Un tag ligero es un puntero sin autor, fecha ni mensaje. El anotado es un objeto con todo eso, y se puede firmar | `check-tag.sh` |
| 3 | **Firmado.** Con la llave SSH o GPG de quien publica. Es lo que permite saber que el tag lo creó una persona autorizada y no alguien con acceso al remoto | `check-tag.sh` (presencia); GitHub muestra "Verified" si la llave está registrada |
| 4 | **Mensaje con forma fija.** Primera línea `mascotuscan X.Y.Z` (los ya publicados llevan el nombre de su momento: `cmux-pet` hasta `v0.2.2`, `lucy` en `v0.3.0`; ver `docs/adr/0010`); línea en blanco; después, tal cual, la sección `## [X.Y.Z]` del `CHANGELOG.md`. El tag se explica solo con `git tag -n99 vX.Y.Z` | `check-tag.sh` |
| 5 | **Apunta a un commit de `main`** y ese commit tiene `VERSION` = `X.Y.Z` y la sección del CHANGELOG | `check-tag.sh --on main`, `release.yml` |
| 6 | **Inmutable.** Un tag empujado no se mueve ni se borra. Si salió mal, se sube la versión y se etiqueta de nuevo; la versión perdida se anota en el CHANGELOG como "no publicada" | ruleset de GitHub: sin `update` ni `deletion` en `v*` |
| 7 | **Uno por versión y en orden.** No se etiqueta una versión menor que la última publicada | `check-tag.sh` |
| 8 | **Lo crea `make tag`.** Es el único camino: valida todo lo anterior antes de empujar. A mano solo para reproducir el flujo en otro sitio | convención; `CLAUDE.md` |

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
make pr && make merge            # la version entra a main por PR, como todo
git checkout main && git pull
make tag                         # tag anotado y firmado, verificado, empujado; CI publica el release
```

`make tag` compone el mensaje, firma, corre `check-tag.sh` y solo entonces empuja.
Si algo falla, borra el tag local (nunca llegó al remoto) y explica qué.

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
y bypass para el rol de administrador del repositorio (creado el 2026-09-17, id
`23606182`). Nadie sin ese rol crea, mueve ni borra un tag de versión: ni un
colaborador, ni un token de CI. El administrador conserva el bypass porque es quien
corre `make tag`; para él la regla 6 es convención, no candado. **El bypass en un
push real se comprueba con el primer `make tag` después del ruleset** ⚠️ 2026-09-17.

```bash
gh api repos/jonattan-infante/mascotuscan/rulesets --jq '.[] | "\(.name): \(.target) \(.enforcement)"'
```

## Automatizar del todo

Todo lo de arriba corre sin preguntar nada, así que un job puede hacerlo:

1. `next-version.sh` → `X.Y.Z`; si sale 1, no hay nada que publicar.
2. `release-notes.sh X.Y.Z` → sección; pegarla al CHANGELOG.
3. `bump-version.sh X.Y.Z`; commit `chore(release): X.Y.Z`; PR; esperar CI; merge.
4. `make tag` con una llave de firma propia del job.

No está montado porque las notas generadas de commits son un borrador, no una
redacción; hoy se prefiere que una persona las lea antes de publicar. El día que se
monte, el job debe usar su propia llave registrada como signing key y entrar al
bypass del ruleset, sin tocar nada de lo anterior.
