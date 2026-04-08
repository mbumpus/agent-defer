---
name: reorient
description: Re-reads workspace CONTEXT.md and restates key constraints to combat context drift. Triggered by "::reorient", "refresh context", "where were we", or "re-read the project context". Use when conversation feels like it's drifting, before major decisions, or after ~30 turns in a long session.
---

# Reorient

Combats context drift by re-reading and restating workspace orientation.

## Trigger Patterns

- `::reorient` — reorient to current project
- `::reorient <project-name>` — reorient to specific project
- "refresh context"
- "re-read the context file"
- "where were we on this project"
- "let's get back on track"

## When to Use

Per the CONTEXT.md template, reorient when:
- Starting a new session
- Conversation exceeds ~30 turns
- Before any commit/finalize/ship decision
- If contradicting something previously established
- User says "wait, didn't we already..."
- Anything feels off or drifty

## Reorient Workflow

### 1. Identify Context File

```bash
# If project specified
PROJECT_NAME="governance-first-training"
CONTEXT_FILE=~/data/research/projects/$PROJECT_NAME/CONTEXT.md

# If no project specified, check for most recently modified
CONTEXT_FILE=$(ls -t ~/data/research/projects/*/CONTEXT.md 2>/dev/null | head -1)

# Fallback to workspace root
if [ -z "$CONTEXT_FILE" ]; then
    CONTEXT_FILE=~/data/research/CONTEXT.md
fi

# Verify exists
if [ ! -f "$CONTEXT_FILE" ]; then
    echo "No CONTEXT.md found. Create a project first with ::scaffold"
    exit 1
fi
```

### 2. Read Context

```bash
cat "$CONTEXT_FILE"
```

### 3. Restate Key Points

After reading, explicitly restate to the user:

**Format:**
```
## Reoriented: [Project Name]

**What this is:** [one-line from Orientation]

**Current state:** [from Current State section]

**Key constraints:**
- [critical item from Key Context]
- [critical item from Key Context]

**Open questions:**
- [from Open Questions]

**What we should NOT do:**
- [any anti-patterns or decisions already made]

---

Ready to continue. What's next?
```

### 4. Check SESSION.md (if exists)

```bash
SESSION_FILE=$(dirname "$CONTEXT_FILE")/SESSION.md

if [ -s "$SESSION_FILE" ]; then
    echo "Recent session state:"
    tail -50 "$SESSION_FILE"
fi
```

Include relevant session state in reorientation if present.

## Example Reorientation

**User:** `::reorient governance-first-training`

**Claude reads:** `~/data/research/projects/governance-first-training/CONTEXT.md`

**Claude responds:**

> ## Reoriented: Governance-First Training
> 
> **What this is:** Research into whether first-round training with governance artifacts produces different base behaviors than capability-first training.
> 
> **Current state:** Theory stage. Spotify dataset available for structure demo. 3090 build pending for validation.
> 
> **Key constraints:**
> - Thesis: first-round training establishes interpretive lens
> - "Always produce output" is the original sin we're trying to avoid
> - Decision trees should include "I don't know" as valid terminal state
> 
> **Key references:**
> - WOPR/WarGames (1983) — "only winning move is not to play"
> - Garth Brooks — yes, this will be cited
> 
> **Open questions:**
> - Control methodology for comparison?
> - Corpus structure for governance artifacts?
> 
> **Decisions already made:**
> - This is a lab/research effort, not a product
> - Small model validation before scaling
> 
> ---
> 
> Ready to continue. What's next?

## Lightweight Reorient

For quick refresh without full readout:

`::reorient --brief`

**Response:**
> **Reoriented:** governance-first-training  
> **Focus:** First-round governance training thesis  
> **State:** Theory stage, pre-validation  
> 
> Context file re-read. Ready to continue.

## Reorient + Capture

If reorienting surfaces something worth noting:

`::reorient --capture`

After restating context, prompt:
> Anything from our recent conversation I should capture before we continue?

## Proactive Reorientation

I should suggest reorienting when:
- User seems to be repeating context I should already have
- I'm about to contradict something from CONTEXT.md
- We're approaching a significant decision point
- The conversation has been going for 30+ turns

**Example prompt:**
> We've been at this for a while and we're about to finalize X. Want me to ::reorient first to make sure I haven't drifted?

## No Context Found

If no CONTEXT.md exists:

> No project context found. 
> 
> Options:
> - `::scaffold <project-name>` to create a new project
> - Tell me what we're working on and I'll help establish context
> 
> What would you like to do?

## Update After Reorient

If reorientation reveals the CONTEXT.md is stale:

> The context file shows [X] but we've since decided [Y]. 
> 
> Want me to update CONTEXT.md to reflect current state?

Then update the file if confirmed.
