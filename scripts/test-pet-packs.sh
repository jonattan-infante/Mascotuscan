#!/usr/bin/env bash
# Valida las mascotas del repositorio y la coherencia del marketplace.
#
# Es la revision automatica de un PR al marketplace. Sin esto, una entrada que
# apunte a un paquete roto rompe `mascotuscan install <id>` para todo el mundo, y
# nadie se entera hasta que alguien lo intenta.
#
#   ./scripts/test-pet-packs.sh            valida los packs locales y el indice
#   ./scripts/test-pet-packs.sh --remote   ademas clona y valida los packs externos
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REMOTE=0
[[ "${1:-}" == "--remote" ]] && REMOTE=1

fail=0
ok()    { printf '  ok   %s\n' "$1"; }
bad()   { printf '  FALLA %s\n' "$1"; fail=1; }
note()  { printf '       %s\n' "$1"; }

BIN="$(swift build --show-bin-path 2>/dev/null)/mascotuscan"
if [[ ! -x "$BIN" ]]; then
  swift build >/dev/null 2>&1 || { echo "no pude compilar para validar"; exit 1; }
  BIN="$(swift build --show-bin-path)/mascotuscan"
fi

echo "mascotas del repositorio:"

# --- cada paquete de pets/ tiene que validar ---
shopt -s nullglob
packs=(pets/*/)
if (( ${#packs[@]} == 0 )); then
  bad "no hay ninguna mascota en pets/"
fi
for dir in "${packs[@]}"; do
  id="$(basename "$dir")"
  if out="$("$BIN" validate "$dir" 2>&1)" && ! grep -q '  falla' <<<"$out"; then
    ok "$id valida"
  else
    bad "$id no valida"
    sed 's/^/         /' <<<"$out"
  fi
  # El id de la carpeta y el del manifiesto tienen que coincidir, o `install`
  # dejaria el paquete en una carpeta con otro nombre.
  manifest_id="$(/usr/bin/python3 -c "
import json,sys
print(json.load(open('$dir/pet.json')).get('id',''))" 2>/dev/null || echo "")"
  if [[ "$manifest_id" == "$id" ]]; then
    ok "$id coincide con el nombre de su carpeta"
  else
    bad "la carpeta se llama \"$id\" pero el manifiesto dice \"$manifest_id\""
  fi
done

echo
echo "marketplace:"

# --- el indice tiene que ser JSON valido y sin ids repetidos ---
if ! /usr/bin/python3 - <<'PY'
import json, sys, re
d = json.load(open("registry.json"))
assert d.get("schemaVersion") == 1, "schemaVersion debe ser 1"
pets = d["pets"]
ids = [p["id"] for p in pets]
dupes = {i for i in ids if ids.count(i) > 1}
assert not dupes, f"ids repetidos: {sorted(dupes)}"
for p in pets:
    for field in ("id", "name", "description", "author", "version", "source"):
        assert p.get(field), f"{p.get('id','?')}: falta {field}"
    assert re.fullmatch(r"[a-z0-9-]{2,32}", p["id"]), f"id invalido: {p['id']}"
    assert re.fullmatch(r"\d+\.\d+\.\d+", p["version"]), f"version invalida en {p['id']}"
    assert p["source"].startswith("http"), f"source no clonable en {p['id']}"

PY
then
  bad "registry.json no pasa la revision"
else
  count="$(/usr/bin/python3 -c "import json;print(len(json.load(open('registry.json'))['pets']))")"
  ok "registry.json valido, $count entrada(s)"
fi

# --- cada entrada que vive en ESTE repo debe existir y coincidir de version ---
/usr/bin/python3 - > /tmp/pack-entries.txt <<'PY'
import json
d = json.load(open("registry.json"))
for p in d["pets"]:
    print("\t".join([p["id"], p["source"], p.get("path", ""), p["version"]]))
PY

while IFS=$'\t' read -r id source path version; do
  [[ -z "$id" ]] && continue
  if [[ "$source" == *"jonattan-infante/mascotuscan"* ]]; then
    dir="${path:-.}"
    if [[ ! -f "$dir/pet.json" ]]; then
      bad "$id apunta a $dir, que no existe en este repositorio"
      continue
    fi
    manifest_version="$(/usr/bin/python3 -c "
import json;print(json.load(open('$dir/pet.json')).get('version',''))")"
    if [[ "$manifest_version" == "$version" ]]; then
      ok "$id: el indice y el manifiesto dicen v$version"
    else
      bad "$id: el indice dice v$version y el manifiesto v$manifest_version"
      note "subir la version en los dos, o el usuario no ve la actualizacion"
    fi
  elif (( REMOTE )); then
    # Un paquete de otra persona: se clona y se valida igual que el propio. Es
    # la unica forma de saber que su `install` funcionara.
    tmp="$(mktemp -d)"
    if git clone --depth 1 --quiet "$source" "$tmp" 2>/dev/null; then
      target="$tmp/${path:-.}"
      if out="$("$BIN" validate "$target" 2>&1)" && ! grep -q '  falla' <<<"$out"; then
        ok "$id valida desde $source"
      else
        bad "$id no valida en su repositorio de origen"
        sed 's/^/         /' <<<"$out"
      fi
    else
      bad "$id: no pude clonar $source"
      note "el source tiene que ser publico y clonable sin credenciales"
    fi
    rm -rf "$tmp"
  else
    note "$id vive fuera de este repo; se revisa con --remote"
  fi
done < /tmp/pack-entries.txt
rm -f /tmp/pack-entries.txt

exit $fail
