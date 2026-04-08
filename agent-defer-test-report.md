# Agent Defer — Test Report & Findings

**Date:** April 8, 2026  
**Repository:** https://github.com/mbumpus/agent-defer  
**Tester:** Claude (automated protocol)

---

## Test Summary

| Component | Tests | Passed | Failed |
|---|---|---|---|
| `time_utils.py` | 39 | 39 | 0 |
| `reorient_snapshot.py` | 28 | 28 | 0 |
| Shell scripts (schedule, run, execute, archive, e2e) | 70 | 66 | 4 |
| **Total** | **137** | **133** | **4** |

Overall pass rate: **97.1%**

---

## Bug Found: `--context-json` merge produces empty output

**Severity:** High  
**Location:** `scripts/schedule-task.sh`, line ~227  
**Symptom:** When `--context-json` is passed without a `reoriented_from` field, the merged context is silently empty, causing the final task JSON to fail with `jq: invalid JSON text passed to --argjson`.

**Root Cause:** The jq filter uses `($extra.reoriented_from // empty)`. In jq, `empty` is a generator that produces zero values — when used as a field value in an object constructor with `jq -n`, it suppresses the *entire object output*. This means the merge command returns nothing, `merged_context` is set to an empty string, and the downstream `--argjson context ''` call fails.

**Reproduction:**
```bash
./scripts/schedule-task.sh --when "10m" --summary "Test" \
  --context-json '{"summary":"ctx","key_points":["a"],"artifacts":[],"constraints":[]}'
# Exits 2 with: jq: invalid JSON text passed to --argjson
```

**Fix:** Change `// empty` to `// null` on line ~227:
```diff
-      reoriented_from: ($extra.reoriented_from // empty)
+      reoriented_from: ($extra.reoriented_from // null)
```

**Impact:** This blocks the `--context-json` feature entirely when `reoriented_from` is absent from the input. The `--reorient` path is *not* affected because `reorient_snapshot.py` always includes `reoriented_from` in its output.

---

## Test Coverage by Component

### 1. `time_utils.py` — 39 tests, all passing

Tested: compact durations (`10m`, `2h`, `1d2h30m`), verbose durations (`10 minutes`, `2 hours`, `1 hour 30 minutes`), abbreviations (`hrs`, `mins`, `secs`), clock parsing (12h/24h, AM/PM with spaces/periods), ISO format, `now`, `today`/`tomorrow` phrases, `+` and `in` prefixes, empty/invalid input rejection.

**Notable finding:** The parser does not support several natural-language patterns users are likely to try: `next monday`, `next week`, `noon`, `midnight`, `3pm EST` (timezone-qualified clock times). These all raise `ValueError`, which the skill handles gracefully (fail-fast). Documented below as a recommendation.

### 2. `reorient_snapshot.py` — 28 tests, all passing

Tested: heading normalization, section alias mapping (all 7 CONTEXT.md section types), bullet/numbered/plain text extraction, `compact_text` behavior, context file resolution (explicit path, project lookup, missing file, environment variable fallback), full `build_snapshot` output (all required keys, summary content, key points from current state, open questions with prefix, constraints from decisions/anti-patterns, artifacts from references, reoriented_from path, empty file fallback).

**No issues found.** The snapshot builder is well-structured and handles edge cases cleanly.

### 3. `schedule-task.sh` — Comprehensive option testing

Tested: basic scheduling, all CLI options (intent, mode, prompt-template, aura-level, key-point, artifact, constraint, custom ID), validation (missing `--when`, missing `--summary`, invalid intent, invalid mode, invalid time expression), context-json merging, prompt_template fallback, special characters in summary, JSON schema compliance.

**Bug found** in `--context-json` merging (see above).

### 4. `run-deferred.sh` + `execute-task.sh` — Runner and execution

Tested: executing due tasks (no executor), skipping future tasks, stale lock recovery, custom executor (success), failing executor (non-zero exit), non-executable `DEFER_EXECUTOR`, prompt file generation and content, status transitions, log entries.

