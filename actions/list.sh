#!/usr/bin/env bash
# T1 疎通確認: herdr CLI をプラグイン経由で呼べることを確かめるだけの action。
set -euo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
"$herdr_bin" agent list
