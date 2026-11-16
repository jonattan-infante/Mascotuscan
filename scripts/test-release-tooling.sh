#!/usr/bin/env bash
# Verifica las herramientas de publicacion sobre un repositorio de git temporal:
# next-version.sh, release-notes.sh, changelog-section.sh y check-tag.sh.
# Nada de esto toca el repositorio real ni el remoto.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok   %s\n' "$desc"
  else
    printf '  FALLA %s (esperaba "%s", obtuve "%s")\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# Un repo limpio, sin firma y con identidad fija: los tests no dependen de la
# configuracion de quien los corre.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
git -C "$WORK" init -q -b main
g() { git -C "$WORK" -c tag.gpgsign=false -c commit.gpgsign=false "$@"; }
commit() {   # commit <mensaje> [version-para-VERSION]
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$WORK/VERSION"
  echo "$1" >> "$WORK/log.txt"
  g add -A >/dev/null
  g commit -q -m "$1"
}
run() { (cd "$WORK" && "$ROOT/scripts/$@"); }

echo "herramientas de publicacion:"

# --- next-version ---
printf '# Changelog\n\n## [0.1.0] — 2026-01-01\n\n### Agregado\n\n- Primera.\n' > "$WORK/CHANGELOG.md"
commit "feat: primera funcion" 0.1.0
check "sin tags y con feat propone 0.1.0" "0.1.0" "$(run next-version.sh 2>/dev/null)"

g tag -a v0.1.0 -m "mascotuscan 0.1.0" -m "- Primera."
check "sin commits desde el tag sale 1" "1" "$(run next-version.sh >/dev/null 2>&1; echo $?)"

commit "fix(voz): arregla algo"
check "solo fix sube patch" "0.1.1" "$(run next-version.sh 2>/dev/null)"

commit "feat(packs): agrega algo (#12)"
check "un feat sube minor" "0.2.0" "$(run next-version.sh 2>/dev/null)"

commit "refactor!: rompe el formato"
check "incompatible en 0.x sube minor, no major" "0.2.0" "$(run next-version.sh 2>/dev/null)"

# --- release-notes ---
notes="$(run release-notes.sh 0.2.0)"
check "encabezado con version y fecha" "## [0.2.0] — $(date +%Y-%m-%d)" "$(printf '%s\n' "$notes" | head -1)"
check "feat va a Agregado, sin prefijo ni #PR, con mayuscula y punto" "- Agrega algo." \
  "$(printf '%s\n' "$notes" | awk '/^### Agregado/{f=1;next} /^###/{f=0} f && /^- /' )"
check "fix va a Corregido" "- Arregla algo." \
  "$(printf '%s\n' "$notes" | awk '/^### Corregido/{f=1;next} /^###/{f=0} f && /^- /' )"
check "tipo! va a Incompatible" "- Rompe el formato." \
  "$(printf '%s\n' "$notes" | awk '/^### Incompatible/{f=1;next} /^###/{f=0} f && /^- /' )"

# --- changelog-section ---
printf '# Changelog\n\n## [0.2.0] — 2026-02-02\n\n### Agregado\n\n- Segunda.\n\n## [0.1.0] — 2026-01-01\n\n### Agregado\n\n- Primera.\n' > "$WORK/CHANGELOG.md"
check "changelog-section saca solo su seccion" "### Agregado|- Segunda." \
  "$(run changelog-section.sh 0.2.0 | sed '/^$/d' | paste -sd'|' -)"
check "changelog-section falla si no existe" "1" "$(run changelog-section.sh 9.9.9 >/dev/null 2>&1; echo $?)"

# --- check-tag ---
commit "chore(release): 0.2.0" 0.2.0
msg="$WORK/msg"
{ echo "mascotuscan 0.2.0"; echo; run changelog-section.sh 0.2.0; } > "$msg"

g tag -a v0.2.0 -F "$msg"
check "un tag correcto pasa (sin firma permitida)" "0" \
  "$(run check-tag.sh v0.2.0 --on main --no-signature >/dev/null 2>&1; echo $?)"
check "sin --no-signature exige firma" "1" \
  "$(run check-tag.sh v0.2.0 --no-signature --on main >/dev/null 2>&1; run check-tag.sh v0.2.0 >/dev/null 2>&1; echo $?)"

g tag ligero-0.2.0
check "un tag ligero falla" "1" "$(run check-tag.sh ligero-0.2.0 --no-signature >/dev/null 2>&1; echo $?)"

g tag -a v0.2.1 -m "0.2.1" -m "notas"
out="$(run check-tag.sh v0.2.1 --no-signature 2>&1 || true)"
check "primera linea distinta de 'mascotuscan X.Y.Z' falla" "1" "$(grep -c "primera linea debe ser 'mascotuscan 0.2.1'" <<< "$out")"
check "VERSION distinta en el commit falla" "1" "$(grep -c "VERSION en el commit dice '0.2.0'" <<< "$out")"

