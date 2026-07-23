#!/usr/bin/env bash
# 両者連携の完了確認。coder は初回ダイアログの解消のみ、leader には役割と
# send.sh の絶対パスをブリーフィングとして注入し、応答まで見届ける。
# leader の「委譲は send.sh で行う」だけは中継機構で代替できない
# (send.sh を経由しないと pending マーカーが書かれず relay が関与できない)。
# coder 側の返信手段は relay が機械的に肩代わりするため注入しない。
# leader ブリーフィングは claude 初期化直後に最初のメッセージが消える問題の
# 捨てメッセージも兼ねる。
#
# exit codes:
#   0  連携可能 (coder ダイアログ解消 + leader ブリーフィング完了)
#   1  agent 不在またはブリーフィング失敗
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
if bash ./send.sh leader "$leader_briefing" >/dev/null 2>&1; then
  # 着手は観測済み。応答の決着まで待って素の入力待ちに戻す
  "$herdr_bin" agent wait leader --timeout 120000 >/dev/null 2>&1 || true
  clear_first_run_dialogs leader
  # ブリーフィングへの応答は中継不要なので返信待ちマーカーを掃除する
  rm -f "$state_dir/pending-reply-leader" 2>/dev/null || true
  echo "leader: briefed"
  echo "link verified: leader <-> coder ready"
  exit 0
fi

echo "leader: briefing failed (state: $("$herdr_bin" agent get leader 2>/dev/null | json_field agent_status))" >&2
exit 1
