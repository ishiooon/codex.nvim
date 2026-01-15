-- このファイルはテスト一式を起動する簡易ランナーです。
-- Test runner for Codex Neovim integration

local M = {}

-- Run all tests
function M.run()
  -- Set up minimal test environment
  require("tests.helpers.setup")()

  -- Discover and run all tests
  M.run_unit_tests()
  M.run_component_tests()
  M.run_integration_tests()

  -- Report results
  M.report_results()
end

-- Run unit tests
function M.run_unit_tests()
  -- Run all unit tests
  require("tests.unit.config_spec")
  require("tests.unit.server_spec")
  require("tests.unit.tools_spec")
  require("tests.unit.selection_spec")
  require("tests.unit.lockfile_spec")
end

-- Run component tests
function M.run_component_tests()
  -- Run all component tests
  require("tests.component.server_spec")
  require("tests.component.tools_spec")
end

-- Run integration tests
function M.run_integration_tests()
  -- Run all integration tests
  require("tests.integration.e2e_spec")
end

-- Report test results
function M.report_results()
  -- Print test summary
  print("All tests completed!")
  -- In a real implementation, this would report
  -- detailed test statistics
end

return M