g tag -a v0.3.0 -m "mascotuscan 0.3.0"
out="$(run check-tag.sh v0.3.0 --no-signature 2>&1 || true)"
check "sin notas falla" "1" "$(grep -c 'sin notas' <<< "$out")"

g tag -a v0.0.9 -F "$msg"
out="$(run check-tag.sh v0.0.9 --no-signature 2>&1 || true)"
check "una version menor que la publicada falla" "1" "$(grep -c 'no es mayor que la ultima publicada' <<< "$out")"

g checkout -q -b aparte
commit "feat: fuera de main" 0.4.0
printf '## [0.4.0] — 2026-03-03\n\n- x.\n' >> "$WORK/CHANGELOG.md"
commit "chore(release): 0.4.0"
g tag -a v0.4.0 -m "mascotuscan 0.4.0" -m "- x."
out="$(run check-tag.sh v0.4.0 --on main --no-signature 2>&1 || true)"
check "un commit fuera de main falla con --on main" "1" "$(grep -c 'no esta en main' <<< "$out")"

# --- tag-release ---
# Repo aparte con un remoto desnudo: el script etiqueta lo que hay en
# origin/main, que es lo que publicar.yml ve despues de un merge.
REL="$WORK/rel" BARE="$WORK/remoto.git"
git init -q --bare "$BARE"
git init -q -b main "$REL"
r() { git -C "$REL" -c tag.gpgsign=false -c commit.gpgsign=false "$@"; }
rcommit() {   # rcommit <mensaje> [version-para-VERSION]
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$REL/VERSION"
  echo "$1" >> "$REL/log.txt"
  r add -A >/dev/null
  r commit -q -m "$1"
}
rel() { (cd "$REL" && "$ROOT/scripts/tag-release.sh" --no-signature "$@"); }
tags_en() { git -C "$1" tag -l "$2" | wc -l | tr -d ' '; }

printf '# Changelog\n\n## [1.0.0] — 2026-04-04\n\n### Agregado\n\n- La de la version.\n' > "$REL/CHANGELOG.md"
rcommit "chore(release): 1.0.0" 1.0.0
release_commit="$(r rev-parse HEAD)"
rcommit "feat: entra despues de subir la version"
r remote add origin "$BARE"
r push -q origin main

check "crea el tag y lo empuja" "0" "$(rel --push >/dev/null 2>&1; echo $?)"
check "el tag apunta al commit que subio VERSION, no a la punta de main" "$release_commit" \
  "$(git -C "$BARE" rev-list -n 1 v1.0.0 2>/dev/null)"
check "el mensaje es 'mascotuscan X.Y.Z' y la seccion del CHANGELOG" "mascotuscan 1.0.0|### Agregado|- La de la version." \
  "$(git -C "$BARE" tag -l --format='%(contents)' v1.0.0 | sed '/^$/d' | paste -sd'|' -)"

out="$(rel --push 2>&1)" && code=0 || code=$?
check "con la version ya publicada sale 0 sin hacer nada" "0|1" "$code|$(grep -c 'ya esta publicada' <<< "$out")"

printf '# Changelog\n\n## [1.1.0] — 2026-05-05\n\n- Otra.\n' > "$REL/CHANGELOG.md"
rcommit "chore(release): 1.1.0" 1.1.0
r push -q origin main
rel >/dev/null 2>&1 || true
check "sin --push el tag queda solo en local" "1|0" "$(tags_en "$REL" v1.1.0)|$(tags_en "$BARE" v1.1.0)"
r tag -d v1.1.0 >/dev/null

rcommit "chore(release): 1.2.0" 1.2.0
r push -q origin main
out="$(rel --push 2>&1)" && code=0 || code=$?
check "sin la seccion del CHANGELOG falla y no crea tag" "1|1|0" \
  "$code|$(grep -c 'sin notas para 1.2.0' <<< "$out")|$(tags_en "$REL" v1.2.0)"

printf '# Changelog\n\n## [0.9.0] — 2026-06-06\n\n- Vieja.\n' > "$REL/CHANGELOG.md"
rcommit "chore(release): 0.9.0" 0.9.0
r push -q origin main
out="$(rel --push 2>&1)" && code=0 || code=$?
check "si check-tag rechaza el tag, sale 1 y no queda ni en local ni en el remoto" "1|0|0" \
  "$code|$(tags_en "$REL" v0.9.0)|$(tags_en "$BARE" v0.9.0)"

printf '# Changelog\n\n## [2.0.0] — 2026-07-07\n\n- Local.\n' > "$REL/CHANGELOG.md"
rcommit "chore(release): 2.0.0" 2.0.0
out="$(rel --push 2>&1)" && code=0 || code=$?
check "solo cuenta lo que llego a origin/main, no un commit local" "0|0" "$(tags_en "$REL" v2.0.0)|$(tags_en "$BARE" v2.0.0)"

exit $fail
