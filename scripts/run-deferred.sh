#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd jq python3
ensure_runtime_dirs

if ! acquire_runner_lock; then
  log_line "runner skipped reason=lock_held"
  exit 0
fi

trap release_runner_lock EXIT

snapshot_file="$(mktemp "${DEFER_RUNTIME_DIR}/deferred-snapshot.XXXXXX")"
cp "$DEFER_TASKS_FILE" "$snapshot_file"

now_epoch="$(python3 "$SCRIPT_DIR/time_utils.py" epoch now)"

while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "$line" ]; then
    continue
  fi

  status="$(printf '%s' "$line" | jq -r '.status')"
  if [ "$status" != "scheduled" ]; then
    continue
  fi

  task_id="$(printf '%s' "$line" | jq -r '.id')"
  run_at="$(printf '%s' "$line" | jq -r '.run_at')"
  run_epoch="$(python3 "$SCRIPT_DIR/time_utils.py" epoch "$run_at")"

  if [ "$run_epoch" -gt "$now_epoch" ]; then
    continue
  fi

  executing_json="$(printf '%s' "$line" | jq \
    --arg started_at "$(now_utc_iso)" \
    '.status = "executing" | .started_at = $started_at')"
  replace_task_record "$executing_json"
  log_line "runner claimed id=$task_id run_at=$run_at"

  if ! printf '%s\n' "$executing_json" | "$SCRIPT_DIR/execute-task.sh" >/dev/null; then
    log_line "runner observed failure id=$task_id"
  fi
done < "$snapshot_file"

rm -f "$snapshot_file"
"$SCRIPT_DIR/archive-deferred.sh" >/dev/null
