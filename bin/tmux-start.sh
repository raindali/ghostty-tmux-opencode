#!/bin/sh
# SPDX-License-Identifier: MIT
# Ghostty + tmux + opencode lifecycle.
#
# Start:
#   1. If no tmux server is running, create a placeholder session so
#      tmux-resurrect/continuum can restore the previous layout.
#   2. Attach to the last session.
#   3. If the pane was running opencode before, resume the exact session
#      (`opencode -s <session-id>`), falling back to `opencode -c`.
#
# Quit Ghostty (SIGHUP or non-zero `tmux attach` exit):
#   1. Save tmux-resurrect state synchronously.
#   2. Record the current pane directory and opencode command.
#   3. Stop opencode TUIs in sessions with no attached clients, keeping the
#      tmux session and shell alive.
#   4. Stop `opencode serve --service` when no TUI remains.
#
# Manual detach (`C-a d`) does not clean up.
#
# Why keep tmux: the tmux server is ~4 MB, while the opencode TUI + service
# is several hundred MB. Keeping tmux gives instant reattach and preserves cwd.

# Prefer Homebrew on macOS, but allow overrides.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

TMUX_BIN=${TMUX_BIN:-$(command -v tmux 2>/dev/null || true)}
OPENCODE_BIN=${OPENCODE_BIN:-$(command -v opencode 2>/dev/null || true)}
[ -n "$TMUX_BIN" ] || TMUX_BIN=/opt/homebrew/bin/tmux
[ -n "$OPENCODE_BIN" ] || OPENCODE_BIN=/opt/homebrew/bin/opencode

TMUX_PLUGIN_DIR=${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins}
RESURRECT_DIR=${TMUX_RESURRECT_DIR:-$HOME/.tmux/resurrect}
RESURRECT_SAVE="$TMUX_PLUGIN_DIR/tmux-resurrect/scripts/save.sh"
RESURRECT_RESTORE="$TMUX_PLUGIN_DIR/tmux-resurrect/scripts/restore.sh"
PS_STRATEGY="$TMUX_PLUGIN_DIR/tmux-resurrect/save_command_strategies/ps.sh"

STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
OPENCODE_STATE_DIR="$STATE_HOME/opencode/tmux-session"
STATE_FILE=${GHOSTTY_TMUX_STATE:-$HOME/.tmux/ghostty-last-pane}
RESURRECT_MAP=${GHOSTTY_TMUX_MAP:-$HOME/.tmux/opencode-session-map}
LOG=${GHOSTTY_TMUX_LOG:-$HOME/.tmux-autostart.log}
PLACEHOLDER="__ghostty_restore__"
TAB=$(printf '\t')


log() {
  echo "[$(date '+%F %T')] $*" >> "$LOG"
  chmod 600 "$LOG" 2>/dev/null || true
}

# 删除 0 字节的保存文件，并保证 last 指向最新的非空文件。
repair_last() {
  [ -d "$RESURRECT_DIR" ] || return 0

  find "$RESURRECT_DIR" -maxdepth 1 -name 'tmux_resurrect_*.txt' -size 0 -delete 2>/dev/null

  last="$RESURRECT_DIR/last"
  if [ -L "$last" ]; then
    tgt=$(readlink "$last")
    case "$tgt" in
      /*) f="$tgt" ;;
      *)  f="$RESURRECT_DIR/$tgt" ;;
    esac
    [ -s "$f" ] || rm -f "$last"
  fi

  if [ ! -e "$last" ]; then
    for f in $(find "$RESURRECT_DIR" -maxdepth 1 -name 'tmux_resurrect_*.txt' -size +0c 2>/dev/null | sort -r); do
      ln -sfn "$(basename "$f")" "$last"
      break
    done
  fi
}

# 把没有 -s 的 opencode 命令补成 `opencode -c`（继续上次会话）。
normalize_opencode_cmd() {
  case "$1" in
    opencode|*/opencode) printf '%s' "$1 -c" ;;
    *) printf '%s' "$1" ;;
  esac
}

