-- このファイルはCodex未接続時のファイルメンションがターミナル入力に反映されることを確認する単体テストです。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("At mention terminal fallback", function()
  local saved_require
  local codex
  local mock_terminal
  local mock_logger
  local mock_config
  local mock_server_init
  local spy = require("luassert.spy")

  local function setup_mocks()
    -- テスト対象以外の依存を安全に差し替える
    mock_terminal = {
      send = spy.new(function()
        return true
      end),
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

    mock_config = {
      defaults = {
        fallback_to_terminal_send = true,
        connection_timeout = 1000,
        connection_wait_delay = 200,
        queue_timeout = 5000,
      },
    }

    mock_server_init = {
      get_status = function()
        return { running = true, client_count = 0 }
      end,
    }

    saved_require = _G.require
    _G.require = function(module_name)
      if module_name == "codex.logger" then
        return mock_logger
      end
      if module_name == "codex.config" then
        return mock_config
      end
      if module_name == "codex.terminal" then
        return mock_terminal
      end
      if module_name == "codex.server.init" then
        return mock_server_init
      end
      return saved_require(module_name)
    end
  end

  local function teardown_mocks()
    _G.require = saved_require
    package.loaded["codex"] = nil
    package.loaded["codex.logger"] = nil
    package.loaded["codex.config"] = nil
    package.loaded["codex.terminal"] = nil
    package.loaded["codex.server.init"] = nil
  end

  before_each(function()
    setup_mocks()
    codex = require("codex")
    codex.state.server = {}
    codex.state.config = mock_config.defaults
    codex._format_path_for_at_mention = function()
      return "test/file.lua", false
    end
  end)

  after_each(function()
    teardown_mocks()
  end)

  it("Codex未接続時にファイルメンションをターミナル入力へ流し込む", function()
    local ok, err = codex.send_at_mention("/tmp/file.lua", nil, nil, "CodexTreeAdd")

    assert.is_true(ok)
    assert.is_nil(err)
    assert.spy(mock_terminal.open).was_called()
    assert.spy(mock_terminal.send).was_called(1)
    local payload = mock_terminal.send.calls[1].vals[1]
    assert_contains(payload, "@test/file.lua")
  end)

  it("選択送信の文脈ではターミナル入力を更新しない", function()
    codex.send_at_mention("/tmp/file.lua", nil, nil, "CodexSend")

    assert.spy(mock_terminal.send).was_not_called()
  end)
end)
