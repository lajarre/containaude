#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/test-lint.sh"
"$ROOT_DIR/script/test-smoke.sh"
"$ROOT_DIR/script/test-integration.sh" "$@"