# ghostty-tmux-opencode

[![CI](https://github.com/raindali/ghostty-tmux-opencode/actions/workflows/ci.yml/badge.svg)](https://github.com/raindali/ghostty-tmux-opencode/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/raindali/ghostty-tmux-opencode)](https://github.com/raindali/ghostty-tmux-opencode/releases)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)

Keep a **tmux** session alive while freeing the memory used by **opencode** when
you quit **Ghostty** — then resume the *exact* opencode session next time.

This is a small lifecycle layer for macOS + [Ghostty](https://ghostty.org) +
[tmux](https://github.com/tmux/tmux) + [opencode](https://opencode.ai).

- Quit Ghostty → stop opencode TUI + background service, **keep the tmux session**
- Reopen Ghostty → attach instantly, same cwd, resume the exact session with
  `opencode -s <session-id>`
- Reboot/crash → tmux-resurrect restores layout + cwd, and the saved command is
  rewritten to `opencode -s <session-id>` when the TUI plugin recorded one
- Manual detach (`C-a d`) leaves everything running

> **Status:** early stage (0.1.0). Tested on macOS with Ghostty + tmux 3.8 +
> opencode 2.2.x. See [CHANGELOG.md](CHANGELOG.md).

## Contents

- [Why](#why)
- [Features](#features)
- [Requirements](#requirements)
- [Project layout](#project-layout)
- [Install](#install)
- [Uninstall](#uninstall)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Configuration](#configuration)
- [Verify](#verify)
- [Tests](#tests)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Security / privacy](#security--privacy)
- [Contributing](#contributing)
- [Prior art](#prior-art)
- [中文快速说明](#中文快速说明)
- [License](#license)

## Why

On a small machine (e.g. 8 GB RAM), the tmux server is not the problem:

| Component | Approx. memory |
|---|---:|
| tmux server | 4 MB |
| tmux server with a full 100k-line pane | ~32 MB |
| opencode TUI | 100–170 MB |
| `opencode serve --service` | 120–160 MB |
| `opencode --standalone` | ~450 MB (TUI + private server) |

Killing tmux saves ~4 MB. Killing opencode saves hundreds of MB. This project
keeps tmux (for instant reattach) and stops opencode.

If you want zero tmux processes, `set -g destroy-unattached on` is simpler, but
it also destroys the session on manual detach and gives no instant resume.

## Features

- **Exact session resume** — a tiny opencode TUI plugin records the active
  session per `TMUX_PANE`; the wrapper reads it and runs
  `opencode -s <session-id>`.
- **Keep tmux, stop opencode** — sessions, panes, cwd and scrollback stay; only
  the heavy TUI/service are stopped.
- **Safe by default** — only sessions with no attached clients are cleaned;
  manual detach is left alone.
- **tmux-resurrect integration** — synchronous save, empty-`last` repair, and
  saved-command rewrite for reboot restore.
- **Graceful fallback** — if the plugin is missing or the session was deleted,
  the wrapper falls back to `opencode -c`.

## Requirements

- macOS (primary target; Linux is not tested)
- [Ghostty](https://ghostty.org)
- tmux 3.x
- [TPM](https://github.com/tmux-plugins/tpm)
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum)
- opencode 2.x
- `sh`, `bash`, `awk`, `sed`, `pgrep`, `ps` (standard on macOS)

### Tested with

| Component | Version |
|---|---|
| macOS | 26/27 (Apple Silicon) |
| Ghostty | 1.x |
| tmux | 3.8 |
| opencode | 2.2.x |
| tmux-resurrect / tmux-continuum | latest from TPM |

## Project layout

```
bin/tmux-start.sh              Ghostty wrapper: restore + attach + cleanup
bin/opencode-clean.sh          Manual cleanup
plugins/tmux-session-state/    opencode TUI plugin (exact session per pane)
config/                        Ghostty and tmux examples
tests/                         Shell unit tests
docs/design.md                 Architecture and trade-offs
```

## Install

```bash
git clone https://github.com/raindali/ghostty-tmux-opencode.git
cd ghostty-tmux-opencode
./install.sh
```

`install.sh` copies:

| Source | Destination |
|---|---|
| `bin/tmux-start.sh` | `~/.config/ghostty/tmux-start.sh` |
| `bin/opencode-clean.sh` | `~/.local/bin/opencode-clean.sh` |
| `plugins/tmux-session-state/tui.tsx` | `~/.config/opencode/plugins/tmux-session-state/tui.tsx` |

Existing files are backed up with a `.bak.<timestamp>` suffix.

### 1. Ghostty

Add this to `~/.config/ghostty/config` (replace `/Users/you` with your home
directory):

```ini
initial-command = /Users/you/.config/ghostty/tmux-start.sh
```

`initial-command` applies to the first window. Other windows use your normal
shell.

### 2. tmux

Merge [`config/tmux.conf.example`](config/tmux.conf.example) into
`~/.tmux.conf`:

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
set -g @resurrect-capture-pane-contents 'on'
set -g @resurrect-dir '~/.tmux/resurrect'
set -g @resurrect-processes 'opencode'

run '~/.tmux/plugins/tpm/tpm'
```

Then install the plugins with `prefix + I` (TPM).

### 3. Restart

Quit Ghostty completely and open it again. The first launch loads the wrapper
and the opencode TUI plugin.

## Uninstall

```bash
./uninstall.sh
```

Then remove the `initial-command` line from your Ghostty config and the
tmux-resurrect block from `~/.tmux.conf`. Logs and tmux-resurrect saves are left
in place.

## Usage

Just use Ghostty normally.

- **Quit Ghostty** (close the window / `Cmd+Q`): opencode TUI is stopped, the
  tmux session stays with a shell at the same directory, and the background
  service is stopped when no TUI remains.
- **Reopen Ghostty**: attach to the previous session and resume the exact
  opencode session.
- **Detach** with `C-a d`: nothing is cleaned; the session and opencode stay.

### Manual cleanup

```bash
opencode-clean.sh --dry-run      # show what would happen
opencode-clean.sh                # stop opencode TUIs, keep tmux sessions
opencode-clean.sh --kill-session # also kill tmux sessions containing opencode
```

## How it works

See [docs/design.md](docs/design.md) for the full design and trade-offs.

### Start

1. Read `~/.tmux/ghostty-last-pane` (`session`, `dir`, `cmd`, `pane`).
2. If no tmux server is running, create a placeholder session so
   tmux-resurrect/continuum can restore the saved layout.
3. Pick the session: the saved one first, then a session with opencode, then
   the most recently active one.
4. If the tmux server was already running (normal quit → relaunch), send the
   saved `opencode -s <id>` command back to the saved pane.
5. Attach.

### Quit Ghostty

1. Record the current pane's directory and command.
2. Build a map of opencode panes → exact session IDs from the TUI plugin state.
3. Save tmux-resurrect synchronously, repair a zero-byte `last`, and rewrite
   saved `:opencode` commands to `:opencode -s <id>` when unambiguous.
4. Stop opencode TUIs in sessions with no attached clients, keeping the tmux
   session and shell.
5. Stop `opencode serve --service` when no opencode TUI remains.

### Exact session tracking

`plugins/tmux-session-state/tui.tsx` uses the opencode TUI plugin API:

```ts
context.ui.router.current() // { type: "session", sessionID } | ...
```

It writes the active session ID atomically to:

```
${XDG_STATE_HOME:-~/.local/state}/opencode/tmux-session/<TMUX_PANE>
```

- One file per tmux pane → multiple TUIs do not collide.
- `router.current()` follows tab switches, so the active tab is exact.
- File mode `0600`, directory `0700`.
- Outside tmux (`TMUX_PANE` unset), the plugin does nothing.

If the file is missing, the wrapper falls back to `opencode -c` (the most recent
session in the current project).

## Configuration

The wrapper reads these environment variables:

| Variable | Default |
|---|---|
| `TMUX_BIN` | `command -v tmux` |
| `OPENCODE_BIN` | `command -v opencode` |
| `TMUX_PLUGIN_MANAGER_PATH` | `~/.tmux/plugins` |
| `TMUX_RESURRECT_DIR` | `~/.tmux/resurrect` |
| `XDG_STATE_HOME` | `~/.local/state` |
| `GHOSTTY_TMUX_STATE` | `~/.tmux/ghostty-last-pane` |
| `GHOSTTY_TMUX_MAP` | `~/.tmux/opencode-session-map` |
| `GHOSTTY_TMUX_LOG` | `~/.tmux-autostart.log` |

## Verify

```bash
# after quitting Ghostty
tmux ls                 # the session should still exist
pgrep -fl opencode      # no opencode TUI
opencode service status # service stopped when no TUI remains

# the plugin should have recorded the active session
ls "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tmux-session/"
cat "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tmux-session/%1" # replace %1

# after reopening Ghostty
tail -20 ~/.tmux-autostart.log
```

Expected log lines:

```
saved state: session=main dir=/path/to/project cmd=opencode -s ses_xxx pane=%1
resurrect save done
patched resurrect with exact session ids
killed opencode in pane %1: 12345
cleaned opencode in session main (session kept)
stopped opencode background service
```

## Tests

```bash
./tests/run.sh   # syntax + shellcheck (if installed) + unit tests
make test
make lint
```

The tests cover `repair_last`, `build_resurrect_map`, the
`:opencode -s <id>` rewrite, the `-c` fallback, and CLI help. CI runs them on
Linux and macOS.

## Troubleshooting

### The session is not resumed

Check that the plugin file exists:

```bash
ls -l "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tmux-session/"
```

If it is empty, restart the TUI once (plugins load at TUI startup) and check the
opencode TUI plugin list.

### tmux-resurrect restores nothing

```bash
readlink ~/.tmux/resurrect/last
wc -c ~/.tmux/resurrect/last
grep '^pane' ~/.tmux/resurrect/last
```

The `last` file must be non-empty and contain `:opencode -s ...` or
`:opencode -c`.

### Ghostty closes the session anyway

`tmux attach` must return non-zero when the terminal closes. Check the log:

```bash
tail -30 ~/.tmux-autostart.log
```

Look for `detached (hup=... status=...)`. If `status=0`, the wrapper treats it
as a manual detach and keeps everything running.

## Limitations

- The state file records one opencode pane per session for terminal-close
  resume. Multiple opencode panes in one session: the resurrect map rewrites
  all of them for reboot, but only the recorded pane is auto-resumed on
  relaunch.
- The TUI plugin API is relatively new. If a future opencode release changes it,
  the plugin may stop writing; the wrapper falls back to `opencode -c`.
- The plugin must be loaded by the TUI. Restart the TUI after installing it.
- `opencode -s <id>` fails if the session was deleted; the wrapper falls back to
  `-c` only when it has no ID, not when the ID is stale. Delete the stale state
  file if needed.
- `@resurrect-capture-pane-contents 'on'` stores pane scrollback (possibly
  sensitive output) in `~/.tmux/resurrect/pane_contents.tar.gz`. Disable it or
  restrict permissions if that matters.

## Security / privacy

- No network calls, telemetry, or external services.
- Session state files are `0600`; the state directory is `0700`.
- The wrapper sets mode `600` on its state, map, and log files.
- The resurrect save directory may be world-readable depending on your umask.
  Consider `chmod 700 ~/.tmux/resurrect` if you capture pane contents.
- The repo contains no personal paths, hostnames, proxy settings, tokens, or
  session IDs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

- Security reports: [SECURITY.md](SECURITY.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)

## Prior art

- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and
  [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) — layout/cwd
  persistence.
- [timvw/tmux-assistant-resurrect](https://github.com/timvw/tmux-assistant-resurrect)
  — a broader multi-assistant approach using an opencode server plugin plus
  process-argument/SQLite fallbacks.
- [guysoft/tmux-resurrect-opencode-sessions](https://github.com/guysoft/tmux-resurrect-opencode-sessions)
  — rewrites tmux-resurrect saves using the pane title and the opencode SQLite
  database.

This project uses the opencode **TUI plugin API** (`ui.router.current()`) so the
active session is known exactly per pane, without title matching or database
guessing.

## 中文快速说明

- 退出 Ghostty 时只结束 opencode TUI 和后台 service，**保留 tmux 会话和 shell**。
- 下次打开 Ghostty 直接 attach，并执行 `opencode -s <session-id>` 精确恢复。
- 手动 `C-a d` detach 不会清理。
- 安装：`./install.sh`，然后把 `initial-command` 加到 Ghostty 配置，把
  `config/tmux.conf.example` 合并到 `~/.tmux.conf`，用 TPM 安装 resurrect/continuum。
- 手动清理：`opencode-clean.sh`（默认保留会话），`--kill-session` 才连会话一起杀。

## License

MIT. See [LICENSE](LICENSE).
