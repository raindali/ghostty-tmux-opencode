# Design

## Problem

On a memory-constrained Mac, quitting Ghostty should not leave a 300 MB opencode
TUI and background service running. But killing tmux throws away the session,
the working directory, and the scrollback.

The useful split is:

- **Keep tmux** (a few MB): instant reattach, cwd and layout survive.
- **Stop opencode** (hundreds of MB): the heavy part.
- **Resume the exact session** next time, not just "the most recent session in
  this project".

## Goals

- Quit Ghostty → no opencode TUI; tmux session and shell remain.
- Reopen Ghostty → attach instantly, same cwd, exact opencode session.
- Reboot/crash → tmux-resurrect restores layout + cwd; the saved opencode
  command resumes the exact session when known.
- Manual detach (`C-a d`) is not treated as a quit.
- No personal data, network calls, or telemetry.

## Non-goals

- Cross-platform terminal multiplexing.
- Replacing tmux-resurrect/continuum.
- Freezing/restoring process memory.
- Managing multiple assistants (Claude Code, Codex, etc.).

## Architecture

```
Ghostty
  └─ tmux-start.sh (initial-command)
       ├─ tmux server / sessions
       ├─ opencode TUI (client)
       └─ opencode serve --service (shared backend)

opencode TUI
  └─ plugin: tmux-session-state
       └─ writes $XDG_STATE_HOME/opencode/tmux-session/<TMUX_PANE>
            = exact active session id

Quit path
  tmux-start.sh
    ├─ save state (session / dir / cmd / pane)
    ├─ build map: pane → exact session id
    ├─ save tmux-resurrect synchronously
    ├─ rewrite :opencode → :opencode -s <id> (when unambiguous)
    ├─ stop opencode TUI in unattached sessions (keep shell)
    └─ stop opencode service when no TUI remains
```

## Lifecycle

### Start

1. Read `~/.tmux/ghostty-last-pane`:
   `session<TAB>dir<TAB>cmd<TAB>pane`.
2. If the tmux server is not running, create a placeholder session so
   tmux-resurrect/continuum can restore. A bare `tmux start-server` exits
   immediately when there are no sessions, which used to kill the restore
   process before it finished.
3. Wait for restored sessions; if continuum missed, run `restore.sh` explicitly.
4. Pick the target session: saved session → session with opencode → most recent
   activity.
5. If the server was already running (normal quit → relaunch) and the target is
   the saved session, send the saved command back to the saved pane.
6. Attach.

### Quit Ghostty

A non-zero `tmux attach` exit or SIGHUP means the terminal is gone. (A manual
detach returns zero and is ignored.)

1. Record the active pane: cwd, command, pane id.
2. Build a map of opencode panes → exact session IDs from the TUI plugin state.
3. Save tmux-resurrect synchronously (`save.sh quiet`). `run-shell` is async and
   can leave a zero-byte `last` after the session dies.
4. Repair `last` if it points at an empty file.
5. Rewrite the saved pane command:
   - unique `(session, title, dir)` match → `:opencode -s <id>`
   - unique `(session, dir)` match → `:opencode -s <id>`
   - otherwise bare `:opencode` → `:opencode -c`
6. Stop opencode TUIs in sessions with no attached clients. Keep the tmux
   session and shell:
   - opencode is a child of the shell → kill the child
   - opencode is the pane process → `respawn-pane` a shell in the same cwd
7. Stop `opencode serve --service` when no opencode TUI remains.

## Exact session tracking

`plugins/tmux-session-state/tui.tsx` is an opencode TUI plugin. It uses:

```ts
context.ui.router.current()
// { type: "session", sessionID: "ses_..." } | { type: "home" } | ...
```

and writes the session id atomically to
`$XDG_STATE_HOME/opencode/tmux-session/<TMUX_PANE>`.

Why not infer from other sources?

| Source | Problem |
|---|---|
| `opencode -c` | “Most recent session in this project”, not the active pane/tab |
| `tabs.json` | Lists open tabs, not the active one; shared per cwd |
| Pane title `OC \| ...` | Can be truncated, duplicated, or overwritten by the shell |
| SQLite `session_v2` | Most recent by cwd; not per pane/TUI |

The TUI plugin knows the route exactly, including tab switches, and `TMUX_PANE`
isolates multiple TUIs.

## Fallbacks

- Plugin missing / file absent → `opencode -c`.
- Plugin state present but the pane is now a shell (user exited opencode) → do
  not resume opencode.
- Resurrect map ambiguous (same title + cwd for multiple panes) → `-c`.
- `last` empty or broken → delete it and relink to the newest non-empty save.
- No tmux server → placeholder session + explicit restore if continuum missed.

## Resource profile (measured)

| Item | Approx. |
|---|---:|
| tmux server, empty history | 4 MB |
| tmux server, 100k-line history | 32 MB |
| tmux server, 10k-line history | 5 MB |
| opencode TUI | 100–170 MB |
| `opencode serve --service` | 120–160 MB |
| `opencode --standalone` | ~450 MB |
| resurrect save, 100k lines, capture on | ~0.47 s / 216 KB |
| resurrect save, capture off | ~0.17 s / 4 KB |

`--standalone` is not a memory optimization: it runs a private server process in
addition to the TUI.

## Alternatives considered

- **Keep killing tmux** (the original setup): saves ~4 MB, loses instant
  reattach, and makes correctness depend on a successful restore on every quit.
- **`destroy-unattached on`**: one line, but manual detach also destroys the
  session and there is no instant resume.
- **Title + SQLite rewrite** (guysoft/tmux-resurrect-opencode-sessions): works,
  but infers the session from a truncated title and the most recent DB row.
- **Server plugin state** (timvw/tmux-assistant-resurrect): close, but a server
  plugin in opencode v2 may run in the shared service process, where
  `TMUX_PANE`/PID do not identify the TUI pane. Its process-args and SQLite
  fallbacks compensate.
- **TUI plugin** (this project): the TUI knows the active route and its own
  `TMUX_PANE`; no guessing.

## Security

- State files `0600`, state directory `0700`.
- No network access.
- tmux-resurrect pane contents may contain sensitive output; disable capture or
  `chmod 700 ~/.tmux/resurrect`.
