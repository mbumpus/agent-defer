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

## Executor Contract

If `DEFER_EXECUTOR` is set, it must be an executable path. The executor:

1. receives one task JSON object on stdin
2. performs the deferred action
3. writes a concise result to stdout
4. exits `0` on success and non-zero on failure

The executor is intentionally simple so the skill remains stateless and auditable.

If `DEFER_EXECUTOR` is not set, the skill still rehydrates the task into `logs/<task-id>.prompt.txt` so the operator can inspect or replay it manually.

## Execution Fields

- `execution.mode`: `fresh` or `callback`
- `execution.prompt_template`: instruction passed into the future run
- `execution.aura_level`: advisory execution-intensity hint. Current scripts accept `low`, `medium`, and `high` and persist the value for downstream executors.

## Scheduling Policy

- Non-ISO time expressions are interpreted in machine time, or in `DEFER_TIMEZONE` if configured.
- Explicit timezone suffixes such as `3pm EST` are rejected.
- `attempts` starts at `0` and increments on executor retries or terminal executor failures.
- `max_retries` controls how many executor failures are retried before the task becomes terminal.
