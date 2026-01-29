# このファイルはCodex.nvimの検証やテストを実行するためのコマンド定義をまとめています。
# Codex.nvim の検証や整形を実行するための Makefile
.PHONY: check format test clean

# Default target
all: format check test

# Detect if we are already inside a Nix shell
ifeq (,$(IN_NIX_SHELL))
# nix が利用できる場合だけ Nix 環境を使う
ifneq ($(shell command -v nix 2>/dev/null),)
NIX_PREFIX := nix develop .#ci -c
else
NIX_PREFIX :=
NIX_MISSING := 1
endif
else
NIX_PREFIX :=
endif

# Check for syntax errors
check:
	@echo "Checking Lua files for syntax errors..."
	$(NIX_PREFIX) find lua -name "*.lua" -type f -exec lua -e "assert(loadfile('{}'))" \;
	@echo "Running luacheck..."
	$(NIX_PREFIX) luacheck lua/ tests/ --no-unused-args --no-max-line-length

# Format all files
format:
	nix fmt

# Run tests
test:
	@echo "Running all tests..."
	@if [ -n "$(NIX_MISSING)" ]; then \
		echo "nix が見つからないためローカルの busted を使用します"; \
		if ! command -v busted >/dev/null 2>&1; then \
			echo "busted が見つかりません。luarocks などでインストールしてください。"; \
			exit 127; \
		fi; \
	fi
	@export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$$LUA_PATH"; \
	TEST_FILES=$$(find tests -type f -name "*_test.lua" -o -name "*_spec.lua" | sort); \
	echo "Found test files:"; \
	echo "$$TEST_FILES"; \
	if [ -n "$$TEST_FILES" ]; then \
		$(NIX_PREFIX) busted --coverage -v $$TEST_FILES; \
	else \
		echo "No test files found"; \
	fi

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -f luacov.report.out luacov.stats.out
	@rm -f tests/lcov.info

# Print available commands
help:
	@echo "Available commands:"
	@echo "  make check  - Check for syntax errors"
	@echo "  make format - Format all files (uses nix fmt or stylua)"
	@echo "  make test   - Run tests"
	@echo "  make clean  - Clean generated files"
	@echo "  make help   - Print this help message"
