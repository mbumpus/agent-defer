#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

schedule_usage() {
  cat <<'EOF'
Usage:
  schedule-task.sh [schedule] --when <time> --summary <text> [options]

Options:
  --intent <resume_task|notify|execute_action>
  --mode <fresh|callback>
  --prompt-template <text>
  --aura-level <low|medium|high>
  --max-retries <count>
  --key-point <text>        Repeatable
  --artifact <text>         Repeatable
  --constraint <text>       Repeatable
  --context-json <json>
  --id <task_id>
  --reorient
  --project <project_name>
  --context-file <path>
  --dry-run
  --compact
  --help

Other commands:
  schedule-task.sh list [--status <value>] [--all] [--compact]
  schedule-task.sh cancel --id <task_id> [--reason <text>] [--compact]
EOF
}

list_usage() {
  cat <<'EOF'
Usage:
  schedule-task.sh list [options]

Options:
  --status <value>   Repeatable. Defaults to scheduled and executing.
  --all              Include every status.
  --compact
  --help
EOF
}

cancel_usage() {
  cat <<'EOF'
Usage:
  schedule-task.sh cancel --id <task_id> [options]

Options:
  --reason <text>
  --compact
  --help
EOF
}

require_cmd jq python3
ensure_runtime_dirs

schedule_task() {
  local when=""
  local summary=""
  local intent="resume_task"
  local mode="fresh"
  local prompt_template=""
  local aura_level="low"
  local max_retries="0"
  local context_json=""
  local task_id=""
  local reorient_requested="false"
  local project_name=""
  local context_file=""
  local dry_run="false"
  local compact_output="false"
  local key_points=()
  local artifacts=()
  local constraints=()
  local reorient_args=()
  local reorient_context_json=""
  local created_at=""
  local run_at=""
  local key_points_json=""
  local artifacts_json=""
  local constraints_json=""
  local base_context=""
  local merged_context=""
  local task_json=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --when)
        when="$2"
        shift 2
        ;;
      --summary)
        summary="$2"
        shift 2
        ;;
      --intent)
        intent="$2"
        shift 2
        ;;
      --mode)
        mode="$2"
        shift 2
        ;;
      --prompt-template)
        prompt_template="$2"
        shift 2
        ;;
      --aura-level)
        aura_level="$2"
        shift 2
        ;;
      --max-retries)
        max_retries="$2"
        shift 2
        ;;
      --key-point)
        key_points+=("$2")
        shift 2
        ;;
      --artifact)
        artifacts+=("$2")
        shift 2
        ;;
      --constraint)
        constraints+=("$2")
        shift 2
        ;;
      --context-json)
        context_json="$2"
        shift 2
        ;;
      --id)
        task_id="$2"
        shift 2
        ;;
      --reorient)
        reorient_requested="true"
        shift
        ;;
      --project)
        project_name="$2"
        shift 2
        ;;
      --context-file)
        context_file="$2"
        shift 2
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --compact)
        compact_output="true"
        shift
        ;;
      --help)
        schedule_usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        schedule_usage >&2
        exit 1
        ;;
    esac
  done

  if [ -z "$when" ]; then
    echo "--when is required" >&2
    exit 1
  fi

  if ! [[ "$max_retries" =~ ^[0-9]+$ ]]; then
    echo "--max-retries must be a non-negative integer" >&2
    exit 1
  fi

  if [ "$reorient_requested" = "true" ]; then
    if [ -n "$project_name" ]; then
      reorient_args+=("--project" "$project_name")
    fi
    if [ -n "$context_file" ]; then
      reorient_args+=("--context-file" "$context_file")
    fi
    reorient_context_json="$(python3 "$SCRIPT_DIR/reorient_snapshot.py" "${reorient_args[@]}")"

    if [ -n "$context_json" ]; then
      context_json="$(jq -cn \
        --argjson existing "$context_json" \
        --argjson reoriented "$reorient_context_json" \
        '{
          summary: ($existing.summary // $reoriented.summary),
          key_points: (($reoriented.key_points // []) + ($existing.key_points // [])),
          artifacts: (($reoriented.artifacts // []) + ($existing.artifacts // [])),
          constraints: (($reoriented.constraints // []) + ($existing.constraints // [])),
          reoriented_from: ($existing.reoriented_from // $reoriented.reoriented_from)
        }')"
    else
      context_json="$reorient_context_json"
    fi
  fi

  if [ -n "$context_json" ]; then
    printf '%s' "$context_json" | jq -e . >/dev/null
    if [ -z "$summary" ]; then
      summary="$(printf '%s' "$context_json" | jq -r '.summary // empty')"
    fi
  fi

  if [ -z "$summary" ]; then
    echo "--summary is required unless provided inside --context-json" >&2
    exit 1
  fi

  case "$intent" in
    resume_task|notify|execute_action) ;;
    *)
      echo "Invalid intent: $intent" >&2
      exit 1
      ;;
  esac

  case "$mode" in
    fresh|callback) ;;
    *)
      echo "Invalid mode: $mode" >&2
      exit 1
      ;;
  esac

  case "$aura_level" in
    low|medium|high) ;;
    *)
      echo "Invalid aura level: $aura_level" >&2
      exit 1
      ;;
  esac

  created_at="$(now_utc_iso)"
  run_at="$(python3 "$SCRIPT_DIR/time_utils.py" normalize "$when")"

  if [ -z "$task_id" ]; then
    task_id="task_$(date -u +%Y%m%d_%H%M%S)_$$"
  fi

  if [ -z "$prompt_template" ]; then
    prompt_template="$summary"
  fi

  if [ "${#key_points[@]}" -gt 0 ]; then
    key_points_json="$(json_array_from_args "${key_points[@]}")"
  else
    key_points_json='[]'
  fi

  if [ "${#artifacts[@]}" -gt 0 ]; then
    artifacts_json="$(json_array_from_args "${artifacts[@]}")"
  else
    artifacts_json='[]'
  fi

  if [ "${#constraints[@]}" -gt 0 ]; then
    constraints_json="$(json_array_from_args "${constraints[@]}")"
  else
    constraints_json='[]'
  fi

  base_context="$(jq -n \
    --arg summary "$summary" \
    --argjson key_points "$key_points_json" \
    --argjson artifacts "$artifacts_json" \
    --argjson constraints "$constraints_json" \
    '{
      summary: $summary,
      key_points: $key_points,
      artifacts: $artifacts,
      constraints: $constraints
    }')"

  if [ -n "$context_json" ]; then
    merged_context="$(jq -n \
      --argjson base "$base_context" \
      --argjson extra "$context_json" \
      '{
        summary: ($base.summary // $extra.summary),
        key_points: (($extra.key_points // []) + ($base.key_points // [])),
        artifacts: (($extra.artifacts // []) + ($base.artifacts // [])),
        constraints: (($extra.constraints // []) + ($base.constraints // [])),
        reoriented_from: ($extra.reoriented_from // null)
      }')"
  else
    merged_context="$base_context"
  fi

  task_json="$(jq -n \
    --arg id "$task_id" \
    --arg created_at "$created_at" \
    --arg run_at "$run_at" \
    --arg intent "$intent" \
    --arg mode "$mode" \
    --arg prompt_template "$prompt_template" \
    --arg aura_level "$aura_level" \
    --argjson context "$merged_context" \
    --arg reorient_requested "$reorient_requested" \
    --arg project_name "$project_name" \
    --arg context_file "$context_file" \
    --argjson max_retries "$max_retries" \
    '{
      id: $id,
      created_at: $created_at,
      run_at: $run_at,
      type: "deferred_task",
      intent: $intent,
      context: $context,
      execution: {
        mode: $mode,
        prompt_template: $prompt_template,
        aura_level: $aura_level
      },
      status: "scheduled",
      attempts: 0,
      max_retries: $max_retries,
      reorient_requested: ($reorient_requested == "true"),
      reorient: {
        requested: ($reorient_requested == "true"),
        project: (if $project_name == "" then null else $project_name end),
        explicit_context_file: (if $context_file == "" then null else $context_file end)
      }
    }')"

  if [ "$dry_run" = "false" ]; then
    append_task_record "$task_json"
    log_line "scheduled id=$task_id run_at=$run_at intent=$intent mode=$mode retries=$max_retries"
  fi

  print_json_output "$task_json" "$compact_output"
}

list_tasks() {
  local compact_output="false"
  local include_all="false"
  local statuses=()
  local statuses_json=""
  local tasks_json=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --status)
        statuses+=("$2")
        shift 2
        ;;
      --all)
        include_all="true"
        shift
        ;;
      --compact)
        compact_output="true"
        shift
        ;;
      --help)
        list_usage
        exit 0
        ;;
      *)
        echo "Unknown argument for list: $1" >&2
        list_usage >&2
        exit 1
        ;;
    esac
  done

  if [ "$include_all" = "false" ] && [ "${#statuses[@]}" -eq 0 ]; then
    statuses=("scheduled" "executing")
  fi

  if [ "${#statuses[@]}" -gt 0 ]; then
    statuses_json="$(json_array_from_args "${statuses[@]}")"
  else
    statuses_json='[]'
  fi

  if [ ! -s "$DEFER_TASKS_FILE" ]; then
    print_json_output '[]' "$compact_output"
    return 0
  fi

  tasks_json="$(jq -s \
    --argjson statuses "$statuses_json" \
    '[.[] | select(($statuses | length) == 0 or (.status as $status | any($statuses[]; . == $status)))]' \
    "$DEFER_TASKS_FILE")"

  print_json_output "$tasks_json" "$compact_output"
}

