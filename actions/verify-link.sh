#!/usr/bin/env bash
# 両者連携の完了確認。初回ダイアログを片付けてから疎通 1 往復を行い、
# send が素の入力待ちに届く状態であることを保証する。
#
# exit codes:
#   0  leader / coder とも疎通完了 (連携可能)
#   1  agent 不在または疎通失敗
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh

for name in leader coder; do
  agent_exists "$name" || { echo "$name is not running; run start-$name first" >&2; exit 1; }
done

fail=0
for name in leader coder; do
  clear_first_run_dialogs "$name"

  if bash ./send.sh "$name" "疎通確認です。'pong' とだけ返答してください。" >/dev/null 2>&1; then
    # 着手は観測済み。応答の決着まで待って素の入力待ちに戻す
    "$herdr_bin" agent wait "$name" --timeout 120000 >/dev/null 2>&1 || true
    clear_first_run_dialogs "$name"
    echo "$name: ok"
  else
    echo "$name: ping failed (state: $("$herdr_bin" agent get "$name" 2>/dev/null | json_field agent_status))" >&2
    fail=1
  fi
done

[ $fail -eq 0 ] && echo "link verified: leader <-> coder ready"
exit $fail
