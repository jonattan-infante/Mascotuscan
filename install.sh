#!/usr/bin/env bash
# Instalador de mascotuscan.
#
#   curl -fsSL https://raw.githubusercontent.com/jonattan-infante/mascotuscan/main/install.sh | bash
#
# O desde un clon:  ./install.sh --from-source
# Para quitarlo:    ./install.sh --uninstall
set -euo pipefail

REPO_URL="https://github.com/jonattan-infante/mascotuscan.git"
LATEST_URL="https://api.github.com/repos/jonattan-infante/mascotuscan/releases/latest"
RAW_URL="https://raw.githubusercontent.com/jonattan-infante/mascotuscan/main/install.sh"
PREFIX="${MASCOTUSCAN_PREFIX:-$HOME/.mascotuscan}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
NAME=mascotuscan
# Nombres anteriores del producto, del mas reciente al mas viejo. Cada uno dejo
# su directorio de estado en ~/.<nombre> y su enganche en el zshrc.
LEGACY_NAMES=(lucy cmux-pet)

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '  aviso: %s\n' "$1" >&2; }
die()  { printf 'error: %s\n' "$1" >&2; exit 1; }

# El enganche de un nombre del producto en el zshrc: un comentario marcador y la
# linea del source debajo.
hook_marker() { printf '# asistente flotante de cmux (%s)' "$1"; }
hook_line()   { printf 'source ~/.%s/shell/pet.zsh' "$1"; }
has_hook()    { [[ -f "$ZSHRC" ]] && grep -qF "$(hook_line "$1")" "$ZSHRC"; }
unhook() {
  local marker; marker="$(hook_marker "$1")"
  /usr/bin/sed -i '' "/^${marker//\//\\/}$/d" "$ZSHRC"
  /usr/bin/sed -i '' "\|^$(hook_line "$1")$|d" "$ZSHRC"
}

# Un solo backup por corrida: dos en el mismo segundo tendrian el mismo nombre y
# el segundo pisaria al original.
backed_up=""
backup_zshrc() {
  [[ -n "$backed_up" ]] && return 0
  cp -p "$ZSHRC" "$ZSHRC.$NAME-backup.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  backed_up=1
}

# ---------------------------------------------------------------- desinstalar

uninstall() {
  bold "Desinstalando mascotuscan"
  pkill -f "$PREFIX/bin/mascotuscan" 2>/dev/null || true
  info "asistente detenido"

  # El launchd agent existio en versiones tempranas; se limpia por si quedo.
  launchctl bootout "gui/$(id -u)/com.jonattan.cmuxpet" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.jonattan.cmuxpet.plist"

  for name in "$NAME" "${LEGACY_NAMES[@]}"; do
    if has_hook "$name"; then
      backup_zshrc
      unhook "$name"
      info "enganche removido de $ZSHRC (backup guardado)"
    fi
  done

  # Nada del usuario se borra sin pedirlo: ni preferencias, ni mascotas, ni arte.
  rm -rf "$PREFIX/bin" "$PREFIX/shell" "$PREFIX/src"
  info "binario y shell removidos"
  bold "Listo."
  echo "  Se conservaron tus preferencias, mascotas y arte en $PREFIX"
  echo "  Para borrar todo:  rm -rf $PREFIX"
  exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall

# ------------------------------------------------------------------ requisitos

bold "Instalando mascotuscan"

[[ "$(uname -s)" == "Darwin" ]] || die "mascotuscan solo corre en macOS"

command -v swift >/dev/null || die "falta Swift. Instala Xcode o las Command Line Tools:
    xcode-select --install"

if ! command -v cmux >/dev/null && [[ ! -x /Applications/cmux.app/Contents/Resources/bin/cmux ]]; then
  warn "no encuentro cmux. El asistente se instala igual, pero sin cmux no recibe eventos."
  warn "cmux: https://cmux.com"
fi

# ------------------------------------------------------------------- obtener

if [[ "${1:-}" == "--from-source" ]]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  info "compilando desde $SRC"
else
  command -v git >/dev/null || die "falta git"
  SRC="$(mktemp -d)/mascotuscan"
  # Se instala la ultima version PUBLICADA, no main: asi lo que corre coincide
  # con lo que la mascota anuncia. Ver docs/reference/versioning.md.
  #   MASCOTUSCAN_VERSION=v0.3.0  fija una version
  #   MASCOTUSCAN_VERSION=main    sigue la rama
  REF="${MASCOTUSCAN_VERSION:-}"
  if [[ -z "$REF" ]]; then
    REF="$(curl -fsSL --max-time 10 -H 'Accept: application/vnd.github+json' "$LATEST_URL" 2>/dev/null \
      | /usr/bin/sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$REF" ]]; then
      warn "no encontre una version publicada (sin releases o sin red): instalo main"
      REF="main"
    fi
  fi
  info "clonando $REPO_URL ($REF)"
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$SRC" >/dev/null 2>&1 \
    || die "no pude clonar el repositorio en $REF"
fi

# -------------------------------------------------------------------- build

cd "$SRC"
info "compilando (la primera vez tarda un minuto)"
swift build -c release >/dev/null 2>&1 || die "la compilacion falló. Corre 'swift build -c release' para ver por qué."

BUILT="$(swift build -c release --show-bin-path)/mascotuscan"
[[ -x "$BUILT" ]] || die "no encuentro el binario compilado en $BUILT"

# ------------------------------------------------------------------ instalar

