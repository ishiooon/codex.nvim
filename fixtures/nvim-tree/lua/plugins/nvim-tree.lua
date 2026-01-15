-- このファイルはフィクスチャ用のNeovim設定としてテスト実行時に読み込まれます。
return {
  "nvim-tree/nvim-tree.lua",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("nvim-tree").setup({
      view = {
        width = 30,
      },
      renderer = {
        group_empty = true,
      },
      filters = {
        dotfiles = true,
      },
    })

    -- Key mappings
    vim.keymap.set("n", "<C-n>", ":NvimTreeToggle<CR>", { silent = true })
    vim.keymap.set("n", "<leader>e", ":NvimTreeFocus<CR>", { silent = true })
  end,
}
