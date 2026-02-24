# claude-sandbox

Run Claude Code inside a Docker container with filesystem isolation.
The agent has network access and can modify your project files, but cannot
reach `~/.ssh`, `~/Documents`, or any other host data.

## Setup

```sh
# One-time: build the image
docker build -t claude-sandbox -f Dockerfile.claude-sandbox .
```

Requires Docker (or OrbStack) and a working `claude` login on macOS
(credentials are extracted from the Keychain at runtime).

## Usage

```sh
# Fresh session (default) — auto-detects .agent/HANDOFF.*.md for context
./claude-sandbox-run.sh ~/workspace/myproject

# Fresh session with a specific task
./claude-sandbox-run.sh ~/workspace/myproject "Fix the failing tests"

# Resume an existing session
./claude-sandbox-run.sh --resume <session-id> ~/workspace/myproject

# Debug — drop into a shell inside the container
./claude-sandbox-run.sh --debug ~/workspace/myproject
```

Find session IDs with `claude --resume` on the host.

## How it works

1. Extracts OAuth credentials from macOS Keychain (never written to disk)
2. Copies `~/.claude` (skills, settings, sessions) read-only into the container
3. Mounts the project's session directory (`~/.claude/projects/<key>/`) read-write
   so sessions persist to the host
4. Mounts the project at its **original macOS path** inside the Linux container —
   Claude derives the session storage key from the cwd, so paths must match
5. In fresh mode, injects an environment preamble telling the agent it's in
   Linux (not macOS) and points it to the latest handoff file if one exists

## Security model

| Resource | Access |
|---|---|
| Project files | Read-write |
| `~/.claude` (skills, settings) | Read-only (copied) |
| Session data (`~/.claude/projects/<key>/`) | Read-write (mounted) |
| Network | Open |
| Everything else (`~/.ssh`, `~/Documents`...) | Inaccessible |

**Caveats:**
- Credentials are visible via `docker inspect` while the container runs.
  Acceptable for local single-user machines; do not use on shared hosts
  or CI without switching to Docker secrets.
- The project directory is mounted read-write. Review changes with `git diff`
  after the run.

## Recommended workflow

1. Work on your project normally in macOS with Claude Code
2. Run `/handoff` at the end of a session (writes `.agent/HANDOFF.<id>.md`)
3. Launch a sandboxed fresh session:
   ```sh
   ./claude-sandbox-run.sh ~/workspace/myproject "Continue from the handoff"
   ```
4. The container agent reads the handoff, knows the environment is Linux,
   and picks up where you left off
5. Session history persists back to the host

Resuming (`--resume`) also works but the agent may be confused by
environment differences (it remembers macOS/mise but is now in bare Linux).
Fresh mode with a handoff avoids this.
