-- このファイルはコマンド引数処理の結合テストを行います。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Codex command arguments integration", function()
  local codex
  local mock_server
  local mock_lockfile
  local mock_selection
  local executed_commands
  local original_require

  before_each(function()
    executed_commands = {}
    local terminal_jobs = {}

    -- Mock vim.fn.termopen to capture actual commands and properly simulate terminal lifecycle
    vim.fn.termopen = function(cmd, opts)
      local job_id = 123 + #terminal_jobs
      table.insert(executed_commands, {
        cmd = cmd,
        opts = opts,
      })

      -- Store the job for cleanup
      table.insert(terminal_jobs, {
        id = job_id,
        on_exit = opts and opts.on_exit,
      })

      -- In headless test mode, immediately schedule the terminal exit
      -- This simulates the terminal closing right away to prevent hanging
      if opts and opts.on_exit then
        vim.schedule(function()
          opts.on_exit(job_id, 0, "exit")
        end)
      end

      return job_id
    end

    vim.fn.mode = function()
      return "n"
    end

    vim.o = {
      columns = 120,
      lines = 30,
    }

    vim.api.nvim_feedkeys = function() end
    vim.api.nvim_replace_termcodes = function(str)
      return str
    end
    local create_user_command_calls = {}
    vim.api.nvim_create_user_command = setmetatable({
      calls = create_user_command_calls,
    }, {
      __call = function(self, ...)
        table.insert(create_user_command_calls, { vals = { ... } })
      end,
    })
    vim.api.nvim_create_autocmd = function() end
    vim.api.nvim_create_augroup = function()
      return 1
    end
    vim.api.nvim_get_current_win = function()
      return 1
    end
    vim.api.nvim_set_current_win = function() end
    vim.api.nvim_win_set_height = function() end
    vim.api.nvim_win_call = function(winid, func)
      func()
    end
    vim.api.nvim_get_current_buf = function()
      return 1
    end
    vim.api.nvim_win_close = function() end
    vim.api.nvim_buf_is_valid = function()
      return false
    end
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_list_wins = function()
      return { 1 }
    end
    vim.api.nvim_win_get_buf = function()
      return 1
    end
    vim.api.nvim_list_bufs = function()
      return { 1 }
    end
    vim.api.nvim_buf_get_option = function()
      return "terminal"
    end
    vim.api.nvim_buf_get_name = function()
      return "terminal://codex"
    end
    vim.cmd = function() end
    vim.bo = setmetatable({}, {
      __index = function()
        return {}
      end,
      __newindex = function() end,
    })
    vim.schedule = function(func)
      func()
    end

    -- Mock vim.notify to prevent terminal notifications in headless mode
    vim.notify = function() end

    mock_server = {
      start = function()
        return true, 12345
      end,
      stop = function()
        return true
      end,
      state = { port = 12345 },
    }

    mock_lockfile = {
      create = function()
        return true, "/mock/path"
      end,
      -- 認証トークン取得が呼ばれても落ちないように、簡易的な戻り値を返す
      get_auth_token = function()
        return false, nil, "auth token not available in test"
      end,
      remove = function()
        return true
      end,
    }

    mock_selection = {
      enable = function() end,
      disable = function() end,
    }

    original_require = _G.require
    _G.require = function(mod)
      if mod == "codex.server.init" then
        return mock_server
      elseif mod == "codex.lockfile" then
        return mock_lockfile
      elseif mod == "codex.selection" then
        return mock_selection
      elseif mod == "codex.config" then
        return {
          apply = function(opts)
            return vim.tbl_deep_extend("force", {
              port_range = { min = 10000, max = 65535 },
              auto_start = false,
              terminal_cmd = nil,
              log_level = "info",
              track_selection = true,
              visual_demotion_delay_ms = 50,
              diff_opts = {
                layout = "vertical",
                open_in_new_tab = true, -- Note: inverted from open_in_current_tab = false
                keep_terminal_focus = false,
              },
            }, opts or {})
          end,
        }
      elseif mod == "codex.diff" then
        return {
          setup = function() end,
        }
      elseif mod == "codex.logger" then
        return {
          setup = function() end,
          debug = function() end,
          error = function() end,
          warn = function() end,
        }
      else
        return original_require(mod)
      end
    end

    -- Clear package cache to ensure fresh requires
    package.loaded["codex"] = nil
    package.loaded["codex.terminal"] = nil
    package.loaded["codex.terminal.snacks"] = nil
    package.loaded["codex.terminal.native"] = nil
    codex = require("codex")
  end)

  after_each(function()
    -- CRITICAL: Add explicit cleanup to prevent hanging
    if codex and codex.state and codex.state.server then
      -- Clean up global deferred responses that prevent garbage collection
      if _G.codex_deferred_responses then
        _G.codex_deferred_responses = {}
      end

      -- Stop the server and selection tracking explicitly
      local selection_ok, selection = pcall(require, "codex.selection")
      if selection_ok and selection.disable then
        selection.disable()
      end

      if codex.stop then
        codex.stop()
      end
    end

    _G.require = original_require
    package.loaded["codex"] = nil
    package.loaded["codex.terminal"] = nil
    package.loaded["codex.terminal.snacks"] = nil
    package.loaded["codex.terminal.native"] = nil
  end)

  describe("with native terminal provider", function()
    it("should execute terminal command with appended arguments", function()
      codex.setup({
        auto_start = false,
        terminal_cmd = "test_codex_cmd",
        terminal = { provider = "native" },
      })

      -- Find and execute the Codex command
      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          command_handler = call.vals[2]
          break
        end
      end

      assert.is_function(command_handler, "Codex command handler should exist")

      command_handler({ args = "--resume --verbose" })

      -- Verify the command was called with arguments
      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      -- For native terminal, cmd should be a table
      if type(last_cmd.cmd) == "table" then
        local cmd_string = table.concat(last_cmd.cmd, " ")
        assert.is_true(cmd_string:find("test_codex_cmd") ~= nil, "Base command not found in: " .. cmd_string)
        assert.is_true(cmd_string:find("--resume") ~= nil, "Arguments not found in: " .. cmd_string)
        assert.is_true(cmd_string:find("--verbose") ~= nil, "Arguments not found in: " .. cmd_string)
      else
        assert.is_true(last_cmd.cmd:find("test_codex_cmd") ~= nil, "Base command not found")
        assert.is_true(last_cmd.cmd:find("--resume") ~= nil, "Arguments not found")
        assert.is_true(last_cmd.cmd:find("--verbose") ~= nil, "Arguments not found")
      end
    end)

    it("should work with default codex command and arguments", function()
      codex.setup({
        auto_start = false,
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "CodexOpen" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = "--help" })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string:find("codex") ~= nil, "Default codex command not found")
      assert.is_true(cmd_string:find("--help") ~= nil, "Arguments not found")
    end)

    it("should handle empty arguments gracefully", function()
      codex.setup({
        auto_start = false,
        terminal_cmd = "codex",
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = "" })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(
        cmd_string == "codex" or cmd_string:find("^codex$") ~= nil,
        "Command should be just 'codex' without extra arguments"
      )
    end)
  end)

  describe("edge cases", function()
    it("should handle special characters in arguments", function()
      codex.setup({
        auto_start = false,
        terminal_cmd = "codex",
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = "--message='hello world' --path=/tmp/test" })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string:find("--message='hello world'") ~= nil, "Special characters not preserved")
      assert.is_true(cmd_string:find("--path=/tmp/test") ~= nil, "Path arguments not preserved")
    end)

    it("should handle very long argument strings", function()
      codex.setup({
        auto_start = false,
        terminal_cmd = "codex",
        terminal = { provider = "native" },
      })

      local long_args = string.rep("--flag ", 50) .. "--final"

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = long_args })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string:find("--final") ~= nil, "Long arguments not preserved")
    end)
  end)

  describe("backward compatibility", function()
    it("should not break existing calls without arguments", function()
      codex.setup({
        auto_start = false,
        terminal_cmd = "codex",
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({})

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string == "codex" or cmd_string:find("^codex$") ~= nil, "Should work exactly as before")
    end)

    it("should maintain existing CodexClose command functionality", function()
      codex.setup({ auto_start = false })

      local close_command_found = false
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "CodexClose" then
          close_command_found = true
          local config = call.vals[3]
          assert.is_nil(config.nargs, "CodexClose should not accept arguments")
          break
        end
      end

      assert.is_true(close_command_found, "CodexClose command should still be registered")
    end)

    it("should pass cwd in termopen opts when terminal.cwd is set", function()
      codex.setup({
        auto_start = false,
        terminal = { provider = "native", cwd = "/mock/repo" },
      })

      local handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          handler = call.vals[2]
          break
        end
      end
      assert.is_function(handler)

      handler({})
      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last = executed_commands[#executed_commands]
      assert.is_table(last.opts, "termopen options missing")
      assert.are.equal("/mock/repo", last.opts.cwd)
    end)

    it("should support cwd_provider function for working directory", function()
      codex.setup({
        auto_start = false,
        terminal = {
          provider = "native",
          cwd_provider = function(ctx)
            return "/from/provider"
          end,
        },
      })

      local handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Codex" then
          handler = call.vals[2]
          break
        end
      end
      assert.is_function(handler)

      handler({})
      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last = executed_commands[#executed_commands]
      assert.is_table(last.opts, "termopen options missing")
      assert.are.equal("/from/provider", last.opts.cwd)
    end)
  end)
end)
