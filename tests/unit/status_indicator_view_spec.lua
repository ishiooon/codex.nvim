-- このファイルは状態表示ビューの描画モードを単体で検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Codex status indicator view", function()
  local view
  local saved_create_namespace
  local saved_set_extmark
  local saved_del_extmark
  local saved_open_win
  local saved_set_config
  local saved_clear_namespace
  local saved_add_highlight

  before_each(function()
    package.loaded["codex.status_indicator_view"] = nil
    saved_create_namespace = vim.api.nvim_create_namespace
    saved_set_extmark = vim.api.nvim_buf_set_extmark
    saved_del_extmark = vim.api.nvim_buf_del_extmark
    saved_open_win = vim.api.nvim_open_win
    saved_set_config = vim.api.nvim_win_set_config
    saved_clear_namespace = vim.api.nvim_buf_clear_namespace
    saved_add_highlight = vim.api.nvim_buf_add_highlight

    if type(vim.api.nvim_open_win) ~= "function" then
      vim.api.nvim_open_win = function(bufnr, enter, config)
        local winid = vim._next_winid
        vim._next_winid = vim._next_winid + 1
        vim._windows[winid] = {
          buf = bufnr,
          width = config and config.width or 80,
          config = config,
        }
        local tab = vim._current_tabpage
        vim._win_tab[winid] = tab
        vim._tab_windows[tab] = vim._tab_windows[tab] or {}
        table.insert(vim._tab_windows[tab], winid)
        if enter then
          vim._current_window = winid
        end
        return winid
      end
    end
    if type(vim.api.nvim_win_set_config) ~= "function" then
      vim.api.nvim_win_set_config = function(winid, config)
        if vim._windows[winid] then
          vim._windows[winid].config = config
        end
      end
    end
    if type(vim.api.nvim_buf_clear_namespace) ~= "function" then
      vim.api.nvim_buf_clear_namespace = function(_, _, _, _)
        return true
      end
    end
    if type(vim.api.nvim_buf_add_highlight) ~= "function" then
      vim.api.nvim_buf_add_highlight = function(_, _, _, _, _, _)
        return true
      end
    end

    view = require("codex.status_indicator_view")
  end)

  after_each(function()
    vim.api.nvim_create_namespace = saved_create_namespace
    vim.api.nvim_buf_set_extmark = saved_set_extmark
    vim.api.nvim_buf_del_extmark = saved_del_extmark
    vim.api.nvim_open_win = saved_open_win
    vim.api.nvim_win_set_config = saved_set_config
    vim.api.nvim_buf_clear_namespace = saved_clear_namespace
    vim.api.nvim_buf_add_highlight = saved_add_highlight
    if view and type(view.stop) == "function" then
      view.stop()
    end
  end)

  it("panelモードでは対象ウィンドウ内に仮想行で描画する", function()
    local open_count = 0
    local extmark_calls = {}
    vim.api.nvim_create_namespace = function(_)
      return 9100
    end
    vim.api.nvim_buf_set_extmark = function(bufnr, ns, line, col, opts)
      table.insert(extmark_calls, {
        bufnr = bufnr,
        ns = ns,
        line = line,
        col = col,
        opts = opts,
      })
      return 101
    end
    vim.api.nvim_buf_del_extmark = function()
      return true
    end
    local open_impl = vim.api.nvim_open_win
    vim.api.nvim_open_win = function(...)
      open_count = open_count + 1
      return open_impl(...)
    end

    local target_winid = vim.api.nvim_get_current_win()
    local target_bufnr = vim.api.nvim_win_get_buf(target_winid)
    view.render("●", nil, { offset_row = 1, offset_col = 1 }, { "1. /tmp/current", "2. /tmp/other" }, "panel", target_winid)

    assert(open_count == 0)
    assert(#extmark_calls == 1)
    assert(extmark_calls[1].bufnr == target_bufnr)
    assert(type(extmark_calls[1].opts.virt_lines) == "table")
    assert(#extmark_calls[1].opts.virt_lines >= 2)
    assert(extmark_calls[1].opts.virt_lines_above == true)
    local last_virtual_line = extmark_calls[1].opts.virt_lines[#extmark_calls[1].opts.virt_lines]
    assert(type(last_virtual_line) == "table")
    assert(type(last_virtual_line[1]) == "table")
    assert(last_virtual_line[1][1] == "")
  end)

  it("panelモードでは9件程度の情報を省略せずに表示する", function()
    local extmark_calls = {}
    vim.api.nvim_create_namespace = function(_)
      return 9300
    end
    vim.api.nvim_buf_set_extmark = function(bufnr, ns, line, col, opts)
      table.insert(extmark_calls, {
        bufnr = bufnr,
        ns = ns,
        line = line,
        col = col,
        opts = opts,
      })
      return 303
    end
    vim.api.nvim_buf_del_extmark = function()
      return true
    end

    local target_winid = vim.api.nvim_get_current_win()
    local lines = {
      "1. /tmp/a",
      "2. /tmp/b",
      "3. /tmp/c",
      "4. /tmp/d",
      "5. /tmp/e",
      "6. /tmp/f",
      "7. /tmp/g",
      "8. /tmp/h",
      "9. /tmp/i",
    }
    view.render("●", nil, { offset_row = 1, offset_col = 1 }, lines, "panel", target_winid)

    assert(#extmark_calls == 1)
    local virt_lines = extmark_calls[1].opts.virt_lines
    assert(type(virt_lines) == "table")
    -- 9件の表示行 + 末尾余白1行
    assert(#virt_lines == 10)
    assert(virt_lines[9][1][1] == "9. /tmp/i")
  end)

  it("panelからfloatingへ切り替えると仮想行を解除する", function()
    local del_calls = {}
    vim.api.nvim_create_namespace = function(_)
      return 9200
    end
    vim.api.nvim_buf_set_extmark = function(_, _, _, _, _)
      return 202
    end
    vim.api.nvim_buf_del_extmark = function(bufnr, ns, id)
      table.insert(del_calls, { bufnr = bufnr, ns = ns, id = id })
      return true
    end

    local target_winid = vim.api.nvim_get_current_win()
    view.render("●", nil, { offset_row = 1, offset_col = 1 }, { "1. /tmp/current" }, "panel", target_winid)
    view.render("●", nil, { offset_row = 1, offset_col = 1 }, { "1. /tmp/current" }, "floating", nil)

    assert(#del_calls >= 1)
    assert(del_calls[1].id == 202)
  end)
end)
