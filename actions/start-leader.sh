#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh
load_conf

if agent_exists leader; then
  echo "leader already running on $(agent_pane leader)"
  exit 0
fi

base=$(focused_pane)
[ -n "$base" ] || { echo "no focused pane in invocation context; run via 'herdr plugin action invoke'" >&2; exit 1; }

# 起動時規約を読んでいない採用セッションには、verify-link で役割を伝える。
if kind=$("$herdr_bin" agent get "$base" 2>/dev/null | json_field agent) && [ "$kind" = "claude" ]; then
  "$herdr_bin" agent rename "$base" leader >/dev/null
  "$herdr_bin" pane rename "$base" leader >/dev/null 2>&1 || true
  echo "leader adopted on $base (existing claude); run verify-link to brief it"
  exit 0
fi

# shellcheck disable=SC2086
start_agent_in_split leader claude "$base" $LEADER_ARGS
