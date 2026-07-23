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

notify() { # notify <title> <body>
  "$herdr_bin" notification show "$1" --body "$2" --sound request >/dev/null 2>&1 || true
}

# blocked は人間の承認が要る状態なので、agent に伝えるのでなく人間へ toast を出す。
# pending は保持し、承認後のターン完了で通常の中継が走る
if [ "$event_status" = "blocked" ]; then
  notify "agentchat: $name blocked" "$name が承認/入力待ちです。herdr agent read $name --source visible で確認"
  exit 0
fi

recent=$("$herdr_bin" agent read "$name" --source recent-unwrapped --lines 80 2>/dev/null | tail -c 3500 || true)
rm -f "$pending"
"$herdr_bin" pane report-metadata "$event_pane" --source thkt.agentchat --clear-title >/dev/null 2>&1 || true

# 返信先が agent なら send で中継、実在しない宛先 (human など) なら人間へ toast。
# leader を介さない直接依頼 (human -> coder) もこれで完結する
if "$herdr_bin" agent get "$dest" >/dev/null 2>&1; then
  bash actions/send.sh "$dest" "[auto-relay] $name のターンが完了しました。send での報告が別途届いていればそちらを優先してください。$name の直近出力:
$recent" >/dev/null 2>&1 || true
else
  notify "agentchat: $name done" "$name のターンが完了しました。herdr agent read $name で出力を確認"
fi
