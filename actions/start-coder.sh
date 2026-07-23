#!/usr/bin/env bash
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

# shellcheck disable=SC2086
start_agent_in_split coder codex "$base" $CODER_ARGS
