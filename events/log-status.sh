#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../actions/env.sh
. "$plugin_root/actions/env.sh"

mkdir -p "$state_dir"

printf '%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "${HERDR_PLUGIN_EVENT_JSON:-no-event-json}" \
  >> "$state_dir/status-events.log"
