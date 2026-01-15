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

  it("codex が含まれるバッファ名を安全な表示名へ差し替える", function()
    buffer.mark_terminal_buffer(1)
    assert.is_false(mock_vim.bo[1].buflisted)
    assert.is_true(buf_vars[1].codex_terminal)

    local call_args = mock_vim.api.nvim_buf_set_name.calls[1].vals
    local new_name = call_args[2]
    assert.is_nil(string.find(new_name:lower(), "codex", 1, true))
    assert.is_not_nil(string.match(new_name, "^term://"))
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
