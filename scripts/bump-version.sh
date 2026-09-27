#!/usr/bin/env bash
# Sube la version del producto en todos los sitios que la copian.
#
#   ./scripts/bump-version.sh 0.3.0
#
# VERSION es la fuente unica; Swift y Python no pueden leer un archivo en tiempo
# de compilacion sin plugins, asi que llevan una copia. Este script es la unica
# forma sancionada de tocarla, y test-repo-integrity.sh falla si divergen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

new="${1:-}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "uso: $0 X.Y.Z" >&2
  exit 2
}

# El CHANGELOG va primero: una version sin notas no se publica.
if ! grep -qE "^## \[$new\]" CHANGELOG.md; then
  echo "error: CHANGELOG.md no tiene la seccion '## [$new]'. Escribela primero." >&2
  exit 1
fi

old="$(tr -d '[:space:]' < VERSION)"
printf '%s\n' "$new" > VERSION
sed -i '' "s/^public let mascoTuscanVersion = \"$old\"\$/public let mascoTuscanVersion = \"$new\"/" \
  Sources/MascoTuscanKit/Support/Paths.swift
sed -i '' "s/^__version__ = \"$old\"\$/__version__ = \"$new\"/" \
  windows/mascotuscan_win/__init__.py

echo "version: $old -> $new"
grep -n "$new" VERSION Sources/MascoTuscanKit/Support/Paths.swift windows/mascotuscan_win/__init__.py
echo ""
echo "siguiente: commit, PR, merge, y luego 'make tag' desde main para publicar"
