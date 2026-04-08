# Agent Defer

[![Tests](https://img.shields.io/badge/tests-210%20%2F%20211%20passing-brightgreen)](#test-results)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Status](https://img.shields.io/badge/status-stable%20v1.0-informational)](#whats-stable)

Stateless deferred execution for AI workflows. Schedule, snapshot, rehydrate, and resume — with JSONL, shell scripts, and cron.

## Why This Exists

AI agents lose context between sessions. Long-running work gets dropped when conversations end. Most solutions reach for databases, daemons, or orchestration frameworks.

Agent Defer takes a different approach: capture a compact snapshot of intent, persist it as one JSON line, and let cron wake a runner to continue the work later. No daemon. No database. No state held in memory. If the machine reboots, cron picks up where it left off.

The result is a time-based re-entry primitive that is stateless, auditable, and easy to reason about.

## How It Works

```
  User                schedule-task.sh         deferred.jsonl
   |                        |                       |
   |--- ::defer 30m ------->|                       |
   |                        |-- normalize time      |
   |                        |-- build snapshot      |
   |                        |-- append record ----->|
   |                                                |
   |    cron (every minute)     run-deferred.sh     |
   |         |                       |              |
   |         |--- wake ------------->|              |
   |         |                       |-- scan ----->|
   |         |                       |              |
   |         |                  execute-task.sh     |
   |         |                       |              |
   |         |                       |-- write prompt artifact
   |         |                       |-- invoke executor (optional)
   |         |                       |-- update status -------->|
   |         |                       |              |
   |         |                  archive-deferred.sh |
   |         |                       |-- sweep terminal records
```

See [docs/architecture.md](docs/architecture.md) for the full design and [docs/lifecycle.md](docs/lifecycle.md) for state transitions.

### This is not a long-running agent system.
### This is not a memory layer.
### This is not a workflow engine.

It is a minimal deferred execution primitive.

## Quick Start

### 1. Schedule a task

```bash
./scripts/schedule-task.sh \
  --when "30m" \
  --summary "Resume the architecture review" \
  --intent "resume_task"
```

### 2. See what's pending

```bash
./scripts/schedule-task.sh list
```

### 3. Run due tasks

```bash
./scripts/run-deferred.sh
```

### 4. Check the archive

```bash
cat ~/data/runtime/archive/deferred_*.jsonl | jq .
```

### Full loop demo

```bash
# Schedule a task due immediately
./scripts/schedule-task.sh --when "now" --summary "Check build status" --id "demo_1"

# Verify it's pending
./scripts/schedule-task.sh list --compact

# Execute due tasks
./scripts/run-deferred.sh

# Task is now archived; prompt artifact is in logs/
cat ~/data/runtime/logs/demo_1.prompt.txt
```

See [examples/](examples/) for more: a simple reminder, a resumed analysis, and a scheduled reorient.

## Features

- **Natural-language scheduling**: `10m`, `2h`, `tomorrow 9am`, `noon`, `midnight`, `next friday 3pm`
- **Compact snapshots**: summary, key points, artifacts, constraints — not raw chat history
- **Two execution modes**: `fresh` (default) and `callback`
- **Retry with backoff**: `--max-retries` reschedules executor failures automatically
- **Preview before committing**: `--dry-run` shows the task JSON without persisting
- **Task management**: `list` and `cancel` subcommands
- **Reorientation**: `--reorient` rebuilds context from `CONTEXT.md` before scheduling
- **Scripting-friendly**: `--compact` emits single-line JSON
- **Deterministic timezone handling**: machine time or `DEFER_TIMEZONE`; explicit suffixes like `3pm EST` are rejected
- **Concurrency-safe**: file-level locking on all writes; runner lock prevents cron overlap
- **Auditable**: every action logged to `deferred.log`; prompt artifacts always created

## Included Skills

### `defer`

The main primitive. Handles scheduling, snapshot persistence, execution, and archival. See [SKILL.md](SKILL.md).

### `reorient`

Rebuilds clean context from a `CONTEXT.md` file and feeds it into deferred snapshots. See [reorient/SKILL.md](reorient/SKILL.md).

## Repository Layout

```
.
├── SKILL.md                    # Defer skill definition
├── README.md
├── LICENSE
├── CHANGELOG.md
├── RELEASE_NOTES_v1.md
├── Makefile
├── .env.example
├── agents/openai.yaml
├── references/task-schema.md   # JSON schema and executor contract
├── scripts/
│   ├── archive-deferred.sh
│   ├── common.sh
│   ├── execute-task.sh
│   ├── reorient_snapshot.py
│   ├── run-deferred.sh
│   ├── schedule-task.sh
│   └── time_utils.py
├── reorient/
│   ├── SKILL.md
│   └── agents/openai.yaml
├── tests/
│   ├── test_time_utils.py
│   ├── test_reorient_snapshot.py
│   ├── test_shell_scripts.sh
│   └── test_new_features.sh
├── examples/
│   ├── reminder.sh
│   ├── resume-analysis.sh
│   └── scheduled-reorient.sh
└── docs/
    ├── architecture.md
    ├── architecture.mermaid
    ├── lifecycle.md
    └── reports/
        └── final-test-report.pdf
```

## Runtime

By default, runtime state lives outside the repository:

```
~/data/runtime/deferred.jsonl       # Active task store
~/data/runtime/archive/             # Monthly archives
~/data/runtime/logs/                # Prompt artifacts and audit log
```

### Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DEFER_RUNTIME_DIR` | `~/data/runtime` | Root directory for all runtime state |
| `DEFER_TASKS_FILE` | `$DEFER_RUNTIME_DIR/deferred.jsonl` | Active task store |
| `DEFER_ARCHIVE_DIR` | `$DEFER_RUNTIME_DIR/archive` | Monthly archive directory |
| `DEFER_LOG_DIR` | `$DEFER_RUNTIME_DIR/logs` | Prompt artifacts and log directory |
| `DEFER_LOG_FILE` | `$DEFER_LOG_DIR/deferred.log` | Audit log |
| `DEFER_TIMEZONE` | System timezone | Timezone for non-ISO time expressions |
| `DEFER_EXECUTOR` | *(none)* | Executable that processes task JSON on stdin |
| `DEFER_CONTEXT_FILE` | *(none)* | Fallback context file for `reorient_snapshot.py` |
| `DEFER_RETRY_DELAY_SECONDS` | `60` | Delay before retrying a failed executor |

See [.env.example](.env.example) for a starter configuration.

### Cron Setup

```cron
* * * * * /absolute/path/to/scripts/run-deferred.sh
```

## Test Results

211 tests across 4 suites. 210 passing. 99.5% pass rate.

| Suite | Tests | Passed |
|---|---|---|
| `time_utils.py` (Python) | 59 | 59 |
| `reorient_snapshot.py` (Python) | 28 | 28 |
| Shell scripts (original) | 70 | 70 |
| Shell scripts (new features) | 54 | 53* |

\* One test-harness issue (grep regex syntax with `[]`), not a code bug.

```bash
make test
```

The full test report is in [docs/reports/final-test-report.pdf](docs/reports/final-test-report.pdf).

## What's Stable

These are committed interfaces. They won't break without a major version bump.

- JSONL task persistence format ([references/task-schema.md](references/task-schema.md))
- Cron wake cycle (`run-deferred.sh`)
- `fresh` and `callback` execution modes
- Retry behavior (`max_retries`, `DEFER_RETRY_DELAY_SECONDS`)
- `list` and `cancel` subcommands
- Time expression parsing (durations, clock times, weekdays, ISO)
- Reorient integration (`--reorient`, `--context-file`, `--project`)
- All environment variables listed above
- Executor contract (stdin JSON, stdout result, exit code)

## Extension Points

These are designed to be built on.

- **Executor adapters**: Write any executable that reads task JSON from stdin. Shell scripts, Python, compiled binaries — anything that follows the contract.
- **Alternative storage backends**: Replace `deferred.jsonl` with a database by swapping `append_task_record` and `replace_task_record` in `common.sh`.
- **Webhook or event triggers**: Wrap `schedule-task.sh` in an HTTP endpoint or message queue consumer.
- **UI wrappers**: `list --compact` and `cancel --compact` emit machine-readable JSON for frontend consumption.
- **Multi-agent routing**: Use `execution.aura_level` or custom executor logic to route tasks to different agents based on complexity.

## Documentation

- [Architecture](docs/architecture.md) — data flow, design decisions, file roles
- [Lifecycle](docs/lifecycle.md) — task states, transitions, dynamic fields, result types
- [Task Schema](references/task-schema.md) — canonical JSON shape, executor contract, scheduling policy
- [SKILL.md](SKILL.md) — the defer skill definition for AI agent integration
- [Changelog](CHANGELOG.md)
- [Release Notes v1.0](RELEASE_NOTES_v1.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md) for the security model and reporting policy.

## License

[MIT](LICENSE)