# 保存前记录所有 opencode pane 的精确 session id，供 resurrect 存档改写。
# 格式：session<TAB>pane_title<TAB>dir<TAB>session_id
build_resurrect_map() {
  : > "$RESURRECT_MAP"
  chmod 600 "$RESURRECT_MAP" 2>/dev/null || true
  "$TMUX_BIN" list-panes -a -F \
    "#{session_name}${TAB}#{pane_id}${TAB}#{pane_title}${TAB}#{pane_current_path}${TAB}#{pane_current_command}" 2>/dev/null |
  while IFS="$TAB" read -r m_sess m_pane m_title m_dir m_cur; do
    [ "$m_cur" = "opencode" ] || continue
    m_sid=$(head -1 "$OPENCODE_STATE_DIR/$m_pane" 2>/dev/null)
    case "$m_sid" in
      ses_*) printf '%s\t%s\t%s\t%s\n' "$m_sess" "$m_title" "$m_dir" "$m_sid" >> "$RESURRECT_MAP" ;;
    esac
  done
}

# 改写 resurrect 存档：有精确 session id 的写成 `opencode -s <id>`，
# 否则裸 `opencode` 回退 `-c`。
patch_resurrect_cmd() {
  [ -s "$RESURRECT_DIR/last" ] || return 0
  last_file="$RESURRECT_DIR/$(readlink "$RESURRECT_DIR/last")"
  [ -f "$last_file" ] || return 0

  if [ -s "$RESURRECT_MAP" ]; then
    awk -F'\t' -v OFS='\t' '
      FNR == NR {
        key = $1 SUBSEP $2 SUBSEP $3
        n[key]++
        sid[key] = $4
        key2 = $1 SUBSEP $3
        n2[key2]++
        sid2[key2] = $4
        next
      }
      /^pane/ && $11 ~ /^:([^ ]*\/)?opencode($| )/ {
        k = $2 SUBSEP $7 SUBSEP substr($8, 2)
        k2 = $2 SUBSEP substr($8, 2)
        if (n[k] == 1) {
          $11 = ":opencode -s " sid[k]
        } else if (n2[k2] == 1) {
          $11 = ":opencode -s " sid2[k2]
        } else if ($11 ~ /^:([^ ]*\/)?opencode$/) {
          $11 = $11 " -c"
        }
      }
      { print }
    ' "$RESURRECT_MAP" "$last_file" > "$last_file.tmp" && mv "$last_file.tmp" "$last_file"
  else
    awk -F'\t' 'BEGIN { OFS="\t" }
      /^pane/ && $11 ~ /^:([^ ]*\/)?opencode$/ { $11 = $11 " -c" }
      { print }' "$last_file" > "$last_file.tmp" && mv "$last_file.tmp" "$last_file"
  fi
  chmod 600 "$last_file" 2>/dev/null || true
}

# 状态文件：session<TAB>dir<TAB>cmd<TAB>pane_id
save_state() {
  ss=$1
  info=$("$TMUX_BIN" list-panes -t "$ss" -F \
    "#{pane_id}${TAB}#{pane_current_path}${TAB}#{pane_current_command}${TAB}#{pane_pid}" 2>/dev/null)

  line=$(printf '%s\n' "$info" | awk -F"$TAB" '$3=="opencode"{print; exit}')
  [ -n "$line" ] || line=$(printf '%s\n' "$info" | head -1)
  [ -n "$line" ] || return 0

  pane_id=$(printf '%s\n' "$line" | cut -f1)
  dir=$(printf '%s\n' "$line" | cut -f2)
  cur=$(printf '%s\n' "$line" | cut -f3)
  pane_pid=$(printf '%s\n' "$line" | cut -f4)
  [ -n "$dir" ] || return 0

  cmd=""
  if [ -x "$PS_STRATEGY" ] && [ -n "$pane_pid" ]; then
    cmd=$("$PS_STRATEGY" "$pane_pid" 2>/dev/null | head -1)
  fi

  # TUI 插件按 pane 记录了精确的当前 session id（Option C）。
  # 只有 pane 现在确实跑着 opencode 时才采用，避免用户先退出 opencode 再关窗口时误恢复。
  sid=""
  if [ "$cur" = "opencode" ] && [ -n "$pane_id" ]; then
    sid=$(head -1 "$OPENCODE_STATE_DIR/$pane_id" 2>/dev/null)
  fi
  case "$sid" in
    ses_*) cmd="opencode -s $sid" ;;
    *) cmd=$(normalize_opencode_cmd "$cmd") ;;
  esac

  [ -n "$pane_id" ] || pane_id="-"
  printf '%s\t%s\t%s\t%s\n' "$ss" "$dir" "$cmd" "$pane_id" > "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
  log "saved state: session=$ss dir=$dir cmd=${cmd:-<shell>} pane=$pane_id"
}

