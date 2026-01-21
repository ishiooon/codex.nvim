-- このファイルはneo-treeとoil.nvimの連携処理を提供します。
--- Tree integration module for Codex.nvim (neo-tree and oil.nvim).
---@module 'codex.integrations'
local M = {}
local logger = require("codex.logger")

---現在のバッファがneo-treeまたはoilの場合に選択ファイルを取得する
---@return table|nil files List of file paths, or nil if error
---@return string|nil error Error message if operation failed
function M.get_selected_files_from_tree()
  local current_ft = vim.bo.filetype

  if current_ft == "neo-tree" then
    -- neo-treeのみを対象にする
    return M._get_neotree_selection()
  end

  if current_ft == "oil" then
    -- oil.nvimの選択ファイルを取得する
    return M._get_oil_selection()
  end

  return nil, "Not in a supported tree buffer (current filetype: " .. current_ft .. ")"
end

---Get selected files from neo-tree
---Uses neo-tree's own visual selection method when in visual mode
---@return table files List of file paths
---@return string|nil error Error message if operation failed
function M._get_neotree_selection()
  local success, manager = pcall(require, "neo-tree.sources.manager")
  if not success then
    logger.debug("integrations/neotree", "neo-tree not available (require failed)")
    return {}, "neo-tree not available"
  end

  local state = manager.get_state("filesystem")
  if not state then
    logger.debug("integrations/neotree", "filesystem state not available from manager")
    return {}, "neo-tree filesystem state not available"
  end

  local files = {}

  -- Use neo-tree's own visual selection method (like their copy/paste feature)
  local mode = vim.fn.mode()
  local current_win = vim.api.nvim_get_current_win()
  logger.debug(
    "integrations/neotree",
    "begin selection",
    "mode=",
    mode,
    "current_win=",
    current_win,
    "state.winid=",
    tostring(state.winid)
  )

  if mode == "V" or mode == "v" or mode == "\22" then
    if state.winid and state.winid == current_win then
      -- Use neo-tree's exact method to get visual range (from their get_selected_nodes implementation)
      local start_pos = vim.fn.getpos("'<")[2]
      local end_pos = vim.fn.getpos("'>")[2]

      -- Fallback to current cursor and anchor if marks are not valid
      if start_pos == 0 or end_pos == 0 then
        local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]
        local anchor_pos = vim.fn.getpos("v")[2]
        if anchor_pos > 0 then
          start_pos = math.min(cursor_pos, anchor_pos)
          end_pos = math.max(cursor_pos, anchor_pos)
        else
          start_pos = cursor_pos
          end_pos = cursor_pos
        end
      end

      if end_pos < start_pos then
        start_pos, end_pos = end_pos, start_pos
      end

      logger.debug("integrations/neotree", "visual selection range", start_pos, "to", end_pos)

      local selected_nodes = {}

      for line = start_pos, end_pos do
        local node = state.tree:get_node(line)
        if node then
          -- Add validation for node types before adding to selection
          if node.type and node.type ~= "message" then
            table.insert(selected_nodes, node)
            local depth = (node.get_depth and node:get_depth()) and node:get_depth() or 0
            logger.debug(
              "integrations/neotree",
              "line",
              line,
              "node type=",
              tostring(node.type),
              "depth=",
              depth,
              "path=",
              tostring(node.path)
            )
          else
            logger.debug("integrations/neotree", "line", line, "node rejected (type)", tostring(node and node.type))
          end
        else
          logger.debug("integrations/neotree", "line", line, "no node returned from state.tree:get_node")
        end
      end

      logger.debug("integrations/neotree", "selected_nodes count=", #selected_nodes)

      for _, node in ipairs(selected_nodes) do
        -- Enhanced validation: check for file type and valid path
        if node.type == "file" and node.path and node.path ~= "" then
          -- Additional check: ensure it's not a root node (depth protection)
          local depth = (node.get_depth and node:get_depth()) and node:get_depth() or 0
          if depth > 1 then
            table.insert(files, node.path)
            logger.debug("integrations/neotree", "accepted file", node.path)
          else
            logger.debug("integrations/neotree", "rejected file (depth<=1)", node.path)
          end
        elseif node.type == "directory" and node.path and node.path ~= "" then
          local depth = (node.get_depth and node:get_depth()) and node:get_depth() or 0
          if depth > 1 then
            table.insert(files, node.path)
            logger.debug("integrations/neotree", "accepted directory", node.path)
          else
            logger.debug("integrations/neotree", "rejected directory (depth<=1)", node.path)
          end
        else
          logger.debug(
            "integrations/neotree",
            "rejected node (missing path or unsupported type)",
            tostring(node and node.type),
            tostring(node and node.path)
          )
        end
      end

      if #files > 0 then
        logger.debug("integrations/neotree", "files from visual selection:", files)
        return files, nil
      end
    end
  end

  if state.tree then
    local selection = nil

    if state.tree.get_selection then
      selection = state.tree:get_selection()
    end

    if (not selection or #selection == 0) and state.selected_nodes then
      selection = state.selected_nodes
    end

    if selection and #selection > 0 then
      logger.debug("integrations/neotree", "using state selection count=", #selection)
      for _, node in ipairs(selection) do
        if node.type == "file" and node.path then
          table.insert(files, node.path)
          logger.debug("integrations/neotree", "accepted file from state selection", node.path)
        else
          logger.debug(
            "integrations/neotree",
            "ignored non-file in state selection",
            tostring(node and node.type),
            tostring(node and node.path)
          )
        end
      end

      if #files > 0 then
        logger.debug("integrations/neotree", "files from state selection:", files)
        return files, nil
      end
    end
  end

  if state.tree then
    local node = state.tree:get_node()

    if node then
      logger.debug(
        "integrations/neotree",
        "fallback single node",
        "type=",
        tostring(node.type),
        "path=",
        tostring(node.path)
      )
      if node.type == "file" and node.path then
        return { node.path }, nil
      elseif node.type == "directory" and node.path then
        return { node.path }, nil
      end
    end
  end

  logger.debug("integrations/neotree", "no file found under cursor/selection")
  return {}, "No file found under cursor"
end

---Get selected files from oil.nvim
---Supports both visual selection and single file under cursor
---@return table files List of file paths
---@return string|nil error Error message if operation failed
function M._get_oil_selection()
  local success, oil = pcall(require, "oil")
  if not success then
    logger.debug("integrations/oil", "oil.nvim not available (require failed)")
    return {}, "oil.nvim not available"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local files = {}
  local mode = vim.fn.mode()
  local oil_selection = require("codex.oil_selection")

  if mode == "V" or mode == "v" or mode == "\22" then
    -- ビジュアル選択の行範囲からoil.nvimのエントリーを収集する
    local visual_commands = require("codex.visual_commands")
    local start_line, end_line = visual_commands.get_visual_range()
    local range_files, range_err = oil_selection.collect_paths_from_range(oil, bufnr, start_line, end_line)
    if range_err then
      return range_files, range_err
    end
    if #range_files > 0 then
      return range_files, nil
    end
  else
    -- 通常モードはカーソル下のエントリーだけを扱う
    local cursor_files, cursor_err = oil_selection.collect_paths_from_cursor(oil, bufnr)
    if cursor_err then
      return cursor_files, cursor_err
    end
    return cursor_files, nil
  end

  return files, "No file found under cursor"
end

return M
