#!/usr/bin/env bash
# このスクリプトはCodex.nvimのテストを指定した環境名で実行するための補助です。
# Codex.nvim のテストを指定環境で実行するためのラッパー。
set -euo pipefail

TEST_ENV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env=*)
      TEST_ENV="${1#--env=}"
      shift
      ;;
    --env)
      TEST_ENV="${2:-}"
      shift 2
      ;;
    *)
      echo "不明な引数です: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$TEST_ENV" ]]; then
  export CODEX_TEST_ENV="$TEST_ENV"
fi

make test
