# herdr-agentchat

herdr 上で leader (Claude Code) と coder (Codex) が、人間の伝書鳩なしに会話しながら実装を進めるためのプラグイン。

中核は send 一体型の設計。`actions/send.sh` が宛先への本文投入と「相手を起こす」を
`herdr agent prompt --wait` の一手で行い、宛先の着手までをその場で見届ける。
そのため「未応答があるかの判定」や「起こす係」が不要になる。

## 構成

```
herdr-agentchat/
  herdr-plugin.toml     # マニフェスト
  actions/
    list.sh             # 疎通確認用 (agent list を返すだけ)
    send.sh             # 送信 + 起こす (中核)
  events/
    log-status.sh       # agent 状態遷移の観測ログ (観測専用、prompt は撃たない)
  templates/
    CLAUDE.md           # 2 体運用規約 (AGENTS.md はこれへのシンボリックリンク)
```

## 前提

- macOS、herdr 0.7.x
- Claude Code / Codex CLI がインストール・ログイン済み

## セットアップ

1. プラグインを登録する。

   ```bash
   herdr plugin install thkt/herdr-agentchat
   herdr plugin list
   ```

   ローカル開発時は clone したディレクトリを `herdr plugin link /path/to/herdr-agentchat` で登録する。
   更新の取り込みは `herdr plugin install` の再実行 (v1 に update コマンドはない)。

2. プロジェクトディレクトリで herdr を起動し、`claude` を起動してペイン名を `leader` にする。

   ```bash
   herdr agent rename <pane_id> leader
   ```

3. leader に依頼する:「右にペインを作って codex を起動し、agent 名を coder にして」。
   leader が `herdr pane split --direction right` → codex 起動 → `herdr agent rename` を行う。

4. 運用規約を配る。

   ```bash
   cp templates/CLAUDE.md <project>/CLAUDE.md
   ln -s CLAUDE.md <project>/AGENTS.md
   ```

5. 各エージェントの初回ダイアログ (codex のフック信頼確認など) を人間が先に片付ける。
   ダイアログ表示中に届いた send の本文はダイアログに吸われて消え、しかも herdr が
   working と分類するため送信側には成功が返る (M1 実機で確認)。会話を始める前に、
   各ペインで短い疎通メッセージを 1 往復させて、素の入力待ちであることを確認する。

## 送信

```bash
bash actions/send.sh coder "POST /todos を実装して。完了したら send で報告して。"
```

exit code の意味は `actions/send.sh` 冒頭のコメントと `templates/CLAUDE.md` を参照。

## 暴走防止

- 自発的な起こしはしない。起こしは常に send (明示的な送信) が起点。状態監視 (`events/log-status.sh`) は観測専用。
- クールダウン: 同一宛先へ同一内容を 30 秒以内に再送しない。
- 往復上限: 同一宛先へ 10 分間に 30 送信を超えたら停止し、人間への報告を促す。

## 受け入れテスト台本 (M1)

実機で上から順に実行し、すべて満たせば合格。

1. セットアップ手順で `leader` / `coder` の 2 ペインを立ち上げる。
2. `herdr plugin link ./` → `herdr plugin list` で有効を確認する。
3. leader にタスクを依頼する。
   例:「Node.js と Express で、メモリ保存の TODO API を作りたい。POST /todos、GET /todos、
   PATCH /todos/:id/complete の 3 つ。npm test も付けて。計画を立てて、実装は send で
   coder に依頼して、完成まで面倒を見て。」
4. 自動着手: leader の `send coder "..."` で、idle の coder が人手なしに working になる。
5. 往復: coder が `send leader "..."` で質問し、leader の回答で再開する。
6. 報告: coder の完了報告を leader が受け、人間に報告する。
7. 暴走なし: 往復が上限内で収束し、無限に起こし合っていない。
8. (該当時) coder の応答が `herdr agent read <名前>` で読めない場面が出たら、
   `--source visible` で読む。それでも読めなければ「応答を Markdown で一時ファイルに
   書き、パスだけ返す」フォールバックに切り替える。

## 実機検証で確認した注意点 (herdr 0.7.5, M1 テスト)

- `agent start` 直後の send は、claude の初期化 (SessionStart hook 実行中) に本文ごと消えることがある。
  最初の送信の前に短い疎通メッセージを 1 往復させると安全になる。
- `agent_prompt_stalled` (exit 6) は「未達」を意味しない。本文は宛先の入力欄に投入済みで、宛先の UI 状態
  により Enter だけが呑まれた場合がある。そのため send.sh は stalled 時に Enter を追い打ちして送信を
  完成させる。同一内容の再送は二重投入になるため行わない。
- codex の承認 UI (コマンド実行確認) は herdr が blocked と検知し、send.sh の blocked ガードが機能する。
  承認は人間が `herdr agent send-keys coder <key>` で行う。承認なし運用にするなら
  `codex -a never -s workspace-write -c sandbox_workspace_write.network_access=true` で起動する
  (network 許可がないと supertest 等のテスト用 listen が sandbox に拒否される)。
- exit 7 (着手観測タイムアウト) は宛先がすでに working のときにも出る。この場合、本文は届いており
  宛先のキューで処理される。`herdr agent get <名前>` で working を確認できたら再送しない。
- sandbox 下の送信者 (codex workspace-write 等) は状態ディレクトリに書けないことがある。send.sh は
  警告を出してガード記録なしで送信を続行する。ガードを生かすには `HERDR_PLUGIN_STATE_DIR` に
  書き込み可能なパスを指定して呼び出す。

## 非目標

会話履歴の完全な永続化、ペイン喪失後の文脈復元、サイドバー状態表示、3 体以上の汎用構成、
放置運転 (夜間仕込み) はスコープ外。
