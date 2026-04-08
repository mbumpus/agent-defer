#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFER_RUNTIME_DIR="${DEFER_RUNTIME_DIR:-$HOME/data/runtime}"
DEFER_TASKS_FILE="${DEFER_TASKS_FILE:-$DEFER_RUNTIME_DIR/deferred.jsonl}"
DEFER_ARCHIVE_DIR="${DEFER_ARCHIVE_DIR:-$DEFER_RUNTIME_DIR/archive}"
DEFER_LOG_DIR="${DEFER_LOG_DIR:-$DEFER_RUNTIME_DIR/logs}"
DEFER_LOG_FILE="${DEFER_LOG_FILE:-$DEFER_LOG_DIR/deferred.log}"
DEFER_TIMEZONE="${DEFER_TIMEZONE:-${TZ:-}}"

now_utc_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ensure_runtime_dirs() {
  mkdir -p "$DEFER_RUNTIME_DIR" "$DEFER_ARCHIVE_DIR" "$DEFER_LOG_DIR"
  touch "$DEFER_TASKS_FILE" "$DEFER_LOG_FILE"
}

require_cmd() {
  local missing=0
  local cmd

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Missing required command: $cmd" >&2
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    return 1
  fi
}

log_line() {
  ensure_runtime_dirs
  printf '%s %s\n' "$(now_utc_iso)" "$*" >> "$DEFER_LOG_FILE"
}

json_array_from_args() {
  if [ "$#" -eq 0 ]; then
    printf '[]'
    return
  fi

  printf '%s\n' "$@" | jq -R . | jq -s .
}

replace_task_record() {
  local updated_json="$1"
  local updated_compact
  local task_id
  local tmp_file
  local found=0
  local line
  local line_id

  ensure_runtime_dirs
  updated_compact="$(printf '%s' "$updated_json" | jq -c .)"
  task_id="$(printf '%s' "$updated_compact" | jq -r '.id')"
  tmp_file="$(mktemp "${DEFER_RUNTIME_DIR}/deferred.XXXXXX")"

  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
      continue
    fi

    line_id="$(printf '%s' "$line" | jq -r '.id')"
    if [ "$line_id" = "$task_id" ]; then
      printf '%s\n' "$updated_compact" >> "$tmp_file"
      found=1
    else
      printf '%s\n' "$line" >> "$tmp_file"
    fi
  done < "$DEFER_TASKS_FILE"

  if [ "$found" -eq 0 ]; then
    printf '%s\n' "$updated_compact" >> "$tmp_file"
  fi

  mv "$tmp_file" "$DEFER_TASKS_FILE"
}

append_task_record() {
  local task_json="$1"
  local task_compact

  ensure_runtime_dirs
  task_compact="$(printf '%s' "$task_json" | jq -c .)"
  printf '%s\n' "$task_compact" >> "$DEFER_TASKS_FILE"
}

acquire_runner_lock() {
  local lock_dir="$DEFER_RUNTIME_DIR/.defer.lock"
  local stale_pid=""

  ensure_runtime_dirs

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    return 0
  fi

  if [ -f "$lock_dir/pid" ]; then
    stale_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    if [ -n "$stale_pid" ] && ! kill -0 "$stale_pid" 2>/dev/null; then
      rm -rf "$lock_dir"
      if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "$lock_dir/pid"
        return 0
      fi
    fi
  fi

  return 1
}

release_runner_lock() {
  rm -rf "$DEFER_RUNTIME_DIR/.defer.lock"
}
