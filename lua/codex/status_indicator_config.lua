-- このファイルは状態アイコンの既定設定を定義します。
---@module "codex.status_indicator_config"

local M = {}

---@type table
M.defaults = {
  enabled = true,
  update_interval_ms = 1000,
  -- 最後の通信から動作中表示を維持する猶予時間（ミリ秒）
  busy_grace_ms = 2000,
  -- CLI入出力の活動猶予時間（ミリ秒）
  cli_activity_grace_ms = 8000,
  -- 応答処理中とみなす最大時間（ミリ秒）
  turn_active_timeout_ms = 300000,
  -- 応答が停止してから動作中表示を解除する猶予時間（ミリ秒）
  turn_idle_grace_ms = 2000,
  -- 実行中リクエストが停止したと判断する猶予時間（ミリ秒）
  inflight_timeout_ms = 300000,
  -- Codex CLI通知ファイルのパス（未設定時は監視しない）
  cli_notify_path = nil,
  offset_row = 1,
  offset_col = 1,
  icons = {
    idle = "○",
    busy = "●",
    wait = "◐",
    disconnected = "✕",
  },
  colors = {
    idle = nil,
    busy = "DiagnosticInfo",
    wait = "DiagnosticWarn",
    disconnected = "DiagnosticError",
  },
}

return M
