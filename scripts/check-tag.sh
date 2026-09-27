#!/usr/bin/env bash
# Verifica que un tag cumpla docs/reference/tags.md. Lo corren `make tag` antes
# de empujar y release.yml antes de publicar: un tag que no pasa por aqui no
# existe para el producto.
#
#   ./scripts/check-tag.sh v0.3.0 [--on <rama-o-ref>] [--no-signature]
#
# --on            ademas exige que el commit etiquetado este en esa referencia
# --no-signature  no exige firma (para tags creados por un robot sin llave)
set -euo pipefail

tag="${1:-}"
[[ -n "$tag" ]] || { echo "uso: $0 vX.Y.Z [--on <ref>] [--no-signature]" >&2; exit 2; }
shift
on=""
need_sig=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --on) on="$2"; shift 2 ;;
    --no-signature) need_sig=0; shift ;;
    *) echo "opcion desconocida: $1" >&2; exit 2 ;;
  esac
done

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FALLA %s\n' "$1"; fail=1; }

echo "tag $tag:"

# 1. nombre
if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ok "nombre vX.Y.Z"
else
  bad "el nombre debe ser vX.Y.Z, sin sufijos ni prerelease"
fi
version="${tag#v}"

git rev-parse -q --verify "refs/tags/$tag^{}" >/dev/null 2>&1 || { bad "el tag no existe"; exit 1; }

# 2. anotado
if [[ "$(git cat-file -t "$tag")" == "tag" ]]; then
  ok "anotado"
else
  bad "es un tag ligero: sin autor, fecha ni mensaje. Usa git tag -s (make tag lo hace)"
  exit 1
fi

raw="$(git cat-file tag "$tag")"
# El mensaje termina donde empieza la firma, si la hay.
msg="$(printf '%s\n' "$raw" | awk 'body { if ($0 ~ /^-----BEGIN (SSH|PGP) SIGNATURE-----$/) exit; print } /^$/ { body = 1 }')"
subject="$(printf '%s\n' "$msg" | head -1)"
body="$(printf '%s\n' "$msg" | tail -n +2 | sed '/^[[:space:]]*$/d')"

# 4. mensaje
if [[ "$subject" == "mascotuscan $version" ]]; then
  ok "primera linea: '$subject'"
else
  bad "la primera linea debe ser 'mascotuscan $version'; es '$subject'"
fi
if [[ -n "$body" ]]; then
  ok "trae notas ($(printf '%s\n' "$body" | wc -l | tr -d ' ') lineas)"
else
  bad "sin notas: el cuerpo del mensaje es la seccion del CHANGELOG (make tag lo compone)"
fi

# 3. firma
if printf '%s\n' "$raw" | grep -qE '^-----BEGIN (SSH|PGP) SIGNATURE-----$'; then
  ok "firmado"
elif (( need_sig )); then
  bad "sin firma. Configura la firma (docs/reference/tags.md) o pasa --no-signature"
else
  printf '  aviso sin firma (permitido con --no-signature)\n'
fi

# 5. el commit etiquetado dice la misma version
commit="$(git rev-list -n 1 "$tag")"
v_file="$(git show "$commit:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
if [[ "$v_file" == "$version" ]]; then
  ok "VERSION en el commit dice $version"
else
  bad "VERSION en el commit dice '${v_file:-<no existe>}', no $version. Corre scripts/bump-version.sh antes"
fi
if git show "$commit:CHANGELOG.md" 2>/dev/null | grep -qE "^## \[$version\]"; then
  ok "CHANGELOG del commit tiene [$version]"
else
  bad "CHANGELOG del commit no tiene la seccion '## [$version]'"
fi
if [[ -n "$on" ]]; then
  if git merge-base --is-ancestor "$commit" "$on" 2>/dev/null; then
    ok "el commit esta en $on"
  else
    bad "el commit no esta en $on: los tags salen de main"
  fi
fi

# 7. en orden: ninguna version publicada es mayor que esta
newest="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -vx "$tag" | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
if [[ -z "$newest" ]]; then
  ok "primera version publicada"
elif [[ "$(printf '%s\n%s\n' "$newest" "$version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" == "$version" && "$newest" != "$version" ]]; then
  ok "es mayor que la ultima publicada ($newest)"
else
  bad "no es mayor que la ultima publicada ($newest): las versiones no retroceden"
fi

exit $fail
