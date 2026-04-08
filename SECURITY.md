# Security

## Security Model

Agent Defer is a local-first tool. It runs on the user's machine, reads and writes to the local filesystem, and invokes executors as local processes. There is no network listener, no authentication layer, and no multi-tenant isolation.

### Input Handling

All user-supplied values (summaries, key points, artifacts, constraints, task IDs, cancel reasons) are passed to jq using `--arg`, which treats them as JSON strings. This prevents shell injection and JSON injection regardless of input content.

Tested explicitly: passing `$(echo INJECTED)` as a summary value is stored literally, not evaluated.

### Timezone Rejection

Explicit timezone suffixes (e.g., `3pm EST`, `9am PST`) are rejected at parse time. This is a deliberate design choice to prevent ambiguous scheduling. Non-ISO time expressions use machine time or the `DEFER_TIMEZONE` environment variable.

### Concurrency Safety

Two lock mechanisms prevent data corruption:

1. **Runner lock** (`$DEFER_RUNTIME_DIR/.defer.lock`): A directory-based lock with stale-PID detection. Prevents overlapping cron invocations from processing the same tasks simultaneously.

2. **Task-file lock** (`$DEFER_RUNTIME_DIR/.deferred-tasks.lock`): Serializes all reads and writes to `deferred.jsonl`. Used by `append_task_record`, `replace_task_record`, and the `cancel` subcommand.

### Executor Trust

The executor (`DEFER_EXECUTOR`) is fully trusted. It is invoked with the complete task JSON on stdin and runs with the same permissions as the user. Do not point `DEFER_EXECUTOR` at untrusted executables.

If the configured executor path is not executable, the task is marked as `failed` immediately without attempting execution.

### File Permissions

Runtime files (`deferred.jsonl`, archives, logs) are created with the user's default umask. If the runtime directory is shared or world-readable, task data (summaries, key points, artifacts) will be visible to other users. Restrict directory permissions if task content is sensitive.

### What This Tool Does Not Do

- Does not listen on any network port
- Does not transmit data over the network
- Does not store credentials or secrets
- Does not execute arbitrary code from task content — only the configured `DEFER_EXECUTOR`
- Does not escalate privileges

## Reporting Vulnerabilities

If you find a security issue, please email the maintainer directly rather than opening a public issue. Include:

- A description of the vulnerability
- Steps to reproduce
- Your assessment of severity

You will receive acknowledgment within 48 hours.

## Scope

This security model covers the scripts and runtime in this repository. It does not cover custom executors, which are the responsibility of the executor author.
