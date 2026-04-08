# Contributing to Agent Defer

Thanks for considering a contribution. This document covers the basics.

## Getting Started

1. Fork the repository and clone your fork.
2. Run `make test` to verify everything passes in your environment.
3. Create a branch for your change.

## Development Setup

You need:

- Bash 4+ (macOS ships 3.x — `brew install bash` if needed)
- Python 3.9+
- jq 1.6+
- Standard coreutils (`date`, `mktemp`, `mkdir`, `mv`, `cat`, `wc`)

No virtual environment is required. The Python modules have zero third-party dependencies.

## Running Tests

```bash
make test
```

This runs all 4 test suites: two Python (`unittest`) and two bash. The full suite should complete in under 30 seconds.

If you add a feature, add tests for it. If you fix a bug, add a test that would have caught it.

## Code Style

**Shell scripts**: Use `set -euo pipefail`. Quote variables. Use `printf` over `echo` for portability. Pass user input through `jq --arg`, never through string interpolation.

**Python**: Follow standard Python style. No third-party dependencies in the core scripts. Type hints are welcome but not required.

**Commit messages**: One line, imperative mood, under 72 characters. If the change needs explanation, add a body after a blank line.

## What Makes a Good Contribution

- Bug fixes with a reproducing test case
- New time expression formats in `time_utils.py`
- Executor adapters (in `examples/` or a separate repo)
- Documentation improvements
- Edge case coverage in the test suite

## What to Avoid

- Adding third-party dependencies to the core scripts
- Breaking the executor contract (stdin JSON, stdout result, exit code)
- Changing the JSONL schema without a version bump discussion
- Adding daemon-style processes — the system is intentionally stateless

## Pull Requests

1. Make sure `make test` passes.
2. Keep PRs focused. One feature or fix per PR.
3. Update documentation if your change affects user-facing behavior.
4. Update CHANGELOG.md.

## Reporting Issues

Open a GitHub issue. Include:

- What you expected
- What happened instead
- Steps to reproduce
- Your OS and shell version (`bash --version`, `jq --version`, `python3 --version`)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
