-- このファイルはCodexターミナル用バッファ設定の単体テストを行います。
describe("codex.terminal.buffer", function()
  local buffer
  local original_vim
  local mock_vim
  local buf_vars
  local buf_names
  local buf_valid
  local bo_store
  local spy

  before_each(function()
    original_vim = _G.vim
    spy = require("luassert.spy")
    buf_vars = {}
    buf_names = { [1] = "term://./codex --help" }
    buf_valid = { [1] = true }
    bo_store = {}

    mock_vim = {
      api = {
        nvim_buf_is_valid = function(bufnr)
          return buf_valid[bufnr] == true
        end,
        nvim_buf_get_name = function(bufnr)
          return buf_names[bufnr] or ""
        end,
        nvim_buf_set_name = spy.new(function(bufnr, name)
          buf_names[bufnr] = name
        end),
        nvim_buf_set_var = spy.new(function(bufnr, key, value)
          buf_vars[bufnr] = buf_vars[bufnr] or {}
          buf_vars[bufnr][key] = value
        end),
        nvim_buf_get_var = function(bufnr, key)
          if buf_vars[bufnr] and buf_vars[bufnr][key] ~= nil then
            return buf_vars[bufnr][key]
          end
          error("missing var")
        end,
      },
      keymap = {
        set = spy.new(function() end),
      },
      bo = setmetatable({}, {
        __index = function(_, bufnr)
          if not bo_store[bufnr] then
            bo_store[bufnr] = {}
          end
          return bo_store[bufnr]
        end,
      }),
    }

    _G.vim = mock_vim
    package.loaded["codex.terminal.buffer"] = nil
    buffer = require("codex.terminal.buffer")
  end)

  after_each(function()
    _G.vim = original_vim
  end)

  it("codex が含まれるバッファ名を Codex 用の表示名へ差し替える", function()
    buffer.mark_terminal_buffer(1)
    assert.is_false(mock_vim.bo[1].buflisted)
    assert.is_true(buf_vars[1].codex_terminal)

    local call_args = mock_vim.api.nvim_buf_set_name.calls[1].vals
    local new_name = call_args[2]
    assert.are.equal("󰆍 Codex", new_name)
    assert.are.equal("󰆍 Codex", buf_names[1])
  end)

  it("Codex ターミナルから移動するキーマップを設定する", function()
    buffer.mark_terminal_buffer(1)

    local call_args = mock_vim.keymap.set.calls[1].vals
    assert.are.equal("t", call_args[1])
    assert.are.equal("<C-]>", call_args[2])
    assert.are.equal("<C-\\><C-n><C-w>p", call_args[3])
    assert.are.equal(1, call_args[4].buffer)
    assert.is_true(call_args[4].silent)
    assert.is_true(call_args[4].noremap)
    assert.is_not_nil(call_args[4].desc)
  end)

  it("指定したキーでCodex ターミナルから移動できるようにする", function()
    -- 利用者が指定したキーマップが優先されることを確認する
    buffer.mark_terminal_buffer(1, { unfocus_key = "<D-w>" })

    local call_args = mock_vim.keymap.set.calls[1].vals
    assert.are.equal("t", call_args[1])
    assert.are.equal("<D-w>", call_args[2])
    assert.are.equal("<C-\\><C-n><C-w>p", call_args[3])
    assert.are.equal(1, call_args[4].buffer)
  end)

  it("unfocus_key が false の場合はキーマップを設定しない", function()
    buffer.mark_terminal_buffer(1, { unfocus_key = false })

    assert.spy(mock_vim.keymap.set).was_not_called()
  end)

  it("unfocus_mapping を指定した場合は移動コマンドに反映する", function()
    -- 利用者が指定した移動コマンドがそのまま使われることを確認する
    buffer.mark_terminal_buffer(1, { unfocus_mapping = "<C-\\><C-n><C-w>h" })

    local call_args = mock_vim.keymap.set.calls[1].vals
    assert.are.equal("<C-\\><C-n><C-w>h", call_args[3])
  end)

  it("バッファ変数で Codex ターミナル判定ができる", function()
    buffer.mark_terminal_buffer(1)
    assert.is_true(buffer.is_codex_terminal_buffer(1))
  end)

  it("変数が無い場合はバッファ名から判定できる", function()
    buf_names[2] = "term://./codex"
    buf_valid[2] = true
    assert.is_true(buffer.is_codex_terminal_buffer(2))
  end)
end)
