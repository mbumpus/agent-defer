# Architecture

Agent Defer is a stateless deferred-execution runtime. There is no daemon, no database, and no long-lived process. The entire system is a JSONL file, a set of shell scripts, and cron.

## Data Flow

```
User invokes ::defer
        |
        v
schedule-task.sh
  - normalizes the time expression (time_utils.py)
  - optionally reorients from CONTEXT.md (reorient_snapshot.py)
  - builds a compact task snapshot
  - appends one JSON line to deferred.jsonl
        |
        v
deferred.jsonl  <--- the single source of truth
        |
        v
cron (every minute) --> run-deferred.sh
  - acquires runner lock
  - scans for tasks where run_at <= now
  - marks each as "executing"
  - hands each to execute-task.sh
        |
        v
execute-task.sh
  - always writes a prompt artifact to logs/
  - if DEFER_EXECUTOR is set and executable, pipes task JSON to it
  - on success: marks "completed"
  - on failure with retries left: reschedules to "scheduled" with new run_at
  - on terminal failure: marks "failed"
        |
        v
archive-deferred.sh
  - moves completed/failed/cancelled records to archive/deferred_YYYYMM.jsonl
  - keeps deferred.jsonl lean
```

## Key Design Decisions

**Stateless over stateful.** No process holds task state in memory. Every relevant fact lives in `deferred.jsonl`. If the machine reboots, cron picks up where it left off.

**Snapshots over transcripts.** The stored task captures intent, summary, key points, artifacts, and constraints — not raw chat history. This keeps records small and makes rehydration deterministic.

**Append-only with archival.** The runtime store is append-safe. Terminal records are swept into monthly archives, so the active file stays fast to scan.

**Lock-based concurrency.** Two lock mechanisms prevent data races: a runner lock (directory-based, stale-PID-aware) prevents overlapping cron invocations, and a task-file lock serializes reads and writes during record updates.

**Explicit timezone rejection.** Non-ISO time expressions use machine time or `DEFER_TIMEZONE`. Timezone suffixes like `3pm EST` are rejected rather than guessed, keeping scheduling deterministic.

## File Roles

| File | Role |
|---|---|
| `scripts/schedule-task.sh` | CLI entry point. Handles schedule, list, and cancel. |
| `scripts/run-deferred.sh` | Cron runner. Scans, claims, and dispatches due tasks. |
| `scripts/execute-task.sh` | Task executor. Writes prompt, optionally invokes executor. |
| `scripts/archive-deferred.sh` | Archiver. Sweeps terminal records to monthly files. |
| `scripts/common.sh` | Shared functions: locking, logging, record I/O. |
| `scripts/time_utils.py` | Time normalization. Durations, clock times, weekdays, ISO. |
| `scripts/reorient_snapshot.py` | Builds a snapshot from CONTEXT.md for deferred tasks. |
| `deferred.jsonl` | Active task store. One JSON object per line. |
| `archive/` | Monthly archives of terminal tasks. |
| `logs/` | Prompt artifacts and the deferred.log audit trail. |
