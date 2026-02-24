-- このファイルは通知イベント連携時の即時更新コールバック挙動を検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Codex activity notify callback", function()
  local original_notify_module

  local function create_notify_stub(events)
    return {
      start = function(_path, on_event)
        for _, event in ipairs(events) do
          on_event(event)
        end
      end,
      stop = function() end,
      _get_state_for_test = function()
        return { path = "/tmp/notify" }
      end,
    }
  end

  before_each(function()
    original_notify_module = package.loaded["codex.activity_notify"]
    package.loaded["codex.activity"] = nil
  end)

  after_each(function()
    package.loaded["codex.activity"] = nil
    package.loaded["codex.activity_notify"] = original_notify_module
  end)

  it("応答状態を変更する通知を受信したら更新コールバックを呼ぶ", function()
    local callback_count = 0
    package.loaded["codex.activity_notify"] = create_notify_stub({
      { type = "turn/started" },
      { type = "turn/completed" },
    })

    local activity = require("codex.activity")
    activity.start_notify_watcher("/tmp/notify", function()
      callback_count = callback_count + 1
    end)

    assert(callback_count == 2)
  end)

  it("状態に影響しない通知では更新コールバックを呼ばない", function()
    local callback_count = 0
    package.loaded["codex.activity_notify"] = create_notify_stub({
      { type = "unknown-event" },
    })

    local activity = require("codex.activity")
    activity.start_notify_watcher("/tmp/notify", function()
      callback_count = callback_count + 1
    end)

    assert(callback_count == 0)
  end)
end)
