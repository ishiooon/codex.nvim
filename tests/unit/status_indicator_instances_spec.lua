-- このファイルは状態インジケータ用のインスタンス一覧取得を検証します。
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Status indicator instances", function()
  local module_name = "codex.status_indicator_instances"
  local original_globpath
  local original_io_open
  local original_json_decode
  local original_loop

  before_each(function()
    package.loaded[module_name] = nil
    package.loaded["codex.lockfile"] = { lock_dir = "/tmp/codex_test/ide" }
    original_globpath = vim.fn.globpath
    original_io_open = io.open
    original_json_decode = vim.json.decode
    original_loop = vim.loop
  end)

  after_each(function()
    vim.fn.globpath = original_globpath
    io.open = original_io_open
    vim.json.decode = original_json_decode
    vim.loop = original_loop
    package.loaded[module_name] = nil
    package.loaded["codex.lockfile"] = nil
  end)

  it("実行中プロセスのロックだけを返し、環境情報を展開する", function()
    local lock_a = "/tmp/codex_test/ide/41001.lock"
    local lock_b = "/tmp/codex_test/ide/41000.lock"
    local contents = {
      [lock_a] = [[{"pid":1002,"workspaceFolders":["/tmp/other"]}]],
      [lock_b] = [[{"pid":1001,"workspaceFolders":["/tmp/current","/tmp/extra"]}]],
    }

    vim.fn.globpath = function()
      -- 逆順で返しても最終結果はポート順に整列されることを確認する
      return { lock_a, lock_b }
    end
    io.open = function(path, mode)
      if mode == "r" and contents[path] then
        return {
          read = function()
            return contents[path]
          end,
          close = function() end,
        }
      end
      return original_io_open(path, mode)
    end
    vim.json.decode = function(text)
      if text == contents[lock_a] then
        return { pid = 1002, workspaceFolders = { "/tmp/other" } }
      end
      if text == contents[lock_b] then
        return { pid = 1001, workspaceFolders = { "/tmp/current", "/tmp/extra" } }
      end
      return {}
    end
    vim.loop = vim.loop or {}
    vim.loop.kill = function(pid, _)
      if pid == 1001 then
        return 0
      end
      return nil, "ESRCH"
    end

    local instances = require(module_name).list_running()
    assert(#instances == 1)
    assert(instances[1].port == 41000)
    assert(instances[1].pid == 1001)
    assert(instances[1].workspace == "/tmp/current")
    assert(type(instances[1].workspace_folders) == "table")
    assert(#instances[1].workspace_folders == 2)
  end)

  it("globpathが使えない場合は空配列を返す", function()
    vim.fn.globpath = nil

    local instances = require(module_name).list_running()
    assert(type(instances) == "table")
    assert(#instances == 0)
  end)

  it("他ユーザー所有でEPERMの場合も稼働中として扱う", function()
    local lock_path = "/tmp/codex_test/ide/42000.lock"
    local content = [[{"pid":2001,"workspaceFolders":["/tmp/shared"]}]]

    vim.fn.globpath = function()
      return { lock_path }
    end
    io.open = function(path, mode)
      if path == lock_path and mode == "r" then
        return {
          read = function()
            return content
          end,
          close = function() end,
        }
      end
      return original_io_open(path, mode)
    end
    vim.json.decode = function(text)
      if text == content then
        return { pid = 2001, workspaceFolders = { "/tmp/shared" } }
      end
      return {}
    end
    vim.loop = vim.loop or {}
    vim.loop.kill = function()
      -- 権限不足時の戻り値（nil, message, errno）を再現する
      return nil, "operation not permitted", "EPERM"
    end

    local instances = require(module_name).list_running()
    assert(#instances == 1)
    assert(instances[1].pid == 2001)
    assert(instances[1].workspace == "/tmp/shared")
  end)

  it("状態スナップショットがあれば他画面の状態として返す", function()
    local lock_path = "/tmp/codex_test/ide/43000.lock"
    local status_path = "/tmp/codex_test/ide/43000.status.json"
    local lock_content = [[{"pid":3001,"workspaceFolders":["/tmp/remote"]}]]
    local status_content = [[{"status":"wait","updatedAtMs":41000}]]

    vim.fn.globpath = function()
      return { lock_path }
    end
    io.open = function(path, mode)
      if mode == "r" and path == lock_path then
        return {
          read = function()
            return lock_content
          end,
          close = function() end,
        }
      end
      if mode == "r" and path == status_path then
        return {
          read = function()
            return status_content
          end,
          close = function() end,
        }
      end
      return original_io_open(path, mode)
    end
    vim.json.decode = function(text)
      if text == lock_content then
        return { pid = 3001, workspaceFolders = { "/tmp/remote" } }
      end
      if text == status_content then
        return { status = "wait", updatedAtMs = 41000 }
      end
      return {}
    end
    vim.loop = vim.loop or {}
    vim.loop.kill = function()
      return 0
    end
    vim.loop.now = function()
      return 42000
    end

    local instances = require(module_name).list_running()
    assert(#instances == 1)
    assert(instances[1].status == "wait")
  end)
end)
