-- このファイルはフィクスチャ用のNeovim設定としてテスト実行時に読み込まれます。
-- Basic plugin configuration
return {
  -- Example: add a colorscheme
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd([[colorscheme tokyonight]])
    end,
  },
}
