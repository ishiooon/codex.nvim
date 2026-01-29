-- このファイルはCodex.nvimの設定既定値と検証処理を定義し、安全に設定を適用します。
---@brief [[
--- Manages configuration for the Codex Neovim integration.
--- Provides default settings, validation, and application of user-defined configurations.
---@brief ]]
---@module 'codex.config'

local M = {}
local status_indicator_config = require("codex.status_indicator_config")

---@type CodexConfig
M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,
  env = {}, -- Custom environment variables for Codex terminal
  log_level = "info",
  -- 認証が必須でないCLIにも接続できるよう、既定はoptionalにする
  auth_mode = "optional",
  -- Codex未接続時にターミナルへ本文を送るかどうか
  fallback_to_terminal_send = true,
  track_selection = true,
  -- When true, focus Codex terminal after a successful send while connected
  focus_after_send = false,
  visual_demotion_delay_ms = 50, -- Milliseconds to wait before demoting a visual selection
  connection_wait_delay = 600, -- Milliseconds to wait after connection before sending queued @ mentions
  connection_timeout = 10000, -- Maximum time to wait for Codex to connect (milliseconds)
  queue_timeout = 5000, -- Maximum time to keep @ mentions in queue (milliseconds)
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false, -- Open diff in a new tab (false = use current tab)
    keep_terminal_focus = false, -- If true, moves focus back to terminal after diff opens
    hide_terminal_in_new_tab = false, -- If true and opening in a new tab, do not show Codex terminal there
    on_new_file_reject = "keep_empty", -- "keep_empty" leaves an empty buffer; "close_window" closes the placeholder split
  },
  models = {
    { name = "デフォルト（Codex CLI の設定に従う）", value = "" },
  },
  -- Codexの既定キーマップ定義
  keymaps = {
    enabled = true,
    mappings = {
      { mode = "n", lhs = "<leader>cc", rhs = "<cmd>Codex<cr>", desc = "Codex: Toggle" },
      { mode = "n", lhs = "<leader>cf", rhs = "<cmd>CodexFocus<cr>", desc = "Codex: Focus" },
      -- 既定キーマップは動作確認済みのコマンドに限定する
      { mode = "v", lhs = "<leader>cs", rhs = "<cmd>CodexSend<cr>", desc = "Codex: 選択範囲を送信" },
      {
        mode = "n",
        lhs = "<leader>cs",
        rhs = "<cmd>CodexTreeAdd<cr>",
        desc = "Codex: ファイルを追加",
        -- neo-treeとoil.nvimを対象にする
        filetypes = { "neo-tree", "oil" },
      },
      -- 差分操作のキーマップは必要に応じて利用者側で追加する
    },
  },
  -- 画面右下に表示する状態アイコンの設定
  status_indicator = status_indicator_config.defaults,
  terminal = nil, -- Will be lazy-loaded to avoid circular dependency
}

