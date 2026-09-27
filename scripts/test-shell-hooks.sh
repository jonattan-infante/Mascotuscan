#!/usr/bin/env bash
# Verifica los hooks de zsh sin depender de la app ni de cmux.
#
# Lo que se prueba es la decision: que se reporta, que se calla, y que el JSON
# que sale es valido. Es el unico lado del sistema que corre dentro del shell del
# usuario, asi que un bug aqui le ensucia el prompt a todo el mundo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LOG="$WORK/shell.jsonl"
export ZDOTDIR="$WORK"
cat > "$WORK/.zshrc" <<EOF
export MASCOTUSCAN_LOG="$LOG"
export MASCOTUSCAN_MIN_SECONDS=2
export MASCOTUSCAN_NO_AUTOSTART=1
export CMUX_WORKSPACE_ID=WS-TEST
export CMUX_SURFACE_ID=SF-TEST
source "$ROOT/shell/pet.zsh"
EOF

fail=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok   %s\n' "$desc"
  else
    printf '  FALLA %s (esperaba %s, obtuve %s)\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# Varios casos ejecutan comandos que fallan a proposito: el shell de prueba
# devolviendo != 0 es parte del caso, no un error del script.
run_zsh() { zsh -i >/dev/null 2>&1 || true; }

echo "hooks de zsh:"

# --- caso 1: un comando largo que termina bien se reporta ---
: > "$LOG"
run_zsh <<'EOS'
sleep 2.3
EOS
check "reporta comando largo" 1 "$(grep -c '"command":"sleep 2.3"' "$LOG" || true)"

# --- caso 2: un comando rapido y exitoso NO se reporta ---
: > "$LOG"
run_zsh <<'EOS'
echo rapido
EOS
check "calla comando rapido" 0 "$(grep -c 'echo rapido' "$LOG" || true)"

# --- caso 3: un fallo se reporta aunque sea instantaneo ---
: > "$LOG"
run_zsh <<'EOS'
false
EOS
check "reporta fallo instantaneo" 1 "$(grep -c '"status":1' "$LOG" || true)"

# --- caso 4: los comandos interactivos nunca se reportan ---
: > "$LOG"
run_zsh <<'EOS'
vim --version > /dev/null
EOS
check "ignora comandos de la denylist" 0 "$(grep -c 'vim' "$LOG" || true)"

# --- caso 5: Ctrl-C no es un fallo ---
: > "$LOG"
run_zsh <<'EOS'
(exit 130)
EOS
check "ignora exit 130 (Ctrl-C)" 0 "$(wc -l < "$LOG" | tr -d ' ')"

# --- caso 6: salta asignaciones y sudo al buscar el comando real ---
: > "$LOG"
run_zsh <<'EOS'
FOO=bar command vim --version > /dev/null
EOS
check "ve el comando real tras asignaciones" 0 "$(grep -c 'vim' "$LOG" || true)"

# --- caso 7: el JSON aguanta comillas y barras ---
: > "$LOG"
run_zsh <<'EOS'
echo "comillas \"dobles\" y \\ barra" && sleep 2.1
EOS
# El assert va en archivo aparte: anidar comillas de python dentro de bash
# dentro de zsh es como se escriben los tests que fallan por el test, no por el codigo.
cat > "$WORK/check_json.py" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]) if l.strip()]
assert len(lines) == 1, f"esperaba 1 linea, hay {len(lines)}"
d = json.loads(lines[0])                      # explota si el escaping esta roto
assert "dobles" in d["command"], d["command"]
assert "barra" in d["command"], d["command"]
assert d["workspace"] == "WS-TEST", d["workspace"]
assert d["surface"] == "SF-TEST", d["surface"]
assert d["status"] == 0 and d["seconds"] >= 2
PY
if /usr/bin/python3 "$WORK/check_json.py" "$LOG" 2>/dev/null; then
  printf '  ok   %s\n' "JSON valido con comillas y barras"
else
  printf '  FALLA %s\n' "JSON invalido con comillas y barras"
  fail=1
fi

# --- caso 8: el autoarranque respeta MASCOTUSCAN_NO_AUTOSTART ---
# pgrep devuelve 1 cuando no hay coincidencias, y con pipefail eso mata el script.
# En la maquina del autor el asistente corre; en CI no. El `|| true` cubre ambos.
count_pets() { pgrep -f 'mascotuscan/bin/mascotuscan' 2>/dev/null | wc -l | tr -d ' ' || true; }
before="$(count_pets)"
run_zsh <<'EOS'
true
EOS
after="$(count_pets)"
check "no autoarranca si se desactiva" "$before" "$after"

exit $fail
