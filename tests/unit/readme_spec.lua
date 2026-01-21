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

  -- 英語セクションが日本語セクションより先に配置されていることを確認する
  it("英語セクションが先に配置されている", function()
    local content = read_readme()
    local english_index = content:find("# codex.nvim (English)", 1, true)
    local japanese_index = content:find("## 特徴", 1, true)

    assert.is_true(english_index ~= nil)
    assert.is_true(japanese_index ~= nil)
    assert.is_true(english_index < japanese_index)
  end)

  -- 英語セクションの冒頭に操作イメージの図があることを確認する
  it("英語セクションの見出し直後に操作イメージがある", function()
    local content = read_readme()
    local english_index = content:find("# codex.nvim (English)", 1, true)
    local image_index = content:find("![操作イメージ](codex.nvim.gif)", 1, true)
    local highlights_index = content:find("## Highlights", 1, true)

    assert.is_true(english_index ~= nil)
    assert.is_true(image_index ~= nil)
    assert.is_true(highlights_index ~= nil)
    assert.is_true(english_index < image_index)
    assert.is_true(image_index < highlights_index)
  end)
end)
