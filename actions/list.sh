#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env.sh
. "$action_dir/env.sh"

"$herdr_bin" agent list
