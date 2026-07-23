#!/usr/bin/env bash
# leader (claude) を決定論で用意する。既に居れば何もしない (冪等)。
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

pane=$(split_from "$base")
[ -n "$pane" ] || { echo "pane split failed" >&2; exit 1; }

# shellcheck disable=SC2086
start_agent leader claude "$pane" $LEADER_ARGS
# agent 名は宛先解決用で TUI に出ないため、pane label も揃えて可視化する
"$herdr_bin" pane rename "$pane" leader >/dev/null 2>&1 || true
echo "leader ready on $pane"
