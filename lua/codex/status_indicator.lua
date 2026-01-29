-- このファイルはCodexの状態アイコンを画面右下に描画します。
---@module "codex.status_indicator"

local M = {}

local defaults = require("codex.status_indicator_config").defaults
local logic = require("codex.status_indicator_logic")
local view = require("codex.status_indicator_view")
local activity = require("codex.activity")
local state = {
  options = nil,
  timer = nil,
}

local function now_ms()
  if vim.loop and type(vim.loop.now) == "function" then
    return vim.loop.now()
  end
  return math.floor(os.time() * 1000)
end

---必要なAPIが揃っているか確認します。
---@return boolean
local function is_available()
  if not (vim.api and vim.loop) then
    return false
  end
  local required_api = {
    "nvim_create_buf",
    "nvim_open_win",
    "nvim_win_set_config",
    "nvim_win_set_buf",
    "nvim_buf_set_lines",
    "nvim_buf_is_valid",
    "nvim_win_is_valid",
    "nvim_create_namespace",
  }
  for _, name in ipairs(required_api) do
    if type(vim.api[name]) ~= "function" then
      return false
    end
  end
  if not (vim.fn and type(vim.fn.strdisplaywidth) == "function") then
    return false
  end
  return true
end
---設定を取り込み、状態表示を開始します。
---@param options table|nil
function M.setup(options)
  local merge = vim.tbl_deep_extend or function(_, base, override)
    local merged = vim.deepcopy(base)
    for k, v in pairs(override or {}) do
      merged[k] = v
    end
    return merged
  end

  state.options = merge("force", defaults, options or {})
  if state.options.enabled == false then
    M.stop()
    return
  end
  M.start()
end

---状態表示を開始します。
function M.start()
  -- タイマーとウィンドウを作成し、状態更新を開始する
  if not is_available() or state.timer then
    return
  end

  if state.options and state.options.cli_notify_path then
    activity.start_notify_watcher(state.options.cli_notify_path)
  end

  view.start()

  state.timer = vim.loop.new_timer()
  state.timer:start(0, state.options.update_interval_ms, function()
    vim.schedule(function()
      M.update()
    end)
  end)

  M.update()
end

---状態表示を停止します。
function M.stop()
  -- タイマー停止とウィンドウ破棄を行う
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  activity.stop_notify_watcher()
  view.stop()
end

---状態表示を更新します。
function M.update()
  if not state.options or state.options.enabled == false then
    return
  end
  local status = M._get_status(now_ms())
  local text, highlight = M._build_display(status, state.options)
  view.render(text, highlight, state.options)
end

---状態判定を行います。
---@param now_ms_value number|nil
---@return string
function M._get_status(now_ms_value)
  local server_status = logic.fetch_server_status()
  local has_pending_wait = logic.has_pending_wait()
  local cli_activity_ms = logic.get_cli_activity_ms()
  local turn_active = logic.get_turn_active()
  local turn_active_since_ms = logic.get_turn_active_since_ms()
  -- CLI応答中の情報も含めて状態を判定する
  return logic.derive_status(
    server_status,
    now_ms_value,
    state.options,
    cli_activity_ms,
    has_pending_wait,
    turn_active,
    turn_active_since_ms
  )
end

---表示用の文字列とハイライトを構築します。
---@param status string
---@param options table
---@return string
---@return string|nil
function M._build_display(status, options)
  local icon = options.icons[status] or options.icons.disconnected
  local highlight = options.colors[status]
  return icon, highlight
end

---テスト向けに状態判定のみを行います。
---@param server_status table|nil
---@param now_ms_value number|nil
---@param options table|nil
---@param cli_activity_ms number|nil
---@param has_pending_wait boolean|nil
---@return string
function M._derive_status(server_status, now_ms_value, options, cli_activity_ms, has_pending_wait, turn_active, turn_active_since_ms)
  return logic.derive_status(
    server_status,
    now_ms_value,
    options,
    cli_activity_ms,
    has_pending_wait,
    turn_active,
    turn_active_since_ms
  )
end

---テスト向けに選択待ち判定のみを行います。
---@return boolean
function M._has_pending_wait()
  return logic.has_pending_wait()
end

return M
