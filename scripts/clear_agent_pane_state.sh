#!/usr/bin/env bash
# Clears agent unread/watch markers on pane/window focus.
set -euo pipefail

pane_id="${1:-}"
window_id="${2:-}"
[[ -n "$pane_id" ]] || exit 0

status="$(tmux show-options -pv -t "$pane_id" @agent_status 2>/dev/null || true)"

tmux set-option -p -u -t "$pane_id" @agent_unread 2>/dev/null || true
tmux set-option -p -u -t "$pane_id" @op_question_pending 2>/dev/null || true

if [[ -n "$window_id" ]]; then
  tmux set-option -w -u -t "$window_id" @unread 2>/dev/null || true
  tmux set-option -w -u -t "$window_id" @watch_failed 2>/dev/null || true
fi

if [[ "$status" != "running" ]]; then
  tmux set-option -p -u -t "$pane_id" @agent_status 2>/dev/null || true
  tmux set-option -p -u -t "$pane_id" @agent_summary 2>/dev/null || true
  tmux set-option -p -u -t "$pane_id" @agent_updated_at 2>/dev/null || true
fi

tmux refresh-client -S 2>/dev/null || true
