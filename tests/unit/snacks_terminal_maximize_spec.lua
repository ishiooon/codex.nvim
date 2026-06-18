-- このファイルはSnacksプロバイダのモーダル表示切替を検証します。
require("tests.busted_setup")

describe("codex.terminal.snacks maximize toggle", function()
  local provider
  local terminal_instance

  local function modal_config(is_maximized)
    return {
      split_side = "right",
      split_width_percentage = 0.3,
      is_maximized = is_maximized,
      maximized_width_percentage = 0.96,
      maximized_height_percentage = 0.96,
      auto_close = true,
      snacks_win_opts = {},
    }
  end

  before_each(function()
    _G.vim = require("tests.mocks.vim")
    vim.o.columns = 120
    vim.o.lines = 40
    vim._buffers[2] = { name = "term://codex", options = { buftype = "terminal" } }
    vim._windows[1000] = { buf = 2, width = 36 }
    vim._tab_windows[1] = { 1000 }
    vim._current_window = 1000
    vim._next_winid = 1001
    vim.bo = setmetatable({}, {
      __index = function(_, bufnr)
        return setmetatable({}, {
          __newindex = function(_, option, value)
            vim._buffers[bufnr].options[option] = value
          end,
        })
      end,
    })

    -- 既存バッファをフローティングウィンドウへ表示した結果を検証できるようにする
    vim.api.nvim_open_win = function(bufnr, enter, window_config)
      local winid = vim._next_winid
      vim._next_winid = vim._next_winid + 1
      vim._windows[winid] = { buf = bufnr, config = window_config }
      table.insert(vim._tab_windows[1], winid)
      if enter then
        vim._current_window = winid
      end
      return winid
    end

    terminal_instance = {
      buf = 2,
      win = 1000,
      buf_valid = function(self)
        return vim.api.nvim_buf_is_valid(self.buf)
      end,
      win_valid = function(self)
        return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
      end,
      on = function() end,
      focus = function(self)
        vim.api.nvim_set_current_win(self.win)
      end,
      close = function(self)
        if self.win and vim.api.nvim_win_is_valid(self.win) then
          vim.api.nvim_win_close(self.win, false)
        end
        self.win = nil
      end,
      toggle = function(self)
        self:close()
      end,
    }

    package.loaded["snacks"] = {
      terminal = {
        open = function()
          return terminal_instance
        end,
      },
    }
    package.loaded["codex.terminal.snacks"] = nil
    package.loaded["codex.terminal.window"] = nil
    package.loaded["codex.terminal.size"] = nil
    provider = require("codex.terminal.snacks")
  end)

  after_each(function()
    package.loaded["snacks"] = nil
    package.loaded["codex.terminal.snacks"] = nil
    package.loaded["codex.terminal.window"] = nil
    package.loaded["codex.terminal.size"] = nil
    _G.vim = nil
  end)

  it("既存Snacksターミナルを96パーセントのフローティングモーダルで表示する", function()
    provider.open("codex", {}, modal_config(false))

    provider.maximize_toggle("codex", {}, modal_config(true))

    local modal_win = terminal_instance.win
    local opened_config = vim._windows[modal_win].config
    assert.are.equal(2, vim._windows[modal_win].buf)
    assert.are.equal("editor", opened_config.relative)
    assert.are.equal(115, opened_config.width)
    assert.are.equal(38, opened_config.height)
  end)
end)
