---
name: defer
description: Schedules stateless work for later by normalizing a future time, capturing a minimal execution snapshot, and registering re-entry for cron-driven execution. Use when a user asks to resume later, remind later, follow up at a specific time, or queue deferred execution without relying on agent memory. Triggers naturally on `::defer`.
metadata:
  short-description: Schedule stateless work for later execution
---

# Defer

Use this skill when the user wants time-based re-entry, not ongoing memory. The skill captures intent, compresses current state into a deterministic snapshot, persists it, and hands execution off to a cron-driven runner.

## Operating Model

The primitive is:

1. Normalize a future time.
2. Compress current state into a structured snapshot.
3. Persist one JSON object per line in the runtime store.
4. Let cron wake a runner.
5. Rehydrate the task and execute a next step without relying on prior conversation memory.

Prefer a minimal snapshot over raw chat history. The stored task should describe:

- intent
- concise summary
- key points
- artifacts
- constraints
- execution mode
- prompt template for re-entry

## Workflow

### 1. Parse the request

Examples:

- `::defer 10m remind me to check the build`
- `::defer 2h resume this analysis`
- `::defer tomorrow 9am follow up with the latest findings`

Translate the request into:

- `when`: natural language or compact duration
- `intent`: `resume_task`, `notify`, or `execute_action`
- `mode`: `fresh` by default, `callback` only when continuation framing matters
- `prompt_template`: the instruction the future invocation should execute

### 2. Build the snapshot

Do not dump raw transcript state. Capture only what the future run needs:

- `summary`: one paragraph or less
- `key_points`: facts, decisions, open questions
- `artifacts`: paths, URLs, IDs, PRs, tickets
- `constraints`: deadlines, safety limits, scope boundaries

If a reorientation skill is available, use it before scheduling. If not, produce the compressed state directly.

### 3. Schedule the task

Use the deterministic scheduler script:

```bash
./scripts/schedule-task.sh \
  --when "30m" \
  --intent "resume_task" \
  --mode "fresh" \
  --summary "Resume the architecture review after the build settles." \
  --prompt-template "Continue the architecture review and focus on unresolved tradeoffs." \
  --key-point "Review in progress" \
  --artifact "/abs/path/to/notes.md" \
  --constraint "Do not assume prior chat memory"
```

The script writes a single task record to the runtime store and prints the resulting JSON.

If `--reorient` is set, the scheduler first builds snapshot context from `CONTEXT.md` using the `reorient` skill contract, then merges task-specific fields on top. Explicit task summary stays authoritative; reoriented context fills in supporting key points, artifacts, constraints, and source metadata.

You can point reorientation at a specific source:

```bash
./scripts/schedule-task.sh \
  --when "tomorrow 9am" \
  --reorient \
  --project "governance-first-training" \
  --summary "Resume the review with fresh context"
```

Or:

```bash
./scripts/schedule-task.sh \
  --when "2h" \
  --reorient \
  --context-file "/abs/path/to/CONTEXT.md" \
  --summary "Follow up on unresolved questions"
```

### 4. Confirm to the user

Summarize:

- what was scheduled
- when it will run
- which mode will be used
- whether the snapshot was captured cleanly

### 5. Execute from cron

Configure cron to run once a minute:

```cron
* * * * * /absolute/path/to/scripts/run-deferred.sh
```

The runner scans scheduled tasks, marks due work as executing, invokes `execute-task.sh`, then archives terminal records.

## Runtime Contract

By default the scripts use:

```text
~/data/runtime/deferred.jsonl
~/data/runtime/archive/deferred_YYYYMM.jsonl
~/data/runtime/logs/deferred.log
```

Override with environment variables when needed:

- `DEFER_RUNTIME_DIR`
- `DEFER_TASKS_FILE`
- `DEFER_ARCHIVE_DIR`
- `DEFER_LOG_DIR`
- `DEFER_LOG_FILE`
- `DEFER_TIMEZONE`
- `DEFER_EXECUTOR`

`DEFER_EXECUTOR` should point to an executable that reads one task JSON object from stdin and writes its result to stdout. If no executor is configured, `execute-task.sh` still produces a rehydration prompt file and marks the task complete with `result.type = "prompt_prepared"`.

## Execution Modes

### Fresh

Default. Use for most deferred work. The future run starts from the stored snapshot, not conversational carry-over.

### Callback

Use when the future run should feel like a continuation of the original framing. Keep the snapshot tight anyway.

## Files

- `scripts/time_utils.py`: normalize and compare times across macOS-friendly environments
- `scripts/reorient_snapshot.py`: derive a defer-ready snapshot from `CONTEXT.md`
- `scripts/schedule-task.sh`: persist a new deferred task
- `scripts/run-deferred.sh`: cron runner
- `scripts/execute-task.sh`: rehydrate and invoke the executor
- `scripts/archive-deferred.sh`: move terminal tasks to monthly archives
- `references/task-schema.md`: snapshot and executor contract

## Failure Handling

- Missing executor: generate a prompt artifact and log it instead of looping forever
- Missing `CONTEXT.md` during `--reorient`: fail fast with the exact missing path or lookup mode
- Invalid time: fail fast before writing any task
- Duplicate runner overlap: prevented by a runtime lock directory
- Context drift: avoid by storing summary, key points, artifacts, and constraints explicitly
- Auditing: every schedule, execution, failure, and archive action is appended to the log

## Output Pattern

When the user invokes `::defer`, the skill should produce a short confirmation in natural language after `schedule-task.sh` succeeds. Keep the user-facing response separate from the stored JSON snapshot.
