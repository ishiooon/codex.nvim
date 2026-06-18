-- このファイルはCodexターミナルの表示サイズ計算をまとめます。
---@module 'codex.terminal.size'

local M = {}

local DEFAULT_MAXIMIZED_PERCENTAGE = 0.96
local DEFAULT_NORMAL_WIDTH = 0.30

---幅の割合として安全に利用できる数値か判定します。
---@param value any
---@return boolean
function M.is_valid_percentage(value)
  return type(value) == "number" and value > 0 and value < 1
end

---大きい表示で使う幅を解決します。
---@param value number|nil
---@return number
function M.resolve_maximized_width(value)
  return M.resolve_modal_percentage(value)
end

---次の表示幅を決めます。
---@param should_maximize boolean
---@param normal_width number
---@param maximized_width number|nil
---@return number
function M.resolve_target_width(should_maximize, normal_width, maximized_width)
  if should_maximize then
    return M.resolve_maximized_width(maximized_width)
  end
  if M.is_valid_percentage(normal_width) then
    return normal_width
  end
  return DEFAULT_NORMAL_WIDTH
end

---モーダル表示で使う割合を解決します。
---@param value number|nil
---@return number
function M.resolve_modal_percentage(value)
  if M.is_valid_percentage(value) then
    return value
  end
  return DEFAULT_MAXIMIZED_PERCENTAGE
end

---エディタ全体に対する中央寄せのフローティングウィンドウ設定を作ります。
---@param columns number
---@param lines number
---@param width_percentage number|nil
---@param height_percentage number|nil
---@return table
function M.resolve_modal_window_config(columns, lines, width_percentage, height_percentage)
  local width = math.max(1, math.floor(columns * M.resolve_modal_percentage(width_percentage)))
  local height = math.max(1, math.floor(lines * M.resolve_modal_percentage(height_percentage)))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    col = math.max(0, math.floor((columns - width) / 2)),
    row = math.max(0, math.floor((lines - height) / 2)),
  }
end

return M