# 递归列出某个进程的所有后代 pid
descendants() {
  for c in $(pgrep -P "$1" 2>/dev/null); do
    printf '%s\n' "$c"
    descendants "$c"
  done
}

# 结束一个 pane 里的 opencode TUI，保留 pane/shell。
clean_pane() {
  cp_pane=$1
  cp_pid=$2
  cp_dir=$3

  cp_cmd=$(ps -o command= -p "$cp_pid" 2>/dev/null | sed 's/^ *//')

  # 少数情况：opencode 就是 pane 的直接进程。respawn 成同目录的 shell。
  case "$cp_cmd" in
    opencode|*/opencode|opencode\ *|*/opencode\ *)
      shell=$("$TMUX_BIN" show-options -gv default-shell 2>/dev/null)
      [ -n "$shell" ] || shell=${SHELL:-/bin/sh}
      "$TMUX_BIN" respawn-pane -k -t "$cp_pane" -c "$cp_dir" "$shell" 2>/dev/null || true
      sleep 0.2
      # respawn 可能只发 HUP，旧进程还在就补一刀（确认 pid 仍是 opencode）
      if ps -o command= -p "$cp_pid" 2>/dev/null | grep -Eq '(^|/)(opencode)( |$)'; then
        kill "$cp_pid" 2>/dev/null || true
        sleep 0.2
        kill -9 "$cp_pid" 2>/dev/null || true
      fi
      log "respawned pane $cp_pane at $cp_dir"
      return 0
      ;;
  esac

  # 常见情况：opencode 是 pane shell 的子进程，杀掉它，shell 留下。
  # 共享后台服务（serve --service）不在这里杀，后面统一 stop
  cp_pids=$(descendants "$cp_pid" | while IFS= read -r p; do
    c=$(ps -o command= -p "$p" 2>/dev/null | sed 's/^ *//')
    printf '%s\n' "$c" | grep -q 'serve --service' && continue
    if printf '%s\n' "$c" | grep -Eq '(^|/)(opencode)( |$)'; then
      printf '%s\n' "$p"
    fi
  done)

  [ -n "$cp_pids" ] || return 0

  for p in $cp_pids; do kill "$p" 2>/dev/null || true; done
  sleep 0.2
  for p in $cp_pids; do kill -9 "$p" 2>/dev/null || true; done
  log "killed opencode in pane $cp_pane: $(printf '%s' "$cp_pids" | tr '\n' ' ')"
}

# 清理一个会话里所有 opencode pane，但保留会话本身。
clean_session() {
  cs=$1
  "$TMUX_BIN" list-panes -t "$cs" -F \
    "#{pane_id}${TAB}#{pane_pid}${TAB}#{pane_current_path}${TAB}#{pane_current_command}" 2>/dev/null |
  while IFS="$TAB" read -r pane_id pane_pid dir cur; do
    [ "$cur" = "opencode" ] || continue
    clean_pane "$pane_id" "$pane_pid" "$dir"
  done
}

