-- このファイルはCodexの状態アイコン判定を単体で検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Codex status indicator", function()
  local indicator

  before_each(function()
    package.loaded["codex.status_indicator"] = nil
    indicator = require("codex.status_indicator")
  end)

  local function server_status(extra)
    -- クライアント接続済みの状態を既定とする
    local base = { running = true, client_count = 1 }
    for key, value in pairs(extra or {}) do
      base[key] = value
    end
    return base
  end

  it("サーバ未起動はdisconnectedになる", function()
    local status = indicator._derive_status({ running = false }, 1000, { busy_grace_ms = 1000 }, 0, false, false, 0)
    assert(status == "disconnected")
  end)

  it("クライアント未接続はidleになる", function()
    local status = indicator._derive_status(
      { running = true, client_count = 0 },
      1000,
      { busy_grace_ms = 1000 },
      0,
      false,
      false,
      0
    )
    assert(status == "idle")
  end)

  it("通知設定が無い場合でも応答中フラグでbusyになる", function()
    local status = indicator._derive_status(
      server_status(),
      1000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, cli_notify_path = nil },
      0,
      false,
      true,
      500
    )
    assert(status == "busy")
  end)

  it("保留レスポンスがあればwaitになる", function()
    local status = indicator._derive_status(
      server_status({ deferred_responses = 1 }),
      1000,
      { busy_grace_ms = 1000 },
      0,
      false,
      false,
      0
    )
    assert(status == "wait")
  end)

  it("選択待ちが明示されていればwaitになる", function()
    local status = indicator._derive_status(
      server_status({ deferred_responses = 0 }),
      1000,
      { busy_grace_ms = 1000 },
      0,
      true,
      false,
      0
    )
    assert(status == "wait")
  end)

  it("実行中リクエストがあればbusyになる", function()
    local status = indicator._derive_status(
      server_status({ inflight_requests = 1 }),
      1000,
      { busy_grace_ms = 1000 },
      0,
      false,
      false,
      0
    )
    assert(status == "busy")
  end)

  it("実行中リクエストが古い場合はbusyにならない", function()
    -- 通信が長時間止まっている場合は実行中リクエストを無視する
    local status = indicator._derive_status(
      server_status({ inflight_requests = 1, last_activity_ms = 1000 }),
      5000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, inflight_timeout_ms = 2000 },
      0,
      false,
      false,
      0
    )
    assert(status == "idle")
  end)

  it("実行中リクエストが最近ならbusyになる", function()
    -- 最終活動が新しければ実行中リクエストを優先する
    local status = indicator._derive_status(
      server_status({ inflight_requests = 1, last_activity_ms = 4000 }),
      5000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, inflight_timeout_ms = 2000 },
      0,
      false,
      false,
      0
    )
    assert(status == "busy")
  end)

  it("最近の通信があればbusyになる", function()
    local status = indicator._derive_status(
      server_status({ last_activity_ms = 900 }),
      1000,
      { busy_grace_ms = 200 },
      0,
      false,
      false,
      0
    )
    assert(status == "busy")
  end)

  it("CLI活動があればbusyになる", function()
    local status = indicator._derive_status(
      server_status(),
      1000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 300 },
      850,
      false,
      false,
      0
    )
    assert(status == "busy")
  end)

  it("応答処理中ならbusyになる", function()
    -- 応答中フラグがある場合に動作中表示になることを確認する
    local status = indicator._derive_status(
      server_status(),
      1000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, turn_idle_grace_ms = 0, cli_notify_path = "/tmp/notify" },
      0,
      false,
      true,
      500
    )
    assert(status == "busy")
  end)

  it("応答処理が長すぎる場合はbusyにならない", function()
    -- 応答開始から時間が経ちすぎた場合に動作中表示を解除する
    local status = indicator._derive_status(
      server_status(),
      5000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, turn_active_timeout_ms = 1000 },
      0,
      false,
      true,
      1000
    )
    assert(status == "idle")
  end)

  it("応答停止が続けばbusyにならない", function()
    -- 応答停止の猶予時間を超えた場合は動作中扱いを解除する
    local status = indicator._derive_status(
      server_status(),
      5000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 3000, turn_idle_grace_ms = 500 },
      1000,
      false,
      true,
      1000
    )
    assert(status == "idle")
  end)

  it("新しいターン開始直後は古い出力でbusyを解除しない", function()
    -- 直前の出力が古い場合でも、ターン開始直後は動作中表示を維持する
    local status = indicator._derive_status(
      server_status(),
      4500,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, turn_idle_grace_ms = 500 },
      1000,
      false,
      true,
      4000
    )
    assert(status == "busy")
  end)

  it("応答停止の猶予時間が無効ならbusyを維持する", function()
    -- 応答停止の猶予時間が0の場合は動作中表示を維持する
    local status = indicator._derive_status(
      server_status(),
      5000,
      { busy_grace_ms = 0, cli_activity_grace_ms = 0, turn_idle_grace_ms = 0, cli_notify_path = "/tmp/notify" },
      1000,
      false,
      true,
      1000
    )
    assert(status == "busy")
  end)

  it("活動が無ければidleになる", function()
    local status = indicator._derive_status(
      server_status({ last_activity_ms = 100 }),
      1000,
      { busy_grace_ms = 200 },
      0,
      false,
      false,
      0
    )
    assert(status == "idle")
  end)

  it("差分の保留があれば選択待ちになる", function()
    package.loaded["codex.diff"] = {
      get_active_diffs = function()
        return { diff1 = { status = "pending" } }
      end,
    }
    local pending = indicator._has_pending_wait()
    assert(pending)
    package.loaded["codex.diff"] = nil
  end)

  it("差分の保留がなければ選択待ちにならない", function()
    -- 差分が未保留の場合は待機状態にならないことを確認する
    package.loaded["codex.diff"] = {
      get_active_diffs = function()
        return { diff1 = { status = "applied" } }
      end,
    }
    local pending = indicator._has_pending_wait()
    assert(pending == false)
    package.loaded["codex.diff"] = nil
  end)
end)
