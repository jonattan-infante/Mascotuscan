#!/usr/bin/env bash
# Verifica el instalador sin tocar la maquina real: prefijo y ZDOTDIR apuntan a
# un directorio temporal.
#
# Se prueba sobre todo la desinstalacion, porque edita el .zshrc del usuario. Un
# sed mal escrito ahi le rompe el shell a alguien.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0

# md5 existe en macOS, md5sum en Linux: el script debe correr en cualquiera.
hash_file() { md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d" " -f1; }
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok   %s\n' "$desc"
  else
    printf '  FALLA %s (esperaba %s, obtuve %s)\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

echo "instalador:"

# --- sintaxis ---
bash -n "$ROOT/install.sh"
check "sintaxis de install.sh" 0 $?

# --- desinstalacion sobre un zshrc con contenido alrededor ---
PREFIX="$WORK/prefix"
mkdir -p "$PREFIX/bin" "$PREFIX/shell" "$PREFIX/pets/mi-mascota/sprites" "$PREFIX/voices"
touch "$PREFIX/bin/mascotuscan" "$PREFIX/shell/pet.zsh"
# El arte del usuario vive dentro de su paquete, no en una carpeta suelta.
echo 'mi-dibujo' > "$PREFIX/pets/mi-mascota/sprites/idle.png"
echo '{"id":"mi-mascota"}' > "$PREFIX/pets/mi-mascota/pet.json"
echo '{"greeting":["hola"]}' > "$PREFIX/voices/mi-mascota.json"
echo '{"quiet":false}' > "$PREFIX/config.json"

cat > "$WORK/.zshrc" <<'EOF'
export PATH=/opt/homebrew/bin:$PATH
alias ll='ls -la'

# asistente flotante de cmux (mascotuscan)
source ~/.mascotuscan/shell/pet.zsh

export EDITOR=vim
EOF

ZDOTDIR="$WORK" MASCOTUSCAN_PREFIX="$PREFIX" "$ROOT/install.sh" --uninstall >/dev/null 2>&1

check "quita la linea del source" 0 "$(grep -c 'pet.zsh' "$WORK/.zshrc" || true)"
check "quita el comentario marcador" 0 "$(grep -c 'mascotuscan' "$WORK/.zshrc" || true)"
check "conserva el PATH del usuario" 1 "$(grep -c 'homebrew' "$WORK/.zshrc" || true)"
check "conserva los alias" 1 "$(grep -c "alias ll" "$WORK/.zshrc" || true)"
check "conserva lo que venia despues" 1 "$(grep -c 'EDITOR=vim' "$WORK/.zshrc" || true)"
check "deja backup del zshrc" 1 "$(ls "$WORK"/.zshrc.mascotuscan-backup.* 2>/dev/null | wc -l | tr -d ' ')"
check "borra el binario" 0 "$(ls "$PREFIX/bin" 2>/dev/null | wc -l | tr -d ' ')"
check "conserva la mascota del usuario" 1 "$(ls "$PREFIX/pets" 2>/dev/null | wc -l | tr -d ' ')"
check "conserva su arte" 1 "$(ls "$PREFIX/pets/mi-mascota/sprites" 2>/dev/null | wc -l | tr -d ' ')"
check "conserva sus frases generadas" 1 "$(ls "$PREFIX/voices" 2>/dev/null | wc -l | tr -d ' ')"
check "conserva la configuracion" 1 "$(ls "$PREFIX/config.json" 2>/dev/null | wc -l | tr -d ' ')"

# --- desinstalar dos veces no debe explotar ni corromper ---
before="$(hash_file "$WORK/.zshrc")"
ZDOTDIR="$WORK" MASCOTUSCAN_PREFIX="$PREFIX" "$ROOT/install.sh" --uninstall >/dev/null 2>&1
check "desinstalar dos veces es idempotente" "$before" "$(hash_file "$WORK/.zshrc")"

