# Changelog

All notable changes to Agent Defer are documented in this file.

## [1.0.0] - 2026-04-08

### Added

- `schedule-task.sh` with `schedule`, `list`, and `cancel` subcommands
- `run-deferred.sh` cron runner with lock-based overlap prevention
- `execute-task.sh` with executor contract and prompt artifact generation
- `archive-deferred.sh` for sweeping terminal records to monthly archives
- `time_utils.py` with support for compact durations (`10m`, `2h`), verbose durations (`2 hours`), clock times (`3pm`, `14:30`), `today`/`tomorrow` phrases, `noon`, `midnight`, `next <weekday>` forms, ISO 8601, and `now`
- `reorient_snapshot.py` for building task snapshots from `CONTEXT.md`
- `--dry-run` flag for previewing task JSON without persisting
- `--compact` flag for single-line JSON output across all subcommands
- `--max-retries` with automatic rescheduling on executor failure
- `--context-json` for passing pre-built snapshots to the scheduler
- `--reorient` integration with `--project` and `--context-file` options
- `aura_level` validation (`low`, `medium`, `high`)
- Task-file locking (`acquire_tasks_lock` / `release_tasks_lock`) for concurrent write safety
- Runner lock with stale-PID recovery
- `DEFER_RETRY_DELAY_SECONDS` environment variable
- Explicit timezone suffix rejection for deterministic scheduling
- 211-test suite covering all scripts, Python modules, and end-to-end workflows
- Documentation: architecture, lifecycle, task schema, examples, security model

### Fixed

- `--context-json` merge failure when `reoriented_from` was absent (jq `// empty` replaced with `// null`)
