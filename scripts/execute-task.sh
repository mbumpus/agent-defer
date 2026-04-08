#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd jq
ensure_runtime_dirs

task_json="$(cat)"
printf '%s' "$task_json" | jq -e . >/dev/null

task_id="$(printf '%s' "$task_json" | jq -r '.id')"
intent="$(printf '%s' "$task_json" | jq -r '.intent')"
mode="$(printf '%s' "$task_json" | jq -r '.execution.mode')"
summary="$(printf '%s' "$task_json" | jq -r '.context.summary // ""')"
prompt_template="$(printf '%s' "$task_json" | jq -r '.execution.prompt_template // .context.summary // ""')"
key_points_block="$(printf '%s' "$task_json" | jq -r '.context.key_points | if length == 0 then "- (none)" else map("- " + .) | join("\n") end')"
artifacts_block="$(printf '%s' "$task_json" | jq -r '.context.artifacts | if length == 0 then "- (none)" else map("- " + .) | join("\n") end')"
constraints_block="$(printf '%s' "$task_json" | jq -r '.context.constraints | if length == 0 then "- (none)" else map("- " + .) | join("\n") end')"
prompt_path="$DEFER_LOG_DIR/${task_id}.prompt.txt"

final_prompt="$(
  printf '%s\n' \
    "You are resuming a deferred task." \
    "" \
    "Task ID: $task_id" \
    "Intent: $intent" \
    "Mode: $mode" \
    "" \
    "Summary:" \
    "$summary" \
    "" \
    "Key Points:" \
    "$key_points_block" \
    "" \
    "Artifacts:" \
    "$artifacts_block" \
    "" \
    "Constraints:" \
    "$constraints_block" \
    "" \
    "Task:" \
    "$prompt_template"
)"

printf '%s\n' "$final_prompt" > "$prompt_path"

completed_at="$(now_utc_iso)"
attempts="$(printf '%s' "$task_json" | jq -r '.attempts // 0')"
max_retries="$(printf '%s' "$task_json" | jq -r '.max_retries // 0')"

if [ -n "${DEFER_EXECUTOR:-}" ]; then
  if [ ! -x "$DEFER_EXECUTOR" ]; then
    error_text="Configured DEFER_EXECUTOR is not executable: $DEFER_EXECUTOR"
    updated_json="$(printf '%s' "$task_json" | jq \
      --arg failed_at "$completed_at" \
      --arg error "$error_text" \
      '.status = "failed" | .failed_at = $failed_at | .error = $error')"
    replace_task_record "$updated_json"
    log_line "failed id=$task_id reason=executor_not_executable"
    printf '%s\n' "$updated_json"
    exit 1
  fi

  if executor_output="$(printf '%s\n' "$task_json" | "$DEFER_EXECUTOR" 2>&1)"; then
    updated_json="$(printf '%s' "$task_json" | jq \
      --arg completed_at "$completed_at" \
      --arg output "$executor_output" \
      --arg prompt_path "$prompt_path" \
      '.status = "completed"
      | .completed_at = $completed_at
      | .result = {
          type: "executor_output",
          output: $output,
          prompt_path: $prompt_path
        }')"
    replace_task_record "$updated_json"
    log_line "executed id=$task_id mode=executor"
    printf '%s\n' "$updated_json"
    exit 0
  fi

  if [ "$attempts" -lt "$max_retries" ]; then
    next_run_at="$(retry_run_at)"
    updated_json="$(printf '%s' "$task_json" | jq \
      --arg run_at "$next_run_at" \
      --arg retried_at "$completed_at" \
      --arg error "$executor_output" \
      --arg prompt_path "$prompt_path" \
      --argjson attempts "$((attempts + 1))" \
      '.status = "scheduled"
      | .run_at = $run_at
      | .attempts = $attempts
      | .last_attempt_at = $retried_at
      | .last_error = $error
      | .result = {
          type: "retry_scheduled",
          next_run_at: $run_at,
          prompt_path: $prompt_path
        }')"
    replace_task_record "$updated_json"
    log_line "retry scheduled id=$task_id attempt=$((attempts + 1)) next_run_at=$next_run_at"
    printf '%s\n' "$updated_json"
    exit 0
  fi

  updated_json="$(printf '%s' "$task_json" | jq \
    --arg failed_at "$completed_at" \
    --arg error "$executor_output" \
    --arg prompt_path "$prompt_path" \
    --argjson attempts "$((attempts + 1))" \
    '.status = "failed"
    | .failed_at = $failed_at
    | .attempts = $attempts
    | .error = $error
    | .result = {
        type: "executor_failed",
        prompt_path: $prompt_path
      }')"
  replace_task_record "$updated_json"
  log_line "failed id=$task_id reason=executor_nonzero"
  printf '%s\n' "$updated_json"
  exit 1
fi

updated_json="$(printf '%s' "$task_json" | jq \
  --arg completed_at "$completed_at" \
  --arg prompt_path "$prompt_path" \
  '.status = "completed"
  | .completed_at = $completed_at
  | .result = {
      type: "prompt_prepared",
      prompt_path: $prompt_path
    }')"

replace_task_record "$updated_json"
log_line "executed id=$task_id mode=prompt_prepared"
printf '%s\n' "$updated_json"
