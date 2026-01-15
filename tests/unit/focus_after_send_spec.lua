-- このファイルは送信後のフォーカス制御を検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("focus_after_send behavior", function()
  local saved_require
  local codex

  local mock_terminal
  local mock_logger
  local mock_server_facade

  local function setup_mocks(focus_after_send)
    mock_terminal = {
      setup = function() end,
      open = spy.new(function() end),
      ensure_visible = spy.new(function() end),
    }

    mock_logger = {
      setup = function() end,
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    mock_server_facade = {
      broadcast = spy.new(function()
        return true
      end),
    }

    local mock_config = {
      apply = function()
        -- Return only fields used in this test path
        return {
          auto_start = false,
          terminal_cmd = nil,
          env = {},
          log_level = "info",
          track_selection = false,
          focus_after_send = focus_after_send,
          diff_opts = {
            layout = "vertical",
            open_in_new_tab = false,
            keep_terminal_focus = false,
            on_new_file_reject = "keep_empty",
          },
          models = { { name = "Codex Sonnet 4 (Latest)", value = "sonnet" } },
        }
      end,
    }

    saved_require = _G.require
    _G.require = function(mod)
      if mod == "codex.config" then
        return mock_config
      elseif mod == "codex.logger" then
        return mock_logger
      elseif mod == "codex.diff" then
        return { setup = function() end }
      elseif mod == "codex.terminal" then
        return mock_terminal
      elseif mod == "codex.server.init" then
        return {
          get_status = function()
            return { running = true, client_count = 1 }
          end,
        }
      else
        return saved_require(mod)
      end
    end
  end

  local function teardown_mocks()
    _G.require = saved_require
    package.loaded["codex"] = nil
    package.loaded["codex.config"] = nil
    package.loaded["codex.logger"] = nil
    package.loaded["codex.diff"] = nil
    package.loaded["codex.terminal"] = nil
    package.loaded["codex.server.init"] = nil
  end

  after_each(function()
    teardown_mocks()
  end)

  it("focuses terminal with open() when enabled", function()
    setup_mocks(true)

    codex = require("codex")
    codex.setup({})

    -- Mark server as present and stub low-level broadcast to succeed
    codex.state.server = mock_server_facade
    codex._broadcast_at_mention = spy.new(function()
      return true, nil
    end)

    -- Act
    local ok, err = codex.send_at_mention("/tmp/file.lua", nil, nil, "test")
    assert.is_true(ok)
    assert.is_nil(err)

    -- Assert focus behavior
    assert.spy(mock_terminal.open).was_called()
    assert.spy(mock_terminal.ensure_visible).was_not_called()
  end)

  it("only ensures visibility when disabled (default)", function()
    setup_mocks(false)

    codex = require("codex")
    codex.setup({})

    codex.state.server = mock_server_facade
    codex._broadcast_at_mention = spy.new(function()
      return true, nil
    end)

    local ok, err = codex.send_at_mention("/tmp/file.lua", nil, nil, "test")
    assert.is_true(ok)
    assert.is_nil(err)

    assert.spy(mock_terminal.ensure_visible).was_called()
    assert.spy(mock_terminal.open).was_not_called()
  end)
end)
