# codex.nvim

<!-- 操作イメージは主要な操作の流れが一目で分かる短い録画を掲載する -->
![操作イメージ](codex.nvim_light.gif)

A Neovim IDE integration for Codex. It follows the original architecture of the Claude Code integration and adapts it for Codex.
will continue to be improved.

## Highlights

- Pure Lua implementation with minimal dependencies
- Built-in WebSocket MCP (Model Context Protocol)
- Safe in-editor Codex terminal control
- Send selections or files as @ mentions to Codex
- Accept or reject diffs inside Neovim

## Installation (lazy.nvim example)

```lua
{
  dir = "/home/dev_local/dev_plugin/codex.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = true,
  keys = {
    { "<leader>cc", "<cmd>Codex<cr>", desc = "Codex: Toggle" },
    { "<leader>cf", "<cmd>CodexFocus<cr>", desc = "Codex: Focus" },
    { "<leader>cs", "<cmd>CodexSend<cr>", mode = "v", desc = "Codex: Send selection" },
    {
      "<leader>cs",
      "<cmd>CodexTreeAdd<cr>",
      desc = "Codex: Add file",
      ft = { "neo-tree", "oil" },
    },
  },
}
```

## Requirements

- Neovim 0.8+
- Codex CLI installed
- `folke/snacks.nvim` recommended for terminal UX

## Usage

1. Open the Codex terminal with `:Codex`
2. Select text in visual mode and run `:CodexSend`
3. From tree views (neo-tree / oil.nvim), use `:CodexTreeAdd`
Only neo-tree and oil.nvim are supported tree views.

## Specify Codex CLI path

```lua
require("codex").setup({
  terminal_cmd = "/path/to/codex",
})
```

## Add environment variables

```lua
require("codex").setup({
  env = {
    ENABLE_IDE_INTEGRATION = "true",
    CODEX_CODE_SSE_PORT = "12345",
  },
})
```
## Status indicator (busy/wait)

正確な動作中/待機表示のために、Codex CLI の通知設定は必須です。通知設定が無い場合は応答中の判定ができないため、動作中/待機の表示は保証されません。
Codex.nvim 側で通知ファイルのパスと環境変数を揃え、Codex CLI が通知 JSON を追記するようにしてください。
```lua
require("codex").setup({
  env = {
    CODEX_NVIM_NOTIFY_PATH = "/tmp/codex.nvim/notify.jsonl",
  },
  status_indicator = {
    cli_notify_path = "/tmp/codex.nvim/notify.jsonl",
    -- 応答処理中の表示を維持する最大時間（ミリ秒）
    turn_active_timeout_ms = 300000,
    -- 応答停止後に動作中表示を解除する猶予時間（ミリ秒）
    turn_idle_grace_ms = 2000,
    -- 実行中リクエストが古い場合に動作中表示を解除する猶予時間（ミリ秒）
    inflight_timeout_ms = 300000,
  },
})
```

Codex CLI config example:

```
notify = ["sh", "/path/to/codex.nvim/scripts/codex_notify.sh"]
```

通知イベントは現時点で `agent-turn-complete` のみ対応のため、応答開始は入力検知で補完します。

外部ターミナルを使う場合、NeovimからCodex CLIの出力を観測できないため、動作中表示は通知イベントだけに依存します。
通知設定が無い場合、応答中フラグは使わず入出力の猶予時間のみで判定します。

When a diff is pending (user choice), the indicator shows ◐.


## Thanks

This plugin is heavily inspired by the design and implementation of `claudecode.nvim`. The repository referenced is https://github.com/coder/claudecode.nvim. Many thanks to its maintainers.

---

# codex.nvim [japanese]
Codex を Neovim から扱うための IDE 統合プラグインです。Claude Code 用に作られた設計を踏襲しつつ、Codex 用に調整しています。
今後も改善を続ける予定です。

## 特徴

- Lua のみで実装した軽量な統合
- MCP (Model Context Protocol) の WebSocket 実装を内蔵
- Codex のターミナルを Neovim 内で安全に制御
- 選択範囲やファイルを @ メンションとして Codex に送信
- 差分プレビューの受け入れ / 拒否を Neovim 内で完結

## インストール（lazy.nvim の例）

<!-- 既定のキーマップ例は動作確認済みのものだけ記載しています。 -->
```lua
{
  dir = "/home/dev_local/dev_plugin/codex.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = true,
  keys = {
    { "<leader>cc", "<cmd>Codex<cr>", desc = "Codex: Toggle" },
    { "<leader>cf", "<cmd>CodexFocus<cr>", desc = "Codex: Focus" },
    { "<leader>cs", "<cmd>CodexSend<cr>", mode = "v", desc = "Codex: 選択範囲を送信" },
    {
      "<leader>cs",
      "<cmd>CodexTreeAdd<cr>",
      desc = "Codex: ファイルを追加",
      ft = { "neo-tree", "oil" },
    },
  },
}
```
neo-tree のポップアップ（filetype: neo-tree-popup）にも同じキーマップが適用されます。oil.nvim（filetype: oil）でも同様に使えます。

## 要件

- Neovim 0.8 以降
- Codex CLI がインストール済みであること
- 端末を快適に扱うために `folke/snacks.nvim` を推奨

## 使い方

1. `:Codex` で Codex ターミナルを開きます
2. 選択範囲をビジュアルモードで選び、`:CodexSend` で送信します
3. ツリー表示（neo-tree / oil.nvim）では `:CodexTreeAdd` が使えます
neo-tree と oil.nvim のみ対応しています。

## ターミナルから前のウィンドウへ戻るキー

既定は `Ctrl-]` で前のウィンドウへ戻ります。macOS で `Cmd-]` にしたい場合は `terminal.unfocus_key` を設定してください。

```lua
require("codex").setup({
  terminal = {
    unfocus_key = "<D-]>", -- Cmd-] でフォーカスを戻す
  },
})
```

## Issue と PR について

Issue や PR 歓迎です。バグ報告や改善提案を気軽にお寄せください。

## Codex CLI のパスを明示する場合

Codex CLI が通常のパスに無い場合は `terminal_cmd` を指定してください。

```lua
require("codex").setup({
  terminal_cmd = "/path/to/codex",
})
```

## Codex の環境変数を調整する場合

Codex CLI 起動時に渡す環境変数を追加できます。

```lua
require("codex").setup({
  env = {
    ENABLE_IDE_INTEGRATION = "true",
    CODEX_CODE_SSE_PORT = "12345",
  },
})
```

## 状態アイコン（動作中/選択待ち）

動作中や選択待ちを正しく表示するには、Codex CLI の notify を使って完了イベントを通知する必要があります。プラグインに通知ファイルのパスと環境変数を設定し、Codex CLI 側でそのファイルへ追記する設定を行ってください。

```lua
require("codex").setup({
  env = {
    CODEX_NVIM_NOTIFY_PATH = "/tmp/codex.nvim/notify.jsonl",
  },
  status_indicator = {
    cli_notify_path = "/tmp/codex.nvim/notify.jsonl",
  },
})
```

Codex CLI の設定例:

```
notify = ["sh", "/path/to/codex.nvim/scripts/codex_notify.sh"]
```

通知イベントは現時点で `agent-turn-complete` のみ対応のため、応答開始は入力検知で補完します。

差分の選択待ち（承認/拒否の保留）がある場合は ◐ を表示します。


## 感謝

本プラグインは `claudecode.nvim` の設計と実装に大きく助けられました。参考にしたリポジトリは https://github.com/coder/claudecode.nvim です。開発者の皆さまに感謝します。
