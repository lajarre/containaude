#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "[lint] bash -n containaude"
bash -n containaude

echo "[lint] shellcheck containaude"
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found in PATH" >&2
  exit 1
fi
shellcheck containaude

echo "[lint] OK"