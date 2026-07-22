#!/usr/bin/env bash
# ============================================================
# tmux-agent-pane — Agent task tracker, notification, and
#                   fzf pane navigator for tmux.
#
# Install via TPM:
#   set -g @plugin 'user/tmux-agent-pane'
#
# Or source directly:
#   run '~/.config/tmux/plugins/tmux-agent-pane/agent.tmux'
# ============================================================
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"

# ============================================================
# Hooks — clear unread/watch state on focus events
# ============================================================

tmux set-hook -g client-attached \
  "run -b \"bash '$SCRIPTS/clear_agent_pane_state.sh' #{q:pane_id} #{q:window_id}\""

tmux set-hook -g after-select-pane \
  "run -b \"bash '$SCRIPTS/clear_agent_pane_state.sh' #{q:pane_id} #{q:window_id}\""
tmux set-hook -ag after-select-pane \
  "run -b \"bash '$CURRENT_DIR/fzf_panes.tmux' update_mru_pane_ids\""

tmux set-hook -g after-select-window \
  "run -b \"bash '$SCRIPTS/clear_agent_pane_state.sh' #{q:pane_id} #{q:window_id}\""
tmux set-hook -ag after-select-window \
  "run -b \"bash '$CURRENT_DIR/fzf_panes.tmux' update_mru_pane_ids\""

tmux set-hook -g client-session-changed \
  "run -b \"bash '$SCRIPTS/clear_agent_pane_state.sh' #{q:pane_id} #{q:window_id}\""

# ============================================================
# Keybindings
# ============================================================

# Toggle unread marker on current window
tmux bind -n M-b run-shell \
  'val=$(tmux show -wv @unread 2>/dev/null); if [ "$val" = "1" ]; then tmux set -wu @unread; tmux set -wu @watch_failed; else tmux set -w @unread 1; tmux set -wu @watch_failed; fi; tmux refresh-client -S'

# Toggle pane watch (monitor command completion)
tmux bind -n M-w run-shell -b \
  "val=\$(tmux show-options -wqv @watching); if [ \"\$val\" = \"1\" ]; then tmux set -wu @watching; tmux set -wu @watch_failed; tmux refresh-client -S; else bash '$SCRIPTS/watch_pane.sh' \"#{pane_id}\" \"#{window_id}\"; fi"

# Jump to latest notified pane
tmux bind -n M-m run-shell \
  "test -f '$SCRIPTS/focus_latest_notified.sh' && bash '$SCRIPTS/focus_latest_notified.sh' || true"

# Jump back to last origin pane
tmux bind -n M-M run-shell \
  "test -f '$SCRIPTS/focus_last_origin.sh' && bash '$SCRIPTS/focus_last_origin.sh' || true"

# fzf pane navigator in a popup
tmux bind f display-popup -E -w 92% -h 88% -T ' pane navigator ' \
  -b rounded -s 'bg=default,fg=default' -S 'bg=default,fg=default' \
  "bash '$CURRENT_DIR/fzf_panes.tmux' do_action"

# Claude Code history manager in a popup
tmux bind C display-popup -E -w 92% -h 88% -T ' Claude sessions ' \
  -b rounded -s 'bg=default,fg=default' -S 'bg=default,fg=default' \
  "TMUX_ORIGIN_PANE='#{pane_id}' '$CURRENT_DIR/claude_sessions.tmux'"

# Clean up default bindings that conflict
tmux unbind P 2>/dev/null || true
tmux unbind N 2>/dev/null || true

# ============================================================
# Status bar — append agent task icon to window format
# ============================================================

# Run after TPM/theme plugins have loaded so the tokyonight
# window-status-format is already set and we can patch it.
bash "$SCRIPTS/append_agent_status_icon.sh"
