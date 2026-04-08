# Release Notes — v1.0.0

**Date:** April 8, 2026

## Summary

Agent Defer v1.0 is the first stable release of a stateless deferred-execution runtime for AI workflows. It provides time-based re-entry without daemons, databases, or long-lived state.

## What It Does

Schedule a task for later execution with a natural-language time expression. The system captures a compact snapshot of intent, persists it as a single JSON line, and lets cron wake a runner to continue the work. The entire runtime is a JSONL file, a set of shell scripts, and cron.

## Highlights

**Natural-language scheduling.** Supports compact durations (`10m`, `2h`), verbose durations (`2 hours 30 minutes`), clock times (`3pm`, `14:30`), day phrases (`tomorrow 9am`), `noon`, `midnight`, weekday forms (`next friday 3pm`), ISO 8601, and `now`.

**Task management.** `list` queries pending tasks with status filtering. `cancel` cancels scheduled tasks by ID with an optional reason.

**Retry behavior.** `--max-retries` reschedules executor failures instead of marking them terminal. The retry delay is configurable via `DEFER_RETRY_DELAY_SECONDS`.

**Preview mode.** `--dry-run` outputs the normalized task JSON without writing to the store or logging.

**Reorientation.** `--reorient` rebuilds context from a `CONTEXT.md` file before scheduling, so deferred tasks start with clean project context.

**Concurrency safety.** File-level locking serializes all task-file writes. A runner lock prevents overlapping cron invocations with stale-PID recovery.

**Deterministic timezone handling.** Non-ISO time expressions use machine time or `DEFER_TIMEZONE`. Explicit suffixes like `3pm EST` are rejected.

## Test Results

211 tests across 4 suites. 210 passing. 99.5% pass rate.

The single non-passing result is a test-harness issue (grep regex syntax), not a code bug. The full test report is at `docs/reports/final-test-report.pdf`.

## Breaking Changes

None. This is the first release.

## Known Limitations

- No built-in web UI or API server. The CLI and cron are the interface.
- Weekday scheduling supports `next <weekday>` only, not `this <weekday>` or ordinal forms like `second tuesday`.
- The executor contract is fire-and-forget per invocation. Long-running executors are not monitored after launch.

## What's Next

See the Extension Points section in the README for where the system is designed to be built on: executor adapters, alternative storage backends, webhook triggers, UI wrappers, and multi-agent routing.
