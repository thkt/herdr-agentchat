#!/usr/bin/env bash
# T2 観測専用フック: agent 状態遷移をログに残す。ここから prompt は撃たない (暴走防止の設計)。
set -euo pipefail

state_dir="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr-agentchat}"
mkdir -p "$state_dir"

printf '%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "${HERDR_PLUGIN_EVENT_JSON:-no-event-json}" \
  >> "$state_dir/status-events.log"
