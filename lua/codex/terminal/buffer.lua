-- このファイルはCodexターミナル用バッファの識別と表示調整を担当します。
---@module 'codex.terminal.buffer'

local M = {}

local CODEX_TERMINAL_VAR = "codex_terminal"
local DEFAULT_DISPLAY_NAME = "term://terminal"

local function is_valid_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function safe_get_buffer_name(bufnr)
  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if ok and type(name) == "string" then
    return name
  end
  return ""
end

local function buffer_name_includes_codex(buf_name)
  if buf_name == "" then
    return false
  end
  return buf_name:lower():find("codex", 1, true) ~= nil
end

local function read_codex_flag(bufnr)
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, CODEX_TERMINAL_VAR)
  if ok then
    return value == true
  end
  return false
end

local function set_codex_flag(bufnr)
  pcall(vim.api.nvim_buf_set_var, bufnr, CODEX_TERMINAL_VAR, true)
end

---Codex ターミナル用バッファをマークし、一覧表示と表示名を調整します。
---@param bufnr number
---@return boolean
function M.mark_terminal_buffer(bufnr)
  if not is_valid_buffer(bufnr) then
    return false
  end

  -- バッファローカル変数を設定し、一覧表示を抑制し、必要なら表示名を差し替える
  set_codex_flag(bufnr)
  vim.bo[bufnr].buflisted = false

  local current_name = safe_get_buffer_name(bufnr)
  if buffer_name_includes_codex(current_name) and current_name ~= DEFAULT_DISPLAY_NAME then
    pcall(vim.api.nvim_buf_set_name, bufnr, DEFAULT_DISPLAY_NAME)
  end

  return true
end

---Codex ターミナル用バッファかどうかを判定します。
---@param bufnr number
---@return boolean
function M.is_codex_terminal_buffer(bufnr)
  if not is_valid_buffer(bufnr) then
    return false
  end

  if read_codex_flag(bufnr) then
    return true
  end

  local name = safe_get_buffer_name(bufnr)
  return buffer_name_includes_codex(name)
end

return M
