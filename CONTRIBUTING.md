# Contributing

Thanks for taking a look.

## Guidelines

- `bin/tmux-start.sh` is POSIX `sh`; keep it that way.
- `bin/opencode-clean.sh` is `bash`.
- Run the local checks before opening a PR:

  ```bash
  ./tests/run.sh
  make lint
  ```

  `tests/run.sh` runs the syntax checks, ShellCheck (if installed), and the
  unit tests.

- Do not commit personal paths, hostnames, proxy settings, tokens, session IDs,
  or machine-specific output. Use placeholders such as `/Users/you`,
  `ses_xxx`, and `/path/to/project`.
- Keep the opencode TUI plugin dependency-free: it may import
  `@opencode/plugin/tui`, `solid-js`, and Node built-ins only.
- If you change the state file format, update both the wrapper and
  `docs/design.md`.

## Reporting issues

Include:

- macOS version
- Ghostty version
- tmux version
- opencode version
- the relevant part of `~/.tmux-autostart.log` with personal data removed
