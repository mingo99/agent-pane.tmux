# tmux-agent-pane

> Agent task tracker, notification system, and fzf pane navigator for tmux.

Tracks AI agent task lifecycle (running → done/failed), provides unread/watch markers per pane/window, and bundles an fzf-based pane navigator with agent status awareness.

## Features

- **Task tracking** — Watch pane commands and track running/done/failed state
- **Unread markers** — Per-pane and per-window "has new output" flags
- **Input pending** — Detects when an agent is waiting for user input
- **Focus-aware clearing** — Unread markers auto-clear when pane/window is selected
- **fzf pane navigator** — Browse all panes with agent status, MRU ordering, preview, and move/kill/swap actions
- **Claude history manager** — Search saved Claude Code sessions, preview transcripts, restore sessions, and trash old history
- **Status bar icons** — Appends agent state icons to existing `window-status-format`

## Installation

### Via TPM

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'user/tmux-agent-pane'
```

Then `Prefix + I` to install.

### Manual

Clone and source in `~/.tmux.conf`:

```tmux
run '~/.config/tmux/plugins/tmux-agent-pane/agent.tmux'
```

## Keybindings

| Key | Action |
|---|---|
| `M-b` | Toggle unread marker on current window |
| `M-w` | Toggle pane watch (monitor command completion) |
| `M-m` | Jump to latest notified pane (question > unread) |
| `M-M` | Jump back to last origin pane |
| `f` | Open fzf pane navigator popup |
| `C` | Open Claude Code history manager popup |

### fzf navigator actions

| Shortcut | Action |
|---|---|
| `Enter` | Switch to selected pane |
| `Ctrl-x` | Kill selected pane |
| `Ctrl-v` | Move pane to left (horizontal split with last pane) |
| `Ctrl-s` | Move pane to bottom (vertical split with last pane) |
| `Ctrl-t` | Swap with last pane |
| `Ctrl-r` | Reload pane list |
| `Alt-p` | Toggle preview |

Multi-select with `Tab` — selecting multiple panes breaks them into a new window with auto-layout (wide → horizontal, tall → vertical, 3+ → tiled).

### Claude history actions

`prefix + C` scans `~/.claude/projects` and opens a searchable Claude Code history list. `subagents/` transcripts are skipped by default.

| Shortcut | Action |
|---|---|
| `Enter` | Restore selected session in a new tmux window |
| `Ctrl-v` | Restore in a right split |
| `Ctrl-s` | Restore in a bottom split |
| `Ctrl-o` | Type the restore command into the origin pane |
| `Ctrl-x` | Choose trash or permanent deletion |
| `Ctrl-y` | Copy session id |
| `Ctrl-r` | Reload session list |
| `Alt-p` | Toggle preview |

Trash location:

```text
~/.local/share/tmux-claude-sessions/trash/
```

After pressing `Ctrl-x`, choose `t` to move the transcript to trash or `d` to
delete it permanently. Both choices require confirmation, and the session list
reopens automatically afterward.

Sessions launched through this manager set pane option `@claude_session_id`, so the history list can mark them as `active` while the pane exists.

## Status Bar Icons

The plugin appends status icons to your existing `window-status-format`:

| Icon | Meaning |
|---|---|
| `󰋗` (blue) | Agent waiting for input |
| `󰅖` (red) | Command/watch failed |
| `󰄬` (green) | Unread output available |
| `󰔟` (yellow) | Task running |

Icons only show on inactive windows. Active window shows the theme format as-is.

## Scripts

| File | Purpose |
|---|---|
| `agent.tmux` | TPM entry point — sets hooks, keybindings, status |
| `scripts/clear_agent_pane_state.sh` | Clears unread/watch flags on focus |
| `scripts/watch_pane.sh` | Monitors a pane for command completion |
| `scripts/focus_latest_notified.sh` | Jumps to the pane with highest-priority notification |
| `scripts/focus_last_origin.sh` | Jumps back to the previous pane |
| `scripts/window_task_icon.sh` | Renders the agent status icon for a window |
| `scripts/append_agent_status_icon.sh` | Patches window-status-format with the icon |
| `fzf_panes.tmux` | fzf-based pane navigator with status, MRU, preview |
| `claude_sessions.tmux` | fzf-based Claude Code history manager |

## Dependencies

- `bash`, `awk`, `sed`, `date` (standard POSIX)
- `fzf` — required for the pane navigator popup (`f` key)
- `python3` — required for the Claude history manager popup (`C` key)
- `claude` — required to restore Claude Code sessions
- Nerd Font — required for status icons
- tmux ≥ 3.2 (for `display-popup` support)
