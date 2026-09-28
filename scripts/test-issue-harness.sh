#!/usr/bin/env bash
# Casos del harness de issues: la ruta, la guardia y el escaneo de secretos son
# lo unico que separa a Claude de publicar algo. Ver docs/reference/claude-issues.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "harness de issues:"
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
