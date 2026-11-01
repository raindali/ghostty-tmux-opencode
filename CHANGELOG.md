# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-01

### Added

- Ghostty `initial-command` wrapper that keeps the tmux session and stops
  opencode on quit.
- Exact opencode session tracking through a TUI plugin
  (`ui.router.current()`), keyed by `TMUX_PANE`.
- tmux-resurrect integration: synchronous save, empty-`last` repair, and
  saved-command rewrite to `opencode -s <session-id>`.
- Manual cleanup script with `--dry-run` and `--kill-session`.
- Install/uninstall scripts with backups.
- Tests for the resurrect rewrite and CLI help.
- CI for shell syntax and ShellCheck on Linux and macOS.
