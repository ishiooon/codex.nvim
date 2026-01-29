-- このファイルは状態アイコンの判定ロジックを担当します。
---@module "codex.status_indicator_logic"

local M = {}

local defaults = require("codex.status_indicator_config").defaults
local activity = require("codex.activity")

---状態判定のみを行います。
---@param server_status table|nil
---@param now_ms number|nil
---@param options table|nil
---@param cli_activity_ms number|nil
---@param has_pending_wait boolean|nil
---@param turn_active boolean|nil
---@param turn_active_since_ms number|nil
---@return string
function M.derive_status(server_status, now_ms, options, cli_activity_ms, has_pending_wait, turn_active, turn_active_since_ms)
  if type(server_status) ~= "table" or server_status.running ~= true then
    return "disconnected"
  end

  local resolved_options = options or defaults
  local is_turn_active = turn_active == true
  local turn_active_timeout_ms = tonumber(resolved_options.turn_active_timeout_ms or 0) or 0
  local turn_idle_grace_ms = tonumber(resolved_options.turn_idle_grace_ms or 0) or 0
  local inflight_timeout_ms = tonumber(resolved_options.inflight_timeout_ms or 0) or 0
  local active_since_ms = tonumber(turn_active_since_ms or 0) or 0
  local last_cli_activity_ms = tonumber(cli_activity_ms or 0) or 0
  local last_activity_ms = tonumber(server_status.last_activity_ms or 0) or 0
  local cleared_by_idle = false

  local deferred_responses = tonumber(server_status.deferred_responses or 0) or 0
  if deferred_responses > 0 or has_pending_wait == true then
    return "wait"
  end

  local inflight_requests = tonumber(server_status.inflight_requests or 0) or 0
  if inflight_requests > 0 then
    -- 実行中リクエストが古い場合は動作中とみなさない
    if now_ms and inflight_timeout_ms > 0 and last_activity_ms > 0 then
      if now_ms - last_activity_ms > inflight_timeout_ms then
        inflight_requests = 0
      end
    end
    if inflight_requests > 0 then
      return "busy"
    end
  end
  if is_turn_active and now_ms and turn_idle_grace_ms > 0 and last_cli_activity_ms > 0 then
    -- 現在のターン開始より前の出力は停止判定に使わない
    if active_since_ms <= 0 or last_cli_activity_ms >= active_since_ms then
      -- 応答が止まって一定時間経過した場合は動作中扱いを解除する
      if now_ms - last_cli_activity_ms > turn_idle_grace_ms then
        is_turn_active = false
        cleared_by_idle = true
      end
    end
  end
  if is_turn_active then
    -- 応答処理中は完了通知が来るまで動作中として扱う
    if now_ms and turn_active_timeout_ms > 0 and active_since_ms > 0 then
      if now_ms - active_since_ms <= turn_active_timeout_ms then
        return "busy"
      end
    else
      return "busy"
    end
  end

  if cleared_by_idle then
    -- 応答停止を検知した場合は、猶予表示を挟まずに待機へ戻す
    return "idle"
  end

  local busy_grace_ms = tonumber(resolved_options.busy_grace_ms or 0) or 0
  if now_ms and busy_grace_ms > 0 and last_activity_ms > 0 then
    if now_ms - last_activity_ms <= busy_grace_ms then
      return "busy"
    end
  end

  local cli_grace_ms = tonumber(resolved_options.cli_activity_grace_ms or 0) or 0
  if now_ms and cli_grace_ms > 0 and last_cli_activity_ms > 0 then
    if now_ms - last_cli_activity_ms <= cli_grace_ms then
      return "busy"
    end
  end

  return "idle"
end

---サーバの状態を取得します。
---@return table|nil
function M.fetch_server_status()
  local ok, server = pcall(require, "codex.server.init")
  if not ok or type(server.get_status) ~= "function" then
    return nil
  end
  return server.get_status()
end

---CLIの活動時刻を取得します。
---@return number
function M.get_cli_activity_ms()
  if activity and type(activity.get_last_activity_ms) == "function" then
    return activity.get_last_activity_ms()
  end
  return 0
end

---CLIの応答処理中フラグを取得します。
---@return boolean
function M.get_turn_active()
  if activity and type(activity.is_turn_active) == "function" then
    return activity.is_turn_active()
  end
  return false
end

---CLIの応答開始時刻を取得します。
---@return number
function M.get_turn_active_since_ms()
  if activity and type(activity.get_turn_active_since_ms) == "function" then
    return activity.get_turn_active_since_ms()
  end
  return 0
end

---ユーザー選択待ちが発生しているかを判定します。
---@return boolean
function M.has_pending_wait()
  local ok, diff = pcall(require, "codex.diff")
  if not ok then
    return false
  end

  local get_diffs = diff.get_active_diffs or diff._get_active_diffs
  if type(get_diffs) ~= "function" then
    return false
  end

  -- 差分一覧の取得関数を利用して待機状態を判定する
  local diffs = get_diffs()
  if type(diffs) ~= "table" then
    return false
  end

  for _, diff_data in pairs(diffs) do
    if type(diff_data) == "table" and diff_data.status == "pending" then
      return true
    end
  end

  return false
end

return M
