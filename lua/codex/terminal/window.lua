-- このファイルはCodexターミナル用ウィンドウの作成と閉じる処理をまとめます。
---@module 'codex.terminal.window'

local M = {}

local terminal_size = require("codex.terminal.size")
local utils = require("codex.utils")

local function focus_or_restore(new_winid, original_winid, focus)
  if focus then
    vim.api.nvim_set_current_win(new_winid)
    vim.cmd("startinsert")
    return
  end

  if original_winid and vim.api.nvim_win_is_valid(original_winid) then
    vim.api.nvim_set_current_win(original_winid)
  end
end

local function split_prefix(split_side)
  if split_side == "left" then
    return "topleft "
  end
  return "botright "
end

---既存バッファを通常の縦分割ウィンドウで表示します。
---@param bufnr number
---@param config CodexTerminalConfig
---@param focus boolean|nil
---@return number|nil
function M.open_existing_buffer_in_split(bufnr, config, focus)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end

  focus = utils.normalize_focus(focus)
  local original_winid = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * config.split_width_percentage)

  -- 既存のターミナルバッファを表示するため、新しい縦分割ウィンドウを作成します。
  vim.cmd(split_prefix(config.split_side) .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, vim.o.lines)
  vim.api.nvim_win_set_buf(new_winid, bufnr)
  focus_or_restore(new_winid, original_winid, focus)
  return new_winid
end

---既存バッファを中央寄せの大きなフローティングウィンドウで表示します。
---@param bufnr number
---@param config CodexTerminalConfig
---@param focus boolean|nil
---@return number|nil
function M.open_existing_buffer_in_float(bufnr, config, focus)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end

  focus = utils.normalize_focus(focus)
  local original_winid = vim.api.nvim_get_current_win()
  local window_config = terminal_size.resolve_modal_window_config(
    vim.o.columns,
    vim.o.lines,
    config.maximized_width_percentage,
    config.maximized_height_percentage
  )

  -- 既存のターミナルバッファをエディタ全体基準のモーダルとして表示します。
  local new_winid = vim.api.nvim_open_win(bufnr, focus, window_config)
  focus_or_restore(new_winid, original_winid, focus)
  return new_winid
end

---指定されたウィンドウを閉じます。バッファとターミナルジョブは保持します。
---@param winid number|nil
---@return boolean
function M.close_window(winid)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return false
  end

  return pcall(vim.api.nvim_win_close, winid, false)
end

return M
