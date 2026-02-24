-- このファイルは状態アイコンの描画処理を担当します。
---@module "codex.status_indicator_view"

local M = {}

local state = {
  icon_win_id = nil,
  icon_buf_id = nil,
  panel_win_id = nil,
  panel_buf_id = nil,
  panel_ns = nil,
  panel_bufnr = nil,
  panel_mark_id = nil,
  hl_ns = nil,
  last_text = nil,
  last_highlight = nil,
  last_lines = nil,
  last_options = nil,
  last_mode = nil,
  last_panel_target_winid = nil,
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

---表示幅を安全に計算します。
---@param text string
---@return number
local function display_width(text)
  if vim.fn and type(vim.fn.strdisplaywidth) == "function" then
    local ok, width = pcall(vim.fn.strdisplaywidth, text)
    if ok and type(width) == "number" then
      return width
    end
  end
  return #tostring(text or "")
end

---行配列から最大表示幅を計算します。
---@param lines string[]
---@return number
local function max_line_width(lines)
  local max_width = 1
  for _, line in ipairs(lines or {}) do
    max_width = math.max(max_width, display_width(line))
  end
  return max_width
end

---ウィンドウ設定から noautocmd を除外します。
---@param config table|nil
---@return table
local function sanitize_window_config(config)
  local sanitized = {}
  for key, value in pairs(config or {}) do
    if key ~= "noautocmd" then
      sanitized[key] = value
    end
  end
  return sanitized
end

---前回のハイライト指定と同一かを判定します。
---@param left any
---@param right any
---@return boolean
local function same_highlight(left, right)
  if type(left) ~= type(right) then
    return false
  end
  if type(left) ~= "table" then
    return left == right
  end
  if #left ~= #right then
    return false
  end
  for index = 1, #left do
    local l = left[index]
    local r = right[index]
    if type(l) ~= "table" or type(r) ~= "table" then
      return false
    end
    if l.group ~= r.group or l.start_col ~= r.start_col or l.end_col ~= r.end_col then
      return false
    end
  end
  return true
end

---前回の行配列と同一かを判定します。
---@param left any
---@param right any
---@return boolean
local function same_lines(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then
    return left == right
  end
  if #left ~= #right then
    return false
  end
  for index = 1, #left do
    if left[index] ~= right[index] then
      return false
    end
  end
  return true
end

---ハイライト指定を複製します。
---@param highlight any
---@return any
local function copy_highlight(highlight)
  if type(highlight) ~= "table" then
    return highlight
  end
  local copied = {}
  for index, item in ipairs(highlight) do
    copied[index] = {
      group = item.group,
      start_col = item.start_col,
      end_col = item.end_col,
    }
  end
  return copied
end

---行配列を複製します。
---@param lines any
---@return any
local function copy_lines(lines)
  if type(lines) ~= "table" then
    return lines
  end
  local copied = {}
  for index, line in ipairs(lines) do
    copied[index] = line
  end
  return copied
end

local function close_icon_window()
  if state.icon_win_id and vim.api.nvim_win_is_valid(state.icon_win_id) then
    pcall(vim.api.nvim_win_close, state.icon_win_id, true)
  end
  state.icon_win_id = nil
  state.icon_buf_id = nil
end

local function close_panel_window()
  if state.panel_win_id and vim.api.nvim_win_is_valid(state.panel_win_id) then
    pcall(vim.api.nvim_win_close, state.panel_win_id, true)
  end
  state.panel_win_id = nil
  state.panel_buf_id = nil
end

local function clear_panel_overlay()
  if not state.panel_ns or not state.panel_bufnr or not state.panel_mark_id then
    state.panel_bufnr = nil
    state.panel_mark_id = nil
    return
  end
  if vim.api
    and type(vim.api.nvim_buf_is_valid) == "function"
    and type(vim.api.nvim_buf_del_extmark) == "function"
  then
    local ok_valid, is_valid = pcall(vim.api.nvim_buf_is_valid, state.panel_bufnr)
    if ok_valid and is_valid then
      pcall(vim.api.nvim_buf_del_extmark, state.panel_bufnr, state.panel_ns, state.panel_mark_id)
    end
  end
  state.panel_bufnr = nil
  state.panel_mark_id = nil
end

local function ensure_icon_buffer()
  if state.icon_buf_id and vim.api.nvim_buf_is_valid(state.icon_buf_id) then
    return state.icon_buf_id
  end
  local buf = vim.api.nvim_create_buf(false, true)
  set_buffer_option(buf, "bufhidden", "wipe")
  set_buffer_option(buf, "swapfile", false)
  set_buffer_option(buf, "modifiable", true)
  state.icon_buf_id = buf
  return buf
end

local function ensure_panel_buffer()
  if state.panel_buf_id and vim.api.nvim_buf_is_valid(state.panel_buf_id) then
    return state.panel_buf_id
  end
  local buf = vim.api.nvim_create_buf(false, true)
  set_buffer_option(buf, "bufhidden", "wipe")
  set_buffer_option(buf, "swapfile", false)
  set_buffer_option(buf, "modifiable", true)
  state.panel_buf_id = buf
  return buf
end

---右下フロート表示の設定を構築します。
---@param text string
---@param options table
---@return table
local function build_icon_window_config(text, options)
  local width = display_width(text)
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

---下部枠表示に使う行を整形します。
---@param lines string[]|nil
---@return string[]
local function normalize_panel_lines(lines)
  if type(lines) ~= "table" or #lines == 0 then
    return { "起動中のCodexはありません" }
  end
  local max_lines = 10
  if #lines <= max_lines then
    return lines
  end
  local normalized = {}
  for index = 1, max_lines do
    normalized[#normalized + 1] = lines[index]
  end
  normalized[#normalized + 1] = string.format("... 他 %d 件", #lines - max_lines)
  return normalized
end

---下部枠表示の設定を構築します。
---@param lines string[]
---@param options table
---@param panel_target_winid number|nil
---@return table
local function build_panel_window_config(lines, options, panel_target_winid)
  if type(panel_target_winid) == "number"
    and panel_target_winid > 0
    and vim.api
    and type(vim.api.nvim_win_is_valid) == "function"
    and type(vim.api.nvim_win_get_width) == "function"
    and type(vim.api.nvim_win_get_height) == "function"
  then
    local ok_valid, is_valid = pcall(vim.api.nvim_win_is_valid, panel_target_winid)
    if ok_valid and is_valid then
      local ok_width, target_width = pcall(vim.api.nvim_win_get_width, panel_target_winid)
      local ok_height, target_height = pcall(vim.api.nvim_win_get_height, panel_target_winid)
      if ok_width and ok_height and type(target_width) == "number" and type(target_height) == "number" then
        local width = math.max(20, math.floor(target_width))
        local max_height = math.max(1, math.floor(target_height))
        local height = math.min(math.max(1, #lines), max_height)
        -- 対象ウィンドウの最下段に揃える
        local row = math.max(0, max_height - height)
        return {
          relative = "win",
          win = panel_target_winid,
          anchor = "NW",
          row = row,
          col = 0,
          width = width,
          height = height,
          style = "minimal",
          border = "single",
          focusable = false,
          noautocmd = true,
          zindex = 45,
        }
      end
    end
  end

  -- 対象ウィンドウが取れない場合は従来どおりエディタ下部へ表示する
  local content_width = max_line_width(lines)
  local max_width = math.max(20, vim.o.columns - 2)
  local width = math.min(math.max(content_width + 2, 20), max_width)
  local max_height = math.max(1, vim.o.lines - 4)
  local height = math.min(math.max(1, #lines), max_height)
  local row = math.max(1, vim.o.lines - 1 - options.offset_row)
  local col = math.max(0, options.offset_col)
  if col + width > vim.o.columns then
    col = math.max(0, vim.o.columns - width)
  end
  return {
    relative = "editor",
    anchor = "SW",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    focusable = false,
    noautocmd = true,
    zindex = 45,
  }
end

---下部枠用の仮想行を構築します。
---@param lines string[]|nil
---@return table
local function build_panel_virtual_lines(lines)
  local virtual_lines = {}
  for _, line in ipairs(normalize_panel_lines(lines)) do
    virtual_lines[#virtual_lines + 1] = {
      { tostring(line), "Comment" },
    }
  end
  -- 入力欄との重なりを避けるため、末尾に1行分の余白を追加する
  virtual_lines[#virtual_lines + 1] = {
    { "", "Normal" },
  }
  return virtual_lines
end

---対象ウィンドウ内の最下部に仮想行で詳細を描画します。
---@param lines string[]|nil
---@param panel_target_winid number|nil
---@return boolean
local function render_panel_overlay(lines, panel_target_winid)
  if type(panel_target_winid) ~= "number" or panel_target_winid <= 0 then
    return false
  end
  if not vim.api then
    return false
  end
  local required = {
    "nvim_win_is_valid",
    "nvim_win_get_buf",
    "nvim_buf_is_valid",
    "nvim_buf_line_count",
    "nvim_create_namespace",
    "nvim_buf_set_extmark",
    "nvim_buf_del_extmark",
  }
  for _, name in ipairs(required) do
    if type(vim.api[name]) ~= "function" then
      return false
    end
  end

  local ok_win_valid, is_win_valid = pcall(vim.api.nvim_win_is_valid, panel_target_winid)
  if not ok_win_valid or not is_win_valid then
    return false
  end
  local ok_buf, target_bufnr = pcall(vim.api.nvim_win_get_buf, panel_target_winid)
  if not ok_buf or type(target_bufnr) ~= "number" or target_bufnr <= 0 then
    return false
  end
  local ok_buf_valid, is_buf_valid = pcall(vim.api.nvim_buf_is_valid, target_bufnr)
  if not ok_buf_valid or not is_buf_valid then
    return false
  end
  if not state.panel_ns then
    state.panel_ns = vim.api.nvim_create_namespace("CodexStatusIndicatorPanel")
  end
  if not state.panel_ns then
    return false
  end

  local ok_count, line_count = pcall(vim.api.nvim_buf_line_count, target_bufnr)
  if not ok_count then
    return false
  end
  local anchor_line = math.max(0, (tonumber(line_count) or 1) - 1)
  local virtual_lines = build_panel_virtual_lines(lines)

  clear_panel_overlay()
  local ok_mark, mark_id = pcall(vim.api.nvim_buf_set_extmark, target_bufnr, state.panel_ns, anchor_line, 0, {
    virt_lines = virtual_lines,
    -- 入力行の上に表示を固定して、下端に隠れないようにする
    virt_lines_above = true,
    hl_mode = "combine",
    priority = 200,
    strict = false,
  })
  if not ok_mark then
    return false
  end
  state.panel_bufnr = target_bufnr
  state.panel_mark_id = mark_id
  return true
end

---アイコン用バッファにハイライトを適用します。
---@param bufnr number
---@param highlight string|table|nil
local function apply_icon_highlight(bufnr, highlight)
  if not state.hl_ns then
    state.hl_ns = vim.api.nvim_create_namespace("CodexStatusIndicator")
  end
  vim.api.nvim_buf_clear_namespace(bufnr, state.hl_ns, 0, -1)
  if type(highlight) == "string" and highlight ~= "" then
    vim.api.nvim_buf_add_highlight(bufnr, state.hl_ns, highlight, 0, 0, -1)
    return
  end
  if type(highlight) ~= "table" then
    return
  end
  for _, item in ipairs(highlight) do
    if type(item) == "table" and type(item.group) == "string" and item.group ~= "" then
      vim.api.nvim_buf_add_highlight(
        bufnr,
        state.hl_ns,
        item.group,
        0,
        tonumber(item.start_col or 0) or 0,
        tonumber(item.end_col or -1) or -1
      )
    end
  end
end

---右下フロート表示を描画します。
---@param text string
---@param highlight string|table|nil
---@param options table
local function render_icon_window(text, highlight, options)
  local bufnr = ensure_icon_buffer()
  set_buffer_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { text })
  set_buffer_option(bufnr, "modifiable", false)
  apply_icon_highlight(bufnr, highlight)

  local config = build_icon_window_config(text, options)
  if state.icon_win_id and vim.api.nvim_win_is_valid(state.icon_win_id) then
    vim.api.nvim_win_set_config(state.icon_win_id, sanitize_window_config(config))
    vim.api.nvim_win_set_buf(state.icon_win_id, bufnr)
    return
  end
  state.icon_win_id = vim.api.nvim_open_win(bufnr, false, config)
end

---下部枠表示を描画します。
---@param lines string[]|nil
---@param options table
---@param panel_target_winid number|nil
local function render_panel_window(lines, options, panel_target_winid)
  local normalized_lines = normalize_panel_lines(lines)
  local bufnr = ensure_panel_buffer()
  set_buffer_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, normalized_lines)
  set_buffer_option(bufnr, "modifiable", false)

  local config = build_panel_window_config(normalized_lines, options, panel_target_winid)
  if state.panel_win_id and vim.api.nvim_win_is_valid(state.panel_win_id) then
    vim.api.nvim_win_set_config(state.panel_win_id, sanitize_window_config(config))
    vim.api.nvim_win_set_buf(state.panel_win_id, bufnr)
    return
  end
  state.panel_win_id = vim.api.nvim_open_win(bufnr, false, config)
end

---下部詳細表示を描画します。可能であればCodex画面内へ直接描画します。
---@param lines string[]|nil
---@param options table
---@param panel_target_winid number|nil
local function render_panel_content(lines, options, panel_target_winid)
  if render_panel_overlay(lines, panel_target_winid) then
    close_panel_window()
    return
  end
  clear_panel_overlay()
  render_panel_window(lines, options, panel_target_winid)
end

---前回状態を使って表示位置だけ再計算します。
local function refresh_layout()
  if not (state.last_text and state.last_options and state.last_mode) then
    return
  end
  if state.last_mode == "panel" then
    render_panel_content(state.last_lines, state.last_options, state.last_panel_target_winid)
    close_icon_window()
    return
  end
  render_icon_window(state.last_text, state.last_highlight, state.last_options)
  clear_panel_overlay()
  close_panel_window()
end

local function render_text(text, highlight, options, lines, mode, panel_target_winid)
  local resolved_mode = mode == "panel" and "panel" or "floating"
  if state.last_text == text
    and same_highlight(highlight, state.last_highlight)
    and same_lines(lines, state.last_lines)
    and state.last_mode == resolved_mode
    and state.last_panel_target_winid == panel_target_winid
  then
    refresh_layout()
    return
  end

  state.last_text = text
  state.last_highlight = copy_highlight(highlight)
  state.last_lines = copy_lines(lines)
  state.last_options = options
  state.last_mode = resolved_mode
  state.last_panel_target_winid = panel_target_winid

  if resolved_mode == "panel" then
    -- Codex画面表示中は下部枠に詳細を出し、右下フロートは隠す
    render_panel_content(lines, options, panel_target_winid)
    close_icon_window()
    return
  end
  -- Codex画面が閉じている時は右下フロートだけを表示する
  render_icon_window(text, highlight, options)
  clear_panel_overlay()
  close_panel_window()
end

---描画を更新します。
---@param text string
---@param highlight string|table|nil
---@param options table
---@param lines string[]|nil
---@param mode "panel"|"floating"|nil
---@param panel_target_winid number|nil
function M.render(text, highlight, options, lines, mode, panel_target_winid)
  render_text(text, highlight, options, lines, mode, panel_target_winid)
end

---リサイズ時の位置調整を登録します。
function M.start()
  if state.autocmd_group then
    return
  end
  state.autocmd_group = vim.api.nvim_create_augroup("CodexStatusIndicator", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = state.autocmd_group,
    callback = refresh_layout,
    desc = "Codex 状態表示の位置を再計算する",
  })
end

---描画状態を停止します。
function M.stop()
  close_icon_window()
  clear_panel_overlay()
  close_panel_window()
  state.panel_ns = nil
  state.last_text = nil
  state.last_highlight = nil
  state.last_lines = nil
  state.last_options = nil
  state.last_mode = nil
  state.last_panel_target_winid = nil
end

return M
