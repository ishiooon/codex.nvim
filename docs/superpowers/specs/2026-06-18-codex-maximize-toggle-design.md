# Codex 画面サイズ切替設計

## 目的

Codex ターミナル画面を `<leader>cm` で通常の分割表示と大きなモーダル表示に切り替えられるようにします。既存の `<leader>cc` と `<leader>cf` の操作感を保ち、Codex ターミナルのプロセスとバッファは保持したまま表示先だけを移し替えます。

## 採用方針

`CodexMaximizeToggle` コマンドを追加し、既定キーマップ `<leader>cm` から呼び出します。表示状態は `codex.terminal` が管理し、各プロバイダは同じターミナルバッファを通常分割または 96% サイズのフローティングウィンドウへ表示します。未起動または非表示の場合は Codex ターミナルを開き、モーダル表示で見せます。

## 変更対象

- `lua/codex/config.lua`: 既定キーマップに `<leader>cm` を追加します。
- `lua/codex/init.lua`: `CodexMaximizeToggle` コマンドを追加します。
- `lua/codex/terminal.lua`: 通常表示とモーダル表示の状態切替を管理します。
- `lua/codex/terminal/size.lua`: 96% モーダル表示のサイズと位置を計算します。
- `lua/codex/terminal/window.lua`: 既存バッファを split または float に表示する処理を集約します。
- `lua/codex/terminal/native.lua`: 既存ターミナルバッファをモーダル表示へ移し替えます。
- `lua/codex/terminal/snacks.lua`: Snacks のターミナルバッファをモーダル表示へ移し替えます。
- `lua/codex/terminal/none.lua`: ターミナル無効時は何もしない関数を追加します。

## 振る舞い

1. `<leader>cm` を押すと `:CodexMaximizeToggle` が実行されます。
2. 通常分割表示の Codex ターミナルは 96% 幅・96% 高さのモーダル表示になります。
3. モーダル表示の Codex ターミナルは通常分割表示に戻ります。
4. ターミナルが非表示または未起動の場合は、モーダル表示で表示します。
5. Codex ターミナルのプロセス、バッファ、入力内容は保持します。

## テスト方針

実装前に振る舞いテストを追加し、失敗を確認します。主にキーマップ登録、コマンド登録、ターミナルラッパーからプロバイダへの委譲、96% サイズ計算、ネイティブプロバイダと Snacks プロバイダのモーダル表示を検証します。テストは `scripts/test.sh --env=localdev` で実行します。

## 制約

ユーザー指示により、ステージ、コミット、プッシュは行いません。設計文書と計画文書は作成しますが、コミットは実行しません。
