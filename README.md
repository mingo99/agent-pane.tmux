# agent-pane.tmux

> Agent task tracker, notification system, and fzf pane navigator for tmux.

Tracks AI agent task lifecycle (running -> done/failed), provides unread/watch markers per pane/window, and bundles matching fzf popups for live panes and saved Claude Code sessions.

## Features

- **Task tracking** — Watch pane commands and track running/done/failed state
- **Unread markers** — Per-pane and per-window "has new output" flags
- **Input pending** — Detects when an agent is waiting for user input
- **Focus-aware clearing** — Unread markers auto-clear when pane/window is selected
- **fzf pane navigator** — Browse all panes with agent status, MRU ordering, terminal preview, and move/kill/swap actions
- **Claude history manager** — Search saved Claude Code sessions, preview transcripts, restore sessions, and trash or delete old history
- **Unified popup UI** — Pane and session popups use the same fzf layout, default terminal background, bottom preview, visible selection background, and bottom shortcut label
- **Status bar icons** — Appends agent state icons to existing `window-status-format`

## Installation

### Via TPM

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'mingo99/agent-pane.tmux'
```

Then `Prefix + I` to install.

### Manual

Clone and source in `~/.tmux.conf`:

```tmux
run '~/.config/tmux/plugins/agent-pane.tmux/agent.tmux'
```

## Claude Code Hooks

The status icons for Claude Code require Claude lifecycle hooks. Add this to
`~/.claude/settings.json`, or merge the `hooks` block into your existing file:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/tmux/plugins/agent-pane.tmux/scripts/claude_task_event.sh start",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/tmux/plugins/agent-pane.tmux/scripts/claude_task_event.sh stop",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/tmux/plugins/agent-pane.tmux/scripts/claude_task_event.sh notify",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

These hooks map Claude events to tmux pane state:

| Claude event | tmux state |
|---|---|
| `UserPromptSubmit` | running |
| `Stop` | done + unread when the pane is inactive |
| `Notification` | waiting for input + unread when the pane is inactive |

Restart any existing Claude Code pane after changing `settings.json`; already
running Claude processes may not reload hook settings.

## Keybindings

| Key | Action |
|---|---|
| `prefix + b` | Toggle unread marker on current window |
| `prefix + w` | Toggle pane watch (monitor command completion) |
| `prefix + m` | Jump to latest notified pane (question > unread) |
| `prefix + M` | Jump back to last origin pane |
| `prefix + f` | Open fzf pane navigator popup |
| `prefix + C` | Open Claude Code history manager popup |

### fzf navigator actions

`prefix + f` opens a searchable list of live tmux panes. The list is aligned into fixed columns and the preview is the raw terminal capture from the selected pane.

| Shortcut | Action |
|---|---|
| `Enter` | Switch to selected pane |
| `Ctrl-x` | Kill selected pane |
| `Ctrl-v` | Move pane to the right of the origin pane |
| `Ctrl-s` | Move pane below the origin pane |
| `Ctrl-t` | Swap with last pane |
| `Ctrl-r` | Reload pane list |
| `Alt-p` | Toggle preview |

Multi-select with `Tab` — selecting multiple panes breaks them into a new window with auto-layout (wide → horizontal, tall → vertical, 3+ → tiled).

### Claude history actions

`prefix + C` scans `~/.claude/projects` and opens a searchable Claude Code history list. `subagents/` transcripts are skipped by default. Active sessions are previewed with the same raw tmux capture used by the pane navigator; closed sessions use a compact transcript preview with `User` and `Claude` role labels.

| Shortcut | Action |
|---|---|
| `Enter` | Restore selected session in a new tmux window |
| `Ctrl-v` | Restore in a right split |
| `Ctrl-s` | Restore in a bottom split |
| `Ctrl-o` | Type the restore command into the origin pane |
| `Ctrl-i` | Toggle selection for the current session |
| `Ctrl-x` | Delete selected sessions, or the current session if none are selected |
| `Ctrl-y` | Copy session id |
| `Ctrl-r` | Reload session list |
| `Alt-p` | Toggle preview |

Trash location:

```text
~/.local/share/tmux-claude-sessions/trash/
```

After pressing `Ctrl-x`, choose `t` to move transcripts to trash or `d` to delete them permanently. Both choices require confirmation, support multiple selected sessions, and reopen the session list automatically afterward.

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
| `scripts/claude_task_event.sh` | Bridges Claude Code hooks into tmux pane status |
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