# Migrar en vez de empezar de cero: nadie deberia perder su configuracion, sus
# mascotas o sus frases generadas solo porque el producto cambio de nombre. La
# mascota vieja se detiene antes porque corre desde ese directorio y podria
# volver a crearlo.
if [[ ! -d "$PREFIX" ]]; then
  for name in "${LEGACY_NAMES[@]}"; do
    legacy="$HOME/.$name"
    [[ -d "$legacy" ]] || continue
    pkill -f "$legacy/bin/$name" 2>/dev/null || true
    mv "$legacy" "$PREFIX"
    info "migrado $legacy -> $PREFIX"
    break
  done
fi

mkdir -p "$PREFIX"/{bin,shell,pets,voices}
pkill -f "$PREFIX/bin/mascotuscan" 2>/dev/null || true
install -m 755 "$BUILT" "$PREFIX/bin/mascotuscan"
install -m 644 shell/pet.zsh "$PREFIX/shell/pet.zsh"
info "instalado $("$PREFIX/bin/mascotuscan" --version) en $PREFIX/bin/mascotuscan"

# Las mascotas que vienen con el repositorio. Se marcan con .bundled y se
# reemplazan al actualizar; sus frases generadas viven aparte en voices/.
#
# Una mascota SIN el marcador es del usuario y no se toca nunca: puede tener el
# mismo id que una incluida si el usuario la creo antes, y pisarla seria borrar
# su trabajo sin avisar.
for pack in pets/*/; do
  [[ -f "$pack/pet.json" ]] || continue
  id="$(basename "$pack")"
  if [[ -d "$PREFIX/pets/$id" && ! -f "$PREFIX/pets/$id/.bundled" ]]; then
    warn "\"$id\" ya existe y la editaste tu: la dejo como esta"
    continue
  fi
  rm -rf "$PREFIX/pets/$id"
  cp -R "$pack" "$PREFIX/pets/$id"
  touch "$PREFIX/pets/$id/.bundled"
  info "mascota incluida: $id"
done

# Carpeta de sprites de versiones anteriores: ya no se lee, y su LEEME mandaba a
# ponerle imagenes a la mascota en un sitio equivocado.
if [[ -d "$PREFIX/sprites" ]]; then
  if [[ -z "$(ls -A "$PREFIX/sprites" | grep -v '^LEEME.txt$')" ]]; then
    rm -rf "$PREFIX/sprites"
  else
    warn "$PREFIX/sprites es de una version vieja y ya no se usa"
    warn "para ponerle imagenes a una mascota:  mascotuscan sprite <id> <estado> <archivo>"
  fi
fi

# Si no hay ninguna activa todavia, se activa la primera que haya.
if ! grep -q '"activePet"[[:space:]]*:[[:space:]]*"' "$PREFIX/config.json" 2>/dev/null; then
  first="$(ls "$PREFIX/pets" 2>/dev/null | head -1)"
  if [[ -n "$first" ]]; then
    "$PREFIX/bin/mascotuscan" use "$first" >/dev/null 2>&1 || true
    info "mascota activa: $first"
  fi
fi

# ------------------------------------------------------------- enganchar zsh

# Por que en el shell y no en launchd: cmux solo acepta control de procesos
# descendientes de cmux (socketControlMode). Un proceso de launchd no lo es y el
# socket lo rechaza en silencio. Ver docs/adr/0001.
#
# El enganche de un nombre anterior apunta a un directorio que ya se migro: zsh
# daria un error al abrir cada terminal. Se reemplaza por el actual.
for name in "${LEGACY_NAMES[@]}"; do
  if has_hook "$name"; then
    backup_zshrc
    unhook "$name"
    info "enganche de $name quitado de $ZSHRC (backup guardado)"
  fi
done
if has_hook "$NAME"; then
  info "el enganche ya estaba en $ZSHRC"
else
  backup_zshrc
  printf '\n%s\n%s\n' "$(hook_marker "$NAME")" "$(hook_line "$NAME")" >> "$ZSHRC"
  info "enganche agregado a $ZSHRC (backup guardado)"
fi

# --------------------------------------------------------------- arrancar ya

if [[ -n "${CMUX_WORKSPACE_ID:-}" ]]; then
  # Estamos dentro de cmux: el proceso hereda el acceso al socket de control.
  ( nohup "$PREFIX/bin/mascotuscan" >> "$PREFIX/pet.log" 2>&1 < /dev/null & ) >/dev/null 2>&1
  sleep 2
  if pgrep -f "$PREFIX/bin/mascotuscan" >/dev/null; then
    info "asistente arrancado"
  else
    warn "no arrancó; mira $PREFIX/pet.log"
  fi
else
  info "abre una terminal de cmux y el asistente arranca solo"
fi

echo ""
bold "Listo."
cat <<EOF
  El droide vive en la esquina inferior derecha. Arrástralo donde quieras.

    click            ir al último aviso
    mouse encima     ver en qué van tus agentes
    click derecho    opciones

  En terminales que ya tenías abiertas:  source ~/.zshrc
  Actualizar:                            mascotuscan update
  Log:                                   tail -f $PREFIX/pet.log
EOF

# El clon temporal del modo curl desaparece, asi que no se puede apuntar a el.
if [[ "${1:-}" == "--from-source" ]]; then
  echo "  Quitar:                                cd $SRC && ./install.sh --uninstall"
else
  echo "  Quitar:                                curl -fsSL $RAW_URL | bash -s -- --uninstall"
fi
