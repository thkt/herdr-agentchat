#!/usr/bin/env bash
# coder (codex) を決定論で用意する。既に居れば何もしない (冪等)。
# leader ペインの右に作る。leader が居なければフォーカスペインから分割する。
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh
load_conf

if agent_exists coder; then
  echo "coder already running on $(agent_pane coder)"
  exit 0
fi

base=$(agent_pane leader)
[ -n "$base" ] || base=$(focused_pane)
[ -n "$base" ] || { echo "no leader pane and no focused pane; run start-leader first" >&2; exit 1; }

pane=$(split_from "$base")
[ -n "$pane" ] || { echo "pane split failed" >&2; exit 1; }

# shellcheck disable=SC2086
start_agent coder codex "$pane" $CODER_ARGS
echo "coder ready on $pane"
