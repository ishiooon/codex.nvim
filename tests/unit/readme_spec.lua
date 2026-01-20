-- このファイルはREADMEに記載する運用案内の単体テストを行います。
describe("README", function()
  local function read_readme()
    -- README.md を読み取るためにファイルを開いて内容を取得する
    local handle = assert(io.open("README.md", "r"))
    local content = handle:read("*a")
    handle:close()
    return content
  end

  it("Issue と PR の歓迎文が記載されている", function()
    local content = read_readme()
    assert.is_true(content:find("Issue や PR 歓迎です。", 1, true) ~= nil)
  end)
end)
