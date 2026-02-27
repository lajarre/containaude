#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/containaude"

fail() {
  echo "❌ $*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "$msg (expected=$expected actual=$actual)"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$msg (missing: $needle)"
  fi
}

assert_file_has_line() {
  local file="$1"
  local line="$2"
  local msg="$3"
  if ! grep -Fxq -- "$line" "$file"; then
    fail "$msg (missing line: $line)"
  fi
}

assert_file_lacks_line() {
  local file="$1"
  local line="$2"
  local msg="$3"
  if grep -Fxq -- "$line" "$file"; then
    fail "$msg (unexpected line: $line)"
  fi
}

run_and_capture() {
  local __status_var="$1"
  local __output_var="$2"
  shift 2

  local captured_output captured_status
  set +e
  captured_output="$("$@" 2>&1)"
  captured_status=$?
  set -e

  printf -v "$__status_var" '%s' "$captured_status"
  printf -v "$__output_var" '%s' "$captured_output"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
HOME_DIR="$TMP_DIR/home"
PROJECT_DIR="$TMP_DIR/project with spaces"
DOCKER_RUN_CAPTURE="$TMP_DIR/docker-run.args"

mkdir -p "$FAKE_BIN" "$HOME_DIR/.claude" "$PROJECT_DIR"

cat > "$FAKE_BIN/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "find-generic-password" ]]; then
  echo "fake-creds"
  exit 0
fi
echo "unexpected security invocation: $*" >&2
exit 1
EOF

cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "image" && "${2:-}" == "inspect" && "${3:-}" == "containaude" ]]; then
  exit 0
fi
if [[ "${1:-}" == "run" ]]; then
  if [[ -n "${DOCKER_RUN_CAPTURE:-}" ]]; then
    : > "$DOCKER_RUN_CAPTURE"
    for arg in "$@"; do
      printf '%s\n' "$arg" >> "$DOCKER_RUN_CAPTURE"
    done
  fi
  exit 0
fi

echo "unexpected docker invocation: $*" >&2
exit 1
EOF

chmod +x "$FAKE_BIN/security" "$FAKE_BIN/docker"

export PATH="$FAKE_BIN:$PATH"
export HOME="$HOME_DIR"
export DOCKER_RUN_CAPTURE

status=""
output=""

echo "[smoke] --help"
run_and_capture status output "$BIN" --help
assert_eq "$status" "0" "--help should exit 0"
assert_contains "$output" "Usage:" "--help output should include usage"

echo "[smoke] missing args"
run_and_capture status output "$BIN"
assert_eq "$status" "1" "missing args should exit 1"
assert_contains "$output" "Usage:" "missing args should print usage"

echo "[smoke] unknown flag"
run_and_capture status output "$BIN" --wat
assert_eq "$status" "1" "unknown flag should exit 1"
assert_contains "$output" "Unknown flag: --wat" "unknown flag should be reported"

echo "[smoke] too many positional args"
run_and_capture status output "$BIN" "$PROJECT_DIR" "msg" "extra"
assert_eq "$status" "1" "too many positional args should exit 1"
assert_contains "$output" "too many positional arguments" "too many args should be reported"

echo "[smoke] invalid project path"
run_and_capture status output "$BIN" "$PROJECT_DIR/does-not-exist"
assert_eq "$status" "1" "invalid project path should exit 1"
assert_contains "$output" "project path does not exist" "invalid project path should be reported"

echo "[smoke] missing resume session id"
run_and_capture status output "$BIN" --resume
assert_eq "$status" "1" "missing --resume value should exit 1"
assert_contains "$output" "--resume requires a session ID" "missing --resume id should be reported"

echo "[smoke] invalid session id"
run_and_capture status output "$BIN" --resume 'bad/id' "$PROJECT_DIR"
assert_eq "$status" "1" "invalid session id should exit 1"
assert_contains "$output" "Invalid session ID format" "invalid session id message missing"

echo "[smoke] resume mode"
run_and_capture status output "$BIN" --resume abc_DEF-123 "$PROJECT_DIR" "Continue"
assert_eq "$status" "0" "resume run should succeed with mocked docker/security"
assert_file_has_line "$DOCKER_RUN_CAPTURE" "-it" "resume mode should allocate TTY"
assert_file_lacks_line "$DOCKER_RUN_CAPTURE" "-i" "resume mode should not run headless"
assert_file_has_line "$DOCKER_RUN_CAPTURE" "CLAUDE_SESSION_ID=abc_DEF-123" "resume session id should be passed"
assert_file_has_line "$DOCKER_RUN_CAPTURE" "$PROJECT_DIR:$PROJECT_DIR" "project path mount should preserve spaces"

echo "[smoke] fresh headless"
run_and_capture status output "$BIN" --headless "$PROJECT_DIR" "Summarize"
assert_eq "$status" "0" "fresh headless run should succeed"
assert_file_has_line "$DOCKER_RUN_CAPTURE" "-i" "headless mode should use -i"
assert_file_lacks_line "$DOCKER_RUN_CAPTURE" "-it" "headless mode should not allocate TTY"
assert_contains "$output" "claude.json not found" "missing claude.json note should be emitted"

echo "[smoke] option terminator --"
run_and_capture status output "$BIN" -- "$PROJECT_DIR" "Continue"
assert_eq "$status" "0" "option terminator should allow project path parsing"
assert_file_has_line "$DOCKER_RUN_CAPTURE" "$PROJECT_DIR:$PROJECT_DIR" "-- mode should preserve project mount"

echo "[smoke] debug + headless (debug wins)"
run_and_capture status output "$BIN" --debug --headless "$PROJECT_DIR"
assert_eq "$status" "0" "debug+headless run should succeed"
assert_file_has_line "$DOCKER_RUN_CAPTURE" "-it" "debug mode should force TTY"

echo "[smoke] OK"