-- このファイルはインスタンス間で共有する状態スナップショットを読み書きします。
---@module "codex.status_indicator_snapshot"

local M = {}

---lockファイルのパスから状態ファイルのパスを作成します。
---@param lock_path string
---@return string|nil
function M.path_from_lock_path(lock_path)
  if type(lock_path) ~= "string" then
    return nil
  end
  local status_path, replaced = lock_path:gsub("%.lock$", ".status.json")
  if replaced == 0 then
    return nil
  end
  return status_path
end

---状態ファイルを読み込み、JSONをテーブルへ変換します。
---@param lock_path string
---@return table|nil
function M.read(lock_path)
  local status_path = M.path_from_lock_path(lock_path)
  if not status_path then
    return nil
  end
  local file = io.open(status_path, "r")
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

---状態ファイルへJSONを書き込みます。
---@param lock_path string
---@param snapshot table
---@return boolean
function M.write(lock_path, snapshot)
  local status_path = M.path_from_lock_path(lock_path)
  if not status_path or type(snapshot) ~= "table" then
    return false
  end
  if not (vim.json and type(vim.json.encode) == "function") then
    return false
  end
  local ok, encoded = pcall(vim.json.encode, snapshot)
  if not ok or type(encoded) ~= "string" then
    return false
  end
  local file = io.open(status_path, "w")
  if not file then
    return false
  end
  local write_ok = pcall(function()
    file:write(encoded)
    file:close()
  end)
  if not write_ok then
    pcall(function()
      file:close()
    end)
    return false
  end
  return true
end

---状態ファイルを削除します。
---@param lock_path string
---@return boolean
function M.remove(lock_path)
  local status_path = M.path_from_lock_path(lock_path)
  if not status_path then
    return false
  end
  local ok = pcall(function()
    os.remove(status_path)
  end)
  return ok
end

return M
