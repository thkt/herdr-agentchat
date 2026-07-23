#!/usr/bin/env bash
# leader の「委譲は send.sh で行う」だけは中継機構で代替できない
# (send.sh を経由しないと pending マーカーが書かれず relay が関与できない)。
# coder 側の返信手段は relay が機械的に肩代わりするため注入しない。
#
# exit codes:
#   0  coder ダイアログ解消 + leader ブリーフィング送信・着手確認
#   1  agent 不在、leader 入力待ち timeout、またはブリーフィング送信失敗
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh

for name in leader coder; do
  agent_exists "$name" || { echo "$name is not running; run start-$name first" >&2; exit 1; }
done

send_path="$(pwd)/send.sh"

leader_briefing=$(cat <<EOF
[役割設定] あなたは leader です。実装は自分で行わず、同じ workspace の coder (codex) に委譲します。coder への連絡は必ず次のコマンドで行うこと: bash $send_path --reply-to leader coder "<本文>"。coder のターンが完了すると、その出力は [auto-relay] として自動であなたに届きます。報告が来ないときは herdr agent read coder で状況を確認します。理解したら 'understood' とだけ返答してください。
EOF
)

clear_first_run_dialogs coder
echo "coder: dialogs cleared"

clear_first_run_dialogs leader
if ! "$herdr_bin" agent wait leader --until idle --until "done" --timeout 120000 >/dev/null 2>&1; then
  echo "leader did not become ready for briefing within 120s" >&2
  exit 1
fi
if bash ./send.sh leader "$leader_briefing" >/dev/null 2>&1; then
  if ! "$herdr_bin" agent wait leader --timeout 120000 >/dev/null 2>&1; then
    echo "warn: leader briefing started but did not settle within 120s" >&2
  fi
  clear_first_run_dialogs leader
  # ブリーフィングへの応答は中継不要なので返信待ちマーカーを掃除する
  rm -f "$state_dir/pending-reply-leader" 2>/dev/null || true
  echo "leader: briefing sent; start confirmed"
  echo "setup ready: coder available, leader briefing started"
  exit 0
fi

echo "leader: briefing failed (state: $("$herdr_bin" agent get leader 2>/dev/null | json_field agent_status))" >&2
exit 1
