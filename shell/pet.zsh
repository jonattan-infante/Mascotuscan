# Integracion de zsh con el asistente flotante de cmux.
#
# Reporta a ~/.mascotuscan/shell.jsonl:
#   - comandos que tardaron mas de MASCOTUSCAN_MIN_SECONDS
#   - comandos que fallaron (cualquier exit code distinto de cero)
#
# Escribe con append a un archivo plano: nunca bloquea el prompt, y si el
# asistente no esta corriendo simplemente no lo lee nadie.
#
# Activar:  echo 'source ~/.mascotuscan/shell/pet.zsh' >> ~/.zshrc

[[ -o interactive || -n ${MASCOTUSCAN_FORCE:-} ]] || return 0

zmodload zsh/datetime 2>/dev/null || return 0

: ${MASCOTUSCAN_LOG:="$HOME/.mascotuscan/shell.jsonl"}
: ${MASCOTUSCAN_MIN_SECONDS:=20}
# Comandos interactivos o de larga duracion por diseno: avisar de ellos es ruido.
: ${MASCOTUSCAN_IGNORE:="vim nvim vi nano emacs less more man top htop btop ssh tmux screen watch tail claude codex gemini opencode lazygit gitui k9s fzf bat delta psql mysql redis-cli python3 python node irb ipython crontab visudo"}

typeset -g _mascotuscan_cmd=""
typeset -gF _mascotuscan_start=0

_mascotuscan_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/}
  s=${s//$'\t'/\\t}
  print -r -- "$s"
}

_mascotuscan_preexec() {
  _mascotuscan_cmd=$1
  _mascotuscan_start=$EPOCHREALTIME
}

_mascotuscan_precmd() {
  local status_code=$?
  local cmd=$_mascotuscan_cmd
  local start=$_mascotuscan_start
  _mascotuscan_cmd=""
  _mascotuscan_start=0

  # Prompt vacio (enter pelado) o primer prompt de la sesion.
  [[ -z $cmd ]] && return
  (( start == 0 )) && return

  local -F elapsed=$(( EPOCHREALTIME - start ))

  # Ctrl-C y Ctrl-Z no son fallos que valga la pena reportar.
  (( status_code == 130 || status_code == 146 || status_code == 148 )) && return

  # Primer token real, saltando asignaciones de entorno y sudo/env.
  local -a words
  words=(${(z)cmd})
  local head=""
  local w
  for w in $words; do
    case $w in
      *=*)        continue ;;
      sudo|env|command|nohup|time) continue ;;
      *)          head=${w:t}; break ;;
    esac
  done
  [[ -n $head && " $MASCOTUSCAN_IGNORE " == *" $head "* ]] && return

  # Reportar solo lo que importa: tardo mucho, o fallo.
  if (( status_code == 0 )) && (( elapsed < MASCOTUSCAN_MIN_SECONDS )); then
    return
  fi

  local esc_cmd=$(_mascotuscan_json_escape "$cmd")
  local esc_cwd=$(_mascotuscan_json_escape "$PWD")

  printf '{"kind":"command","status":%d,"seconds":%.2f,"command":"%s","cwd":"%s","workspace":"%s","surface":"%s"}\n' \
    "$status_code" "$elapsed" "$esc_cmd" "$esc_cwd" \
    "${CMUX_WORKSPACE_ID:-}" "${CMUX_SURFACE_ID:-}" \
    >> "$MASCOTUSCAN_LOG" 2>/dev/null

  # Rotacion barata: el archivo es un buzon, no un historial.
  if [[ -f $MASCOTUSCAN_LOG ]]; then
    local size=$(zstat +size "$MASCOTUSCAN_LOG" 2>/dev/null || echo 0)
    (( size > 262144 )) && : > "$MASCOTUSCAN_LOG"
  fi
}

autoload -Uz add-zsh-hook 2>/dev/null && {
  zmodload zsh/stat 2>/dev/null
  add-zsh-hook preexec _mascotuscan_preexec
  add-zsh-hook precmd  _mascotuscan_precmd
}

# Arranca el asistente si no esta corriendo.
#
# Por que desde el shell y no desde launchd: cmux solo acepta control de
# procesos descendientes de cmux (socketControlMode). Un proceso lanzado por
# launchd no lo es y el socket lo rechaza en silencio. Toda terminal de cmux
# si es hija de cmux, asi que el asistente hereda el acceso.
#
# Para desactivar:  export MASCOTUSCAN_NO_AUTOSTART=1  antes del source.
if [[ -z ${MASCOTUSCAN_NO_AUTOSTART:-} && -x $HOME/.mascotuscan/bin/mascotuscan ]]; then
  if ! pgrep -f 'mascotuscan/bin/mascotuscan' >/dev/null 2>&1; then
    ( nohup "$HOME/.mascotuscan/bin/mascotuscan" >> "$HOME/.mascotuscan/pet.log" 2>&1 & ) >/dev/null 2>&1
  fi
fi