# 启动时把 opencode 送回上次的 pane
resume_opencode() {
  ro_s=$1
  ro_dir=$2
  ro_cmd=$3
  ro_pane=$4

  case "$ro_cmd" in opencode*|*/opencode*) ;; *) return 0 ;; esac

  pane=""
  if [ -n "$ro_pane" ] && \
     "$TMUX_BIN" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$ro_pane"; then
    pane=$ro_pane
  fi

  if [ -z "$pane" ]; then
    pane=$("$TMUX_BIN" list-panes -t "$ro_s" -F \
      "#{pane_id}${TAB}#{pane_current_path}${TAB}#{pane_current_command}" 2>/dev/null |
      awk -F"$TAB" -v d="$ro_dir" '$2==d && $3!="opencode"{print $1; exit}')
  fi

  if [ -z "$pane" ]; then
    pane=$("$TMUX_BIN" list-panes -t "$ro_s" -F \
      "#{pane_id}${TAB}#{pane_current_command}" 2>/dev/null |
      awk -F"$TAB" '$2!="opencode"{print $1; exit}')
  fi
  [ -n "$pane" ] || return 0

  cur=$("$TMUX_BIN" display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null)
  case "$cur" in
    opencode) return 0 ;;
    zsh|bash|sh|fish|dash|ksh|-zsh|-bash) ;;
    *) return 0 ;;
  esac

  pdir=$("$TMUX_BIN" display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)
  if [ -n "$ro_dir" ] && [ "$pdir" != "$ro_dir" ]; then
    "$TMUX_BIN" send-keys -t "$pane" "cd \"$ro_dir\"" C-m
  fi
  "$TMUX_BIN" send-keys -t "$pane" "$ro_cmd" C-m
  log "resumed opencode in pane $pane: $ro_cmd"
}

# 选会话：优先状态文件里的会话，其次有 opencode 的，最后最近活跃的。
pick_target() {
  list=$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null | grep -vx "$PLACEHOLDER")
  [ -n "$list" ] || return 0

  if [ -n "$sess" ] && printf '%s\n' "$list" | grep -qx "$sess"; then
    printf '%s\n' "$sess"
    return 0
  fi

  oc=$(printf '%s\n' "$list" | while IFS= read -r s; do
    [ -n "$s" ] || continue
    if "$TMUX_BIN" list-panes -t "$s" -F '#{pane_current_command}' 2>/dev/null | grep -qx opencode; then
      printf '%s\n' "$s"
    fi
  done)

  if [ -n "$oc" ]; then
    best=$(printf '%s\n' "$oc" | while IFS= read -r s; do
      act=$("$TMUX_BIN" display-message -p -t "$s" '#{session_activity}' 2>/dev/null || echo 0)
      printf '%s\t%s\n' "${act:-0}" "$s"
    done | sort -t "$TAB" -k1 -n | tail -1 | cut -f2-)
    [ -n "$best" ] && { printf '%s\n' "$best"; return 0; }
  fi

  "$TMUX_BIN" list-sessions -F "#{session_name}${TAB}#{session_activity}" 2>/dev/null \
    | grep -v "^$PLACEHOLDER${TAB}" \
    | sort -t "$TAB" -k2 -n | tail -1 | cut -f1
}

# Allow tests to source the functions without running the lifecycle.
if [ "${GHOSTTY_TMUX_SOURCE_ONLY:-0}" = 1 ]; then
  return 0 2>/dev/null || exit 0
fi

log "initial-command start (TERM=$TERM, TMUX=${TMUX:-unset})"

repair_last

# 读取上次退出时的状态
sess=""
sdir="$HOME"
scmd=""
spane=""
if [ -s "$STATE_FILE" ]; then
  IFS="$TAB" read -r st1 st2 st3 st4 < "$STATE_FILE" || true
  if [ -n "$st4" ]; then
    # 新格式：session dir cmd pane
    sess=$st1; sdir=$st2; scmd=$st3; spane=$st4
  elif [ -n "$st3" ]; then
    # 三字段：session dir cmd
    sess=$st1; sdir=$st2; scmd=$st3
  else
    # 旧格式：dir cmd
    sdir=$st1; scmd=$st2
  fi
fi
[ -n "$sdir" ] || sdir="$HOME"

server_was_running=0
if "$TMUX_BIN" list-sessions >/dev/null 2>&1; then
  server_was_running=1
fi

