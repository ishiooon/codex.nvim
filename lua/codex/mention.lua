-- このファイルは@メンションの範囲表記を共通化し、表示用の文字列を生成します。
---@module "codex.mention"

local M = {}

---表示用の範囲表記を作成する
---@param start_line number|nil 0始まりの開始行
---@param end_line number|nil 0始まりの終了行
---@return string range_text 表示用の行範囲。条件に合わない場合は空文字列
function M.format_range(start_line, end_line)
  if type(start_line) ~= "number" or type(end_line) ~= "number" then
    return ""
  end

  local display_start = start_line + 1
  local display_end = end_line + 1
  if display_start == display_end then
    return tostring(display_start)
  end
  return string.format("%d-%d", display_start, display_end)
end

return M