cancel_task() {
  local target_id=""
  local reason=""
  local compact_output="false"
  local tmp_file=""
  local line=""
  local line_id=""
  local line_status=""
  local cancelled_json=""
  local found="false"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        target_id="$2"
        shift 2
        ;;
      --reason)
        reason="$2"
        shift 2
        ;;
      --compact)
        compact_output="true"
        shift
        ;;
      --help)
        cancel_usage
        exit 0
        ;;
      *)
        echo "Unknown argument for cancel: $1" >&2
        cancel_usage >&2
        exit 1
        ;;
    esac
  done

  if [ -z "$target_id" ]; then
    echo "--id is required for cancel" >&2
    exit 1
  fi

  acquire_tasks_lock
  tmp_file="$(mktemp "${DEFER_RUNTIME_DIR}/deferred.XXXXXX")"

  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
      continue
    fi

    line_id="$(printf '%s' "$line" | jq -r '.id')"
    if [ "$line_id" = "$target_id" ]; then
      line_status="$(printf '%s' "$line" | jq -r '.status')"
      if [ "$line_status" != "scheduled" ]; then
        rm -f "$tmp_file"
        release_tasks_lock
        echo "Only scheduled tasks can be cancelled. Current status: $line_status" >&2
        exit 1
      fi

      cancelled_json="$(printf '%s' "$line" | jq \
        --arg cancelled_at "$(now_utc_iso)" \
        --arg reason "$reason" \
        '.status = "cancelled"
        | .cancelled_at = $cancelled_at
        | .cancel_reason = (if $reason == "" then null else $reason end)')"
      printf '%s\n' "$(printf '%s' "$cancelled_json" | jq -c .)" >> "$tmp_file"
      found="true"
    else
      printf '%s\n' "$line" >> "$tmp_file"
    fi
  done < "$DEFER_TASKS_FILE"

  if [ "$found" != "true" ]; then
    rm -f "$tmp_file"
    release_tasks_lock
    echo "Task not found: $target_id" >&2
    exit 1
  fi

  mv "$tmp_file" "$DEFER_TASKS_FILE"
  release_tasks_lock
  log_line "cancelled id=$target_id"
  print_json_output "$cancelled_json" "$compact_output"
}

subcommand="schedule"
if [ "$#" -gt 0 ]; then
  case "$1" in
    schedule|list|cancel)
      subcommand="$1"
      shift
      ;;
  esac
fi

case "$subcommand" in
  schedule)
    schedule_task "$@"
    ;;
  list)
    list_tasks "$@"
    ;;
  cancel)
    cancel_task "$@"
    ;;
esac
