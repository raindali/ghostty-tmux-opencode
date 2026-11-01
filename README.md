# ghostty-tmux-opencode

[English](README.en.md) | 简体中文

[![CI](https://github.com/raindali/ghostty-tmux-opencode/actions/workflows/ci.yml/badge.svg)](https://github.com/raindali/ghostty-tmux-opencode/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/raindali/ghostty-tmux-opencode)](https://github.com/raindali/ghostty-tmux-opencode/releases)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)

退出 **Ghostty** 时释放 **opencode** 占用的内存，同时保留 **tmux** 会话；下次打开时精确恢复原来的 opencode 会话。

这是一个面向 macOS + [Ghostty](https://ghostty.org) + [tmux](https://github.com/tmux/tmux) + [opencode](https://opencode.ai) 的小型生命周期管理工具。

- 退出 Ghostty → 停止 opencode TUI 和后台 service，**保留 tmux 会话**
- 重新打开 Ghostty → 瞬时 attach，保持原目录，并用 `opencode -s <session-id>` 精确恢复
- 机器重启/崩溃 → tmux-resurrect 恢复布局和 cwd；如果 TUI 插件记录过 session，存档命令会被改写成 `opencode -s <session-id>`
- 手动 detach（`C-a d`）不会清理任何东西

> **状态：** 早期阶段（0.1.0）。已在 macOS + Ghostty + tmux 3.8 + opencode 2.2.x 上测试。见 [CHANGELOG.md](CHANGELOG.md)。

## 目录

- [为什么](#为什么)
- [功能](#功能)
- [环境要求](#环境要求)
- [项目结构](#项目结构)
- [安装](#安装)
- [卸载](#卸载)
- [使用](#使用)
- [工作原理](#工作原理)
- [配置](#配置)
- [验证](#验证)
- [测试](#测试)
- [故障排查](#故障排查)
- [限制](#限制)
- [安全与隐私](#安全与隐私)
- [贡献](#贡献)
- [相关项目](#相关项目)
- [许可证](#许可证)

## 为什么

在小内存机器（例如 8 GB）上，tmux server 不是问题：

| 组件 | 大约内存 |
|---|---:|
| tmux server | 4 MB |
| tmux server（单个 pane 满 10 万行历史） | 约 32 MB |
| opencode TUI | 100–170 MB |
| `opencode serve --service` | 120–160 MB |
| `opencode --standalone` | 约 450 MB（TUI + 私有 server） |

杀掉 tmux 只省约 4 MB；杀掉 opencode 能省几百 MB。本项目保留 tmux（为了瞬时 reattach），只停止 opencode。

如果你希望 tmux 进程也归零，`set -g destroy-unattached on` 更简单，但手动 detach 也会销毁会话，而且没有瞬时恢复。

## 功能

- **精确恢复会话** —— 一个很小的 opencode TUI 插件按 `TMUX_PANE` 记录当前 session；wrapper 读取后执行 `opencode -s <session-id>`。
- **保留 tmux，停止 opencode** —— 会话、pane、cwd、scrollback 都保留；只停止占内存的 TUI/service。
- **默认安全** —— 只清理没有客户端 attach 的会话；手动 detach 不动。
- **集成 tmux-resurrect** —— 同步保存、修复空的 `last`、为重启恢复改写存档命令。
- **优雅回退** —— 插件缺失或 session 被删除时，回退到 `opencode -c`。

## 环境要求

- macOS（主要目标；Linux 未测试）
- [Ghostty](https://ghostty.org)
- tmux 3.x
- [TPM](https://github.com/tmux-plugins/tpm)
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum)
- opencode 2.x
- `sh`、`bash`、`awk`、`sed`、`pgrep`、`ps`（macOS 自带）

### 测试环境

| 组件 | 版本 |
|---|---|
| macOS | 26/27（Apple Silicon） |
| Ghostty | 1.x |
| tmux | 3.8 |
| opencode | 2.2.x |
| tmux-resurrect / tmux-continuum | TPM 最新版 |

## 项目结构

```
bin/tmux-start.sh              Ghostty wrapper：恢复 + attach + 清理
bin/opencode-clean.sh          手动清理
plugins/tmux-session-state/    opencode TUI 插件（按 pane 精确记录 session）
config/                        Ghostty 和 tmux 配置示例
tests/                         Shell 单元测试
docs/design.md                 架构与取舍（英文）
```

## 安装

```bash
git clone https://github.com/raindali/ghostty-tmux-opencode.git
cd ghostty-tmux-opencode
./install.sh
```

`install.sh` 会复制：

| 源文件 | 目标位置 |
|---|---|
| `bin/tmux-start.sh` | `~/.config/ghostty/tmux-start.sh` |
| `bin/opencode-clean.sh` | `~/.local/bin/opencode-clean.sh` |
| `plugins/tmux-session-state/tui.tsx` | `~/.config/opencode/plugins/tmux-session-state/tui.tsx` |

已有文件会备份为 `.bak.<timestamp>`。

### 1. Ghostty

把下面一行加到 `~/.config/ghostty/config`（把 `/Users/you` 换成你的 home 目录）：

```ini
initial-command = /Users/you/.config/ghostty/tmux-start.sh
```

`initial-command` 只作用于第一个窗口；其它窗口使用普通 shell。

### 2. tmux

把 [`config/tmux.conf.example`](config/tmux.conf.example) 合并到 `~/.tmux.conf`：

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

然后用 `prefix + I`（TPM）安装插件。

### 3. 重启

完全退出 Ghostty 再打开。第一次启动会加载 wrapper 和 opencode TUI 插件。

## 卸载

```bash
./uninstall.sh
```

然后从 Ghostty 配置里删掉 `initial-command`，从 `~/.tmux.conf` 删掉 tmux-resurrect 配置块。日志和 tmux-resurrect 存档会保留。

## 使用

正常使用 Ghostty 即可。

- **退出 Ghostty**（关窗口 / `Cmd+Q`）：opencode TUI 被停止，tmux 会话保留在原目录的 shell；没有 TUI 时后台 service 也会停止。
- **重新打开 Ghostty**：attach 到上次的会话，并精确恢复 opencode 会话。
- **`C-a d` detach**：不清理；会话和 opencode 都保留。

### 手动清理

```bash
opencode-clean.sh --dry-run      # 只打印会做什么
opencode-clean.sh                # 停止 opencode TUI，保留 tmux 会话
opencode-clean.sh --kill-session # 连同含 opencode 的 tmux 会话一起杀掉
```

## 工作原理

完整设计和取舍见 [docs/design.md](docs/design.md)（英文）。

### 启动

1. 读取 `~/.tmux/ghostty-last-pane`（`session`、`dir`、`cmd`、`pane`）。
2. 如果没有 tmux server，先创建一个占位会话，让 tmux-resurrect/continuum 能恢复上次布局。
3. 选择会话：优先上次的会话，其次有 opencode 的会话，最后最近活跃的会话。
4. 如果 tmux server 本来就在（正常退出后再打开），把保存的 `opencode -s <id>` 送回原来的 pane。
5. attach。

### 退出 Ghostty

1. 记录当前 pane 的目录和命令。
2. 根据 TUI 插件状态，建立 opencode pane → 精确 session ID 的映射。
3. 同步保存 tmux-resurrect，修复 0 字节的 `last`；在能唯一确定时，把存档里的 `:opencode` 改写成 `:opencode -s <id>`。
4. 停止没有客户端 attach 的会话里的 opencode TUI，保留 tmux 会话和 shell。
5. 没有 opencode TUI 时，停止 `opencode serve --service`。

### 精确 session 追踪

`plugins/tmux-session-state/tui.tsx` 使用 opencode TUI 插件 API：

```ts
context.ui.router.current() // { type: "session", sessionID } | ...
```

它把当前 session ID 原子写入：

```
${XDG_STATE_HOME:-~/.local/state}/opencode/tmux-session/<TMUX_PANE>
```

- 每个 tmux pane 一个文件 → 多个 TUI 不会互相覆盖。
- `router.current()` 会跟随 tab 切换，所以当前 tab 是精确的。
- 文件权限 `0600`，目录权限 `0700`。
- 不在 tmux 里（`TMUX_PANE` 未设置）时，插件什么都不做。

如果文件不存在，wrapper 回退到 `opencode -c`（当前项目最近一次会话）。

## 配置

wrapper 读取以下环境变量：

| 变量 | 默认值 |
|---|---|
| `TMUX_BIN` | `command -v tmux` |
| `OPENCODE_BIN` | `command -v opencode` |
| `TMUX_PLUGIN_MANAGER_PATH` | `~/.tmux/plugins` |
| `TMUX_RESURRECT_DIR` | `~/.tmux/resurrect` |
| `XDG_STATE_HOME` | `~/.local/state` |
| `GHOSTTY_TMUX_STATE` | `~/.tmux/ghostty-last-pane` |
| `GHOSTTY_TMUX_MAP` | `~/.tmux/opencode-session-map` |
| `GHOSTTY_TMUX_LOG` | `~/.tmux-autostart.log` |

## 验证

```bash
# 退出 Ghostty 后
tmux ls                 # 会话应该还在
pgrep -fl opencode      # 不应该有 opencode TUI
opencode service status # 没有 TUI 时 service 应该已停止

# 插件应该记录了当前 session
ls "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tmux-session/"
cat "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tmux-session/%1" # 把 %1 换成你的 pane id

# 重新打开 Ghostty 后
tail -20 ~/.tmux-autostart.log
```

日志里正常会看到（脚本输出为英文）：

```
saved state: session=main dir=/path/to/project cmd=opencode -s ses_xxx pane=%1
resurrect save done
patched resurrect with exact session ids
killed opencode in pane %1: 12345
cleaned opencode in session main (session kept)
stopped opencode background service
```

## 测试

```bash
./tests/run.sh   # 语法 + shellcheck（如果已安装）+ 单元测试
make test
make lint
```

测试覆盖 `repair_last`、`build_resurrect_map`、`:opencode -s <id>` 改写、`-c` 回退和 CLI help。CI 在 Linux 和 macOS 上运行。

## 故障排查

### 会话没有恢复

确认插件文件存在：

```bash
ls -l "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tmux-session/"
```

如果是空的，重启一次 TUI（插件在 TUI 启动时加载），并检查 opencode TUI 插件列表。

### tmux-resurrect 什么都没恢复

```bash
readlink ~/.tmux/resurrect/last
wc -c ~/.tmux/resurrect/last
grep '^pane' ~/.tmux/resurrect/last
```

`last` 必须非空，并且包含 `:opencode -s ...` 或 `:opencode -c`。

### Ghostty 退出后会话还在

终端关闭时 `tmux attach` 必须返回非 0。检查日志：

```bash
tail -30 ~/.tmux-autostart.log
```

找 `detached (hup=... status=...)`。如果 `status=0`，wrapper 会把它当成手动 detach，保留一切。

## 限制

- 状态文件为“终端关闭后再打开”记录一个 opencode pane。一个会话里有多个 opencode pane 时：resurrect 映射会为重启恢复改写全部，但重新打开时只会自动恢复记录的那个 pane。
- TUI 插件 API 比较新。如果未来 opencode 改动它，插件可能不再写入；wrapper 会回退到 `opencode -c`。
- 插件必须由 TUI 加载。安装后需要重启 TUI。
- 如果 session 被删除，`opencode -s <id>` 会失败；wrapper 只在没有 ID 时回退 `-c`，不会校验 ID 是否过期。必要时删掉过期的状态文件。
- `@resurrect-capture-pane-contents 'on'` 会把 pane 的 scrollback（可能包含敏感输出）存到 `~/.tmux/resurrect/pane_contents.tar.gz`。如果介意，关掉它或限制目录权限。

## 安全与隐私

- 不发起网络请求，没有遥测，不依赖外部服务。
- session 状态文件权限 `0600`，状态目录 `0700`。
- wrapper 会把 state、map、log 文件设置为 `600`。
- resurrect 存档目录的权限取决于你的 umask。如果开启了 pane 内容捕获，建议 `chmod 700 ~/.tmux/resurrect`。
- 仓库不包含个人路径、主机名、代理设置、token 或 session ID。

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。参与即表示同意 [Code of Conduct](CODE_OF_CONDUCT.md)。

- 安全报告：[SECURITY.md](SECURITY.md)
- 变更记录：[CHANGELOG.md](CHANGELOG.md)

## 相关项目

- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) 和 [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) —— 布局/cwd 持久化。
- [timvw/tmux-assistant-resurrect](https://github.com/timvw/tmux-assistant-resurrect) —— 更通用的多助手方案，使用 opencode server 插件 + 进程参数/SQLite 回退。
- [guysoft/tmux-resurrect-opencode-sessions](https://github.com/guysoft/tmux-resurrect-opencode-sessions) —— 通过 pane 标题和 opencode SQLite 数据库改写 tmux-resurrect 存档。

本项目使用 opencode **TUI 插件 API**（`ui.router.current()`），按 pane 精确知道当前 session，不依赖标题匹配或数据库猜测。

## 许可证

MIT，见 [LICENSE](LICENSE)。
