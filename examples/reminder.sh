#!/bin/bash
# Example: Simple reminder
#
# Schedule a notification for 30 minutes from now.
# When the runner picks it up, it writes a prompt artifact
# that an agent (or human) can act on.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

"$SCRIPT_DIR/schedule-task.sh" \
  --when "30m" \
  --intent "notify" \
  --summary "Check whether the staging deploy finished" \
  --key-point "Deploy kicked off at $(date -u +%H:%M) UTC" \
  --key-point "Expected duration: ~20 minutes" \
  --constraint "If it failed, do not re-deploy automatically"

echo ""
echo "Reminder scheduled. Run '$SCRIPT_DIR/schedule-task.sh list' to confirm."
