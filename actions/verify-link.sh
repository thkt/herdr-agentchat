#!/usr/bin/env bash
# 両者連携の完了確認。初回ダイアログを片付けたうえで、役割・返信手段を
# ブリーフィングとして各エージェントに注入し、応答まで見届ける。
# 規約ファイルの配置やプロンプトの書き方に依存せず、send プロトコルが
# 双方に届いた状態をセットアップの完了条件にする (leader が返信手段を
# 依頼文に書かず往復が途切れる incident が 2 回再発したための決定論化)。
#
# exit codes:
#   0  leader / coder ともブリーフィング完了 (連携可能)
#   1  agent 不在またはブリーフィング失敗
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh

for name in leader coder; do
  agent_exists "$name" || { echo "$name is not running; run start-$name first" >&2; exit 1; }
done

send_path="$(pwd)/send.sh"

briefing_for() { # briefing_for <name>
  case "$1" in
    leader) cat <<EOF
[役割設定] あなたは leader です。実装は自分で行わず、同じ workspace の coder (codex) に委譲します。coder への連絡は必ず次のコマンドで行うこと: bash $send_path --reply-to leader coder "<本文>"。--reply-to により返信手段が本文に自動で埋め込まれます。依頼文には「完了したら send で報告」と明記し、報告が来ないときは herdr agent read coder で状況を確認します。理解したら 'understood' とだけ返答してください。
EOF
      ;;
    coder) cat <<EOF
[役割設定] あなたは coder です。leader (claude) から send で指示が届きます。不明点の質問と完了報告は、ペイン出力で終わらせず必ず次のコマンドで送ること: bash $send_path --reply-to coder leader "<本文>"。理解したら 'understood' とだけ返答してください。
EOF
      ;;
  esac
}

fail=0
for name in leader coder; do
  clear_first_run_dialogs "$name"

  if bash ./send.sh "$name" "$(briefing_for "$name")" >/dev/null 2>&1; then
    # 着手は観測済み。応答の決着まで待って素の入力待ちに戻す
    "$herdr_bin" agent wait "$name" --timeout 120000 >/dev/null 2>&1 || true
    clear_first_run_dialogs "$name"
    echo "$name: briefed"
  else
    echo "$name: briefing failed (state: $("$herdr_bin" agent get "$name" 2>/dev/null | json_field agent_status))" >&2
    fail=1
  fi
done

[ $fail -eq 0 ] && echo "link verified: leader <-> coder ready"
exit $fail
