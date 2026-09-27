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

exit $fail
