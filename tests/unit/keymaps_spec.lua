-- このファイルはCodex.nvimのデフォルトキーマップ登録を検証する単体テストです。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("codex.keymaps", function()
  local keymaps
  local config

  local function reset_state()
    -- テスト用にモック状態とキーマップの記録を初期化する
    if vim._mock and vim._mock.reset then
      vim._mock.reset()
    end
    vim._keymaps = {}
    vim._autocmds = {}
  end

  local function add_buffer_with_filetype(filetype)
    -- 現在バッファのfiletypeを明示的に設定する
    if vim._mock and vim._mock.add_buffer then
      vim._mock.add_buffer(1, "/tmp/test_tree.lua", "", { filetype = filetype })
    end
  end

  local function find_filetype_autocmd(group, filetype)
    if not group or not group.events then
      return nil
    end

    for _, event in pairs(group.events) do
      local pattern = event.opts and event.opts.pattern
      if type(pattern) == "table" then
        for _, value in ipairs(pattern) do
          if value == filetype then
            return event
          end
        end
      elseif pattern == filetype then
        return event
      end
    end

    return nil
  end

  local function find_event_autocmd(group, event_name)
    -- イベント名でオートコマンドを検索する
    if not group or not group.events then
      return nil
    end

    for _, event in pairs(group.events) do
      local events = event.events
      if type(events) == "table" then
        for _, value in ipairs(events) do
          if value == event_name then
            return event
          end
        end
      elseif events == event_name then
        return event
      end
    end

    return nil
  end

  before_each(function()
    -- テスト対象モジュールを再読み込みするためにキャッシュをクリアする
    package.loaded["codex.keymaps"] = nil
    package.loaded["codex.config"] = nil
    reset_state()
    keymaps = require("codex.keymaps")
    config = require("codex.config")
  end)

  it("デフォルトのキーマップを登録する", function()
    keymaps.setup(config.defaults.keymaps)

    expect(vim._keymaps.n["<leader>cc"].rhs).to_be("<cmd>Codex<cr>")
    expect(vim._keymaps.n["<leader>cf"].rhs).to_be("<cmd>CodexFocus<cr>")
    expect(vim._keymaps.n["<leader>cr"].rhs).to_be("<cmd>Codex --resume<cr>")
    expect(vim._keymaps.n["<leader>cC"].rhs).to_be("<cmd>Codex --continue<cr>")
    expect(vim._keymaps.n["<leader>cm"].rhs).to_be("<cmd>CodexSelectModel<cr>")
    expect(vim._keymaps.n["<leader>cb"].rhs).to_be("<cmd>CodexAdd %<cr>")
    expect(vim._keymaps.v["<leader>cs"].rhs).to_be("<cmd>CodexSend<cr>")
    expect(vim._keymaps.n["<leader>ca"].rhs).to_be("<cmd>CodexDiffAccept<cr>")
    expect(vim._keymaps.n["<leader>cd"].rhs).to_be("<cmd>CodexDiffDeny<cr>")
  end)

  it("ファイルツリー向けのキーマップをFileTypeで登録する", function()
    -- neo-treeのみを対象とする
    keymaps.setup(config.defaults.keymaps)

    local group = vim._autocmds["CodexKeymaps"]
    expect(group).not_to_be_nil()

    local event = find_filetype_autocmd(group, "neo-tree")
    expect(event).not_to_be_nil()
    expect(event.events).to_be("FileType")

    event.opts.callback()
    expect(vim._keymaps.n["<leader>cs"].rhs).to_be("<cmd>CodexTreeAdd<cr>")
    expect(vim._keymaps.n["<leader>cs"].opts.buffer).to_be(1)
  end)

  it("BufEnterでも対象ファイルタイプならキーマップを登録する", function()
    add_buffer_with_filetype("neo-tree")

    keymaps.setup(config.defaults.keymaps)

    local group = vim._autocmds["CodexKeymaps"]
    local event = find_event_autocmd(group, "BufEnter")
    expect(event).not_to_be_nil()

    event.opts.callback()
    expect(vim._keymaps.n["<leader>cs"].rhs).to_be("<cmd>CodexTreeAdd<cr>")
    expect(vim._keymaps.n["<leader>cs"].opts.buffer).to_be(1)
  end)

  it("既に開いている対象ファイルタイプのバッファにもキーマップを登録する", function()
    add_buffer_with_filetype("neo-tree")

    keymaps.setup(config.defaults.keymaps)

    expect(vim._keymaps.n["<leader>cs"].rhs).to_be("<cmd>CodexTreeAdd<cr>")
    expect(vim._keymaps.n["<leader>cs"].opts.buffer).to_be(1)
  end)

  it("無効化された場合はキーマップを登録しない", function()
    keymaps.setup({ enabled = false, mappings = config.defaults.keymaps.mappings })

    expect(vim._keymaps.n).to_be_nil()
    expect(vim._autocmds["CodexKeymaps"]).to_be_nil()
  end)
end)