# 服务端不在：先建占位会话撑住，等 resurrect 恢复
if [ "$server_was_running" = 0 ]; then
  i=0
  while [ "$i" -lt 10 ]; do
    if "$TMUX_BIN" has-session -t "$PLACEHOLDER" 2>/dev/null; then
      break
    fi
    if "$TMUX_BIN" new-session -d -s "$PLACEHOLDER" -c "$HOME" 2>/dev/null; then
      break
    fi
    sleep 0.2
    i=$((i + 1))
  done

  has_state=0
  [ -s "$RESURRECT_DIR/last" ] && has_state=1

  restored_sessions() {
    "$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null | grep -vx "$PLACEHOLDER"
  }

  if [ "$has_state" = 1 ]; then
    i=0
    while [ "$i" -lt 15 ]; do
      [ -n "$(restored_sessions)" ] && break
      sleep 0.2
      i=$((i + 1))
    done

    if [ -z "$(restored_sessions)" ] && [ -x "$RESURRECT_RESTORE" ]; then
      log "continuum restore missed, running restore.sh explicitly"
      "$TMUX_BIN" run-shell "$RESURRECT_RESTORE" >/dev/null 2>&1 || true
      i=0
      while [ "$i" -lt 25 ]; do
        [ -n "$(restored_sessions)" ] && break
        sleep 0.2
        i=$((i + 1))
      done
    fi
  fi

fi

# 清理占位会话（包括上次异常退出留下的）
"$TMUX_BIN" kill-session -t "$PLACEHOLDER" 2>/dev/null || true

target=$(pick_target)

if [ -z "$target" ]; then
  target=main
  dir="$sdir"
  [ -d "$dir" ] || dir="$HOME"
  log "no session restored, creating $target in $dir (cmd=${scmd:-<shell>})"
  "$TMUX_BIN" new-session -d -s "$target" -c "$dir"
  case "$scmd" in
    opencode*) "$TMUX_BIN" send-keys -t "$target" "$scmd" C-m; log "restored command: $scmd" ;;
  esac
else
  # 正常退出 Ghostty 后再打开：会话还在，把 opencode 放回去
  if [ "$server_was_running" = 1 ] && [ "$target" = "$sess" ]; then
    resume_opencode "$target" "$sdir" "$scmd" "$spane"
  fi
fi

hup=0
trap 'hup=1' HUP TERM
log "attach $target"
"$TMUX_BIN" attach -t "$target"
status=$?
log "detached (hup=$hup status=$status)"

# 终端被关闭时，SIGHUP 通常只发给前台进程组的 tmux attach，父 shell 的 trap
# 不一定触发；tmux attach 的非 0 退出码同样视为“终端没了”。
if [ "$hup" = 1 ] || [ "$status" -ne 0 ]; then
  save_state "$target"

  # 在保存前记录精确 session（TUI 插件状态文件），保存后改写存档
  build_resurrect_map

  if [ -x "$RESURRECT_SAVE" ]; then
    # 同步保存：run-shell 是异步的，会话/服务端退出后会留下 0 字节文件
    "$RESURRECT_SAVE" quiet >/dev/null 2>&1 || true
    log "resurrect save done"
  fi
  repair_last
  patch_resurrect_cmd
  [ -s "$RESURRECT_MAP" ] && log "patched resurrect with exact session ids"
  rm -f "$RESURRECT_MAP"

  clients=$("$TMUX_BIN" list-clients -t "$target" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$clients" -eq 0 ]; then
    clean_session "$target"
    log "cleaned opencode in session $target (session kept)"
  else
    log "session $target still has $clients client(s), skipped"
  fi

  # 其它无人 attach 的会话也清理 opencode，但保留会话
  "$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null |
  while IFS= read -r s; do
    [ "$s" = "$target" ] && continue
    attached=$("$TMUX_BIN" display-message -p -t "$s" '#{session_attached}' 2>/dev/null || echo 0)
    [ "$attached" = 0 ] || continue
    clean_session "$s"
    log "cleaned opencode in detached session $s (session kept)"
  done

  sleep 0.5

  # shellcheck disable=SC2009 # need the full command line to exclude the service
  if ! ps -axo command= | grep -v grep \
       | grep -E '(^|/)opencode( |$)' | grep -v 'serve --service' | grep -q .; then
    "$OPENCODE_BIN" service stop >/dev/null 2>&1 || true
    log "stopped opencode background service"
  fi
fi

exec "${SHELL:-/bin/sh}" -l
