#!/usr/bin/env bash
# exit codes:
#   0  送信し、宛先の着手または決着を観測した
#   3  クールダウン抑止 (同一宛先へ同一内容の連投)
#   4  往復上限抑止 (ループの疑い)
#   5  宛先が blocked (承認 UI へ文字を流し込まないためのガード)
#   6  宛先を起こせなかった (agent_prompt_stalled)
#   7  送信は通ったが着手を観測できないままタイムアウト
#   2  usage error / 宛先が見つからない
set -euo pipefail

action_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env.sh
. "$action_dir/env.sh"

usage() {
  echo "usage: send.sh [--reply-to <your-agent-name>] <to-agent-name> <body>" >&2
  exit 2
}
reply_to=""
if [ "${1:-}" = "--reply-to" ]; then
  [ $# -ge 3 ] || usage
  reply_to="$2"
  shift 2
fi
[ $# -eq 2 ] || usage
to="$1"
body="$2"

# 受信者に規約 (AGENTS.md) が届いていない環境でも返信経路が伝わるよう、
# 返信手段をメッセージ自体に埋め込む (規約なしの coder が send せずペイン出力で
# 終了し、往復が途切れた実機 incident への対策)
if [ -n "$reply_to" ]; then
  script_path="$action_dir/send.sh"
  body="$body

[返信方法] このメッセージへの返信・質問・完了報告は次のコマンドで送ること: bash $script_path $reply_to \"<本文>\""
fi

# 送信者が sandbox 下 (codex workspace-write 等) だと state_dir に書けないことがある。
# その場合もガード記録を諦めるだけで送信は続行する (実機で確認)。
state_writable=1
mkdir -p "$state_dir" 2>/dev/null || state_writable=0

cooldown_secs=30    # 同一宛先・同一内容の再送を抑止する秒数
max_sends=30        # window 内の同一宛先への送信上限 (往復上限の保険)
window_secs=600

now=$(date +%s)
body_hash=$(printf '%s\n%s' "$to" "$body" | shasum -a 256 | cut -d' ' -f1)

last_file="$state_dir/last-send-$to"
if [ -f "$last_file" ]; then
  read -r last_ts last_hash < "$last_file" || true
  if [ "${last_hash:-}" = "$body_hash" ] && [ $((now - ${last_ts:-0})) -lt $cooldown_secs ]; then
    echo "cooldown: identical message to '$to' within ${cooldown_secs}s; not sent" >&2
    exit 3
  fi
fi

# タスク境界を持てないため、rolling window の送信数で wake loop を抑止する。
count_file="$state_dir/sends-$to.log"
if [ -f "$count_file" ]; then
  recent=$(awk -v cutoff=$((now - window_secs)) '$1 >= cutoff' "$count_file" | wc -l | tr -d ' ')
  if [ "$recent" -ge $max_sends ]; then
    echo "depth limit: $recent sends to '$to' in the last $((window_secs / 60))min; refusing to prevent a wake loop" >&2
    exit 4
  fi
fi

# 承認・質問 UI への文字流し込みを避けるため、blocked には送らない。
agent_info=$("$herdr_bin" agent get "$to" 2>&1) || {
  echo "unknown agent '$to': $agent_info" >&2
  exit 2
}
if printf '%s' "$agent_info" | grep -qE '"agent_status"[[:space:]]*:[[:space:]]*"blocked"'; then
  echo "guard: '$to' is blocked (approval/question UI); resolve it first, message not sent" >&2
  exit 5
fi

# 送信記録 (stalled の連打も抑止対象にするため、結果を問わず先に記録する)
if [ $state_writable -eq 1 ] && printf '%s %s\n' "$now" "$body_hash" > "$last_file" 2>/dev/null; then
  printf '%s\n' "$now" >> "$count_file" 2>/dev/null || true
else
  echo "warn: state dir '$state_dir' not writable; cooldown/depth guards inactive for this sender" >&2
fi

# 受信者が send を怠っても報告を返すため、成功時に返信先 marker を残す。
mark_pending() {
  dest="$reply_to"
  [ -n "$dest" ] || { [ "$to" = "coder" ] && dest="leader"; } || true
  [ -n "$dest" ] || return 0
  [ "$state_writable" -eq 1 ] || return 0
  printf '%s\n' "$dest" > "$state_dir/pending-reply-$to" 2>/dev/null || true
  to_pane=$("$herdr_bin" agent get "$to" 2>/dev/null | json_field pane_id)
  [ -n "$to_pane" ] && "$herdr_bin" pane report-metadata "$to_pane" --source thkt.agentchat --title "reply pending -> $dest" >/dev/null 2>&1 || true
}

# 投入 + 着手観測。--wait は非 working からの送信で 5 秒以内の状態遷移を要求し、
# 観測できなければ agent_prompt_stalled を返す (herdr 仕様)。
# --until working で「着手」を成功にし、done / blocked も決着として受ける。
set +e
err=$("$herdr_bin" agent prompt "$to" "$body" --wait \
  --until working --until "done" --until blocked \
  --timeout 15000 2>&1 >/dev/null)
status=$?
set -e

if [ $status -eq 0 ]; then
  post_state=$("$herdr_bin" agent get "$to" 2>/dev/null | json_field agent_status || true)
  mark_pending
  echo "sent to '$to'; recipient reacted (${post_state:-agent_status unavailable})"
  exit 0
fi

if printf '%s' "$err" | grep -q 'agent_prompt_stalled'; then
  # stalled は「未達」ではない。本文は宛先の入力欄に投入済みで、宛先 UI の状態
  # (hook 実行中など) により Enter だけが呑まれた場合がある (実機で確認)。
  # 同一内容の再送は二重投入になるため、Enter の追い打ちで送信を完成させる。
  "$herdr_bin" agent send-keys "$to" enter >/dev/null 2>&1 || true
  if "$herdr_bin" agent wait "$to" --until working --until "done" --until blocked --timeout 5000 >/dev/null 2>&1; then
    mark_pending
    echo "sent to '$to'; recipient reacted after enter nudge"
    exit 0
  fi
  echo "wake failed: '$to' did not react within 5s (agent_prompt_stalled); body may sit unsubmitted in its input box" >&2
  exit 6
fi
if printf '%s' "$err" | grep -qi 'timeout'; then
  # 宛先がすでに working の場合もここに来る。本文は届いておりキューで処理されるため
  # 返信待ちマーカーは残す (ターン完了時に relay が拾う)
  mark_pending
  echo "sent to '$to' but no start-of-work observed within 15s" >&2
  exit 7
fi

echo "send failed: $err" >&2
exit 1
