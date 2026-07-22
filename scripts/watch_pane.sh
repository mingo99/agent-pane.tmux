#!/usr/bin/env bash
# Watches a pane for command completion and sets agent status markers.
set -euo pipefail

pane_id="$1"
window_id="$2"

[[ -z "$pane_id" || -z "$window_id" ]] && exit 1

pane_pid=$(tmux display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null || true)
if [[ -z "$pane_pid" ]]; then exit 0; fi

pane_shell=$(ps -o comm= -p "$pane_pid" 2>/dev/null | sed 's|.*/||; s/^-//')
if [[ -z "$pane_shell" ]]; then exit 0; fi

current_cmd=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null || true)
if [[ -z "$current_cmd" ]]; then exit 0; fi

clear_pane_watch() {
  tmux set-option -p -u -t "$pane_id" @pane_watching 2>/dev/null || true
  tmux set-option -p -u -t "$pane_id" @pane_watch_done 2>/dev/null || true
  tmux set-option -p -u -t "$pane_id" @pane_watch_exit_status 2>/dev/null || true
}

trap clear_pane_watch EXIT

track_start() {
  local now
  now="$(date +%s)"
  tmux set-option -p -t "$pane_id" @agent_status running 2>/dev/null || true
  tmux set-option -p -t "$pane_id" @agent_summary "$current_cmd" 2>/dev/null || true
  tmux set-option -p -t "$pane_id" @agent_updated_at "$now" 2>/dev/null || true
  tmux set-option -p -u -t "$pane_id" @agent_unread 2>/dev/null || true
}

track_completion() {
  local message now
  message="${current_cmd} finished"
  now="$(date +%s)"
  tmux set-option -p -t "$pane_id" @agent_status done 2>/dev/null || true
  tmux set-option -p -t "$pane_id" @agent_summary "$message" 2>/dev/null || true
  tmux set-option -p -t "$pane_id" @agent_updated_at "$now" 2>/dev/null || true
  tmux set-option -p -t "$pane_id" @agent_unread 1 2>/dev/null || true
}

if [[ "$current_cmd" == "$pane_shell" ]]; then
  exit 0
fi

# Interactive AI CLIs remain running between turns. Their native lifecycle
# hooks create and finish tracker tasks at the correct time.
case "$current_cmd" in
  claude|codex) exit 0 ;;
esac

tmux set -wu -t "$window_id" @unread 2>/dev/null || true
tmux set -wu -t "$window_id" @watch_failed 2>/dev/null || true
tmux set -w -t "$window_id" @watching 1 2>/dev/null || true
tmux set-option -p -t "$pane_id" @pane_watching 1 2>/dev/null || true
tmux set-option -p -t "$pane_id" @pane_watch_done 0 2>/dev/null || true
tmux set-option -p -u -t "$pane_id" @pane_watch_exit_status 2>/dev/null || true
tmux refresh-client -S
track_start

while true; do
  sleep 1
  watching=$(tmux show -wv -t "$window_id" @watching 2>/dev/null || true)
  [[ "$watching" != "1" ]] && exit 0
  watch_done=$(tmux show-options -pv -t "$pane_id" @pane_watch_done 2>/dev/null || true)
  [[ "$watch_done" == "1" ]] && break
  cmd=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null || true)
  if [[ -z "$cmd" || "$cmd" == "$pane_shell" ]]; then
    break
  fi
done

exit_status=$(tmux show-options -pv -t "$pane_id" @pane_watch_exit_status 2>/dev/null || true)

tmux set -wu -t "$window_id" @watching 2>/dev/null || true
if [[ "$exit_status" =~ ^[0-9]+$ && "$exit_status" != "0" ]]; then
  tmux set -w -t "$window_id" @watch_failed 1 2>/dev/null || true
else
  tmux set -wu -t "$window_id" @watch_failed 2>/dev/null || true
fi
tmux set -w -t "$window_id" @unread 1 2>/dev/null || true
tmux refresh-client -S
track_completion
