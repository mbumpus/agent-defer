#!/bin/bash
# Example: Schedule a task with reorientation from CONTEXT.md
#
# Before scheduling, the system re-reads a project's CONTEXT.md and
# extracts a clean snapshot (summary, key points, constraints, references).
# This is merged with the task-specific fields so the future run starts
# with full project context.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

# Create a sample CONTEXT.md for the demo
CONTEXT_FILE="/tmp/demo-context.md"
cat > "$CONTEXT_FILE" <<'EOF'
# Governance-First Training

## Orientation
Research into whether first-round training with governance artifacts produces different base behaviors than capability-first training.

## Current State
- Theory stage
- Spotify dataset available for structure demo
- 3090 build pending for validation

## Key Constraints
- Thesis: first-round training establishes interpretive lens
- Decision trees should include "I don't know" as valid terminal state

## Open Questions
- Control methodology for comparison?
- Corpus structure for governance artifacts?

## Decisions Already Made
- This is a lab/research effort, not a product
- Small model validation before scaling
EOF

echo "Created sample CONTEXT.md at $CONTEXT_FILE"
echo ""

"$SCRIPT_DIR/schedule-task.sh" \
  --when "next monday 9am" \
  --intent "resume_task" \
  --reorient \
  --context-file "$CONTEXT_FILE" \
  --summary "Resume the governance-first training review with fresh context" \
  --key-point "Validation environment should be ready by Monday"

echo ""
echo "Task scheduled with reoriented context."
echo "The snapshot includes key points, constraints, and open questions from CONTEXT.md."

rm -f "$CONTEXT_FILE"
