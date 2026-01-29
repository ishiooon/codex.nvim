-- このファイルはCodexターミナルの入出力を監視し、活動状態を更新します。
---@module "codex.terminal.activity"

local M = {}

local activity = require("codex.activity")
local constants = require("codex.terminal.constants")

local key_ns = nil
local attached_buffers = {}
local enter_mapped_buffers = {}

-- Enterキーの表記ゆれを吸収して入力判定する
local function is_enter_key(key)
  return key == "\r" or key == "\n" or key == "<CR>"
end

local function is_user_input_key(key)
  if type(key) ~= "string" or key == "" then
    return false
  end
  if is_enter_key(key) then
    return false
  end
  if key:sub(1, 1) == "<" and key:sub(-1) == ">" then
    return false
  end
  local first_byte = key:byte(1)
  if not first_byte or first_byte < 32 then
    return false
  end
  return true
end

local function is_codex_terminal_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, constants.CODEX_TERMINAL_VAR)
  if ok then
    return value == true
  end
  return false
end

local function is_terminal_mode()
  if not (vim.api and type(vim.api.nvim_get_mode) == "function") then
    return false
  end
  local ok, mode = pcall(vim.api.nvim_get_mode)
  if not ok or type(mode) ~= "table" then
    return false
  end
  if type(mode.mode) ~= "string" then
    return false
  end
  -- ターミナルモードの入力のみを応答開始として扱う
  return mode.mode:sub(1, 1) == "t"
end

local function ensure_on_key_listener()
  if key_ns or type(vim.on_key) ~= "function" then
    return
  end

  key_ns = vim.api.nvim_create_namespace("CodexTerminalActivity")
  -- Enter入力を監視して活動開始を記録する
  vim.on_key(function(key)
    local bufnr = vim.api.nvim_get_current_buf()
    if is_codex_terminal_buffer(bufnr) then
      -- 通常モードのEnterで誤判定しないようにターミナルモードのみ許可する
      if not is_terminal_mode() then
        return
      end
      if is_enter_key(key) then
        -- 送信操作として扱い、応答開始を記録する
        activity.record_turn_start()
      elseif is_user_input_key(key) then
        -- 入力開始を検知したため、入力時刻のみ更新する
        activity.record_terminal_input()
      end
    end
  end, key_ns)
end

local function ensure_enter_mapping(bufnr)
  if enter_mapped_buffers[bufnr] then
    return
  end
  if not (vim.keymap and vim.keymap.set) then
    return
  end
  -- 既存のEnterマッピングがある場合は上書きしない
  if vim.fn and type(vim.fn.maparg) == "function" then
    if vim.fn.maparg("<CR>", "t") ~= "" then
      return
    end
  end

  -- Enter入力時に応答開始を記録し、Enter自体は通す
  vim.keymap.set("t", "<CR>", function()
    activity.record_turn_start()
    return "\r"
  end, {
    buffer = bufnr,
    expr = true,
    noremap = true,
    silent = true,
    replace_keycodes = false,
    desc = "Codex: Enter 送信時の応答開始を記録する",
  })
  enter_mapped_buffers[bufnr] = true
end

local function attach_output_observer(bufnr)
  if attached_buffers[bufnr] then
    return
  end
  if not (vim.api and type(vim.api.nvim_buf_attach) == "function") then
    return
  end

  -- ターミナル出力の更新を検知して活動時刻を更新する
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      activity.record_terminal_output()
    end,
    on_bytes = function()
      activity.record_terminal_output()
    end,
  })
  -- 同一バッファへの二重登録を防ぐために記録する
  attached_buffers[bufnr] = true
end

---ターミナルの活動検知を有効化します。
---@param bufnr number
function M.attach(bufnr)
  ensure_on_key_listener()
  attach_output_observer(bufnr)
  ensure_enter_mapping(bufnr)
end

---テスト向けにユーザー入力判定を公開します。
---@param key string
---@return boolean
function M._is_user_input_key(key)
  return is_user_input_key(key)
end

return M
