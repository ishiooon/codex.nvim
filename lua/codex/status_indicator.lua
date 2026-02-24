-- このファイルはCodexの状態アイコンを画面右下に描画します。
---@module "codex.status_indicator"

local M = {}

local defaults = require("codex.status_indicator_config").defaults
local logic = require("codex.status_indicator_logic")
local view = require("codex.status_indicator_view")
local activity = require("codex.activity")
local snapshot = require("codex.status_indicator_snapshot")
local state = {
  options = nil,
  timer = nil,
  last_published_lock_path = nil,
}

local function now_ms()
  if vim.loop and type(vim.loop.now) == "function" then
    return vim.loop.now()
  end
  return math.floor(os.time() * 1000)
end

---通知イベント受信時に表示を即時更新します。
local function update_from_notify_event()
  -- 停止済みや無効化時には更新しない
  if not state.options or state.options.enabled == false or not state.timer then
    return
  end
  M.update()
end

---Codexターミナルが表示されているウィンドウID一覧を返します。
---@return number[]
local function get_codex_screen_windows()
  local ok, terminal = pcall(require, "codex.terminal")
  if not ok or type(terminal.get_active_terminal_bufnr) ~= "function" then
    return {}
  end
  local bufnr = terminal.get_active_terminal_bufnr()
  if type(bufnr) ~= "number" or bufnr <= 0 then
    return {}
  end
  if not (vim.fn and type(vim.fn.getbufinfo) == "function") then
    return {}
  end
  local ok_info, bufinfo = pcall(vim.fn.getbufinfo, bufnr)
  if not ok_info or type(bufinfo) ~= "table" or #bufinfo == 0 then
    return {}
  end
  local windows = {}
  for _, winid in ipairs(bufinfo[1] and bufinfo[1].windows or {}) do
    if type(winid) == "number" and winid > 0 then
      windows[#windows + 1] = winid
    end
  end
  return windows
end

---UTF-8文字列のバイト長を返します。
---@param text string|nil
---@return number
local function byte_length(text)
  return #tostring(text or "")
end

---現在のNeovimプロセスIDを取得します。
---@return number
local function current_pid()
  if vim.fn and type(vim.fn.getpid) == "function" then
    local ok, pid = pcall(vim.fn.getpid)
    if ok then
      return tonumber(pid or 0) or 0
    end
  end
  return 0
end

---現在の作業ディレクトリを取得します。
---@return string
local function current_workspace()
  if vim.fn and type(vim.fn.getcwd) == "function" then
    local ok, cwd = pcall(vim.fn.getcwd)
    if ok and type(cwd) == "string" then
      return cwd
    end
  end
  return ""
end

---ローカル画面に対応するインスタンスの添字を探します。
---@param instances table[]
---@param server_status table|nil
---@param pid number
---@return number|nil
local function find_current_instance(instances, server_status, pid)
  local port = tonumber(server_status and server_status.port or 0) or 0
  if port > 0 then
    for index, instance in ipairs(instances) do
      if tonumber(instance.port or 0) == port then
        return index
      end
    end
  end
  if pid > 0 then
    for index, instance in ipairs(instances) do
      if tonumber(instance.pid or 0) == pid then
        return index
      end
    end
  end
  return nil
end

---テーブルを浅い複製でコピーします。
---@param source table
---@return table
local function copy_table(source)
  if type(vim.deepcopy) == "function" then
    return vim.deepcopy(source)
  end
  local copied = {}
  for key, value in pairs(source) do
    copied[key] = value
  end
  return copied
end

---現在サーバーに対応するlockファイルのパスを返します。
---@param server_status table|nil
---@return string|nil
local function resolve_lock_path(server_status)
  local port = tonumber(server_status and server_status.port or 0) or 0
  if port <= 0 then
    return nil
  end
  local ok, lockfile = pcall(require, "codex.lockfile")
  if not ok or type(lockfile.lock_dir) ~= "string" then
    return nil
  end
  return string.format("%s/%d.lock", lockfile.lock_dir, port)
end

---公開済みの状態ファイルを削除します。
local function clear_published_snapshot()
  if state.last_published_lock_path then
    snapshot.remove(state.last_published_lock_path)
    state.last_published_lock_path = nil
  end
end

---現在画面の状態スナップショットを保存します。
---@param status string
---@param server_status table|nil
---@param pid number
---@param workspace string
---@param now number
local function publish_snapshot(status, server_status, pid, workspace, now)
  local lock_path = resolve_lock_path(server_status)
  if not lock_path then
    clear_published_snapshot()
    return
  end
  if state.last_published_lock_path and state.last_published_lock_path ~= lock_path then
    snapshot.remove(state.last_published_lock_path)
  end
  snapshot.write(lock_path, {
    status = status,
    updatedAtMs = now,
    pid = pid,
    workspace = workspace,
    port = tonumber(server_status and server_status.port or 0) or nil,
  })
  state.last_published_lock_path = lock_path
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
    "nvim_win_close",
    "nvim_create_namespace",
    "nvim_buf_clear_namespace",
    "nvim_buf_add_highlight",
    "nvim_create_augroup",
    "nvim_create_autocmd",
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

  view.start()

  state.timer = vim.loop.new_timer()
  state.timer:start(0, state.options.update_interval_ms, function()
    vim.schedule(function()
      M.update()
    end)
  end)

  if state.options and state.options.cli_notify_path then
    -- notify更新時はタイマー周期を待たずに画面を更新する
    activity.start_notify_watcher(state.options.cli_notify_path, update_from_notify_event)
  end

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
  clear_published_snapshot()
  view.stop()
end

---状態表示を更新します。
function M.update()
  if not state.options or state.options.enabled == false then
    return
  end
  local now = now_ms()
  local pid = current_pid()
  local workspace = current_workspace()
  local server_status = logic.fetch_server_status()
  local status = M._get_status(now, server_status)
  publish_snapshot(status, server_status, pid, workspace, now)
  local instances = logic.list_running_instances()
  local display = M._build_multi_display(
    status,
    state.options,
    instances,
    server_status,
    pid,
    workspace
  )
  local panel_target_winid = M._resolve_panel_target_winid()
  local view_mode = panel_target_winid and "panel" or "floating"
  view.render(display.text, display.highlights, state.options, display.hover_lines, view_mode, panel_target_winid)
end

---状態判定を行います。
---@param now_ms_value number|nil
---@param server_status table|nil
---@return string
function M._get_status(now_ms_value, server_status)
  local resolved_server_status = server_status or logic.fetch_server_status()
  local has_pending_wait = logic.has_pending_wait()
  local cli_activity_ms = logic.get_cli_activity_ms()
  local turn_active = logic.get_turn_active()
  local turn_active_since_ms = logic.get_turn_active_since_ms()
  -- CLI応答中の情報も含めて状態を判定する
  return logic.derive_status(
    resolved_server_status,
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

---複数インスタンス向けの表示情報を構築します。
---@param local_status string
---@param options table
---@param instances table[]|nil
---@param server_status table|nil
---@param pid number
---@param workspace string
---@return table
function M._build_multi_display(local_status, options, instances, server_status, pid, workspace)
  local rows = {}
  for _, instance in ipairs(instances or {}) do
    if type(instance) == "table" then
      table.insert(rows, copy_table(instance))
    end
  end
  local current_index = find_current_instance(rows, server_status, pid)
  if current_index then
    rows[current_index].is_current = true
  end

  if local_status ~= "disconnected" and not current_index then
    table.insert(rows, {
      is_current = true,
      pid = pid,
      port = server_status and server_status.port or nil,
      workspace = workspace,
      workspace_folders = { workspace },
    })
  end

  if #rows == 0 then
    local text, highlight = M._build_display(local_status, options)
    local highlights = {}
    if type(highlight) == "string" and highlight ~= "" then
      table.insert(highlights, {
        group = highlight,
        start_col = 0,
        -- nvim_buf_add_highlight は表示幅ではなくバイト位置を受け取る
        end_col = byte_length(text),
      })
    end
    return {
      text = text,
      highlights = highlights,
      hover_lines = { "起動中のCodexはありません" },
    }
  end

  local icons = {}
  local highlights = {}
  local hover_lines = {}
  local byte_offset = 0
  local separator = " "
  local separator_bytes = byte_length(separator)
  for index, row in ipairs(rows) do
    local status_key = row.is_current and local_status or row.status or "idle"
    local icon = options.icons[status_key] or options.icons.idle or options.icons.disconnected
    local icon_bytes = byte_length(icon)
    local entry_text = icon
    local entry_bytes = byte_length(entry_text)
    table.insert(icons, entry_text)
    local highlight = options.colors[status_key]
    if type(highlight) == "string" and highlight ~= "" then
      table.insert(highlights, {
        group = highlight,
        start_col = byte_offset,
        end_col = byte_offset + icon_bytes,
      })
    end
    local resolved_workspace = row.workspace
    if type(resolved_workspace) ~= "string" or resolved_workspace == "" then
      resolved_workspace = "(環境情報なし)"
    end
    local details = { "状態:" .. status_key }
    if row.is_current then
      table.insert(details, "この画面")
    end
    if row.port then
      table.insert(details, "port:" .. tostring(row.port))
    end
    if row.pid then
      table.insert(details, "pid:" .. tostring(row.pid))
    end
    table.insert(hover_lines, string.format("%s %s (%s)", icon, resolved_workspace, table.concat(details, ", ")))
    byte_offset = byte_offset + entry_bytes
    if index < #rows then
      byte_offset = byte_offset + separator_bytes
    end
  end

  return {
    text = table.concat(icons, separator),
    highlights = highlights,
    hover_lines = hover_lines,
  }
end

---下部枠表示の対象にするCodex画面ウィンドウIDを返します。
---@return number|nil
function M._resolve_panel_target_winid()
  local windows = get_codex_screen_windows()
  if #windows == 0 then
    return nil
  end
  if vim.api and type(vim.api.nvim_win_is_valid) == "function" then
    for _, winid in ipairs(windows) do
      local ok_valid, is_valid = pcall(vim.api.nvim_win_is_valid, winid)
      if ok_valid and is_valid then
        return winid
      end
    end
    return nil
  end
  return windows[1]
end

---表示モードを判定します。
---@return "panel"|"floating"
function M._resolve_view_mode()
  if M._resolve_panel_target_winid() then
    -- Codex画面が開いている間は下部枠で詳細を表示する
    return "panel"
  end
  return "floating"
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
