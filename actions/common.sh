# setup 系 action の共有関数。単体実行はしない (各 action から source する)。

herdr_bin="${HERDR_BIN_PATH:-herdr}"

# 起動引数の既定値。HERDR_PLUGIN_CONFIG_DIR/agentchat.conf で上書きできる。
# leader は人間の権限選択を尊重して既定は素の claude、coder は承認なし運用が既定
# (network 許可がないとテスト用 listen が sandbox に拒否されるため付与する)。
LEADER_ARGS=""
CODER_ARGS="-a never -s workspace-write -c sandbox_workspace_write.network_access=true"

load_conf() {
  conf="${HERDR_PLUGIN_CONFIG_DIR:-}/agentchat.conf"
  # shellcheck disable=SC1090
  [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "$conf" ] && . "$conf"
  return 0
}

json_field() { # json_field <key> : stdin の JSON から最初の文字列値を取り出す
  grep -oE "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

agent_exists() { # agent_exists <name>
  "$herdr_bin" agent get "$1" >/dev/null 2>&1
}

agent_pane() { # agent_pane <name>
  "$herdr_bin" agent get "$1" 2>/dev/null | json_field pane_id
}

focused_pane() {
  if [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
    printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | json_field focused_pane_id
  fi
}

split_from() { # split_from <base_pane> : 右に分割して新ペイン id を返す
  "$herdr_bin" pane split "$1" --direction right | json_field pane_id
}

start_agent() { # start_agent <name> <kind> <pane> [args...]
  name="$1" kind="$2" pane="$3"
  shift 3
  # ペインのシェルが立ち上がるまで agent_pane_busy になりうるので短くリトライする
  for _ in 1 2 3 4 5; do
    if out=$("$herdr_bin" agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 -- "$@" 2>&1); then
      return 0
    fi
    printf '%s' "$out" | grep -q agent_pane_busy || { printf '%s\n' "$out" >&2; return 1; }
    sleep 1
  done
  printf '%s\n' "$out" >&2
  return 1
}

# codex の初回フック信頼ダイアログを片付ける。表示中に届いた send は本文ごと
# 吸われるため、会話開始前にここで解消しておく (M1/M2 実機で確認した挙動)。
clear_first_run_dialogs() { # clear_first_run_dialogs <name>
  for _ in 1 2 3; do
    screen=$("$herdr_bin" agent read "$1" --source visible 2>/dev/null || true)
    if printf '%s' "$screen" | grep -q 'Press t to trust all'; then
      "$herdr_bin" agent send-keys "$1" t >/dev/null
      sleep 1
      continue
    fi
    if printf '%s' "$screen" | grep -q 'Press enter to view hooks; esc to close'; then
      "$herdr_bin" agent send-keys "$1" esc >/dev/null
      sleep 1
      continue
    fi
    return 0
  done
  return 0
}
