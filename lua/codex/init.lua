-- このファイルはCodex.nvimの中核モジュールとして、初期化と起動停止、各種コマンド登録を担当します。
---@brief [[
--- Codex Neovim Integration
--- This plugin integrates Codex CLI with Neovim, enabling
--- seamless AI-assisted coding experiences directly in Neovim.
---@brief ]]

---@module 'codex'
local M = {}

local logger = require("codex.logger")
local mention = require("codex.mention")

--- Current plugin version
---@type CodexVersion
M.version = {
  major = 0,
  minor = 2,
  patch = 0,
  prerelease = nil,
  string = function(self)
    local version = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease then
      version = version .. "-" .. self.prerelease
    end
    return version
  end,
}

-- Module state
---@type CodexState
M.state = {
  config = require("codex.config").defaults,
  server = nil,
  port = nil,
  auth_token = nil,
  initialized = false,
  mention_queue = {},
  mention_timer = nil,
  connection_timer = nil,
}

---Check if Codex is connected to WebSocket server
---@return boolean connected Whether Codex has active connections
function M.is_codex_connected()
  if not M.state.server then
    return false
  end

  local server_module = require("codex.server.init")
  local status = server_module.get_status()
  if not status.running then
    return false
  end

  -- Prefer handshake-aware check when client info is available; otherwise fall back to client_count
  if status.clients and #status.clients > 0 then
    for _, info in ipairs(status.clients) do
      if (info.state == "connected" or info.handshake_complete == true) and info.handshake_complete == true then
        return true
      end
    end
    return false
  else
    return status.client_count and status.client_count > 0
  end
end

