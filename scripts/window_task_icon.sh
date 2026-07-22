#!/usr/bin/env bash
# Status bar icon for agent/window state.
# Embeds inline in window-status-format via #() tmux syntax.
set -euo pipefail

window_id="${1:-}"
unread="${2:-0}"
watching="${3:-0}"
watch_failed="${4:-0}"
window_active="${5:-0}"
[[ -z "$window_id" ]] && exit 0
[[ "$window_active" == "1" ]] && exit 0

has_bell=0
has_fail=0
has_question=0
has_watch=0

[[ "$unread" == "1" ]] && has_bell=1
[[ "$unread" == "1" && "$watch_failed" == "1" ]] && has_fail=1
[[ "$watching" == "1" ]] && has_watch=1

question_pane=$(tmux list-panes -t "$window_id" -F '#{@op_question_pending}' 2>/dev/null | grep -F -m1 -x '1' || true)
[[ -n "$question_pane" ]] && has_question=1

agent_state=$(tmux list-panes -t "$window_id" -F '#{@agent_status}:#{@agent_unread}' 2>/dev/null || true)
agent_unread=$(grep -m1 ':1$' <<< "$agent_state" || true)
[[ -n "$agent_unread" ]] && has_bell=1

agent_running=$(grep -m1 '^running:' <<< "$agent_state" || true)
[[ -n "$agent_running" ]] && has_watch=1

if (( has_question )); then
  printf '#[fg=#7dcfff]󰋗'
elif (( has_fail )); then
  printf '#[fg=#f7768e]󰅖'
elif (( has_bell )); then
  printf '#[fg=#9ece6a]󰄬'
elif (( has_watch )); then
  printf '#[fg=#e0af68]󰔟'
fi
