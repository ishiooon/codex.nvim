#!/usr/bin/env sh
# Codex CLI の notify イベントをファイルへ追記する

if [ -z "${CODEX_NVIM_NOTIFY_PATH:-}" ]; then
  exit 0
fi

notify_dir=$(dirname "$CODEX_NVIM_NOTIFY_PATH")
if [ -n "$notify_dir" ]; then
  mkdir -p "$notify_dir"
fi

printf '%s\n' "$1" >> "$CODEX_NVIM_NOTIFY_PATH"
