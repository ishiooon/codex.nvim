-- このファイルは状態アイコンの描画処理を担当します。
---@module "codex.status_indicator_view"

local M = {}

local state = {
  win_id = nil,
  buf_id = nil,
  hl_ns = nil,
  last_text = nil,
  last_highlight = nil,
  last_options = nil,
  autocmd_group = nil,
}

local function set_buffer_option(bufnr, name, value)
  if vim.api and type(vim.api.nvim_set_option_value) == "function" then
    pcall(vim.api.nvim_set_option_value, name, value, { buf = bufnr })
  end
  if vim.bo and type(vim.bo) == "table" then
    pcall(function()
      vim.bo[bufnr][name] = value
    end)
  end
end

local function ensure_buffer()
  if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
    return state.buf_id
  end
  -- 表示専用バッファを作成する
  local buf = vim.api.nvim_create_buf(false, true)
  set_buffer_option(buf, "bufhidden", "wipe")
  set_buffer_option(buf, "swapfile", false)
  set_buffer_option(buf, "modifiable", true)
  state.buf_id = buf
  return buf
end

local function build_window_config(text, options)
  local width = vim.fn.strdisplaywidth(text)
  local row = math.max(0, vim.o.lines - 1 - options.offset_row)
  local col = math.max(0, vim.o.columns - 1 - options.offset_col)
  return {
    relative = "editor",
    anchor = "SE",
    row = row,
    col = col,
    width = math.max(1, width),
    height = 1,
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = 50,
  }
end

local function sanitize_window_config(config)
  local sanitized = {}
  for key, value in pairs(config or {}) do
    if key ~= "noautocmd" then
      sanitized[key] = value
    end
  end
  return sanitized
end

local function ensure_window(text, options)
  local buf = ensure_buffer()
  local config = build_window_config(text, options)

  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    -- 既存ウィンドウの設定を更新する
    vim.api.nvim_win_set_config(state.win_id, sanitize_window_config(config))
    vim.api.nvim_win_set_buf(state.win_id, buf)
    return
  end

  state.win_id = vim.api.nvim_open_win(buf, false, config)
end

local function render_text(text, highlight, options)
  if state.last_text == text and highlight == state.last_highlight then
    ensure_window(text, options)
    return
  end

  state.last_text = text
  state.last_highlight = highlight
  state.last_options = options

  local buf = ensure_buffer()
  set_buffer_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  set_buffer_option(buf, "modifiable", false)

  if not state.hl_ns then
    state.hl_ns = vim.api.nvim_create_namespace("CodexStatusIndicator")
  end
  vim.api.nvim_buf_clear_namespace(buf, state.hl_ns, 0, -1)
  if highlight then
    vim.api.nvim_buf_add_highlight(buf, state.hl_ns, highlight, 0, 0, -1)
  end

  ensure_window(text, options)
end

---描画を更新します。
---@param text string
---@param highlight string|nil
---@param options table
function M.render(text, highlight, options)
  render_text(text, highlight, options)
end

---リサイズ時の位置調整を登録します。
function M.start()
  if state.autocmd_group then
    return
  end
  state.autocmd_group = vim.api.nvim_create_augroup("CodexStatusIndicator", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = state.autocmd_group,
    callback = function()
      if state.last_text and state.last_options then
        ensure_window(state.last_text, state.last_options)
      end
    end,
    desc = "Codex 状態アイコンの位置を再計算する",
  })
end

---描画状態を停止します。
function M.stop()
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    pcall(vim.api.nvim_win_close, state.win_id, true)
  end
  state.win_id = nil
  state.buf_id = nil
  state.last_text = nil
  state.last_highlight = nil
  state.last_options = nil
end

return M
