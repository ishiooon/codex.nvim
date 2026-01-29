-- このファイルはCodex CLI活動の記録を単体で検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Codex activity", function()
  local activity

  before_each(function()
    package.loaded["codex.activity"] = nil
    activity = require("codex.activity")
    activity._reset_for_test()
  end)

  it("入力があれば活動中になる", function()
    activity.record_terminal_input(1000)
    assert(activity.is_turn_active() == false)
    assert(activity.get_last_activity_ms() == 0)
    assert(activity.get_turn_active_since_ms() == 0)
  end)

  it("出力があれば活動中になる", function()
    activity.record_terminal_output(900)
    assert(activity.is_turn_active() == false)
    assert(activity.get_last_activity_ms() == 0)
    assert(activity.get_turn_active_since_ms() == 0)
  end)

  it("完了通知で活動が終了する", function()
    activity.record_turn_start(1000)
    activity.record_turn_complete(1500)
    assert(activity.is_turn_active() == false)
    assert(activity.get_last_activity_ms() == 0)
    assert(activity.get_turn_active_since_ms() == 0)
  end)

  it("活動中の開始時刻は最初の入力時刻を維持する", function()
    -- 途中の出力では開始時刻が更新されないことを確認する
    activity.record_turn_start(1000)
    activity.record_terminal_output(1200)
    assert(activity.get_turn_active_since_ms() == 1000)
  end)

  it("活動中のみ出力で活動を維持する", function()
    activity.record_turn_start(1000)
    activity.record_terminal_output(1500)
    assert(activity.is_turn_active())
    assert(activity.get_last_activity_ms() == 1500)
    assert(activity.get_turn_active_since_ms() == 1000)
  end)

  it("活動中の入力は応答中フラグを維持する", function()
    activity.record_turn_start(1000)
    activity.record_terminal_input(1200)
    assert(activity.is_turn_active())
    assert(activity.get_turn_active_since_ms() == 1000)
  end)
end)
