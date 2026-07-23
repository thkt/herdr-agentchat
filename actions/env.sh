# shellcheck shell=bash
# shellcheck disable=SC2034

herdr_bin="${HERDR_BIN_PATH:-herdr}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/thkt.agentchat}"

json_field() { # json_field <key>: stdin の JSON から最初の文字列値を取り出す
  grep -oE "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}
