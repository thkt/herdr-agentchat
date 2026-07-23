#!/usr/bin/env bash
# send.sh <to-agent-name> <body>
#
# 送信と「相手を起こす」を一手で行う (設計 4.1)。
# 宛先へ agent prompt --wait で本文を投入し、宛先が着手 (working) するか
# 決着 (done / blocked) するかをその場で見届けて結果を返す。
#
# exit codes:
#   0  送信し、宛先の着手または決着を観測した
#   3  クールダウン抑止 (同一宛先へ同一内容の連投)
#   4  往復上限抑止 (ループの疑い)
#   5  宛先が blocked (承認 UI へ文字を流し込まないためのガード)
#   6  宛先を起こせなかった (agent_prompt_stalled)
#   7  送信は通ったが着手を観測できないままタイムアウト
#   2  usage error / 宛先が見つからない
set -euo pipefail

usage() {
  echo "usage: send.sh <to-agent-name> <body>" >&2
  exit 2
}
[ $# -eq 2 ] || usage
to="$1"
body="$2"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr-agentchat}"
mkdir -p "$state_dir"

# 暴走防止パラメータ (設計 4.2)
cooldown_secs=30    # 同一宛先・同一内容の再送を抑止する秒数
max_sends=30        # window 内の同一宛先への送信上限 (往復上限の保険)
window_secs=600

now=$(date +%s)
body_hash=$(printf '%s\n%s' "$to" "$body" | shasum -a 256 | cut -d' ' -f1)

# クールダウン: 直前と同一内容の連投を抑止
last_file="$state_dir/last-send-$to"
if [ -f "$last_file" ]; then
  read -r last_ts last_hash < "$last_file" || true
  if [ "${last_hash:-}" = "$body_hash" ] && [ $((now - ${last_ts:-0})) -lt $cooldown_secs ]; then
    echo "cooldown: identical message to '$to' within ${cooldown_secs}s; not sent" >&2
    exit 3
  fi
fi

# 往復上限: window 内の送信回数 (タスク境界を持たないため rolling window で代用)
count_file="$state_dir/sends-$to.log"
if [ -f "$count_file" ]; then
  recent=$(awk -v cutoff=$((now - window_secs)) '$1 >= cutoff' "$count_file" | wc -l | tr -d ' ')
  if [ "$recent" -ge $max_sends ]; then
    echo "depth limit: $recent sends to '$to' in the last $((window_secs / 60))min; refusing to prevent a wake loop" >&2
    exit 4
  fi
fi

# blocked ガード: 承認・質問 UI が出ているペインには送らない
agent_info=$("$herdr_bin" agent get "$to" 2>&1) || {
  echo "unknown agent '$to': $agent_info" >&2
  exit 2
}
if printf '%s' "$agent_info" | grep -qE '"agent_status"[[:space:]]*:[[:space:]]*"blocked"'; then
  echo "guard: '$to' is blocked (approval/question UI); resolve it first, message not sent" >&2
  exit 5
fi

# 送信記録 (stalled の連打も抑止対象にするため、結果を問わず先に記録する)
printf '%s %s\n' "$now" "$body_hash" > "$last_file"
printf '%s\n' "$now" >> "$count_file"

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
  post_state=$("$herdr_bin" agent get "$to" 2>/dev/null | grep -oE '"agent_status"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 || true)
  echo "sent to '$to'; recipient reacted (${post_state:-agent_status unavailable})"
  exit 0
fi

if printf '%s' "$err" | grep -q 'agent_prompt_stalled'; then
  echo "wake failed: '$to' did not react within 5s (agent_prompt_stalled)" >&2
  exit 6
fi
if printf '%s' "$err" | grep -qi 'timeout'; then
  echo "sent to '$to' but no start-of-work observed within 15s" >&2
  exit 7
fi

echo "send failed: $err" >&2
exit 1
