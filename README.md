# Agent Defer

Stateless deferred execution for AI workflows: schedule, snapshot, rehydrate, and resume via JSONL and cron.

Agent Defer is a small skill-driven runtime for time-based re-entry. Instead of relying on long-lived agent state, it captures a compact task snapshot, persists it to an auditable log, and lets a cron-driven runner wake up later to continue the work.

The main primitive in this repository is [`defer`](./SKILL.md). It handles scheduling, snapshot persistence, execution, and archival. The repo also includes [`reorient`](./reorient/SKILL.md), which can rebuild clean context from a `CONTEXT.md` file before a task is scheduled.

## How It Works

1. Capture the task as a structured snapshot instead of raw chat history.
2. Normalize a future execution time such as `10m`, `2h`, or `tomorrow 9am`.
3. Persist the task as one JSON object per line in `deferred.jsonl`.
4. Let cron invoke the runner once a minute.
5. Rehydrate the stored context and execute the next step.

This keeps the system stateless, log-driven, auditable, and easy to replay.

## Included Skills

### `defer`

- Schedules future work with natural-language or duration-based time input
- Persists compact task snapshots to JSONL
- Supports `fresh` and `callback` execution modes
- Rehydrates due tasks from cron
- Logs scheduling, execution, failure, and archival events

### `reorient`

- Re-reads project context from `CONTEXT.md`
- Extracts a compact summary, constraints, references, and open questions
- Feeds cleaned context into deferred snapshots when requested via `--reorient`

## Repository Layout

```text
.
├── SKILL.md
├── agents/openai.yaml
├── references/task-schema.md
├── scripts/
│   ├── archive-deferred.sh
│   ├── common.sh
│   ├── execute-task.sh
│   ├── reorient_snapshot.py
│   ├── run-deferred.sh
│   ├── schedule-task.sh
│   └── time_utils.py
└── reorient/
    ├── SKILL.md
    └── agents/openai.yaml
```

## Quick Start

Schedule a deferred task:

```bash
./scripts/schedule-task.sh \
  --when "30m" \
  --summary "Resume the architecture review" \
  --intent "resume_task"
```

Schedule a task after reorienting from a context file:

```bash
./scripts/schedule-task.sh \
  --when "tomorrow 9am" \
  --reorient \
  --context-file "/abs/path/to/CONTEXT.md" \
  --summary "Continue the review with fresh context"
```

Run due tasks manually:

```bash
./scripts/run-deferred.sh
```

Run it continuously from cron:

```cron
* * * * * /absolute/path/to/scripts/run-deferred.sh
```

## Runtime

By default, runtime state is stored outside the repository:

```text
~/data/runtime/deferred.jsonl
~/data/runtime/archive/
~/data/runtime/logs/
```

You can override that with:

- `DEFER_RUNTIME_DIR`
- `DEFER_TASKS_FILE`
- `DEFER_ARCHIVE_DIR`
- `DEFER_LOG_DIR`
- `DEFER_LOG_FILE`
- `DEFER_TIMEZONE`
- `DEFER_EXECUTOR`
- `DEFER_CONTEXT_FILE`

## Notes

- `DEFER_EXECUTOR` is optional. If it is not set, execution writes a rehydration prompt artifact instead of invoking an external executor.
- The runtime intentionally lives outside the repo by default so scheduled state and logs do not pollute the source tree.
- This repository is licensed under `MIT`. That applies to both the scripts and the skill Markdown files, since the Markdown is part of the instruction surface.
