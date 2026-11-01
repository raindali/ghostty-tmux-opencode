# Security

This project runs local shell scripts and an opencode TUI plugin. It does not
make network requests, collect telemetry, or send data anywhere.

## Sensitive data

- opencode session IDs are stored in
  `${XDG_STATE_HOME:-~/.local/state}/opencode/tmux-session/` with mode `0600`
  and a `0700` directory.
- The wrapper sets mode `600` on `~/.tmux/ghostty-last-pane`,
  `~/.tmux/opencode-session-map`, and `~/.tmux-autostart.log`.
- tmux-resurrect may capture pane scrollback in
  `~/.tmux/resurrect/pane_contents.tar.gz`. If that output can contain secrets,
  disable `@resurrect-capture-pane-contents` or run:

  ```bash
  chmod 700 ~/.tmux/resurrect
  ```

- The wrapper's log (`~/.tmux-autostart.log`) contains session names, paths,
  and opencode session IDs. Treat it as private.

## Reporting

Please use GitHub Security Advisories for vulnerabilities. Do not open a public
issue containing secrets, tokens, or private paths.
