// SPDX-License-Identifier: MIT
import { Plugin } from "@opencode/plugin/tui"
import { createEffect, createRoot } from "solid-js"
import { mkdirSync, renameSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

// Record the TUI's active session per tmux pane.
//
// The wrapper reads this file at quit time and resumes the exact session with
// `opencode -s <session-id>`. Outside tmux (no TMUX_PANE) this plugin does
// nothing.
const pane = process.env.TMUX_PANE
const stateRoot = process.env.XDG_STATE_HOME || join(process.env.HOME || homedir(), ".local/state")
const stateDir = join(stateRoot, "opencode", "tmux-session")

export default Plugin.define({
  id: "tmux-session-state",
  setup(context) {
    if (!pane || !/^%\d+$/.test(pane)) return

    try {
      mkdirSync(stateDir, { recursive: true, mode: 0o700 })
    } catch {
      // Never break the TUI if the state directory cannot be created.
      return
    }
    const file = join(stateDir, pane)

    const dispose = createRoot((dispose) => {
      createEffect(() => {
        const route = context.ui.router.current()
        if (route.type !== "session") return
        // Ignore placeholder routes used before a real session exists.
        if (!route.sessionID.startsWith("ses_")) return

        // Write atomically so the wrapper never reads a partial file.
        const temp = `${file}.${process.pid}.tmp`
        try {
          writeFileSync(temp, `${route.sessionID}\n`, { encoding: "utf8", mode: 0o600 })
          renameSync(temp, file)
        } catch {
          // Never break the TUI if the state directory is unavailable.
          // The wrapper falls back to `opencode -c`.
        }
      })
      return dispose
    })

    return () => dispose()
  },
})