---Validates the provided configuration table.
---Throws an error if any validation fails.
---@param config table The configuration table to validate.
---@return boolean true if the configuration is valid.
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  assert(config.terminal_cmd == nil or type(config.terminal_cmd) == "string", "terminal_cmd must be nil or a string")

  -- Validate terminal config
  assert(type(config.terminal) == "table", "terminal must be a table")

  -- Validate provider_opts if present
  if config.terminal.provider_opts then
    assert(type(config.terminal.provider_opts) == "table", "terminal.provider_opts must be a table")

    -- Validate external_terminal_cmd in provider_opts
    if config.terminal.provider_opts.external_terminal_cmd then
      local cmd_type = type(config.terminal.provider_opts.external_terminal_cmd)
      assert(
        cmd_type == "string" or cmd_type == "function",
        "terminal.provider_opts.external_terminal_cmd must be a string or function"
      )
      -- Only validate %s placeholder for strings
      if cmd_type == "string" and config.terminal.provider_opts.external_terminal_cmd ~= "" then
        assert(
          config.terminal.provider_opts.external_terminal_cmd:find("%%s"),
          "terminal.provider_opts.external_terminal_cmd must contain '%s' placeholder for the Codex command"
        )
      end
    end
  end

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  local valid_auth_modes = { "required", "optional", "disabled" }
  local is_valid_auth_mode = false
  local auth_mode = config.auth_mode or "optional"
  for _, mode in ipairs(valid_auth_modes) do
    if auth_mode == mode then
      is_valid_auth_mode = true
      break
    end
  end
  assert(is_valid_auth_mode, "auth_mode must be one of: " .. table.concat(valid_auth_modes, ", "))

  if config.fallback_to_terminal_send ~= nil then
    assert(type(config.fallback_to_terminal_send) == "boolean", "fallback_to_terminal_send must be a boolean")
  end

  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")
  -- Allow absence in direct validate() calls; apply() supplies default
  if config.focus_after_send ~= nil then
    assert(type(config.focus_after_send) == "boolean", "focus_after_send must be a boolean")
  end

  assert(
    type(config.visual_demotion_delay_ms) == "number" and config.visual_demotion_delay_ms >= 0,
    "visual_demotion_delay_ms must be a non-negative number"
  )

  assert(
    type(config.connection_wait_delay) == "number" and config.connection_wait_delay >= 0,
    "connection_wait_delay must be a non-negative number"
  )

  assert(
    type(config.connection_timeout) == "number" and config.connection_timeout > 0,
    "connection_timeout must be a positive number"
  )

  assert(type(config.queue_timeout) == "number" and config.queue_timeout > 0, "queue_timeout must be a positive number")

  assert(type(config.diff_opts) == "table", "diff_opts must be a table")
  -- New diff options (optional validation to allow backward compatibility)
  if config.diff_opts.layout ~= nil then
    assert(
      config.diff_opts.layout == "vertical" or config.diff_opts.layout == "horizontal",
      "diff_opts.layout must be 'vertical' or 'horizontal'"
    )
  end
  if config.diff_opts.open_in_new_tab ~= nil then
    assert(type(config.diff_opts.open_in_new_tab) == "boolean", "diff_opts.open_in_new_tab must be a boolean")
  end
  if config.diff_opts.keep_terminal_focus ~= nil then
    assert(type(config.diff_opts.keep_terminal_focus) == "boolean", "diff_opts.keep_terminal_focus must be a boolean")
  end
  if config.diff_opts.hide_terminal_in_new_tab ~= nil then
    assert(
      type(config.diff_opts.hide_terminal_in_new_tab) == "boolean",
      "diff_opts.hide_terminal_in_new_tab must be a boolean"
    )
  end
  if config.diff_opts.on_new_file_reject ~= nil then
    assert(
      type(config.diff_opts.on_new_file_reject) == "string"
        and (
          config.diff_opts.on_new_file_reject == "keep_empty" or config.diff_opts.on_new_file_reject == "close_window"
        ),
      "diff_opts.on_new_file_reject must be 'keep_empty' or 'close_window'"
    )
  end

  -- Legacy diff options (accept if present to avoid breaking old configs)
  if config.diff_opts.auto_close_on_accept ~= nil then
    assert(type(config.diff_opts.auto_close_on_accept) == "boolean", "diff_opts.auto_close_on_accept must be a boolean")
  end
  if config.diff_opts.show_diff_stats ~= nil then
    assert(type(config.diff_opts.show_diff_stats) == "boolean", "diff_opts.show_diff_stats must be a boolean")
  end
  if config.diff_opts.vertical_split ~= nil then
    assert(type(config.diff_opts.vertical_split) == "boolean", "diff_opts.vertical_split must be a boolean")
  end
  if config.diff_opts.open_in_current_tab ~= nil then
    assert(type(config.diff_opts.open_in_current_tab) == "boolean", "diff_opts.open_in_current_tab must be a boolean")
  end

  -- Validate env
  assert(type(config.env) == "table", "env must be a table")
  for key, value in pairs(config.env) do
    assert(type(key) == "string", "env keys must be strings")
    assert(type(value) == "string", "env values must be strings")
  end

  -- Validate models
  assert(type(config.models) == "table", "models must be a table")
  assert(#config.models > 0, "models must not be empty")

  for i, model in ipairs(config.models) do
    assert(type(model) == "table", "models[" .. i .. "] must be a table")
    assert(type(model.name) == "string" and model.name ~= "", "models[" .. i .. "].name must be a non-empty string")
    assert(type(model.value) == "string", "models[" .. i .. "].value must be a string")
  end

  -- キーマップ設定は無効化を許容し、必要項目だけを検証する
  if config.keymaps ~= nil then
    assert(type(config.keymaps) == "table" or config.keymaps == false, "keymaps must be a table or false")
    if type(config.keymaps) == "table" then
      if config.keymaps.enabled ~= nil then
        assert(type(config.keymaps.enabled) == "boolean", "keymaps.enabled must be a boolean")
      end
      if config.keymaps.mappings ~= nil then
        assert(type(config.keymaps.mappings) == "table", "keymaps.mappings must be a table")
        for i, mapping in ipairs(config.keymaps.mappings) do
          assert(type(mapping) == "table", "keymaps.mappings[" .. i .. "] must be a table")
          assert(type(mapping.lhs) == "string", "keymaps.mappings[" .. i .. "].lhs must be a string")
          local rhs_type = type(mapping.rhs)
          assert(rhs_type == "string" or rhs_type == "function", "keymaps.mappings[" .. i .. "].rhs must be a string or function")
          if mapping.mode ~= nil then
            assert(type(mapping.mode) == "string" or type(mapping.mode) == "table", "keymaps.mappings[" .. i .. "].mode must be a string or table")
          end
          if mapping.filetypes ~= nil then
            assert(type(mapping.filetypes) == "table", "keymaps.mappings[" .. i .. "].filetypes must be a table")
          end
        end
      end
    end
  end

  if config.status_indicator ~= nil then
    assert(type(config.status_indicator) == "table", "status_indicator must be a table")
    if config.status_indicator.enabled ~= nil then
      assert(type(config.status_indicator.enabled) == "boolean", "status_indicator.enabled must be a boolean")
    end
    if config.status_indicator.update_interval_ms ~= nil then
      assert(
        type(config.status_indicator.update_interval_ms) == "number" and config.status_indicator.update_interval_ms > 0,
        "status_indicator.update_interval_ms must be a positive number"
      )
    end
    if config.status_indicator.busy_grace_ms ~= nil then
      -- 最後の通信から動作中表示を維持する猶予時間の検証
      assert(
        type(config.status_indicator.busy_grace_ms) == "number" and config.status_indicator.busy_grace_ms >= 0,
        "status_indicator.busy_grace_ms must be a non-negative number"
      )
    end
    if config.status_indicator.cli_activity_grace_ms ~= nil then
      -- CLIの入出力から動作中表示を維持する猶予時間の検証
      assert(
        type(config.status_indicator.cli_activity_grace_ms) == "number"
          and config.status_indicator.cli_activity_grace_ms >= 0,
        "status_indicator.cli_activity_grace_ms must be a non-negative number"
      )
    end
    if config.status_indicator.turn_active_timeout_ms ~= nil then
      -- 応答処理を継続表示する上限時間の検証
      assert(
        type(config.status_indicator.turn_active_timeout_ms) == "number"
          and config.status_indicator.turn_active_timeout_ms >= 0,
        "status_indicator.turn_active_timeout_ms must be a non-negative number"
      )
    end
    if config.status_indicator.turn_idle_grace_ms ~= nil then
      -- 応答停止後に動作中表示を解除する猶予時間の検証
      assert(
        type(config.status_indicator.turn_idle_grace_ms) == "number"
          and config.status_indicator.turn_idle_grace_ms >= 0,
        "status_indicator.turn_idle_grace_ms must be a non-negative number"
      )
    end
    if config.status_indicator.inflight_timeout_ms ~= nil then
      -- 実行中リクエストの停止判定の猶予時間の検証
      assert(
        type(config.status_indicator.inflight_timeout_ms) == "number"
          and config.status_indicator.inflight_timeout_ms >= 0,
        "status_indicator.inflight_timeout_ms must be a non-negative number"
      )
    end
    if config.status_indicator.cli_notify_path ~= nil then
      -- CLI通知ファイルパスの検証
      assert(
        type(config.status_indicator.cli_notify_path) == "string",
        "status_indicator.cli_notify_path must be a string"
      )
    end
    if config.status_indicator.offset_row ~= nil then
      assert(type(config.status_indicator.offset_row) == "number", "status_indicator.offset_row must be a number")
    end
    if config.status_indicator.offset_col ~= nil then
      assert(type(config.status_indicator.offset_col) == "number", "status_indicator.offset_col must be a number")
    end
    if config.status_indicator.icons ~= nil then
      assert(type(config.status_indicator.icons) == "table", "status_indicator.icons must be a table")
    end
    if config.status_indicator.colors ~= nil then
      assert(type(config.status_indicator.colors) == "table", "status_indicator.colors must be a table")
    end
  end

  return true
end

---Applies user configuration on top of default settings and validates the result.
---@param user_config table|nil The user-provided configuration table.
---@return CodexConfig config The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  -- Lazy-load terminal defaults to avoid circular dependency
  if config.terminal == nil then
    local terminal_ok, terminal_module = pcall(require, "codex.terminal")
    if terminal_ok and terminal_module.defaults then
      config.terminal = terminal_module.defaults
    end
  end

  if user_config then
    -- Use vim.tbl_deep_extend if available, otherwise simple merge
    if vim.tbl_deep_extend then
      config = vim.tbl_deep_extend("force", config, user_config)
    else
      -- Simple fallback for testing environment
      for k, v in pairs(user_config) do
        config[k] = v
      end
    end
  end

  -- Backward compatibility: map legacy diff options to new fields if provided
  if config.diff_opts then
    local d = config.diff_opts
    -- Map vertical_split -> layout (legacy option takes precedence)
    if type(d.vertical_split) == "boolean" then
      d.layout = d.vertical_split and "vertical" or "horizontal"
    end
    -- Map open_in_current_tab -> open_in_new_tab (legacy option takes precedence)
    if type(d.open_in_current_tab) == "boolean" then
      d.open_in_new_tab = not d.open_in_current_tab
    end
  end

  if config.status_indicator
    and type(config.status_indicator.cli_notify_path) == "string"
    and config.status_indicator.cli_notify_path ~= ""
  then
    -- CLI通知ファイルパスを環境変数に反映する
    config.env = config.env or {}
    if config.env.CODEX_NVIM_NOTIFY_PATH == nil then
      config.env.CODEX_NVIM_NOTIFY_PATH = config.status_indicator.cli_notify_path
    end
  end

  M.validate(config)

  return config
end

return M