**All passing.** The runner lock mechanism correctly detects and recovers from stale locks. The executor contract is properly enforced.

### 5. `archive-deferred.sh` — Terminal record archival

Tested: archiving completed tasks, failed tasks, cancelled tasks, preserving scheduled/executing tasks, empty file handling.

**All passing.** Archive file naming uses the correct `YYYYMM` format.

### 6. End-to-end workflow

Tested: schedule 3 tasks (2 due, 1 future) → run → verify only future task remains → verify archive has 2 entries → verify prompt files created for executed tasks.

**All passing.** The full lifecycle works correctly.

### 7. Edge cases and security

Tested: empty JSONL file, duplicate runs, concurrent scheduling (5 parallel appends), command injection via `--summary '$(echo INJECTED)'`.

**All passing.** Command injection is properly mitigated by jq's `--arg` flag. Concurrent appends are safe due to atomic `>>` on Linux (for small writes).

---

## Recommendations

### Critical (bug fix)

1. **Fix the `// empty` jq bug in `schedule-task.sh`** — Replace `// empty` with `// null` on line ~227 in the context merge filter. This completely breaks the `--context-json` feature when `reoriented_from` is absent.

### High Priority (functionality)

2. **Add `noon` and `midnight` support to `time_utils.py`** — These are common natural-language time references. A simple mapping before the clock parser would handle them:
   ```python
   if lowered in ("noon", "12pm"): return datetime.combine(now_local.date(), time(12, 0), tzinfo=tzinfo)
   if lowered in ("midnight", "12am"): return datetime.combine(now_local.date() + timedelta(days=1), time(0, 0), tzinfo=tzinfo)
   ```

3. **Add weekday support** (`next monday`, `next friday`) — Users scheduling deferred work will frequently use day-of-week references. This is a natural extension of the existing `today`/`tomorrow` parsing.

### Medium Priority (robustness)

4. **Add file locking to `replace_task_record`** — While `append_task_record` is safe for concurrent use (atomic `>>`), `replace_task_record` uses a read-modify-write pattern with `mktemp` + `mv`. If two processes try to replace different records simultaneously, one's changes could be lost. Consider using `flock` on the JSONL file.

5. **Add timezone-qualified clock time support** (`3pm EST`, `9am PST`) — Currently only the system timezone or `DEFER_TIMEZONE` is used. Adding explicit timezone parsing would make the skill more portable for users working across timezones.

6. **Add a `--dry-run` flag to `schedule-task.sh`** — Useful for validating time expressions and snapshot content without persisting anything.

### Low Priority (polish)

7. **Standardize output format** — `schedule-task.sh` outputs pretty-printed JSON (via `jq -n`) while internal operations use compact JSON (via `jq -c`). Consider adding a `--compact` flag or always outputting compact JSON for consistency with the JSONL format.

8. **Add `--list` and `--cancel` subcommands** — The skill currently has no way to view pending tasks or cancel a scheduled task without manually editing the JSONL file.

9. **Consider adding a `max_retries` field to the task schema** — Currently a failed executor marks the task as terminal. For transient failures, a retry mechanism would be useful.

10. **Document the `aura_level` field** — This field appears in the schema and code but isn't explained in the SKILL.md or task-schema.md reference. Its purpose and allowed values should be documented.

---

## Test Artifacts

All test files are located in the cloned repository at `agent-defer/tests/`:

- `test_time_utils.py` — 39 unit tests for time parsing
- `test_reorient_snapshot.py` — 28 unit tests for context snapshot building
- `test_shell_scripts.sh` — 70 integration tests covering all shell scripts and the end-to-end workflow

To run all tests:
```bash
cd agent-defer
python3 -m unittest tests.test_time_utils tests.test_reorient_snapshot -v
bash tests/test_shell_scripts.sh
```
