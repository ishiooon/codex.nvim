-- このファイルはCodex未接続時のターミナル送信フォールバックを検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Selection terminal fallback", function()
  local selection
  local mock_terminal
  local mock_terminal_buffer
  local mock_codex_main
  local original_require
  local spy = require("luassert.spy")

  before_each(function()
    package.loaded["codex.selection"] = nil

    mock_terminal = {
      last_payload = nil,
      last_opts = nil,
      send = spy.new(function(payload, opts)
        mock_terminal.last_payload = payload
        mock_terminal.last_opts = opts
        return true
      end),
    }

    mock_terminal_buffer = {
      is_codex_terminal_buffer = function()
        return false
      end,
    }

    mock_codex_main = {
      state = {
        server = {},
        config = {
          fallback_to_terminal_send = true,
        },
      },
      is_codex_connected = function()
        return false
      end,
      send_at_mention = function()
        return true, nil
      end,
      _format_path_for_at_mention = function(_file_path)
        return "test/file.lua", false
      end,
    }

    original_require = _G.require
    _G.require = function(module_name)
      if module_name == "codex" then
        return mock_codex_main
      end
      if module_name == "codex.terminal" then
        return mock_terminal
      end
      if module_name == "codex.terminal.buffer" then
        return mock_terminal_buffer
      end
      return original_require(module_name)
    end

    selection = require("codex.selection")
    selection.state.tracking_enabled = true
    selection.server = {
      broadcast = function()
        return true
      end,
    }

    if _G.vim._mock and _G.vim._mock.add_buffer then
      _G.vim._mock.add_buffer(1, "/test/file.lua", { "line 1", "line 2", "line 3" })
    end
  end)

  after_each(function()
    _G.require = original_require
  end)

  it("should send fallback text to terminal when disconnected", function()
    local result = selection.send_at_mention_for_visual_selection(1, 2)

    assert.is_true(result)
    assert.spy(mock_terminal.send).was_called(1)
    assert_contains(mock_terminal.last_payload, "@test/file.lua:1-2")
    assert_contains(mock_terminal.last_payload, "line 1")
    assert_contains(mock_terminal.last_payload, "line 2")
  end)
end)
