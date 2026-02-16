# CLAUDE.md

Entry point for AI agents working on Erimil.

## Quick Start

1. Read **PROJECT.md** — vision, principles, what Erimil does NOT do
2. Read **ARCHITECTURE.md** — code structure, data flow, components
3. Read **WORKFLOW.md** — development process, commit conventions
4. Check latest session log in `docs/sessions/` — Handoff Bridge has carry-forward items and warnings

## Methodology

This project follows **Bebop Style Development** v0.1.1
https://github.com/zembutsu/bebop-style-development

Human and AI collaborate as equal "Voices" in numbered sessions (S001, S002, ...).

## Key Rules

- Erimil = 「選り見る」— browse → evaluate → mark → export. Nothing else.
- Propose before large changes; small fixes can be applied directly
- Never modify files outside the Erimil Xcode project without approval
- Design decisions go in DESIGN.md, not code comments
- When in doubt about scope, ask rather than implement

## Session Logs

Location: `docs/sessions/SNNN_erimil_en.md`

Each log contains:
- **Handoff Bridge** — what the next session needs to know
- **Parked** — deferred topics (deferred for a reason)
- **Decisions** — rationale for choices made
- **Warnings** — things to watch out for

Always read the latest session's Handoff Bridge before starting work.

## Tech Stack

macOS 14+ / SwiftUI / Swift / ZIPFoundation / MIT License
