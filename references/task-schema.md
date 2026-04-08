# Defer Task Schema

`deferred.jsonl` is append-safe and line-oriented. Each line is one task object.

## Canonical Shape

```json
{
  "id": "task_20260408_163500_4821",
  "created_at": "2026-04-08T16:35:00Z",
  "run_at": "2026-04-08T16:45:00Z",
  "type": "deferred_task",
  "intent": "resume_task",
  "context": {
    "summary": "Resume architecture review after the build settles.",
    "key_points": [
      "Review already narrowed to scheduler semantics",
      "Need a decision on callback vs fresh"
    ],
    "artifacts": [
      "/abs/path/to/notes.md"
    ],
    "constraints": [
      "No reliance on prior chat memory"
    ],
    "reoriented_from": "/abs/path/to/CONTEXT.md"
  },
  "execution": {
    "mode": "fresh",
    "prompt_template": "Continue the review and produce the next concrete recommendation.",
    "aura_level": "low"
  },
  "status": "scheduled",
  "attempts": 0,
  "max_retries": 2,
  "reorient_requested": true,
  "reorient": {
    "requested": true,
    "project": null,
    "explicit_context_file": "/abs/path/to/CONTEXT.md"
  }
}
```

## Status Lifecycle

- `scheduled`: task is waiting for `run_at`
- `executing`: runner claimed the task
- `completed`: execution succeeded or a prompt artifact was prepared
- `failed`: execution reached a terminal error
- `cancelled`: reserved for external cancellation flows

Terminal records are moved to `archive/deferred_YYYYMM.jsonl`.

When an executor fails and `attempts < max_retries`, the task is returned to `scheduled` with a new `run_at`, updated `attempts`, and `last_error`.

## Dynamic Fields

These fields appear during lifecycle transitions and are not always present on the initial scheduled record:

- `started_at`: set when the runner claims a task
- `completed_at`: set when execution completes
- `failed_at`: set when execution fails terminally
- `cancelled_at`: set when a scheduled task is cancelled
- `cancel_reason`: optional cancellation reason, `null` when omitted
- `last_attempt_at`: set when an executor failure triggers a retry
- `last_error`: most recent executor error recorded before retry
- `error`: terminal failure reason

## Result Types

`result.type` can be one of:

- `prompt_prepared`: no executor was configured; a prompt artifact was created
- `executor_output`: executor succeeded and returned output
- `executor_failed`: executor failed terminally after retries were exhausted
- `retry_scheduled`: executor failed but the task was rescheduled for another attempt

## Executor Contract

If `DEFER_EXECUTOR` is set, it must be an executable path. The executor:

1. receives one task JSON object on stdin
2. performs the deferred action
3. writes a concise result to stdout
4. exits `0` on success and non-zero on failure

The executor is intentionally simple so the skill remains stateless and auditable.

The prompt artifact at `logs/<task-id>.prompt.txt` is always created as an audit trail before executor handling begins.

If `DEFER_EXECUTOR` is not set, execution stops after creating that prompt artifact.

## Execution Fields

- `execution.mode`: `fresh` or `callback`
- `execution.prompt_template`: instruction passed into the future run
- `execution.aura_level`: advisory execution-intensity hint. Current scripts accept `low`, `medium`, and `high` and persist the value for downstream executors.

## Scheduling Policy

- Non-ISO time expressions are interpreted in machine time, or in `DEFER_TIMEZONE` if configured.
- Explicit timezone suffixes such as `3pm EST` are rejected.
- `attempts` starts at `0` and increments on executor retries or terminal executor failures.
- `max_retries` controls how many executor failures are retried before the task becomes terminal.
