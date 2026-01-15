-- このファイルは最低限の動作を確認する簡易テストです。
-- Simple test without using the mock vim API

describe("Simple Tests", function()
  describe("Math operations", function()
    it("should add numbers correctly", function()
      assert.are.equal(4, 2 + 2)
    end)

    it("should multiply numbers correctly", function()
      assert.are.equal(6, 2 * 3)
    end)
  end)

  describe("String operations", function()
    it("should concatenate strings", function()
      assert.are.equal("Hello World", "Hello " .. "World")
    end)
  end)
end)
