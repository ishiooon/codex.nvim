-- このファイルはロックファイルから稼働中のCodexインスタンス一覧を取得します。
---@module "codex.status_indicator_instances"

local M = {}
local snapshot = require("codex.status_indicator_snapshot")
local STATUS_STALE_MS = 15000

local known_statuses = {
  idle = true,
  busy = true,
  wait = true,
  disconnected = true,
}

---改行区切り文字列を配列へ変換します。
---@param text string
---@return string[]
local function split_lines(text)
  local lines = {}
  for line in string.gmatch(text, "[^\n]+") do
    table.insert(lines, line)
  end
  return lines
end

---globpathの戻り値を配列へ正規化します。
---@param value any
---@return string[]
local function normalize_paths(value)
  if type(value) == "table" then
    return value
  end
  if type(value) == "string" and value ~= "" then
    return split_lines(value)
  end
  return {}
end

---ロックディレクトリ内のlockファイル一覧を取得します。
---@param lock_dir string
---@return string[]
local function list_lock_paths(lock_dir)
  if type(lock_dir) ~= "string" or lock_dir == "" then
    return {}
  end
  if not (vim.fn and type(vim.fn.globpath) == "function") then
    return {}
  end
  local ok, result = pcall(vim.fn.globpath, lock_dir, "*.lock", false, true)
  if not ok then
    return {}
  end
  return normalize_paths(result)
end

---JSONファイルを読み込んでテーブルへ変換します。
---@param path string
---@return table|nil
local function read_json(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  if type(content) ~= "string" or content == "" then
    return nil
  end
  if not (vim.json and type(vim.json.decode) == "function") then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

---現在時刻をミリ秒で返します。
---@return number
local function now_ms()
  local uv = vim.uv or vim.loop
  if uv and type(uv.now) == "function" then
    return uv.now()
  end
  return math.floor(os.time() * 1000)
end

---状態文字列を検証し、既定値へ正規化します。
---@param value any
---@return string
local function normalize_status(value)
  if type(value) == "string" and known_statuses[value] then
    return value
  end
  return "idle"
end

---状態スナップショットから有効な状態を取り出します。
---@param lock_path string
---@param current_ms number
---@return string
local function resolve_remote_status(lock_path, current_ms)
  local status_data = snapshot.read(lock_path)
  if type(status_data) ~= "table" then
    return "idle"
  end
  local status_value = normalize_status(status_data.status)
  local updated_at = tonumber(status_data.updatedAtMs or 0) or 0
  if updated_at > 0 and current_ms - updated_at > STATUS_STALE_MS then
    return "idle"
  end
  return status_value
end

---対象のPIDが稼働中かを判定します。
---@param pid number
---@return boolean
local function is_process_alive(pid)
  if type(pid) ~= "number" or pid <= 0 then
    return false
  end
  local uv = vim.uv or vim.loop
  if not (uv and type(uv.kill) == "function") then
    return true
  end
  local ok, result, err_message, err_name = pcall(uv.kill, pid, 0)
  if not ok then
    return false
  end
  if result == 0 or result == true then
    return true
  end
  if result == nil then
    -- 他ユーザー所有プロセスでは権限不足になるため、生存中として扱う
    local name_text = string.upper(tostring(err_name or ""))
    local message_text = string.upper(tostring(err_message or ""))
    if name_text == "EPERM" or name_text == "EACCES" then
      return true
    end
    if message_text:find("EPERM", 1, true) or message_text:find("EACCES", 1, true) then
      return true
    end
    if message_text:find("OPERATION NOT PERMITTED", 1, true) or message_text:find("PERMISSION DENIED", 1, true) then
      return true
    end
  end
  return false
end

---ロックファイル名からポート番号を抽出します。
---@param lock_path string
---@return number|nil
local function parse_port(lock_path)
  local port_text = lock_path:match("([0-9]+)%.lock$")
  if not port_text then
    return nil
  end
  return tonumber(port_text)
end

---workspaceFoldersから先頭の有効なパスを返します。
---@param workspace_folders any
---@return string[] all
---@return string|nil first
local function extract_workspaces(workspace_folders)
  if type(workspace_folders) ~= "table" then
    return {}, nil
  end
  local all = {}
  for _, folder in ipairs(workspace_folders) do
    if type(folder) == "string" and folder ~= "" then
      table.insert(all, folder)
    end
  end
  return all, all[1]
end

---ロック情報を表示用のインスタンス情報へ変換します。
---@param lock_path string
---@param lock_data table
---@param current_ms number
---@return table|nil
local function to_instance(lock_path, lock_data, current_ms)
  local pid = tonumber(lock_data.pid or 0) or 0
  if pid <= 0 or not is_process_alive(pid) then
    return nil
  end
  local workspace_folders, workspace = extract_workspaces(lock_data.workspaceFolders)
  return {
    lock_path = lock_path,
    port = parse_port(lock_path),
    pid = pid,
    workspace = workspace,
    workspace_folders = workspace_folders,
    status = resolve_remote_status(lock_path, current_ms),
  }
end

---稼働中インスタンスをロックディレクトリから収集します。
---@return table[]
function M.list_running()
  local ok, lockfile = pcall(require, "codex.lockfile")
  if not ok or type(lockfile.lock_dir) ~= "string" then
    return {}
  end
  local instances = {}
  local current_ms = now_ms()
  for _, lock_path in ipairs(list_lock_paths(lockfile.lock_dir)) do
    local lock_data = read_json(lock_path)
    if lock_data then
      local instance = to_instance(lock_path, lock_data, current_ms)
      if instance then
        table.insert(instances, instance)
      end
    end
  end
  table.sort(instances, function(a, b)
    local a_port = a.port or math.huge
    local b_port = b.port or math.huge
    if a_port ~= b_port then
      return a_port < b_port
    end
    return (a.lock_path or "") < (b.lock_path or "")
  end)
  return instances
end

return M
