#!/bin/bash
# komon-tmux.sh - tmux で komon チームメンバーをリアルタイム監視・介入
#
# Usage:
#   ./scripts/komon-tmux.sh          # 3メンバー + 監視ペインで起動
#   ./scripts/komon-tmux.sh suke     # suke のみ起動
#   ./scripts/komon-tmux.sh kill     # セッション終了
#
# キーバインド (prefix = Ctrl-b):
#   F1 / M-1  : suke ペインにジャンプ
#   F2 / M-2  : kaku ペインにジャンプ
#   F3 / M-3  : yashichi ペインにジャンプ
#   F4 / M-4  : monitor ペインにジャンプ
#   Ctrl-b z  : ペインをズーム（全画面切替）
#   Ctrl-b d  : デタッチ（バックグラウンド継続）

set -euo pipefail

SESSION="komon"
PROJECT_DIR="/Users/hakaru/MIDI2Kit-SDK"
TODO="$PROJECT_DIR/tasks/todo.md"

# --- kill サブコマンド ---
if [[ "${1:-}" == "kill" ]]; then
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "komon セッションを終了しました" || echo "komon セッションは存在しません"
    exit 0
fi

# 既存セッションがあればアタッチ
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "既存の komon セッションにアタッチします"
    exec tmux attach-session -t "$SESSION"
fi

member="${1:-all}"

setup_style() {
    # ペインボーダーにタイトルを表示
    tmux set-option -t "$SESSION" pane-border-status top
    tmux set-option -t "$SESSION" pane-border-format " #[bold]#{pane_title}#[default] | #{pane_current_command} "
    tmux set-option -t "$SESSION" pane-border-style "fg=colour240"
    tmux set-option -t "$SESSION" pane-active-border-style "fg=colour39,bold"

    # ステータスバーのカスタマイズ
    tmux set-option -t "$SESSION" status-style "bg=colour235,fg=colour248"
    tmux set-option -t "$SESSION" status-left "#[fg=colour39,bold] komon #[default]| "
    tmux set-option -t "$SESSION" status-right "#[fg=colour245]%H:%M | Ctrl-b z:zoom | F1-F4:jump "
    tmux set-option -t "$SESSION" status-left-length 20
    tmux set-option -t "$SESSION" status-right-length 50
}

setup_keybindings() {
    # F1-F4 でペインにジャンプ (team ウィンドウ内)
    tmux bind-key -t "$SESSION" F1 select-pane -t "$SESSION:team.0" 2>/dev/null || \
        tmux bind-key F1 select-pane -t "$SESSION:team.0"
    tmux bind-key -t "$SESSION" F2 select-pane -t "$SESSION:team.1" 2>/dev/null || \
        tmux bind-key F2 select-pane -t "$SESSION:team.1"
    tmux bind-key -t "$SESSION" F3 select-pane -t "$SESSION:team.2" 2>/dev/null || \
        tmux bind-key F3 select-pane -t "$SESSION:team.2"
    tmux bind-key -t "$SESSION" F4 select-pane -t "$SESSION:team.3" 2>/dev/null || \
        tmux bind-key F4 select-pane -t "$SESSION:team.3"

    # Alt+数字でもジャンプ可能
    tmux bind-key M-1 select-pane -t "$SESSION:team.0"
    tmux bind-key M-2 select-pane -t "$SESSION:team.1"
    tmux bind-key M-3 select-pane -t "$SESSION:team.2"
    tmux bind-key M-4 select-pane -t "$SESSION:team.3"
}

# --- 監視用ペインで todo.md を watch ---
monitor_cmd="watch -n 10 -d 'echo \"=== komon progress ===\"; grep -E \"^- \\[[ x]\\]\" $TODO 2>/dev/null || echo \"todo.md not found\"'"

case "$member" in
    suke|kaku|yashichi)
        tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR" -n "$member"
        tmux send-keys -t "$SESSION:$member" "claude '/komon $member'" Enter
        tmux select-pane -t "$SESSION:$member.0" -T "$member"
        setup_style
        tmux attach-session -t "$SESSION"
        ;;
    all|go)
        # ┌──────────────────┬──────────────────┐
        # │                  │  kaku (広報・Web) │
        # │  suke (設計・実装) ├──────────────────┤
        # │                  │ yashichi (ドキュメント) │
        # │                  ├──────────────────┤
        # │                  │  monitor (進捗)  │
        # └──────────────────┴──────────────────┘

        tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR" -n team

        # ペイン0: suke（左 50%）
        tmux send-keys -t "$SESSION:team" "claude '/komon suke'" Enter

        # ペイン1: kaku（右上）
        tmux split-window -h -t "$SESSION:team" -c "$PROJECT_DIR" -p 50
        tmux send-keys -t "$SESSION:team.1" "claude '/komon kaku'" Enter

        # ペイン2: yashichi（右中）
        tmux split-window -v -t "$SESSION:team.1" -c "$PROJECT_DIR" -p 66
        tmux send-keys -t "$SESSION:team.2" "claude '/komon yashichi'" Enter

        # ペイン3: monitor（右下 - 進捗監視）
        tmux split-window -v -t "$SESSION:team.2" -c "$PROJECT_DIR" -p 30
        tmux send-keys -t "$SESSION:team.3" "$monitor_cmd" Enter

        # ペインタイトル設定
        tmux select-pane -t "$SESSION:team.0" -T "suke (設計・実装)"
        tmux select-pane -t "$SESSION:team.1" -T "kaku (広報・Web)"
        tmux select-pane -t "$SESSION:team.2" -T "yashichi (ドキュメント)"
        tmux select-pane -t "$SESSION:team.3" -T "monitor (進捗)"

        # スタイル・キーバインド設定
        setup_style
        setup_keybindings

        # suke ペインにフォーカス
        tmux select-pane -t "$SESSION:team.0"

        tmux attach-session -t "$SESSION"
        ;;
    *)
        cat <<'USAGE'
Usage: komon-tmux.sh [command]

Commands:
  all, go     3メンバー + 監視ペインで起動 (デフォルト)
  suke        suke のみ起動
  kaku        kaku のみ起動
  yashichi    yashichi のみ起動
  kill        セッション終了

キーバインド (Ctrl-b prefix):
  F1 / Alt-1  suke にジャンプ
  F2 / Alt-2  kaku にジャンプ
  F3 / Alt-3  yashichi にジャンプ
  F4 / Alt-4  monitor にジャンプ
  z           ズーム切替
  d           デタッチ
USAGE
        exit 1
        ;;
esac
