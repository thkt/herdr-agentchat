#!/usr/bin/env bash
# marker gating で中継を1回に制限し、blocked は人間の承認後まで保持する。
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=../actions/env.sh
. actions/env.sh

ev="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -n "$ev" ] || exit 0

event_status=$(printf '%s' "$ev" | json_field agent_status)
event_pane=$(printf '%s' "$ev" | json_field pane_id)
case "$event_status" in done | idle | blocked) ;; *) exit 0 ;; esac
[ -n "$event_pane" ] || exit 0

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

# 実在しない返信先は、人間から直接依頼した turn を閉じるため toast にする。
if "$herdr_bin" agent get "$dest" >/dev/null 2>&1; then
  bash actions/send.sh "$dest" "[auto-relay] $name のターンが完了しました。send での報告が別途届いていればそちらを優先してください。$name の直近出力:
$recent" >/dev/null 2>&1 || true
else
  notify "agentchat: $name done" "$name のターンが完了しました。herdr agent read $name で出力を確認"
fi
