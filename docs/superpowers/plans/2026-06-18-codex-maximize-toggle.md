# Codex Maximize Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `<leader>cm` で Codex ターミナルの通常分割表示と 96% モーダル表示を切り替えられるようにする。

**Architecture:** `codex.config` が既定キーマップを提供し、`codex.init` が `CodexMaximizeToggle` コマンドを登録する。表示状態とプロバイダ呼び出しは `codex.terminal` に集約し、各プロバイダは既存ターミナルバッファを通常 split または 96% float に移し替える。

**Tech Stack:** Lua, Neovim API, Busted, 既存テストモック

---

### Task 1: キーマップとコマンドの失敗テスト

**Files:**
- Modify: `tests/unit/keymaps_spec.lua`
- Modify: `tests/unit/init_spec.lua`

- [ ] **Step 1: Write the failing keymap test**

```lua
it("Codex画面サイズ切替のキーマップを登録する", function()
  keymaps.setup(config.defaults.keymaps)

  expect(vim._keymaps.n["<leader>cm"].rhs).to_be("<cmd>CodexMaximizeToggle<cr>")
  expect(vim._keymaps.n["<leader>cm"].opts.desc).to_be("Codex: Toggle modal")
end)
```

- [ ] **Step 2: Write the failing command test**

```lua
it("CodexMaximizeToggleコマンドからターミナルのサイズ切替を呼び出す", function()
  local codex = require("codex")
  codex.setup({ auto_start = false })

  local command_handler
  for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
    if call.vals[1] == "CodexMaximizeToggle" then
      command_handler = call.vals[2]
      break
    end
  end

  assert.is_function(command_handler, "CodexMaximizeToggle command should be registered")
  command_handler({})
  assert(#mock_terminal.maximize_toggle.calls > 0, "terminal.maximize_toggle was not called")
end)
```

- [ ] **Step 3: Run tests to verify RED**

Run: `timeout 120 ./scripts/test.sh --env=localdev`

Expected: FAIL because `<leader>cm` and `CodexMaximizeToggle` are not implemented.

### Task 2: ターミナルラッパーのモーダル切替テスト

**Files:**
- Modify: `tests/unit/terminal_spec.lua`
- Create: `tests/unit/terminal/size_spec.lua`
- Modify: `tests/unit/native_terminal_toggle_spec.lua`
- Create: `tests/unit/snacks_terminal_maximize_spec.lua`

- [ ] **Step 1: Write wrapper behavior tests**

```lua
it("通常表示から96パーセントのモーダル表示へ切り替える", function()
  terminal_wrapper.setup({ split_width_percentage = 0.3 })
  terminal_wrapper.maximize_toggle()

  mock_snacks_provider.maximize_toggle:was_called(1)
  local config_arg = mock_snacks_provider.maximize_toggle:get_call(1).refs[3]
  assert.is_true(config_arg.is_maximized)
  assert.are.equal(0.96, config_arg.maximized_width_percentage)
  assert.are.equal(0.96, config_arg.maximized_height_percentage)
end)

it("モーダル表示から通常表示へ切り替える", function()
  terminal_wrapper.setup({ split_width_percentage = 0.3 })
  terminal_wrapper.maximize_toggle()
  terminal_wrapper.maximize_toggle()

  local config_arg = mock_snacks_provider.maximize_toggle:get_call(2).refs[3]
  assert.is_false(config_arg.is_maximized)
  assert.are.equal(0.3, config_arg.split_width_percentage)
end)
```

- [ ] **Step 2: Run tests to verify RED**

Run: `timeout 120 ./scripts/test.sh --env=localdev`

Expected: FAIL because modal state, geometry calculation, and provider float display are not implemented.

### Task 3: 最小実装

**Files:**
- Modify: `lua/codex/config.lua`
- Modify: `lua/codex/init.lua`
- Modify: `lua/codex/terminal.lua`
- Modify: `lua/codex/terminal/size.lua`
- Create: `lua/codex/terminal/window.lua`
- Modify: `lua/codex/terminal/native.lua`
- Modify: `lua/codex/terminal/snacks.lua`
- Modify: `lua/codex/terminal/none.lua`

- [ ] **Step 1: Add keymap**

Add `<leader>cm` to `M.defaults.keymaps.mappings`.

- [ ] **Step 2: Add command**

Add `CodexMaximizeToggle` in `M._create_commands()` and call `terminal.maximize_toggle()`.

- [ ] **Step 3: Add wrapper state**

Add `is_maximized` state passed through `M.maximize_toggle()`, with `maximized_width_percentage = 0.96` and `maximized_height_percentage = 0.96`.

- [ ] **Step 4: Add provider methods**

Add `maximize_toggle(cmd_string, env_table, effective_config)` to native, snacks, and none providers. Native and Snacks should reuse the existing terminal buffer and switch its window between split and float.

- [ ] **Step 5: Run tests to verify GREEN**

Run: `timeout 120 ./scripts/test.sh --env=localdev`

Expected: PASS.

### Task 4: 文書と最終検証

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README keymap examples**

Add `<leader>cm` to English and Japanese setup examples.

- [ ] **Step 2: Run full verification**

Run: `timeout 180 ./scripts/test.sh --env=localdev`

Expected: PASS.

- [ ] **Step 3: Do not commit**

Do not run `git add`, `git commit`, or `git push`. Report a commit message suggestion only.
