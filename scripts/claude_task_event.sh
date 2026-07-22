#!/usr/bin/env bash
# Bridge Claude Code lifecycle hooks to tmux pane/window state.
set -euo pipefail

event="${1:-}"
pane_id="${TMUX_PANE:-}"

if [[ -z "$pane_id" ]]; then
  exit 0
fi

if ! tmux has-session 2>/dev/null; then
  exit 0
fi

window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}' 2>/dev/null || true)"
active_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"

set_pane() {
  tmux set-option -p -t "$pane_id" "$@" 2>/dev/null || true
}

unset_pane() {
  tmux set-option -p -u -t "$pane_id" "$1" 2>/dev/null || true
}

set_window_unread() {
  if [[ -n "$window_id" && "$pane_id" != "$active_pane" ]]; then
    tmux set-option -w -t "$window_id" @unread 1 2>/dev/null || true
  fi
}

case "$event" in
  start)
    set_pane @agent_status running
    set_pane @agent_updated_at "$(date +%s)"
    unset_pane @agent_unread
    unset_pane @op_question_pending
    if [[ -n "$window_id" ]]; then
      tmux set-option -w -u -t "$window_id" @watch_failed 2>/dev/null || true
    fi
    ;;
  stop)
    set_pane @agent_status done
    set_pane @agent_updated_at "$(date +%s)"
    unset_pane @op_question_pending
    if [[ "$pane_id" != "$active_pane" ]]; then
      set_pane @agent_unread 1
      set_window_unread
    else
      unset_pane @agent_unread
    fi
    ;;
  notify)
    set_pane @agent_status input
    set_pane @op_question_pending 1
    set_pane @agent_updated_at "$(date +%s)"
    if [[ "$pane_id" != "$active_pane" ]]; then
      set_pane @agent_unread 1
      set_window_unread
    fi
    ;;
  *)
    exit 0
    ;;
esac

tmux refresh-client -S 2>/dev/null || true
