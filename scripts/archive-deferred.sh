#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd jq
ensure_runtime_dirs

tmp_file="$(mktemp "${DEFER_RUNTIME_DIR}/deferred.XXXXXX")"

while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "$line" ]; then
    continue
  fi

  status="$(printf '%s' "$line" | jq -r '.status')"
  case "$status" in
    completed|failed|cancelled)
      archive_stamp="$(printf '%s' "$line" | jq -r '.completed_at // .failed_at // .cancelled_at // .created_at')"
      archive_month="${archive_stamp%%-*}"
      archive_month="${archive_stamp:0:7}"
      archive_month="${archive_month//-/}"
      archive_file="$DEFER_ARCHIVE_DIR/deferred_${archive_month}.jsonl"
      printf '%s\n' "$line" >> "$archive_file"
      task_id="$(printf '%s' "$line" | jq -r '.id')"
      log_line "archived id=$task_id file=$archive_file"
      ;;
    *)
      printf '%s\n' "$line" >> "$tmp_file"
      ;;
  esac
done < "$DEFER_TASKS_FILE"

mv "$tmp_file" "$DEFER_TASKS_FILE"
