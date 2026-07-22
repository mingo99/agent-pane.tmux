#!/usr/bin/env bash
# fzf-based pane navigator with agent status indicators.
# Supports MRU ordering, preview, kill/move/swap panes.

new_window() {
    [[ -x $(command -v fzf 2>/dev/null) ]] || return
    pane_id=$(tmux show -gqv '@fzf_pane_id')
    [[ -n $pane_id ]] && tmux kill-pane -t $pane_id >/dev/null 2>&1
    tmux new-window "bash $0 do_action" >/dev/null 2>&1
}

# invoked by pane-focus-in event
update_mru_pane_ids() {
    o_data=($(tmux show -gqv '@mru_pane_ids'))
    current_pane_id=$(tmux display-message -p '#D')
    n_data=($current_pane_id)
    for i in ${!o_data[@]}; do
        [[ $current_pane_id != ${o_data[i]} ]] && n_data+=(${o_data[i]})
    done
    tmux set -g '@mru_pane_ids' "${n_data[*]}"
}

do_action() {
    trap 'tmux set -gu @fzf_pane_id' EXIT SIGINT SIGTERM
    current_pane_id=$(tmux display-message -p '#D')
    tmux set -g @fzf_pane_id $current_pane_id

    cmd="bash $0 panes_src"
    set -- 'tmux capture-pane -pe -S' \
        '$(start=$(( $(tmux display-message -t {1} -p "#{pane_height}")' \
        '- $FZF_PREVIEW_LINES ));' \
        '(( start>0 )) && echo $start || echo 0) -t {1}'
    preview_cmd=$*
    last_pane_cmd='$(tmux show -gqv "@mru_pane_ids" | cut -d\  -f1)'
    selected=$(FZF_DEFAULT_COMMAND=$cmd fzf -m --ansi --preview="$preview_cmd" \
        --layout=reverse --info=inline --header-lines=1 --padding=1 \
        --input-border=rounded --input-label=' Search panes ' \
        --list-border=rounded --list-label=' Panes ' \
        --preview-border=rounded --preview-label=' Preview ' \
        --preview-window='down:55%' --prompt=' 󰆍  ' --pointer='▌' --marker='󰄬' \
        --color='bg:-1,bg+:-1,gutter:-1,fg:#a9b1d6,fg+:#c0caf5,hl:#7dcfff,hl+:#7dcfff,header:#737aa2,info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7,marker:#9ece6a,spinner:#e0af68,border:#3b4261,label:#7aa2f7,preview-bg:-1' \
        --delimiter='\s{2,}' --with-nth=2..-1 --nth=2..-1 \
        --bind="alt-p:toggle-preview" \
        --bind="ctrl-r:reload($cmd)" \
        --bind="ctrl-x:execute-silent(tmux kill-pane -t {1})+reload($cmd)" \
        --bind="ctrl-v:execute(tmux move-pane -h -t $last_pane_cmd -s {1})+accept" \
        --bind="ctrl-s:execute(tmux move-pane -v -t $last_pane_cmd -s {1})+accept" \
        --bind="ctrl-t:execute-silent(tmux swap-pane -t $last_pane_cmd -s {1})+reload($cmd)")
    (($?)) && return

    ids_o=($(tmux show -gqv '@mru_pane_ids'))
    ids=()
    for id in ${ids_o[@]}; do
        while read pane_line; do
            pane_info=($pane_line)
            pane_id=${pane_info[0]}
            [[ $id == $pane_id ]] && ids+=($id)
        done <<<$selected
    done

    id_n=${#ids[@]}
    id1=${ids[0]}
    if ((id_n == 1)); then
        tmux switch-client -t$id1
    elif ((id_n > 1)); then
        tmux break-pane -s$id1
        i=1
        tmux_cmd="tmux "
        while ((i < id_n)); do
            tmux_cmd+="move-pane -t${ids[i-1]} -s${ids[i]} \; select-layout -t$id1 'tiled' \; "
            ((i++))
        done

        # Auto-detect layout: wide windows get horizontal split
        if (( id_n == 2 )); then
            w_size=($(tmux display-message -p '#{window_width} #{window_height}'))
            w_wid=${w_size[0]}
            w_hei=${w_size[1]}
            if (( 9*w_wid > 16*w_hei )); then
                layout='even-horizontal'
            else
                layout='even-vertical'
            fi
        else
            layout='tiled'
        fi

        tmux_cmd+="switch-client -t$id1 \; select-layout -t$id1 $layout \; "
        eval $tmux_cmd
    fi
}

panes_src() {
    printf "%-6s  %-12s  %-6s  %-13s  %-14s  %-16s  %s\n" \
        'PANEID' 'SESSION' 'PANE' 'TYPE' 'STATUS' 'COMMAND' 'DETAIL'
    ids=()
    ordered_ids=($(tmux show -gqv '@mru_pane_ids'))
    for pane_id in $(tmux list-panes -aF '#{pane_id}'); do
        [[ $pane_id == "$TMUX_PANE" ]] && continue
        found=0
        for known_id in ${ordered_ids[@]}; do
            [[ $known_id == $pane_id ]] && found=1 && break
        done
        (( found == 0 )) && ordered_ids+=($pane_id)
    done
    for id in ${ordered_ids[@]}; do
        pane_info=$(tmux display-message -p -t "$id" \
            '#{pane_id}|#{session_name}|#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{window_id}|#{@unread}|#{@watch_failed}|#{@op_question_pending}|#{@agent_status}|#{@agent_unread}|#{@agent_summary}' 2>/dev/null || true)
        [[ -z $pane_info ]] && continue
        IFS='|' read -r pane_id session pane cmd location window_id unread watch_failed question_pending agent_status agent_unread agent_summary <<<$pane_info
        [[ $pane_id == "$TMUX_PANE" ]] && continue

        # Classify pane type
        case "$cmd" in
            claude|codex) kind='󰚩 agent' ;;
            ssh)          kind='󰣀 remote' ;;
            zsh|bash|fish) kind=' shell' ;;
            *)            kind='󰆍 process' ;;
        esac

        location=${location/#$HOME/\~}
        detail=${agent_summary:-$location}
        detail=$(printf '%s' "$detail" | tr '\t\r\n' '   ' | cut -c1-120)

        # Determine status and color
        if [[ $question_pending == 1 ]]; then
            status='󰋗 input'
            color=$'\033[38;2;125;207;255m'
            detail="Waiting for input · $location"
        elif [[ $unread == 1 && $watch_failed == 1 ]]; then
            status='󰅖 failed'
            color=$'\033[38;2;247;118;142m'
        elif [[ $agent_status == running ]]; then
            status='󰔟 running'
            color=$'\033[38;2;224;175;104m'
        elif [[ $agent_unread == 1 ]] || [[ $unread == 1 ]]; then
            status='󰄬 unread'
            color=$'\033[38;2;158;206;106m'
        else
            status='· idle'
            color=$'\033[38;2;86;95;137m'
            detail=$location
        fi

        status_cell=$(printf '%-14s' "$status")
        printf "%-6s  %-12s  %-6s  %-13s  %b%s\033[0m  %-16s  %s\n" \
            "$pane_id" "$session" "$pane" "$kind" "$color" "$status_cell" "$cmd" "$detail"
        ids+=($id)
    done
    tmux set -g '@mru_pane_ids' "${ids[*]}"
}

$@
