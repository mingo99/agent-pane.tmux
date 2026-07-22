#!/usr/bin/env bash
# Jump to the most important inactive pane:
#   1. question/input pending
#   2. unread completed agent/watch pane
set -euo pipefail

RUN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/run"
mkdir -p "$RUN_DIR"

current_pane="${TMUX_PANE:-}"

find_target() {
  local mode="$1"
  tmux list-panes -a \
    -F '#{session_id}:::#{window_id}:::#{pane_id}:::#{@op_question_pending}:::#{@agent_status}:::#{@agent_unread}:::#{@agent_updated_at}:::#{@watch_failed}:::#{@unread}' 2>/dev/null \
    | awk -F ':::' -v mode="$mode" -v current="$current_pane" '
        $3 == current { next }
        mode == "question" && $4 == "1" {
          ts = ($7 ~ /^[0-9]+$/ ? $7 : 0)
          if (ts >= best) { best = ts; line = $1 "\t" $2 "\t" $3 }
        }
        mode == "unread" && (($6 == "1") || ($9 == "1")) {
          ts = ($7 ~ /^[0-9]+$/ ? $7 : 0)
          if (ts >= best) { best = ts; line = $1 "\t" $2 "\t" $3 }
        }
        END { if (line != "") print line }
      '
}

target="$(find_target question)"
if [[ -z "$target" ]]; then
  target="$(find_target unread)"
fi
[[ -n "$target" ]] || exit 0

IFS=$'\t' read -r sid wid pid <<< "$target"
[[ -n "${sid:-}" && -n "${wid:-}" && -n "${pid:-}" ]] || exit 0

if [[ -n "$current_pane" ]]; then
  current=$(tmux display-message -p "#{session_id}:::#{window_id}:::#{pane_id}:::#{session_name}:::#{window_index}:::#{pane_index}" 2>/dev/null | tr -d '\r\n')
  printf '%s\n' "$current" > "$RUN_DIR/jump_back.txt"
fi

tmux set-option -p -u -t "$pid" @agent_unread 2>/dev/null || true
tmux set-option -p -u -t "$pid" @op_question_pending 2>/dev/null || true
tmux set-option -w -u -t "$wid" @unread 2>/dev/null || true
tmux set-option -w -u -t "$wid" @watch_failed 2>/dev/null || true

tmux switch-client -t "$sid" \; select-window -t "$wid" \; select-pane -t "$pid"
