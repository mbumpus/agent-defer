.PHONY: test test-python test-shell demo clean-runtime install help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  %-18s %s\n", $$1, $$2}'

test: test-python test-shell ## Run all tests

test-python: ## Run Python unit tests
	python3 -m unittest tests.test_time_utils tests.test_reorient_snapshot -v

test-shell: ## Run shell integration tests
	bash tests/test_shell_scripts.sh
	bash tests/test_new_features.sh

demo: ## Run the full-loop demo (schedule, list, run, inspect)
	@echo "=== Scheduling a task due now ==="
	./scripts/schedule-task.sh --when "now" --summary "Demo task" --id "demo_$$$$(date +%s)"
	@echo ""
	@echo "=== Listing pending tasks ==="
	./scripts/schedule-task.sh list --compact
	@echo ""
	@echo "=== Running due tasks ==="
	./scripts/run-deferred.sh
	@echo ""
	@echo "=== Done. Check ~/data/runtime/logs/ for the prompt artifact."

clean-runtime: ## Remove all runtime state (tasks, archives, logs)
	@echo "This will delete all deferred tasks, archives, and logs."
	@echo "Press Ctrl+C to cancel, or Enter to continue."
	@read _confirm
	rm -rf "$${DEFER_RUNTIME_DIR:-$$HOME/data/runtime}"
	@echo "Runtime cleaned."

install: ## Make scripts executable and verify dependencies
	chmod +x scripts/*.sh
	chmod +x examples/*.sh
	@echo "Checking dependencies..."
	@command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed."; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required but not installed."; exit 1; }
	@echo "All dependencies present."
	@echo ""
	@echo "To set up cron, add this line to your crontab (crontab -e):"
	@echo "  * * * * * $(CURDIR)/scripts/run-deferred.sh"
	@echo ""
	@echo "See .env.example for optional configuration."
