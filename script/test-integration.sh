#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/containaude"
PROJECT_PATH="${1:-$ROOT_DIR}"

if [[ "${CONTAINAUDE_RUN_INTEGRATION:-0}" != "1" ]]; then
  cat <<'EOF'
[integration] Skipped.
Set CONTAINAUDE_RUN_INTEGRATION=1 to run a real end-to-end check.
This requires:
  - Docker image built locally: docker build -t containaude .
  - macOS Keychain credentials for Claude Code
  - network access and working Claude auth
EOF
  exit 0
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "[integration] project path does not exist: $PROJECT_PATH" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[integration] docker not found in PATH" >&2
  exit 1
fi

if ! command -v security >/dev/null 2>&1; then
  echo "[integration] macOS security CLI not found" >&2
  exit 1
fi

if ! docker image inspect containaude >/dev/null 2>&1; then
  echo "[integration] image containaude missing; run: docker build -t containaude ." >&2
  exit 1
fi

echo "[integration] Running real headless containaude session"
"$BIN" --headless "$PROJECT_PATH" "Reply with exactly: integration-ok"

echo "[integration] Completed"