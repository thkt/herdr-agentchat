#!/usr/bin/env bash
# 完了自動中継。send.sh が書いた返信待ちマーカー (pending-reply-<name>) がある
# エージェントのターン完了 (done / idle) を検知したら、そのペインの直近出力を
# 返信先へ中継してマーカーを消す。受信者が send での報告を怠っても、herdr の
# 状態遷移から機械的に報告が届く。中継は 1 送信につき最大 1 回で、中継自体は
# マーカーを書かないため起こし合いのループにはならない。
# blocked 遷移は承認待ちの通知だけ送り、マーカーは保持する。
set -euo pipefail
cd "$(dirname "$0")/.."

herdr_bin="${HERDR_BIN_PATH:-herdr}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/thkt.agentchat}"
ev="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -n "$ev" ] || exit 0

json_field() { grep -oE "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }

event_status=$(printf '%s' "$ev" | json_field agent_status)
event_pane=$(printf '%s' "$ev" | json_field pane_id)
case "$event_status" in done | idle | blocked) ;; *) exit 0 ;; esac
[ -n "$event_pane" ] || exit 0

# pending マーカーを持つ名前付き agent のペインか判定する
name=""
for candidate in leader coder; do
  [ -f "$state_dir/pending-reply-$candidate" ] || continue
  pane=$("$herdr_bin" agent get "$candidate" 2>/dev/null | json_field pane_id)
  [ "$pane" = "$event_pane" ] && name="$candidate" && break
done
[ -n "$name" ] || exit 0

pending="$state_dir/pending-reply-$name"
dest=$(head -1 "$pending" 2>/dev/null || true)
[ -n "$dest" ] || { rm -f "$pending"; exit 0; }

if [ "$event_status" = "blocked" ]; then
  bash actions/send.sh "$dest" "[auto-relay] $name が承認/入力待ち (blocked) です。herdr agent read $name --source visible で内容を確認してください。" >/dev/null 2>&1 || true
  exit 0
fi

recent=$("$herdr_bin" agent read "$name" --source recent-unwrapped --lines 80 2>/dev/null | tail -c 3500 || true)
rm -f "$pending"
bash actions/send.sh "$dest" "[auto-relay] $name のターンが完了しました。send での報告が別途届いていればそちらを優先してください。$name の直近出力:
$recent" >/dev/null 2>&1 || true
