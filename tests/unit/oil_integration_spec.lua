-- このファイルはoil.nvim連携でファイル選択を取得できるかを検証します。
-- luacheck: globals expect
require("tests.busted_setup")

describe("oil.nvim integration", function()
  local integrations
  local mock_vim

  local function setup_mocks()
    package.loaded["codex.integrations"] = nil
    package.loaded["codex.visual_commands"] = nil
    package.loaded["codex.logger"] = nil

    -- テスト用に最低限のロガーを差し替える
    package.loaded["codex.logger"] = {
      debug = function() end,
      warn = function() end,
      error = function() end,
    }

    mock_vim = {
      fn = {
        mode = function()
          return "n" -- 既定は通常モードとして扱う
        end,
        line = function(mark)
          if mark == "'<" then
            return 2
          elseif mark == "'>" then
            return 4
          end
          return 1
        end,
      },
      api = {
        nvim_get_current_buf = function()
          return 1
        end,
        nvim_win_get_cursor = function()
          return { 4, 0 }
        end,
        nvim_get_mode = function()
          return { mode = "n" }
        end,
      },
      bo = { filetype = "oil" },
    }

    _G.vim = mock_vim
  end

  before_each(function()
    setup_mocks()
    integrations = require("codex.integrations")
  end)

  describe("_get_oil_selection", function()
    it("通常モードでカーソル下のファイルを取得できる", function()
      local mock_oil = {
        get_cursor_entry = function()
          return { type = "file", name = "main.lua" }
        end,
        get_current_dir = function(bufnr)
          return "/Users/test/project/"
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be_nil()
      expect(files).to_be_table()
      expect(#files).to_be(1)
      expect(files[1]).to_be("/Users/test/project/main.lua")
    end)

    it("通常モードでディレクトリを取得できる", function()
      local mock_oil = {
        get_cursor_entry = function()
          return { type = "directory", name = "src" }
        end,
        get_current_dir = function(bufnr)
          return "/Users/test/project/"
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be_nil()
      expect(files).to_be_table()
      expect(#files).to_be(1)
      expect(files[1]).to_be("/Users/test/project/src/")
    end)

    it("親ディレクトリのエントリーは除外する", function()
      local mock_oil = {
        get_cursor_entry = function()
          return { type = "directory", name = ".." }
        end,
        get_current_dir = function(bufnr)
          return "/Users/test/project/"
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be("No file found under cursor")
      expect(files).to_be_table()
      expect(#files).to_be(0)
    end)

    it("シンボリックリンクもファイルとして扱う", function()
      local mock_oil = {
        get_cursor_entry = function()
          return { type = "link", name = "linked_file.lua" }
        end,
        get_current_dir = function(bufnr)
          return "/Users/test/project/"
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be_nil()
      expect(files).to_be_table()
      expect(#files).to_be(1)
      expect(files[1]).to_be("/Users/test/project/linked_file.lua")
    end)

    it("ビジュアルモードの選択範囲を処理できる", function()
      -- ビジュアルモードでの行範囲を模擬する
      mock_vim.fn.mode = function()
        return "V"
      end
      mock_vim.api.nvim_get_mode = function()
        return { mode = "V" }
      end

      package.loaded["codex.visual_commands"] = {
        get_visual_range = function()
          return 2, 4
        end,
      }

      local line_entries = {
        [2] = { type = "file", name = "file1.lua" },
        [3] = { type = "directory", name = "src" },
        [4] = { type = "file", name = "file2.lua" },
      }

      local mock_oil = {
        get_current_dir = function(bufnr)
          return "/Users/test/project/"
        end,
        get_entry_on_line = function(bufnr, line)
          return line_entries[line]
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be_nil()
      expect(files).to_be_table()
      expect(#files).to_be(3)
      expect(files[1]).to_be("/Users/test/project/file1.lua")
      expect(files[2]).to_be("/Users/test/project/src/")
      expect(files[3]).to_be("/Users/test/project/file2.lua")
    end)

    it("oil.nvimのエラーをそのまま返す", function()
      local mock_oil = {
        get_cursor_entry = function()
          error("Failed to get cursor entry")
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be("Failed to get cursor entry")
      expect(files).to_be_table()
      expect(#files).to_be(0)
    end)

    it("oil.nvimが無い場合はエラーを返す", function()
      package.loaded["oil"] = nil

      local files, err = integrations._get_oil_selection()

      expect(err).to_be("oil.nvim not available")
      expect(files).to_be_table()
      expect(#files).to_be(0)
    end)
  end)

  describe("get_selected_files_from_tree", function()
    it("oilのfiletypeで_get_oil_selectionに委譲する", function()
      -- filetypeがoilの場合の分岐を検証する
      mock_vim.bo.filetype = "oil"

      local mock_oil = {
        get_cursor_entry = function()
          return { type = "file", name = "test.lua" }
        end,
        get_current_dir = function(bufnr)
          return "/path/"
        end,
      }

      package.loaded["oil"] = mock_oil

      local files, err = integrations.get_selected_files_from_tree()

      expect(err).to_be_nil()
      expect(files).to_be_table()
      expect(#files).to_be(1)
      expect(files[1]).to_be("/path/test.lua")
    end)
  end)
end)
