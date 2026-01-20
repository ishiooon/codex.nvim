-- このファイルはCodex.nvimで利用する型定義をまとめています。
---@meta
---@brief [[
--- Centralized type definitions for Codex.nvim public API.
--- This module contains all user-facing types and configuration structures.
---@brief ]]
---@module 'codex.types'

-- Version information type
---@class CodexVersion
---@field major integer
---@field minor integer
---@field patch integer
---@field prerelease? string
---@field string fun(self: CodexVersion): string

-- Diff behavior configuration
---@class CodexDiffOptions
---@field layout CodexDiffLayout
---@field open_in_new_tab boolean Open diff in a new tab (false = use current tab)
---@field keep_terminal_focus boolean Keep focus in terminal after opening diff
---@field hide_terminal_in_new_tab boolean Hide Codex terminal in newly created diff tab
---@field on_new_file_reject CodexNewFileRejectBehavior Behavior when rejecting a new-file diff

-- Model selection option
---@class CodexModelOption
---@field name string
---@field value string

-- キーマップ設定
---@class CodexKeymap
---@field mode string|string[]|nil
---@field lhs string
---@field rhs string|function
---@field desc string|nil
---@field opts table|nil
---@field filetypes string[]|nil

---@class CodexKeymapsConfig
---@field enabled boolean
---@field mappings CodexKeymap[]

-- Log level type alias
---@alias CodexLogLevel "trace"|"debug"|"info"|"warn"|"error"

-- Diff layout type alias
---@alias CodexDiffLayout "vertical"|"horizontal"

-- Behavior when rejecting new-file diffs
---@alias CodexNewFileRejectBehavior "keep_empty"|"close_window"

-- Terminal split side positioning
---@alias CodexSplitSide "left"|"right"

-- In-tree terminal provider names
---@alias CodexTerminalProviderName "auto"|"snacks"|"native"|"external"|"none"

-- Terminal provider-specific options
---@class CodexTerminalProviderOptions
---@field external_terminal_cmd string|(fun(cmd: string, env: table): string)|table|nil Command for external terminal (string template with %s or function)

-- Working directory resolution context and provider
---@class CodexCwdContext
---@field file string|nil   -- absolute path of current buffer file (if any)
---@field file_dir string|nil -- directory of current buffer file (if any)
---@field cwd string        -- current Neovim working directory

---@alias CodexCwdProvider fun(ctx: CodexCwdContext): string|nil

-- @ mention queued for Codex
---@class CodexMention
---@field file_path string The absolute file path to mention
---@field start_line number? Optional start line (0-indexed for Codex compatibility)
---@field end_line number? Optional end line (0-indexed for Codex compatibility)
---@field timestamp number Creation timestamp from vim.loop.now() for expiry tracking

-- Terminal provider interface
---@class CodexTerminalProvider
---@field setup fun(config: CodexTerminalConfig)
---@field open fun(cmd_string: string, env_table: table, config: CodexTerminalConfig, focus: boolean?)
---@field close fun()
---@field toggle fun(cmd_string: string, env_table: table, effective_config: CodexTerminalConfig)
---@field simple_toggle fun(cmd_string: string, env_table: table, effective_config: CodexTerminalConfig)
---@field focus_toggle fun(cmd_string: string, env_table: table, effective_config: CodexTerminalConfig)
---@field get_active_bufnr fun(): number?
---@field is_available fun(): boolean
---@field ensure_visible? function
---@field _get_terminal_for_test fun(): table?

-- Terminal configuration
---@class CodexTerminalConfig
---@field split_side CodexSplitSide
---@field split_width_percentage number
---@field provider CodexTerminalProviderName|CodexTerminalProvider
---@field show_native_term_exit_tip boolean
---@field terminal_cmd string?
---@field provider_opts CodexTerminalProviderOptions?
---@field auto_close boolean
---@field env table<string, string>
---@field snacks_win_opts snacks.win.Config
---@field cwd string|nil                 -- static working directory for Codex terminal
---@field git_repo_cwd boolean|nil      -- use git root of current file/cwd as working directory
---@field cwd_provider? CodexCwdProvider -- custom function to compute working directory
---@field unfocus_key string|false|nil  -- Codex ターミナルから前のウィンドウへ戻るためのキー
---@field unfocus_mapping string|nil    -- ターミナルモードで実行する移動コマンド

-- Port range configuration
---@class CodexPortRange
---@field min integer
---@field max integer

-- Server status information
---@class CodexServerStatus
---@field running boolean
---@field port integer?
---@field client_count integer
---@field clients? table<string, any>

-- Main configuration structure
---@class CodexConfig
---@field port_range CodexPortRange
---@field auto_start boolean
---@field terminal_cmd string|nil
---@field env table<string, string>
---@field log_level CodexLogLevel
---@field auth_mode "required"|"optional"|"disabled" -- 認証ヘッダーの扱い方針
---@field fallback_to_terminal_send boolean -- Codex未接続時にターミナルへ送信するかどうか
---@field track_selection boolean
---@field focus_after_send boolean
---@field visual_demotion_delay_ms number
---@field connection_wait_delay number
---@field connection_timeout number
---@field queue_timeout number
---@field diff_opts CodexDiffOptions
---@field models CodexModelOption[]
---@field keymaps CodexKeymapsConfig|false|nil
---@field disable_broadcast_debouncing? boolean
---@field enable_broadcast_debouncing_in_tests? boolean
---@field terminal CodexTerminalConfig?

---@class (partial) PartialCodexConfig: CodexConfig

-- Server interface for main module
---@class CodexServerFacade
---@field start fun(config: CodexConfig, auth_token: string|nil): (success: boolean, port_or_error: number|string)
---@field stop fun(): (success: boolean, error_message: string?)
---@field broadcast fun(method: string, params: table?): boolean
---@field get_status fun(): CodexServerStatus

-- Main module state
---@class CodexState
---@field config CodexConfig
---@field server CodexServerFacade|nil
---@field port integer|nil
---@field auth_token string|nil
---@field initialized boolean
---@field mention_queue CodexMention[]
---@field mention_timer uv.uv_timer_t?  -- (compatible with vim.loop timer)
---@field connection_timer uv.uv_timer_t?  -- (compatible with vim.loop timer)

-- This module only defines types, no runtime functionality
return {}
