#!/usr/bin/env bash
# Crea el tag de la version de VERSION segun docs/reference/tags.md y, con
# --push, lo empuja. Es el unico camino para crear un tag de version: lo corre
# publicar.yml al mergear a main, y `make tag` como respaldo manual.
#
#   ./scripts/tag-release.sh [--push] [--commit <ref>] [--remote origin] [--no-signature]
#
# --push          empuja el tag; sin esto queda solo en local
# --commit        commit a etiquetar (por defecto la punta de <remote>/main).
#                 publicar.yml pasa el que disparo el workflow
# --remote        remoto del que se toma main (por defecto origin)
# --no-signature  no firma (para los tests, que corren sin llave)
#
# La version es la de VERSION en ese commit. Si su tag ya existe, no hay nada
# que publicar y sale 0.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
push=0
target=""
remote=origin
sign=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) push=1; shift ;;
    --commit) target="$2"; shift 2 ;;
    --remote) remote="$2"; shift 2 ;;
    --no-signature) sign=0; shift ;;
    *) echo "opcion desconocida: $1" >&2; exit 2 ;;
  esac
done

die() { echo "$1" >&2; exit 1; }

# --force: el remoto manda sobre las copias locales de los tags. Sin esto, un
# checkout de GitHub Actions (que deja los tags como commits) haria fallar el
# fetch con "would clobber existing tag".
git fetch "$remote" --quiet --tags --force
main="$remote/main"
git rev-parse -q --verify "$main" >/dev/null || die "no existe $main: falta traer el remoto"

commit="$(git rev-parse -q --verify "${target:-$main}^{commit}")" \
  || die "no existe el commit ${target:-$main}"
version="$(git show "$commit:VERSION" 2>/dev/null | tr -d '[:space:]')"
[[ -n "$version" ]] || die "el commit ${commit:0:12} no tiene VERSION"
tag="v$version"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "$tag ya esta publicada: nada que hacer. Para publicar otra, sube la version (scripts/bump-version.sh)"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Las notas salen del CHANGELOG del commit etiquetado, no del de la punta: si
# despues alguien corrige la prosa, el tag sigue diciendo lo que se publico.
git show "$commit:CHANGELOG.md" > "$work/CHANGELOG.md" 2>/dev/null \
  || die "el commit ${commit:0:12} no tiene CHANGELOG.md"
{ echo "mascotuscan $version"; echo; "$here/changelog-section.sh" "$version" "$work/CHANGELOG.md"; } > "$work/msg" \
  || die "sin notas para $version: escribe su seccion en el CHANGELOG antes de publicar"

# verbatim: el modo por defecto de `git tag -F` (strip) borra las lineas que
# empiezan con #, y con ellas los encabezados `### Agregado` de las notas. Asi
# perdio v0.3.0 los suyos.
if (( sign )); then
  git tag -s --cleanup=verbatim "$tag" "$commit" -F "$work/msg" \
    || die "no pude firmar: configura la firma, ver docs/reference/tags.md"
else
  git -c tag.gpgsign=false tag -a --cleanup=verbatim "$tag" "$commit" -F "$work/msg"
fi

check=(--on "$main")
(( sign )) || check+=(--no-signature)
if ! "$here/check-tag.sh" "$tag" "${check[@]}"; then
  git tag -d "$tag" >/dev/null
  die "tag borrado en local; no se empujo nada"
fi

if (( push )); then
  if ! git push "$remote" "refs/tags/$tag"; then
    git tag -d "$tag" >/dev/null
    die "no pude empujar $tag; quedo borrado en local para reintentar"
  fi
  echo "$tag empujado; el release lo publica release.yml"
else
  echo "$tag creado en local, sin empujar (falta --push)"
fi
