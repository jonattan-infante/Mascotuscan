#!/usr/bin/env bash
# Casos de los harness de Claude, el de issues y el revisor de PRs: la ruta, la
# guardia, el veredicto y el escaneo de secretos son lo unico que separa a Claude
# de publicar algo. Ver docs/reference/claude-issues.md y claude-revision.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "harness de Claude (issues y revision de PRs):"
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
