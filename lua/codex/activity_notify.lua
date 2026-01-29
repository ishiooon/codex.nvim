-- このファイルはCodex CLIの通知ファイルを監視し、イベントを渡します。
---@module "codex.activity_notify"

local M = {}

local state = {
  watcher = nil,
  path = nil,
  offset = 0,
  on_event = nil,
}

local function decode_json_line(line)
  if type(line) ~= "string" or line == "" then
    return nil
  end
  if vim and vim.json and type(vim.json.decode) == "function" then
    local ok, decoded = pcall(vim.json.decode, line)
    if ok then
      return decoded
    end
    return nil
  end
  if vim and vim.fn and type(vim.fn.json_decode) == "function" then
    local ok, decoded = pcall(vim.fn.json_decode, line)
    if ok then
      return decoded
    end
  end
  return nil
end

local function read_notify_lines(path)
  local handle = io.open(path, "r")
  if not handle then
    return
  end

  handle:seek("set", state.offset)
  for line in handle:lines() do
    local event = decode_json_line(line)
    if event and state.on_event then
      state.on_event(event)
    end
  end
  state.offset = handle:seek() or state.offset
  handle:close()
end

---通知ファイルの監視を開始します。
---@param path string
---@param on_event fun(event: table)
function M.start(path, on_event)
  if state.watcher then
    return
  end
  if type(path) ~= "string" or path == "" then
    return
  end

  state.path = path
  state.offset = 0
  state.on_event = on_event
  state.watcher = vim.loop.new_fs_poll()
  if not state.watcher then
    return
  end

  -- 通知ファイルの更新を監視し、イベントを読み取る
  state.watcher:start(path, 1000, function()
    vim.schedule(function()
      read_notify_lines(path)
    end)
  end)
end

---通知ファイルの監視を停止します。
function M.stop()
  if state.watcher then
    state.watcher:stop()
    state.watcher:close()
    state.watcher = nil
  end
  state.path = nil
  state.offset = 0
  state.on_event = nil
end

---内部状態を取得します（テスト向け）。
---@return table
function M._get_state_for_test()
  return {
    path = state.path,
    offset = state.offset,
  }
end

return M