---Clear the mention queue and stop any pending timer
local function clear_mention_queue()
  -- Initialize mention_queue if it doesn't exist (for test compatibility)
  if not M.state.mention_queue then
    M.state.mention_queue = {}
  else
    if #M.state.mention_queue > 0 then
      logger.debug("queue", "Clearing " .. #M.state.mention_queue .. " queued @ mentions")
    end
    M.state.mention_queue = {}
  end

  if M.state.mention_timer then
    M.state.mention_timer:stop()
    M.state.mention_timer:close()
    M.state.mention_timer = nil
  end
end

---Process mentions when Codex is connected (debounced mode)
local function process_connected_mentions()
  -- Reset the debounce timer
  if M.state.mention_timer then
    M.state.mention_timer:stop()
    M.state.mention_timer:close()
  end

  -- Set a new timer to process the queue after 50ms of inactivity
  M.state.mention_timer = vim.loop.new_timer()
  local debounce_delay = math.max(10, 50) -- Minimum 10ms debounce, 50ms for batching

  -- Use vim.schedule_wrap if available, otherwise fallback to vim.schedule + function call
  local wrapped_function = vim.schedule_wrap and vim.schedule_wrap(M.process_mention_queue)
    or function()
      vim.schedule(M.process_mention_queue)
    end

  M.state.mention_timer:start(debounce_delay, 0, wrapped_function)
end

---Start connection timeout timer if not already started
local function start_connection_timeout_if_needed()
  if not M.state.connection_timer then
    M.state.connection_timer = vim.loop.new_timer()
    M.state.connection_timer:start(M.state.config.connection_timeout, 0, function()
      vim.schedule(function()
        if #M.state.mention_queue > 0 then
          logger.error("queue", "Connection timeout - clearing " .. #M.state.mention_queue .. " queued @ mentions")
          clear_mention_queue()
        end
      end)
    end)
  end
end

---Add @ mention to queue
---@param file_path string The file path to mention
---@param start_line number|nil Optional start line
---@param end_line number|nil Optional end line
local function queue_mention(file_path, start_line, end_line)
  -- Initialize mention_queue if it doesn't exist (for test compatibility)
  if not M.state.mention_queue then
    M.state.mention_queue = {}
  end

  local mention_data = {
    file_path = file_path,
    start_line = start_line,
    end_line = end_line,
    timestamp = vim.loop.now(),
  }

  table.insert(M.state.mention_queue, mention_data)
  logger.debug("queue", "Queued @ mention: " .. file_path .. " (queue size: " .. #M.state.mention_queue .. ")")

  -- Process based on connection state
  if M.is_codex_connected() then
    -- Connected: Use debounced processing (old broadcast_queue behavior)
    process_connected_mentions()
  else
    -- Disconnected: Start connection timeout timer (old queued_mentions behavior)
    start_connection_timeout_if_needed()
  end
end

---Process the mention queue (handles both connected and disconnected modes)
---@param from_new_connection boolean|nil Whether this is triggered by a new connection (adds delay)
function M.process_mention_queue(from_new_connection)
  -- Initialize mention_queue if it doesn't exist (for test compatibility)
  if not M.state.mention_queue then
    M.state.mention_queue = {}
    return
  end

  if #M.state.mention_queue == 0 then
    return
  end

  if not M.is_codex_connected() then
    -- Still disconnected or handshake not complete yet, wait for readiness
    logger.debug("queue", "Codex not ready (no handshake). Keeping ", #M.state.mention_queue, " mentions queued")

    -- If triggered by a new connection, poll until handshake completes (bounded by connection_timeout timer)
    if from_new_connection then
      local retry_delay = math.max(50, math.floor((M.state.config.connection_wait_delay or 200) / 4))
      vim.defer_fn(function()
        M.process_mention_queue(true)
      end, retry_delay)
    end
    return
  end

  -- 先に保留中の選択通知を送信し、挿入に必要な情報を揃える
  local selection_module_ok, selection_module = pcall(require, "codex.selection")
  if selection_module_ok and type(selection_module.flush_pending_selection) == "function" then
    selection_module.flush_pending_selection()
  end

  local mentions_to_send = vim.deepcopy(M.state.mention_queue)
  M.state.mention_queue = {} -- Clear queue

  -- Stop any existing timer
  if M.state.mention_timer then
    M.state.mention_timer:stop()
    M.state.mention_timer:close()
    M.state.mention_timer = nil
  end

  -- Stop connection timer since we're now connected
  if M.state.connection_timer then
    M.state.connection_timer:stop()
    M.state.connection_timer:close()
    M.state.connection_timer = nil
  end

  logger.debug("queue", "Processing " .. #mentions_to_send .. " queued @ mentions")

  -- Send mentions with a small delay between each to prevent WebSocket/extension overwhelm
  local function send_mention_sequential(index)
    if index > #mentions_to_send then
      logger.debug("queue", "All queued mentions sent successfully")
      return
    end

    local mention = mentions_to_send[index]

    -- Check if mention has expired (same timeout logic as old system)
    local current_time = vim.loop.now()
    if (current_time - mention.timestamp) > M.state.config.queue_timeout then
      logger.debug("queue", "Skipped expired @ mention: " .. mention.file_path)
    else
      -- Directly broadcast without going through the queue system to avoid infinite recursion
      local params = {
        filePath = mention.file_path,
        lineStart = mention.start_line,
        lineEnd = mention.end_line,
      }

      local broadcast_success = M.state.server.broadcast("at_mentioned", params)
      if broadcast_success then
        logger.debug("queue", "Sent queued @ mention: " .. mention.file_path)
      else
        logger.error("queue", "Failed to send queued @ mention: " .. mention.file_path)
      end
    end

    -- Process next mention with delay
    if index < #mentions_to_send then
      local inter_message_delay = 25 -- ms
      vim.defer_fn(function()
        send_mention_sequential(index + 1)
      end, inter_message_delay)
    end
  end

  -- Apply delay for new connections, send immediately for debounced processing
  if #mentions_to_send > 0 then
    if from_new_connection then
      -- Wait for connection_wait_delay when processing queue after new connection
      local initial_delay = (M.state.config and M.state.config.connection_wait_delay) or 200
      logger.debug("queue", "Waiting ", initial_delay, "ms after connect before flushing queue")
      vim.defer_fn(function()
        send_mention_sequential(1)
      end, initial_delay)
    else
      -- Send immediately for debounced processing (Codex already connected)
      send_mention_sequential(1)
    end
  end
end

---Show terminal if Codex is connected and it's not already visible
---@return boolean success Whether terminal was shown or was already visible
function M._ensure_terminal_visible_if_connected()
  if not M.is_codex_connected() then
    return false
  end

  local terminal = require("codex.terminal")
  local active_bufnr = terminal.get_active_terminal_bufnr and terminal.get_active_terminal_bufnr()

  if not active_bufnr then
    return false
  end

  local bufinfo = vim.fn.getbufinfo(active_bufnr)[1]
  local is_visible = bufinfo and #bufinfo.windows > 0

  if not is_visible then
    terminal.simple_toggle()
  end

  return true
end

local function should_skip_terminal_fallback(context)
  -- 選択送信は別の経路でターミナル入力を更新するため、ここでは除外する
  return context == "CodexSend" or context == "CodexSend_visual"
end

local function format_at_mention_path(file_path)
  -- 送信対象のパス表記を統一してから@メンションへ利用する
  if type(file_path) ~= "string" or file_path == "" then
    return nil
  end

  local ok, formatted_path = pcall(M._format_path_for_at_mention, file_path)
  if ok and type(formatted_path) == "string" and formatted_path ~= "" then
    return formatted_path
  end

  return file_path
end

local function build_at_mention_text(formatted_path, start_line, end_line)
  if type(formatted_path) ~= "string" or formatted_path == "" then
    return nil
  end

  local range_text = mention.format_range(start_line, end_line)
  if range_text ~= "" then
    return "@" .. formatted_path .. ":" .. range_text
  end
  return "@" .. formatted_path
end

---Send @ mention to Codex, handling connection state automatically
---@param file_path string The file path to send
---@param start_line number|nil Start line (0-indexed for Codex)
---@param end_line number|nil End line (0-indexed for Codex)
---@param context string|nil Context for logging
---@return boolean success Whether the operation was successful
---@return string|nil error Error message if failed
function M.send_at_mention(file_path, start_line, end_line, context)
  context = context or "command"

  if not M.state.server then
    logger.error(context, "Codex integration is not running")
    return false, "Codex integration is not running"
  end

  -- Check if Codex is connected
  if M.is_codex_connected() then
    -- Codex is connected, send immediately and ensure terminal is visible
    local success, error_msg = M._broadcast_at_mention(file_path, start_line, end_line)
    if success then
      local terminal = require("codex.terminal")
      if M.state.config and M.state.config.focus_after_send then
        -- Open focuses the terminal without toggling/hiding if already focused
        terminal.open()
      else
        terminal.ensure_visible()
      end
    end
    return success, error_msg
  else
    -- Codex not connected, queue the mention and launch terminal
    local formatted_path = format_at_mention_path(file_path) or file_path
    queue_mention(formatted_path, start_line, end_line)

    -- Launch terminal with Codex
    local terminal = require("codex.terminal")
    terminal.open()

    local config = M.state.config or {}
    local allow_fallback = config.fallback_to_terminal_send ~= false
    if allow_fallback and not should_skip_terminal_fallback(context) then
      local mention_text = build_at_mention_text(formatted_path, start_line, end_line)
      if mention_text and mention_text ~= "" then
        -- ターミナルの入力欄へ@メンションを差し込む
        terminal.send(mention_text .. " ", { submit = false })
      end
    end

    logger.debug(context, "Queued @ mention and launched Codex: " .. tostring(formatted_path))

    return true, nil
  end
end

---Set up the plugin with user configuration
---@param opts PartialCodexConfig|nil Optional configuration table to override defaults.
---@return table module The plugin module
function M.setup(opts)
  opts = opts or {}

  local config = require("codex.config")
  M.state.config = config.apply(opts)
  -- vim.g.codex_user_config is no longer needed as config values are passed directly.

  logger.setup(M.state.config)

  -- Setup terminal module: always try to call setup to pass terminal_cmd and env,
  -- even if terminal_opts (for split_side etc.) are not provided.
  -- Map top-level cwd-related aliases into terminal config for convenience
  do
    local t = opts.terminal or {}
    local had_alias = false
    if opts.git_repo_cwd ~= nil then
      t.git_repo_cwd = opts.git_repo_cwd
      had_alias = true
    end
    if opts.cwd ~= nil then
      t.cwd = opts.cwd
      had_alias = true
    end
    if opts.cwd_provider ~= nil then
      t.cwd_provider = opts.cwd_provider
      had_alias = true
    end
    if had_alias then
      opts.terminal = t
    end
  end

  local terminal_setup_ok, terminal_module = pcall(require, "codex.terminal")
  if terminal_setup_ok then
    -- Guard in case tests or user replace the module with a minimal stub without `setup`.
    if type(terminal_module.setup) == "function" then
      -- terminal_opts might be nil, which the setup function should handle gracefully.
      terminal_module.setup(opts.terminal, M.state.config.terminal_cmd, M.state.config.env)
    end
  else
    logger.error("init", "Failed to load codex.terminal module for setup.")
  end

  local diff = require("codex.diff")
  diff.setup(M.state.config)

  if M.state.config.auto_start then
    M.start(false) -- Suppress notification on auto-start
  end

  M._create_commands()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("CodexShutdown", { clear = true }),
    callback = function()
      if M.state.server then
        M.stop()
      else
        -- Clear queue even if server isn't running
        clear_mention_queue()
      end
    end,
    desc = "Automatically stop Codex integration when exiting Neovim",
  })

  -- Codexの既定キーマップを登録する
  local keymaps = require("codex.keymaps")
  keymaps.setup(M.state.config.keymaps)

  M.state.initialized = true
  return M
end

---Start the Codex integration
---@param show_startup_notification? boolean Whether to show a notification upon successful startup (defaults to true)
---@return boolean success Whether the operation was successful
---@return number|string port_or_error The WebSocket port if successful, or error message if failed
function M.start(show_startup_notification)
  if show_startup_notification == nil then
    show_startup_notification = true
  end
  if M.state.server then
    local msg = "Codex integration is already running on port " .. tostring(M.state.port)
    logger.warn("init", msg)
    return false, "Already running"
  end

  local server = require("codex.server.init")
  local lockfile = require("codex.lockfile")

  -- Generate auth token first so we can pass it to the server
  local auth_token
  local auth_success, auth_result = pcall(function()
    return lockfile.generate_auth_token()
  end)

  if not auth_success then
    local error_msg = "Failed to generate authentication token: " .. (auth_result or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  auth_token = auth_result

  -- Validate the generated auth token
  if not auth_token or type(auth_token) ~= "string" or #auth_token < 10 then
    local error_msg = "Invalid authentication token generated"
    logger.error("init", error_msg)
    return false, error_msg
  end

  local success, result = server.start(M.state.config, auth_token)

  if not success then
    local error_msg = "Failed to start Codex server: " .. (result or "unknown error")
    if result and result:find("auth") then
      error_msg = error_msg .. " (authentication related)"
    end
    logger.error("init", error_msg)
    return false, error_msg
  end

  M.state.server = server
  M.state.port = tonumber(result)
  M.state.auth_token = auth_token

  local lock_success, lock_result, returned_auth_token = lockfile.create(M.state.port, auth_token)

  if not lock_success then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Failed to create lock file: " .. (lock_result or "unknown error")
    if lock_result and lock_result:find("auth") then
      error_msg = error_msg .. " (authentication token issue)"
    end
    logger.error("init", error_msg)
    return false, error_msg
  end

  -- Verify that the auth token in the lock file matches what we generated
  if returned_auth_token ~= auth_token then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Authentication token mismatch between server and lock file"
    logger.error("init", error_msg)
    return false, error_msg
  end

  if M.state.config.track_selection then
    local selection = require("codex.selection")
    selection.enable(M.state.server, M.state.config.visual_demotion_delay_ms)
  end

  if show_startup_notification then
    logger.info("init", "Codex integration started on port " .. tostring(M.state.port))
  end

  return true, M.state.port
end

---Stop the Codex integration
---@return boolean success Whether the operation was successful
---@return string|nil error Error message if operation failed
function M.stop()
  if not M.state.server then
    logger.warn("init", "Codex integration is not running")
    return false, "Not running"
  end

  local lockfile = require("codex.lockfile")
  local lock_success, lock_error = lockfile.remove(M.state.port)

  if not lock_success then
    logger.warn("init", "Failed to remove lock file: " .. lock_error)
    -- Continue with shutdown even if lock file removal fails
  end

  if M.state.config.track_selection then
    local selection = require("codex.selection")
    selection.disable()
  end

  local success, error = M.state.server.stop()

  if not success then
    logger.error("init", "Failed to stop Codex integration: " .. error)
    return false, error
  end

  M.state.server = nil
  M.state.port = nil
  M.state.auth_token = nil

  -- Clear any queued @ mentions when server stops
  clear_mention_queue()

  logger.info("init", "Codex integration stopped")

  return true
end

---Set up user commands
---@private
function M._create_commands()
  vim.api.nvim_create_user_command("CodexStart", function()
    M.start()
  end, {
    desc = "Start Codex integration",
  })

  vim.api.nvim_create_user_command("CodexStop", function()
    M.stop()
  end, {
    desc = "Stop Codex integration",
  })

  vim.api.nvim_create_user_command("CodexStatus", function()
    if M.state.server and M.state.port then
      logger.info("command", "Codex integration is running on port " .. tostring(M.state.port))
    else
      logger.info("command", "Codex integration is not running")
    end
  end, {
    desc = "Show Codex integration status",
  })

  ---@param file_paths table List of file paths to add
  ---@param options table|nil Optional settings: { delay?: number, show_summary?: boolean, context?: string }
  ---@return number success_count Number of successfully added files
  ---@return number total_count Total number of files attempted
  local function add_paths_to_codex(file_paths, options)
    options = options or {}
    local delay = options.delay or 0
    local show_summary = options.show_summary ~= false
    local context = options.context or "command"

    if not file_paths or #file_paths == 0 then
      return 0, 0
    end

    local success_count = 0
    local total_count = #file_paths

    if delay > 0 then
      local function send_files_sequentially(index)
        if index > total_count then
          if show_summary then
            local message = success_count == 1 and "Added 1 file to Codex context"
              or string.format("Added %d files to Codex context", success_count)
            if total_count > success_count then
              message = message .. string.format(" (%d failed)", total_count - success_count)
            end

            if total_count > success_count then
              if success_count > 0 then
                logger.warn(context, message)
              else
                logger.error(context, message)
              end
            elseif success_count > 0 then
              logger.info(context, message)
            else
              logger.debug(context, message)
            end
          end
          return
        end

        local file_path = file_paths[index]
        local success, error_msg = M.send_at_mention(file_path, nil, nil, context)
        if success then
          success_count = success_count + 1
        else
          logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
        end

        if index < total_count then
          vim.defer_fn(function()
            send_files_sequentially(index + 1)
          end, delay)
        else
          if show_summary then
            local message = success_count == 1 and "Added 1 file to Codex context"
              or string.format("Added %d files to Codex context", success_count)
            if total_count > success_count then
              message = message .. string.format(" (%d failed)", total_count - success_count)
            end

            if total_count > success_count then
              if success_count > 0 then
                logger.warn(context, message)
              else
                logger.error(context, message)
              end
            elseif success_count > 0 then
              logger.info(context, message)
            else
              logger.debug(context, message)
            end
          end
        end
      end

      send_files_sequentially(1)
    else
      for _, file_path in ipairs(file_paths) do
        local success, error_msg = M.send_at_mention(file_path, nil, nil, context)
        if success then
          success_count = success_count + 1
        else
          logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
        end
      end

      if show_summary and success_count > 0 then
        local message = success_count == 1 and "Added 1 file to Codex context"
          or string.format("Added %d files to Codex context", success_count)
        if total_count > success_count then
          message = message .. string.format(" (%d failed)", total_count - success_count)
        end
        logger.debug(context, message)
      end
    end

    return success_count, total_count
  end

  local function handle_send_normal(opts)
    local current_ft = (vim.bo and vim.bo.filetype) or ""
    local current_bufname = (vim.api and vim.api.nvim_buf_get_name and vim.api.nvim_buf_get_name(0)) or ""

    -- neo-treeのみをツリー表示として判定する
    local is_tree_buffer = current_ft == "neo-tree"
      or string.match(current_bufname, "neo%-tree")

    if is_tree_buffer then
      local integrations = require("codex.integrations")
      local files, error = integrations.get_selected_files_from_tree()

      if error then
        logger.error("command", "CodexSend->TreeAdd: " .. error)
        return
      end

      if not files or #files == 0 then
        logger.warn("command", "CodexSend->TreeAdd: No files selected")
        return
      end

      add_paths_to_codex(files, { context = "CodexSend->TreeAdd" })

      return
    end

    -- ビジュアル選択のマークから、現在バッファの行範囲を安全に取り出す
    local function get_visual_range_from_marks()
      local ok_buf, current_buf = pcall(vim.api.nvim_get_current_buf)
      if not ok_buf or not current_buf then
        return nil, nil
      end

      local ok_start, start_pos = pcall(vim.fn.getpos, "'<")
      local ok_end, end_pos = pcall(vim.fn.getpos, "'>")
      if not ok_start or not ok_end then
        return nil, nil
      end

      if type(start_pos) ~= "table" or type(end_pos) ~= "table" then
        return nil, nil
      end

      local start_buf = start_pos[1] == 0 and current_buf or start_pos[1]
      local end_buf = end_pos[1] == 0 and current_buf or end_pos[1]
      local start_line = start_pos[2]
      local end_line = end_pos[2]

      if start_buf == current_buf and end_buf == current_buf then
        if start_line and end_line and start_line >= 1 and end_line >= 1 then
          if end_line < start_line then
            start_line, end_line = end_line, start_line
          end
          return start_line, end_line
        end
      end

      -- ビジュアルマークが取得できない場合は直前の開始位置と現在カーソル位置から範囲を復元する
      local ok_anchor, anchor_pos = pcall(vim.fn.getpos, "v")
      if not ok_anchor or type(anchor_pos) ~= "table" then
        return nil, nil
      end

      local anchor_buf = anchor_pos[1] == 0 and current_buf or anchor_pos[1]
      local anchor_line = anchor_pos[2]
      if anchor_buf ~= current_buf or not anchor_line or anchor_line < 1 then
        return nil, nil
      end

      local ok_cursor, cursor_pos = pcall(vim.api.nvim_win_get_cursor, 0)
      if not ok_cursor or type(cursor_pos) ~= "table" then
        return nil, nil
      end

      local cursor_line = cursor_pos[1]
      if not cursor_line or cursor_line < 1 then
        return nil, nil
      end

      if cursor_line < anchor_line then
        anchor_line, cursor_line = cursor_line, anchor_line
      end

      return anchor_line, cursor_line
    end

    local selection_module_ok, selection_module = pcall(require, "codex.selection")
    if selection_module_ok then
      -- 可能ならビジュアル範囲を復元し、明示的な範囲選択として送る
      local line1, line2 = nil, nil
      if opts and opts.range and opts.range > 0 then
        line1, line2 = opts.line1, opts.line2
      else
        line1, line2 = get_visual_range_from_marks()
      end
      local sent_successfully = selection_module.send_at_mention_for_visual_selection(line1, line2)
      if sent_successfully then
        -- Exit any potential visual mode (for consistency)
        pcall(function()
          if vim.api and vim.api.nvim_feedkeys then
            local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
            vim.api.nvim_feedkeys(esc, "i", true)
          end
        end)
      end
    else
      logger.error("command", "CodexSend: Failed to load selection module.")
    end
  end

  local function handle_send_visual(visual_data, opts)
    -- Check if we're in a tree buffer first
    local current_ft = (vim.bo and vim.bo.filetype) or ""
    local current_bufname = (vim.api and vim.api.nvim_buf_get_name and vim.api.nvim_buf_get_name(0)) or ""

    -- neo-treeのみをツリー表示として判定する
    local is_tree_buffer = current_ft == "neo-tree"
      or string.match(current_bufname, "neo%-tree")

    if is_tree_buffer then
      local integrations = require("codex.integrations")
      local visual_cmd_module = require("codex.visual_commands")
      local files, error

      -- neo-treeのビジュアル選択を優先して取得する
      files, error = visual_cmd_module.get_files_from_visual_selection(visual_data)
      if (not files or #files == 0) and not error then
        -- ビジュアル選択が取得できない場合は通常選択にフォールバックする
        files, error = integrations.get_selected_files_from_tree()
      end

      if error then
        logger.error("command", "CodexSend_visual->TreeAdd: " .. error)
        return
      end

      if not files or #files == 0 then
        logger.warn("command", "CodexSend_visual->TreeAdd: No files selected")
        return
      end

      add_paths_to_codex(files, { context = "CodexSend_visual->TreeAdd" })
      return
    end

    -- Fall back to old visual selection logic for non-tree buffers
    if visual_data and visual_data.tree_type then
      local visual_commands = require("codex.visual_commands")
      local files, error = visual_commands.get_files_from_visual_selection(visual_data)

      if not error and files and #files > 0 then
        local success_count = add_paths_to_codex(files, {
          delay = 10,
          context = "CodexSend_visual",
          show_summary = false,
        })
        if success_count > 0 then
          local message = success_count == 1 and "Added 1 file to Codex context from visual selection"
            or string.format("Added %d files to Codex context from visual selection", success_count)
          logger.debug("command", message)
        end
        return
      end
    end

    -- Handle regular text selection using range from visual mode
    local selection_module_ok, selection_module = pcall(require, "codex.selection")
    if not selection_module_ok then
      return
    end

    -- Use the marks left by visual mode instead of trying to get current visual selection
    local line1, line2 = nil, nil
    if visual_data and visual_data.start_pos and visual_data.end_pos then
      -- ビジュアル解除前に取得した範囲を優先して送信対象を確定する
      line1, line2 = visual_data.start_pos, visual_data.end_pos
    else
      line1, line2 = vim.fn.line("'<"), vim.fn.line("'>")
    end

    if line1 and line2 and line1 > 0 and line2 > 0 then
      if line2 < line1 then
        line1, line2 = line2, line1
      end
      -- この範囲を使ってCodexへ選択範囲の内容を送信する
      selection_module.send_at_mention_for_visual_selection(line1, line2)
    else
      selection_module.send_at_mention_for_visual_selection()
    end
  end

  local visual_commands = require("codex.visual_commands")
  local unified_send_handler = visual_commands.create_visual_command_wrapper(handle_send_normal, handle_send_visual)

  vim.api.nvim_create_user_command("CodexSend", unified_send_handler, {
    desc = "Send current visual selection as an at_mention to Codex (supports tree visual selection)",
    range = true,
  })

  local function handle_tree_add_normal()
    if not M.state.server then
      logger.error("command", "CodexTreeAdd: Codex integration is not running.")
      return
    end

    local integrations = require("codex.integrations")
    local files, error = integrations.get_selected_files_from_tree()

    if error then
      logger.error("command", "CodexTreeAdd: " .. error)
      return
    end

    if not files or #files == 0 then
      logger.warn("command", "CodexTreeAdd: No files selected")
      return
    end

    -- Use connection-aware broadcasting for each file
    local success_count = 0
    local total_count = #files

    for _, file_path in ipairs(files) do
      local success, error_msg = M.send_at_mention(file_path, nil, nil, "CodexTreeAdd")
      if success then
        success_count = success_count + 1
      else
        logger.error(
          "command",
          "CodexTreeAdd: Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error")
        )
      end
    end

    if success_count == 0 then
      logger.error("command", "CodexTreeAdd: Failed to add any files")
    elseif success_count < total_count then
      local message = string.format("Added %d/%d files to Codex context", success_count, total_count)
      logger.debug("command", message)
    else
      local message = success_count == 1 and "Added 1 file to Codex context"
        or string.format("Added %d files to Codex context", success_count)
      logger.debug("command", message)
    end
  end

  local function handle_tree_add_visual(visual_data)
    if not M.state.server then
      logger.error("command", "CodexTreeAdd_visual: Codex integration is not running.")
      return
    end

    local visual_cmd_module = require("codex.visual_commands")
    local files, error = visual_cmd_module.get_files_from_visual_selection(visual_data)

    if error then
      logger.error("command", "CodexTreeAdd_visual: " .. error)
      return
    end

    if not files or #files == 0 then
      logger.warn("command", "CodexTreeAdd_visual: No files selected in visual range")
      return
    end

    -- Use connection-aware broadcasting for each file
    local success_count = 0
    local total_count = #files

    for _, file_path in ipairs(files) do
      local success, error_msg = M.send_at_mention(file_path, nil, nil, "CodexTreeAdd_visual")
      if success then
        success_count = success_count + 1
      else
        logger.error(
          "command",
          "CodexTreeAdd_visual: Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error")
        )
      end
    end

    if success_count > 0 then
      local message = success_count == 1 and "Added 1 file to Codex context from visual selection"
        or string.format("Added %d files to Codex context from visual selection", success_count)
      logger.debug("command", message)

      if success_count < total_count then
        logger.warn("command", string.format("Added %d/%d files from visual selection", success_count, total_count))
      end
    else
      logger.error("command", "CodexTreeAdd_visual: Failed to add any files from visual selection")
    end
  end

  local unified_tree_add_handler =
    visual_commands.create_visual_command_wrapper(handle_tree_add_normal, handle_tree_add_visual)

  vim.api.nvim_create_user_command("CodexTreeAdd", unified_tree_add_handler, {
    desc = "Add selected file(s) from tree explorer to Codex context (supports visual selection)",
  })

  vim.api.nvim_create_user_command("CodexAdd", function(opts)
    if not M.state.server then
      logger.error("command", "CodexAdd: Codex integration is not running.")
      return
    end

    if not opts.args or opts.args == "" then
      logger.error("command", "CodexAdd: No file path provided")
      return
    end

    local args = vim.split(opts.args, "%s+")
    local file_path = args[1]
    local start_line = args[2] and tonumber(args[2]) or nil
    local end_line = args[3] and tonumber(args[3]) or nil

    if #args > 3 then
      logger.error(
        "command",
        "CodexAdd: Too many arguments. Usage: CodexAdd <file-path> [start-line] [end-line]"
      )
      return
    end

    if args[2] and not start_line then
      logger.error("command", "CodexAdd: Invalid start line number: " .. args[2])
      return
    end

    if args[3] and not end_line then
      logger.error("command", "CodexAdd: Invalid end line number: " .. args[3])
      return
    end

    if start_line and start_line < 1 then
      logger.error("command", "CodexAdd: Start line must be positive: " .. start_line)
      return
    end

    if end_line and end_line < 1 then
      logger.error("command", "CodexAdd: End line must be positive: " .. end_line)
      return
    end

    if start_line and end_line and start_line > end_line then
      logger.error(
        "command",
        "CodexAdd: Start line (" .. start_line .. ") must be <= end line (" .. end_line .. ")"
      )
      return
    end

    file_path = vim.fn.expand(file_path)
    if vim.fn.filereadable(file_path) == 0 and vim.fn.isdirectory(file_path) == 0 then
      logger.error("command", "CodexAdd: File or directory does not exist: " .. file_path)
      return
    end

    local codex_start_line = start_line and (start_line - 1) or nil
    local codex_end_line = end_line and (end_line - 1) or nil

    local success, error_msg = M.send_at_mention(file_path, codex_start_line, codex_end_line, "CodexAdd")
    if not success then
      logger.error("command", "CodexAdd: " .. (error_msg or "Failed to add file"))
    else
      local message = "CodexAdd: Successfully added " .. file_path
      if start_line or end_line then
        if start_line and end_line then
          message = message .. " (lines " .. start_line .. "-" .. end_line .. ")"
        elseif start_line then
          message = message .. " (from line " .. start_line .. ")"
        end
      end
      logger.debug("command", message)
    end
  end, {
    nargs = "+",
    complete = "file",
    desc = "Add specified file or directory to Codex context with optional line range",
  })

  local terminal_ok, terminal = pcall(require, "codex.terminal")
  if terminal_ok then
    vim.api.nvim_create_user_command("Codex", function(opts)
      local current_mode = vim.fn.mode()
      if current_mode == "v" or current_mode == "V" or current_mode == "\22" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      end
      local cmd_args = opts.args and opts.args ~= "" and opts.args or nil
      terminal.simple_toggle({}, cmd_args)
    end, {
      nargs = "*",
      desc = "Toggle the Codex terminal window (simple show/hide) with optional arguments",
    })

    vim.api.nvim_create_user_command("CodexFocus", function(opts)
      local current_mode = vim.fn.mode()
      if current_mode == "v" or current_mode == "V" or current_mode == "\22" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      end
      local cmd_args = opts.args and opts.args ~= "" and opts.args or nil
      terminal.focus_toggle({}, cmd_args)
    end, {
      nargs = "*",
      desc = "Smart focus/toggle Codex terminal (switches to terminal if not focused, hides if focused)",
    })

    vim.api.nvim_create_user_command("CodexOpen", function(opts)
      local cmd_args = opts.args and opts.args ~= "" and opts.args or nil
      terminal.open({}, cmd_args)
    end, {
      nargs = "*",
      desc = "Open the Codex terminal window with optional arguments",
    })

    vim.api.nvim_create_user_command("CodexClose", function()
      terminal.close()
    end, {
      desc = "Close the Codex terminal window",
    })
  else
    logger.error(
      "init",
      "Terminal module not found. Terminal commands (Codex, CodexOpen, CodexClose) not registered."
    )
  end

  -- Diff management commands
  vim.api.nvim_create_user_command("CodexDiffAccept", function()
    local diff = require("codex.diff")
    diff.accept_current_diff()
  end, {
    desc = "Accept the current diff changes",
  })

  vim.api.nvim_create_user_command("CodexDiffDeny", function()
    local diff = require("codex.diff")
    diff.deny_current_diff()
  end, {
    desc = "Deny/reject the current diff changes",
  })

  vim.api.nvim_create_user_command("CodexSelectModel", function(opts)
    local cmd_args = opts.args and opts.args ~= "" and opts.args or nil
    M.open_with_model(cmd_args)
  end, {
    nargs = "*",
    desc = "Select and open Codex terminal with chosen model and optional arguments",
  })
end

M.open_with_model = function(additional_args)
  local models = M.state.config.models

  if not models or #models == 0 then
    logger.error("command", "No models configured for selection")
    return
  end

  vim.ui.select(models, {
    prompt = "Select Codex model:",
    format_item = function(item)
      return item.name
    end,
  }, function(choice)
    if not choice then
      return -- User cancelled
    end

    if not choice.value or type(choice.value) ~= "string" then
      logger.error("command", "Invalid model value selected")
      return
    end

    local model_arg = choice.value ~= "" and ("--model " .. choice.value) or ""
    local final_args
    if model_arg ~= "" then
      final_args = additional_args and (model_arg .. " " .. additional_args) or model_arg
    else
      final_args = additional_args or ""
    end

    if final_args ~= "" then
      vim.cmd("Codex " .. final_args)
    else
      vim.cmd("Codex")
    end
  end)
end

---Codex ターミナルをトグルする（ウィンドウの開閉を行う）。
---@param cmd_args string|nil Codex CLI に追加で渡す引数
function M.toggle(cmd_args)
  local terminal = require("codex.terminal")
  terminal.simple_toggle({}, cmd_args)
end

---Codex 操作用の軽量アクション群。
M.actions = {
  ---選択範囲を Codex に送信する（現在の選択やツリー選択を解釈する）。
  send_selection = function()
    vim.cmd("CodexSend")
  end,
  ---Codex ターミナルへ任意の文字列を送信する（ターミナルへ入力する）。
  ---@param text string
  ---@param opts table|nil
  ---@return boolean sent
  send = function(text, opts)
    local terminal = require("codex.terminal")
    return terminal.send(text, opts)
  end,
}

---Get version information
---@return { version: string, major: integer, minor: integer, patch: integer, prerelease: string|nil }
function M.get_version()
  return {
    version = M.version:string(),
    major = M.version.major,
    minor = M.version.minor,
    patch = M.version.patch,
    prerelease = M.version.prerelease,
  }
end

---Format file path for at mention (exposed for testing)
---@param file_path string The file path to format
---@return string formatted_path The formatted path
---@return boolean is_directory Whether the path is a directory
function M._format_path_for_at_mention(file_path)
  -- Input validation
  if not file_path or type(file_path) ~= "string" or file_path == "" then
    error("format_path_for_at_mention: file_path must be a non-empty string")
  end

  -- Only check path existence in production (not tests)
  -- This allows tests to work with mock paths while still providing validation in real usage
  if not package.loaded["busted"] then
    if vim.fn.filereadable(file_path) == 0 and vim.fn.isdirectory(file_path) == 0 then
      error("format_path_for_at_mention: path does not exist: " .. file_path)
    end
  end

  local is_directory = vim.fn.isdirectory(file_path) == 1
  local formatted_path = file_path

  if is_directory then
    local cwd = vim.fn.getcwd()
    if string.find(file_path, cwd, 1, true) == 1 then
      local relative_path = string.sub(file_path, #cwd + 2)
      if relative_path ~= "" then
        formatted_path = relative_path
      else
        formatted_path = "./"
      end
    end
    if not string.match(formatted_path, "/$") then
      formatted_path = formatted_path .. "/"
    end
  else
    local cwd = vim.fn.getcwd()
    if string.find(file_path, cwd, 1, true) == 1 then
      local relative_path = string.sub(file_path, #cwd + 2)
      if relative_path ~= "" then
        formatted_path = relative_path
      end
    end
  end

  return formatted_path, is_directory
end

---Test helper functions (exposed for testing)
function M._broadcast_at_mention(file_path, start_line, end_line)
  if not M.state.server then
    return false, "Codex integration is not running"
  end

  -- Safely format the path and handle validation errors
  local formatted_path, is_directory
  local format_success, format_result, is_dir_result = pcall(M._format_path_for_at_mention, file_path)
  if not format_success then
    return false, format_result -- format_result contains the error message
  end
  formatted_path, is_directory = format_result, is_dir_result

  if is_directory and (start_line or end_line) then
    logger.debug("command", "Line numbers ignored for directory: " .. formatted_path)
    start_line = nil
    end_line = nil
  end

  local params = {
    filePath = formatted_path,
    lineStart = start_line,
    lineEnd = end_line,
  }

  -- For tests or when explicitly configured, broadcast immediately without queuing
  if
    (M.state.config and M.state.config.disable_broadcast_debouncing)
    or (package.loaded["busted"] and not (M.state.config and M.state.config.enable_broadcast_debouncing_in_tests))
  then
    local broadcast_success = M.state.server.broadcast("at_mentioned", params)
    if broadcast_success then
      return true, nil
    else
      local error_msg = "Failed to broadcast " .. (is_directory and "directory" or "file") .. " " .. formatted_path
      logger.error("command", error_msg)
      return false, error_msg
    end
  end

  -- Use mention queue system for debounced broadcasting
  queue_mention(formatted_path, start_line, end_line)

  -- Always return success since we're queuing the message
  -- The actual broadcast result will be logged in the queue processing
  return true, nil
end

function M._add_paths_to_codex(file_paths, options)
  options = options or {}
  local delay = options.delay or 0
  local show_summary = options.show_summary ~= false
  local context = options.context or "command"
  local batch_size = options.batch_size or 10
  local max_files = options.max_files or 100

  if not file_paths or #file_paths == 0 then
    return 0, 0
  end

  if #file_paths > max_files then
    logger.warn(context, string.format("Too many files selected (%d), limiting to %d", #file_paths, max_files))
    local limited_paths = {}
    for i = 1, max_files do
      limited_paths[i] = file_paths[i]
    end
    file_paths = limited_paths
  end

  local success_count = 0
  local total_count = #file_paths

  if delay > 0 then
    local function send_batch(start_index)
      if start_index > total_count then
        if show_summary then
          local message = success_count == 1 and "Added 1 file to Codex context"
            or string.format("Added %d files to Codex context", success_count)
          if total_count > success_count then
            message = message .. string.format(" (%d failed)", total_count - success_count)
          end

          if total_count > success_count then
            if success_count > 0 then
              logger.warn(context, message)
            else
              logger.error(context, message)
            end
          elseif success_count > 0 then
            logger.info(context, message)
          else
            logger.debug(context, message)
          end
        end
        return
      end

      -- Process a batch of files
      local end_index = math.min(start_index + batch_size - 1, total_count)
      local batch_success = 0

      for i = start_index, end_index do
        local file_path = file_paths[i]
        local success, error_msg = M._broadcast_at_mention(file_path)
        if success then
          success_count = success_count + 1
          batch_success = batch_success + 1
        else
          logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
        end
      end

      logger.debug(
        context,
        string.format(
          "Processed batch %d-%d: %d/%d successful",
          start_index,
          end_index,
          batch_success,
          end_index - start_index + 1
        )
      )

      if end_index < total_count then
        vim.defer_fn(function()
          send_batch(end_index + 1)
        end, delay)
      else
        if show_summary then
          local message = success_count == 1 and "Added 1 file to Codex context"
            or string.format("Added %d files to Codex context", success_count)
          if total_count > success_count then
            message = message .. string.format(" (%d failed)", total_count - success_count)
          end

          if total_count > success_count then
            if success_count > 0 then
              logger.warn(context, message)
            else
              logger.error(context, message)
            end
          elseif success_count > 0 then
            logger.info(context, message)
          else
            logger.debug(context, message)
          end
        end
      end
    end

    send_batch(1)
  else
    local progress_interval = math.max(1, math.floor(total_count / 10))

    for i, file_path in ipairs(file_paths) do
      local success, error_msg = M._broadcast_at_mention(file_path)
      if success then
        success_count = success_count + 1
      else
        logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
      end

      if total_count > 20 and i % progress_interval == 0 then
        logger.debug(
          context,
          string.format("Progress: %d/%d files processed (%d successful)", i, total_count, success_count)
        )
      end
    end

    if show_summary then
      local message = success_count == 1 and "Added 1 file to Codex context"
        or string.format("Added %d files to Codex context", success_count)
      if total_count > success_count then
        message = message .. string.format(" (%d failed)", total_count - success_count)
      end

      if total_count > success_count then
        if success_count > 0 then
          logger.warn(context, message)
        else
          logger.error(context, message)
        end
      elseif success_count > 0 then
        logger.info(context, message)
      else
        logger.debug(context, message)
      end
    end
  end

  return success_count, total_count
end

return M
