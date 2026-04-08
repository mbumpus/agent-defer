#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-task.sh --when <time> --summary <text> [options]

Options:
  --intent <resume_task|notify|execute_action>
  --mode <fresh|callback>
  --prompt-template <text>
  --aura-level <low|medium|high>
  --key-point <text>        Repeatable
  --artifact <text>         Repeatable
  --constraint <text>       Repeatable
  --context-json <json>
  --id <task_id>
  --reorient
  --project <project_name>
  --context-file <path>
  --help
EOF
}

require_cmd jq python3
ensure_runtime_dirs

when=""
summary=""
intent="resume_task"
mode="fresh"
prompt_template=""
aura_level="low"
context_json=""
task_id=""
reorient_requested="false"
project_name=""
context_file=""
key_points=()
artifacts=()
constraints=()

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
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$when" ]; then
  echo "--when is required" >&2
  exit 1
fi

if [ "$reorient_requested" = "true" ]; then
  reorient_args=()
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
      reoriented_from: ($extra.reoriented_from // empty)
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
    reorient_requested: ($reorient_requested == "true"),
    reorient: {
      requested: ($reorient_requested == "true"),
      project: (if $project_name == "" then null else $project_name end),
      explicit_context_file: (if $context_file == "" then null else $context_file end)
    }
  }')"

append_task_record "$task_json"
log_line "scheduled id=$task_id run_at=$run_at intent=$intent mode=$mode"

printf '%s\n' "$task_json"
