-- このファイルはターミナル表示サイズの計算を検証します。
require("tests.busted_setup")

describe("codex.terminal.size", function()
  local terminal_size

  before_each(function()
    package.loaded["codex.terminal.size"] = nil
    terminal_size = require("codex.terminal.size")
  end)

  it("96パーセントのモーダル表示位置とサイズを計算する", function()
    local config = terminal_size.resolve_modal_window_config(120, 40, 0.96, 0.96)

    assert.are.equal("editor", config.relative)
    assert.are.equal("minimal", config.style)
    assert.are.equal("rounded", config.border)
    assert.are.equal(115, config.width)
    assert.are.equal(38, config.height)
    assert.are.equal(2, config.col)
    assert.are.equal(1, config.row)
  end)

  it("無効な割合では96パーセントを既定値にする", function()
    local config = terminal_size.resolve_modal_window_config(100, 50, 3, nil)

    assert.are.equal(96, config.width)
    assert.are.equal(48, config.height)
    assert.are.equal(2, config.col)
    assert.are.equal(1, config.row)
  end)
end)
