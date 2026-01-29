-- このファイルはターミナル入力検知の判定ロジックを単体で検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Codex terminal activity", function()
  local activity_module

  before_each(function()
    package.loaded["codex.terminal.activity"] = nil
    activity_module = require("codex.terminal.activity")
  end)

  it("入力キーはユーザー入力として扱う", function()
    assert(activity_module._is_user_input_key("a"))
    assert(activity_module._is_user_input_key("1"))
    assert(activity_module._is_user_input_key(" "))
  end)

  it("制御キーはユーザー入力として扱わない", function()
    assert(activity_module._is_user_input_key("<Esc>") == false)
    assert(activity_module._is_user_input_key("<C-\\>") == false)
    assert(activity_module._is_user_input_key("<C-n>") == false)
  end)

  it("Enterはユーザー入力として扱わない", function()
    assert(activity_module._is_user_input_key("\r") == false)
    assert(activity_module._is_user_input_key("\n") == false)
    assert(activity_module._is_user_input_key("<CR>") == false)
  end)
end)
