#!/bin/bash
# Example: Resume a multi-step analysis later
#
# You're partway through an architecture review and need to step away.
# Capture the current state as a snapshot and schedule re-entry for
# tomorrow morning.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

"$SCRIPT_DIR/schedule-task.sh" \
  --when "tomorrow 9am" \
  --intent "resume_task" \
  --mode "fresh" \
  --summary "Resume the architecture review — focus on retry semantics" \
  --prompt-template "Continue the architecture review. The open question is whether retry delays should be exponential or fixed. Produce a recommendation with tradeoffs." \
  --key-point "Reviewed scheduling and execution paths" \
  --key-point "Retry semantics still unresolved" \
  --key-point "Lock mechanism validated" \
  --artifact "/tmp/arch-review-notes.md" \
  --constraint "Do not assume prior conversation memory" \
  --constraint "Keep the recommendation under 500 words"

echo ""
echo "Analysis scheduled for tomorrow 9am."
echo "The runner will rehydrate context from the snapshot, not from chat history."
