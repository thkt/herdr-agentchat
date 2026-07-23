#!/usr/bin/env bash
# 途中失敗時は rollback しないため、再実行は既存 agent が揃った正常系に限る。
set -euo pipefail
cd "$(dirname "$0")"

bash ./start-leader.sh
bash ./start-coder.sh
bash ./verify-link.sh
