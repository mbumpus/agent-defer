# Task Lifecycle

A deferred task moves through a small set of states. Every transition is logged to `deferred.log` and persisted to `deferred.jsonl`.

## States

```
                          +-----------+
                          | scheduled |<--------+
                          +-----+-----+         |
                                |               |
                          run_at <= now     retry (attempts < max_retries)
                                |               |
                          +-----v-----+         |
                          | executing |----+    |
                          +-----------+    |    |
                                           |    |
                     +----------+----------+----+
                     |          |          |
                success   failure    failure
                     |     (terminal)  (retriable)
                     |          |
               +-----v---+ +---v----+
               | completed| | failed |
               +----------+ +--------+

                          +-----------+
                          | cancelled |  (via cancel subcommand)
                          +-----------+
```

## Transitions

| From | To | Trigger |
|---|---|---|
| scheduled | executing | Runner claims the task (run_at <= now) |
| executing | completed | Executor succeeds or no executor configured |
| executing | failed | Executor fails terminally (retries exhausted or non-executable) |
| executing | scheduled | Executor fails with retries remaining (rescheduled) |
| scheduled | cancelled | User runs `schedule-task.sh cancel --id <id>` |

## Terminal States

`completed`, `failed`, and `cancelled` are terminal. The archiver moves terminal records from `deferred.jsonl` to `archive/deferred_YYYYMM.jsonl` after each runner cycle.

## Fields Added During Transitions

| Field | Set When |
|---|---|
| `started_at` | Runner claims the task |
| `completed_at` | Execution succeeds |
| `failed_at` | Execution fails terminally |
| `cancelled_at` | Task is cancelled |
| `cancel_reason` | Task is cancelled (optional) |
| `last_attempt_at` | Executor failure triggers a retry |
| `last_error` | Executor failure (most recent error) |
| `error` | Terminal failure reason |
| `result.type` | Any execution outcome |

## Result Types

| Type | Meaning |
|---|---|
| `prompt_prepared` | No executor configured; prompt artifact written |
| `executor_output` | Executor ran and succeeded |
| `executor_failed` | Executor failed terminally |
| `retry_scheduled` | Executor failed; task rescheduled for another attempt |
