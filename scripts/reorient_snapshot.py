#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Optional


SECTION_ALIASES = {
    "orientation": "orientation",
    "what this is": "orientation",
    "overview": "orientation",
    "current state": "current_state",
    "state": "current_state",
    "status": "current_state",
    "key constraints": "key_constraints",
    "constraints": "key_constraints",
    "key context": "key_constraints",
    "open questions": "open_questions",
    "questions": "open_questions",
    "what we should not do": "anti_patterns",
    "anti patterns": "anti_patterns",
    "decisions already made": "decisions",
    "decisions": "decisions",
    "key references": "references",
    "references": "references",
}


def normalize_heading(raw: str) -> str:
    cleaned = raw.strip().strip(":").lower()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned


def parse_markdown_sections(text: str):
    sections = {}
    current_key = "__preamble__"
    lines = []

    def flush():
        content = "\n".join(lines).strip()
        if content:
            sections.setdefault(current_key, []).append(content)

    for line in text.splitlines():
        match = re.match(r"^\s{0,3}#{1,6}\s+(.*)$", line)
        if match:
            flush()
            heading = normalize_heading(match.group(1))
            current_key = SECTION_ALIASES.get(heading, heading)
            lines = []
        else:
            lines.append(line.rstrip())

    flush()
    return sections


def section_to_items(blocks):
    items = []
    for block in blocks or []:
        for raw_line in block.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            bullet = re.match(r"^[-*+]\s+(.*)$", line)
            numbered = re.match(r"^\d+\.\s+(.*)$", line)
            if bullet:
                items.append(bullet.group(1).strip())
            elif numbered:
                items.append(numbered.group(1).strip())
            else:
                items.append(line)
    return items


def compact_text(blocks):
    items = section_to_items(blocks)
    if items:
        return items[0]
    if not blocks:
        return ""
    paragraph = " ".join(part.strip() for part in blocks if part.strip())
    paragraph = re.sub(r"\s+", " ", paragraph).strip()
    return paragraph


def resolve_context_file(project_name: Optional[str], explicit_path: Optional[str]) -> Path:
    if explicit_path:
        candidate = Path(os.path.expanduser(explicit_path))
        if candidate.is_file():
            return candidate
        raise FileNotFoundError(f"Context file not found: {candidate}")

    if project_name:
        candidate = Path.home() / "data" / "research" / "projects" / project_name / "CONTEXT.md"
        if candidate.is_file():
            return candidate
        raise FileNotFoundError(f"Context file not found for project '{project_name}': {candidate}")

    env_candidate = os.environ.get("DEFER_CONTEXT_FILE")
    if env_candidate:
        candidate = Path(os.path.expanduser(env_candidate))
        if candidate.is_file():
            return candidate
        raise FileNotFoundError(f"DEFER_CONTEXT_FILE does not exist: {candidate}")

    project_dir = Path.home() / "data" / "research" / "projects"
    if project_dir.is_dir():
        candidates = sorted(project_dir.glob("*/CONTEXT.md"), key=lambda path: path.stat().st_mtime, reverse=True)
        if candidates:
            return candidates[0]

    research_root = Path.home() / "data" / "research" / "CONTEXT.md"
    if research_root.is_file():
        return research_root

    workspace_root = Path.cwd() / "CONTEXT.md"
    if workspace_root.is_file():
        return workspace_root

    raise FileNotFoundError("No CONTEXT.md found via project lookup, DEFER_CONTEXT_FILE, or workspace root")


def build_snapshot(context_file: Path):
    text = context_file.read_text(encoding="utf-8")
    sections = parse_markdown_sections(text)

    summary = compact_text(sections.get("orientation")) or compact_text(sections.get("__preamble__"))
    current_state = section_to_items(sections.get("current_state"))
    open_questions = [f"Open question: {item}" for item in section_to_items(sections.get("open_questions"))]
    references = section_to_items(sections.get("references"))
    constraints = (
        section_to_items(sections.get("key_constraints"))
        + [f"Decision: {item}" for item in section_to_items(sections.get("decisions"))]
        + [f"Avoid: {item}" for item in section_to_items(sections.get("anti_patterns"))]
    )

    if not summary:
        summary = f"Reoriented from {context_file.name}"

    if not current_state:
        current_state = ["Context re-read from CONTEXT.md"]

    snapshot = {
        "summary": summary,
        "key_points": current_state + open_questions,
        "artifacts": references,
        "constraints": constraints,
        "reoriented_from": str(context_file),
    }
    return snapshot


def main():
    parser = argparse.ArgumentParser(description="Build a defer snapshot from a reorient CONTEXT.md file.")
    parser.add_argument("--project")
    parser.add_argument("--context-file")
    args = parser.parse_args()

    try:
        context_file = resolve_context_file(args.project, args.context_file)
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    snapshot = build_snapshot(context_file)
    print(json.dumps(snapshot, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
