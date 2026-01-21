# codex.nvim

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


## 感謝

本プラグインは `claudecode.nvim` の設計と実装に大きく助けられました。参考にしたリポジトリは https://github.com/coder/claudecode.nvim です。開発者の皆さまに感謝します。

---

# codex.nvim (English)

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


## Thanks

This plugin is heavily inspired by the design and implementation of `claudecode.nvim`. The repository referenced is https://github.com/coder/claudecode.nvim. Many thanks to its maintainers.
