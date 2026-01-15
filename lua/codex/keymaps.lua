-- このファイルはCodex.nvimの既定キーマップ登録を担当します。
---@brief Default keymap setup for Codex.nvim.
---@module 'codex.keymaps'

local M = {}

local DEFAULT_KEYMAP_OPTS = { noremap = true, silent = true }

local should_skip
local register_filetype_keymap
local register_bufenter_keymap
local apply_keymap_to_existing_buffers
local resolve_current_buffer
local resolve_existing_buffers
local buffer_has_filetype
local apply_keymap
local build_keymap_opts

---CodexのキーマップをNeovimに登録する
---@param keymaps_config table|false|nil キーマップ設定
function M.setup(keymaps_config)
  -- NeovimにキーマップとFileTypeの自動コマンドを追加する
  if should_skip(keymaps_config) then
    return
  end

  local mappings = keymaps_config.mappings or {}
  local group = vim.api.nvim_create_augroup("CodexKeymaps", { clear = true })

  for _, mapping in ipairs(mappings) do
    if mapping.filetypes and #mapping.filetypes > 0 then
      register_filetype_keymap(mapping, group)
      register_bufenter_keymap(mapping, group)
      apply_keymap_to_existing_buffers(mapping)
    else
      apply_keymap(mapping, nil)
    end
  end
end

should_skip = function(keymaps_config)
  if keymaps_config == false then
    return true
  end
  if type(keymaps_config) ~= "table" then
    return true
  end
  if keymaps_config.enabled == false then
    return true
  end
  return false
end

register_filetype_keymap = function(mapping, group)
  -- 指定したFileTypeのバッファにキーマップを追加する
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = mapping.filetypes,
    desc = mapping.desc,
    callback = function()
      local buffer = resolve_current_buffer()
      if buffer then
        apply_keymap(mapping, { buffer = buffer })
      else
        apply_keymap(mapping, nil)
      end
    end,
  })
end

register_bufenter_keymap = function(mapping, group)
  -- FileType自動コマンドを取りこぼす場合に備えて、入室時にも判定してキーマップを追加する
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    desc = mapping.desc,
    callback = function()
      local buffer = resolve_current_buffer()
      if buffer and buffer_has_filetype(buffer, mapping.filetypes) then
        apply_keymap(mapping, { buffer = buffer })
      end
    end,
  })
end

apply_keymap_to_existing_buffers = function(mapping)
  -- 既に存在するバッファに対してもFileTypeに一致する場合はキーマップを追加する
  for _, bufnr in ipairs(resolve_existing_buffers()) do
    if buffer_has_filetype(bufnr, mapping.filetypes) then
      apply_keymap(mapping, { buffer = bufnr })
    end
  end
end

resolve_current_buffer = function()
  if vim.api and vim.api.nvim_get_current_buf then
    return vim.api.nvim_get_current_buf()
  end
  if vim.fn and vim.fn.bufnr then
    return vim.fn.bufnr()
  end
  return nil
end

resolve_existing_buffers = function()
  if vim.api and vim.api.nvim_list_bufs then
    return vim.api.nvim_list_bufs()
  end
  local current = resolve_current_buffer()
  if current then
    return { current }
  end
  return {}
end

buffer_has_filetype = function(bufnr, filetypes)
  if not filetypes or #filetypes == 0 then
    return false
  end

  local filetype = nil
  if vim.api and vim.api.nvim_buf_get_option then
    filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  elseif vim.bo and vim.bo[bufnr] then
    filetype = vim.bo[bufnr].filetype
  elseif vim.bo then
    filetype = vim.bo.filetype
  end

  if not filetype or filetype == "" then
    return false
  end

  for _, allowed in ipairs(filetypes) do
    if allowed == filetype then
      return true
    end
  end

  return false
end

apply_keymap = function(mapping, extra_opts)
  -- Neovimにキーマップを登録する
  local mode = mapping.mode or "n"
  local opts = build_keymap_opts(mapping, extra_opts)
  vim.keymap.set(mode, mapping.lhs, mapping.rhs, opts)
end

build_keymap_opts = function(mapping, extra_opts)
  local opts = vim.tbl_extend("force", DEFAULT_KEYMAP_OPTS, mapping.opts or {})
  if extra_opts then
    opts = vim.tbl_extend("force", opts, extra_opts)
  end
  if mapping.desc and opts.desc == nil then
    opts.desc = mapping.desc
  end
  return opts
end

return M