# --- un zshrc sin el enganche no se toca ---
echo 'export FOO=bar' > "$WORK/.zshrc"
untouched="$(hash_file "$WORK/.zshrc")"
ZDOTDIR="$WORK" MASCOTUSCAN_PREFIX="$PREFIX" "$ROOT/install.sh" --uninstall >/dev/null 2>&1
check "no toca un zshrc ajeno" "$untouched" "$(hash_file "$WORK/.zshrc")"

# --- desinstalar quita tambien el enganche de un nombre anterior ---
cat > "$WORK/.zshrc" <<'EOF'
export PATH=/opt/homebrew/bin:$PATH

# asistente flotante de cmux (lucy)
source ~/.lucy/shell/pet.zsh

# asistente flotante de cmux (mascotuscan)
source ~/.mascotuscan/shell/pet.zsh
EOF
rm -f "$WORK"/.zshrc.mascotuscan-backup.*
ZDOTDIR="$WORK" MASCOTUSCAN_PREFIX="$PREFIX" "$ROOT/install.sh" --uninstall >/dev/null 2>&1
check "quita el enganche actual y el viejo" 0 "$(grep -c 'pet.zsh\|asistente flotante' "$WORK/.zshrc" || true)"
check "un solo backup, con el zshrc original" 2 "$(cat "$WORK"/.zshrc.mascotuscan-backup.* 2>/dev/null | grep -c '^source ' || true)"

# --- actualizar una instalacion que tenia el nombre anterior ---
# LucyGlow dejo su estado en ~/.lucy y su enganche en el zshrc. Se instala con
# un swift falso: lo que se prueba es la migracion, no la compilacion.
FAKE="$WORK/fake"
mkdir -p "$FAKE/bin" "$FAKE/build"
printf '#!/usr/bin/env bash\necho "mascotuscan 0.0.0"\n' > "$FAKE/build/mascotuscan"
printf '#!/usr/bin/env bash\n[[ " $* " == *" --show-bin-path "* ]] && echo "%s"\nexit 0\n' "$FAKE/build" \
  > "$FAKE/bin/swift"
chmod +x "$FAKE/bin/swift" "$FAKE/build/mascotuscan"

H="$WORK/home"
mkdir -p "$H/.lucy/bin" "$H/.lucy/voices"
echo '{"activePet":"gatito"}' > "$H/.lucy/config.json"
echo '{"greeting":["miau"]}' > "$H/.lucy/voices/gatito.json"
cat > "$H/.zshrc" <<'EOF'
export PATH=/opt/homebrew/bin:$PATH

# asistente flotante de cmux (lucy)
source ~/.lucy/shell/pet.zsh
EOF

code=0
env -u MASCOTUSCAN_PREFIX -u CMUX_WORKSPACE_ID HOME="$H" ZDOTDIR="$H" PATH="$FAKE/bin:$PATH" \
  "$ROOT/install.sh" --from-source > "$WORK/install.log" 2>&1 || code=$?
check "instala sobre el nombre anterior" 0 "$code"
[[ "$code" == 0 ]] || sed 's/^/        /' "$WORK/install.log"
check "migra la configuracion" 1 "$(grep -c 'gatito' "$H/.mascotuscan/config.json" 2>/dev/null || true)"
check "migra las frases generadas" 1 "$(grep -c 'miau' "$H/.mascotuscan/voices/gatito.json" 2>/dev/null || true)"
check "no deja el directorio viejo" 0 "$(ls -d "$H/.lucy" 2>/dev/null | wc -l | tr -d ' ')"
check "quita el enganche viejo" 0 "$(grep -c '\.lucy' "$H/.zshrc" || true)"
check "pone el enganche nuevo" 1 "$(grep -cx 'source ~/.mascotuscan/shell/pet.zsh' "$H/.zshrc" || true)"
check "conserva el resto del zshrc" 1 "$(grep -c 'homebrew' "$H/.zshrc" || true)"
check "el backup es el zshrc original" 1 "$(cat "$H"/.zshrc.mascotuscan-backup.* 2>/dev/null | grep -c '\.lucy' || true)"

exit $fail
