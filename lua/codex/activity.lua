-- このファイルはCodex CLIの入出力活動を記録し、状態表示に利用します。
---@module "codex.activity"

local M = {}

local notify = require("codex.activity_notify")

local state = {
  last_terminal_output_ms = 0,
  last_terminal_input_ms = 0,
  last_turn_complete_ms = 0,
  turn_active_since_ms = 0,
  turn_active = false,
}

local function now_ms()
  if vim and vim.loop and type(vim.loop.now) == "function" then
    return vim.loop.now()
  end
  return math.floor(os.time() * 1000)
end

local function normalize_ms(timestamp_ms)
  local numeric = tonumber(timestamp_ms or 0) or 0
  if numeric <= 0 then
    return now_ms()
  end
  return numeric
end

local function activate_turn(timestamp_ms)
  -- 応答開始時刻を記録し、進行中として扱う
  if not state.turn_active then
    state.turn_active_since_ms = normalize_ms(timestamp_ms)
  elseif (state.turn_active_since_ms or 0) <= 0 then
    state.turn_active_since_ms = normalize_ms(timestamp_ms)
  end
  state.turn_active = true
end

local function apply_notify_event(event)
  if type(event) ~= "table" then
    return
  end
  if event.type == "agent-turn-complete" or event.type == "turn/completed" or event.type == "turn/cancelled" then
    M.record_turn_complete()
    return
  end
  if event.type == "turn/started" then
    M.record_turn_start()
  end
end

---通知ファイルの監視を開始します。
---@param path string
function M.start_notify_watcher(path)
  -- 通知ファイル監視を開始し、イベントを反映する
  notify.start(path, apply_notify_event)
end

---通知ファイルの監視を停止します。
function M.stop_notify_watcher()
  -- 通知ファイルの監視を停止する
  notify.stop()
end

---Codex CLIの出力を検知した時刻を更新します。
---@param timestamp_ms number|nil
function M.record_terminal_output(timestamp_ms)
  -- 出力を検知したため活動中として記録する
  local normalized_ms = normalize_ms(timestamp_ms)
  state.last_terminal_output_ms = normalized_ms
  -- 入力で開始した応答中のみ出力を活動として扱う
  if state.turn_active then
    activate_turn(normalized_ms)
  end
end

---Codex CLIへの入力送信時刻を更新します。
---@param timestamp_ms number|nil
function M.record_terminal_input(timestamp_ms)
  -- 入力欄への入力を記録する（応答開始は扱わない）
  if state.turn_active then
    return
  end
  state.last_terminal_input_ms = normalize_ms(timestamp_ms)
end

---Codex CLIの応答開始を記録します。
---@param timestamp_ms number|nil
function M.record_turn_start(timestamp_ms)
  -- 応答開始として活動中フラグを立てる
  local normalized_ms = normalize_ms(timestamp_ms)
  state.last_terminal_input_ms = normalized_ms
  activate_turn(normalized_ms)
end

---Codex CLIの応答完了時刻を更新します。
---@param timestamp_ms number|nil
function M.record_turn_complete(timestamp_ms)
  -- 応答完了の時刻を記録し、活動中フラグを解除する
  state.last_turn_complete_ms = normalize_ms(timestamp_ms)
  state.turn_active_since_ms = 0
  state.turn_active = false
end

---現在の応答が進行中かどうかを返します。
---@return boolean
function M.is_turn_active()
  return state.turn_active == true
end

---応答開始時刻を取得します。
---@return number
function M.get_turn_active_since_ms()
  return tonumber(state.turn_active_since_ms or 0) or 0
end

---CLIの最新活動時刻を取得します。
---@return number
function M.get_last_activity_ms()
  if not state.turn_active then
    return 0
  end
  -- 入力は応答中判定に使わず、出力のみを活動として扱う
  local last_output = tonumber(state.last_terminal_output_ms or 0) or 0
  if last_output <= 0 then
    return 0
  end
  return last_output
end

---内部状態を取得します（テスト向け）。
---@return table
function M._get_state_for_test()
  local notify_state = notify._get_state_for_test()
  return {
    last_terminal_output_ms = state.last_terminal_output_ms,
    last_terminal_input_ms = state.last_terminal_input_ms,
    last_turn_complete_ms = state.last_turn_complete_ms,
    turn_active_since_ms = state.turn_active_since_ms,
    turn_active = state.turn_active,
    notify_path = notify_state.path,
  }
end

---テスト向けに状態を初期化します。
function M._reset_for_test()
  state.last_terminal_output_ms = 0
  state.last_terminal_input_ms = 0
  state.last_turn_complete_ms = 0
  state.turn_active_since_ms = 0
  state.turn_active = false
  M.stop_notify_watcher()
end

return M
