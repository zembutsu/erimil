# Erimil Workflow

This document defines the development process and collaboration rules for this project.

---

## Development Phases

### Phase Definition

| Phase | Goal | Criteria |
|-------|------|----------|
| **Phase 1 (MVP)** | Core functionality | Browse ZIP, preview images, select exclusions, generate _opt.zip |
| **Phase 2** | Enhanced UX | Export to folder, settings panel, selection mode toggle |
| **Phase 3** | Extended formats | tar.gz/7z support, kurumil integration, batch processing |

### Version Strategy

- **0.x.x**: Pre-release development
- **1.0.0**: First public release (Phase 1 complete)
- **Major**: Breaking changes or major features
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes, minor improvements

---

## System-Assisted Development

### Collaboration Model

This project uses AI-assisted development:

```
Human: Define goal/problem
    ↓
System: Propose approach
    ↓
Human: Review & approve approach
    ↓
System: Implement
    ↓
Human: Review & test
    ↓
Human: Commit & merge
```

### Roles and Responsibilities

| Role | Responsibilities |
|------|------------------|
| **Human (Zem)** | Vision, approval, review, testing, Git operations, releases |
| **System (Claude)** | Analysis, proposal, implementation, documentation drafts |

### Decision Authority

| Decision Type | Authority |
|---------------|-----------|
| Architecture changes | Human approval required |
| New features | Human approval required |
| Bug fixes (small) | System can implement directly |
| Refactoring (small) | System can implement directly |
| Documentation | System can draft, human reviews |
| Design decisions | Human approval, record in DESIGN.md |

### Auto-Judgment Scope (AI Autonomous Operations)

Some operations can be performed by AI/System without human approval:

| Operation | AI Authority | Human Involvement |
|-----------|--------------|-------------------|
| Typo fixes | ✅ Execute | None required |
| Debug log addition | ✅ Execute | None required |
| Minor bugfix (obvious) | ✅ Execute | Final check only |
| Code formatting | ✅ Execute | None required |
| Test additions | ✅ Execute | Review at merge |
| New feature | ❌ Propose only | Approval required |
| Design changes | ❌ Propose only | Approval required |
| Dependency changes | ❌ Propose only | Approval required |

**Repository naming convention for AI experiments**:
- Prefix: `ai-exp/<name>` - Indicates AI-driven experimental work
- Example: `ai-exp/auto-refactor`, `ai-exp/test-coverage`

**Scope completion**:
- If work stays within Auto-Judgment Scope, AI/System can mark complete
- Human performs final check or merge at their discretion
- No blocking on human review for trivial changes

**Human Delegation (Technical Constraints)**:

AI/System cannot currently perform certain operations due to technical limitations. In these cases, AI may **request** human to execute on its behalf. This is a collaborative relationship - AI asks, human decides whether and how to act.

| Operation | Constraint | AI Action |
|-----------|------------|-----------|
| Run app / manual testing | No GUI access | Request human to test, provide test steps |
| Git commit / push | No Git credentials | Prepare commit message, request human to execute |
| GitHub Issue / PR operations | No API access | Draft content, request human to create |
| Xcode build / run | No Xcode access | Provide code, request human to build |
| File system verification | Container isolation | Request human to verify local state |

**Delegation format**:
```
[DELEGATE] <operation>
- What: <specific action needed>
- Why: <technical constraint>
- Expected result: <what human should see/verify>
```

Note: These constraints are technical, not policy. As tooling evolves, AI autonomy may expand.

### Parking Lot Mechanism (Scope Control)

During a session, off-topic ideas or out-of-scope discussions should be immediately parked:

```
Topic emerges during session
    ↓
Is it in scope for current Setlist?
    ├─ Yes → Continue discussion
    └─ No → PARK IT
            ↓
        Record in one of:
        ├─ LOGBOOK.md → Ideas section
        ├─ GitHub Issue → New issue with label
        └─ Session Sheet → Parked section
            ↓
        Return to session focus
```

**Purpose**:
- Prevent context bloat
- Maintain focus on current goals
- Capture ideas without losing them

**Trigger phrases**:
- "That's a good idea, let's park it"
- "Out of scope for this session"
- "Add to Ideas/Parked"

**Parked item format**:
```markdown
- [PARKED] <topic> - <one-line description> (from LOG#<num>)
```

### Communication Protocol

1. **Before implementation**: System proposes approach, waits for approval
2. **Large changes**: Split into phases, propose plan first
3. **During implementation**: Explain changes being made
4. **After implementation**: Provide summary and test guidance
5. **On uncertainty**: Ask for clarification rather than assuming
6. **Design decisions**: Document rationale in DESIGN.md

### Quality Gates

Before proposing implementation complete:
- [ ] Code compiles without errors
- [ ] Changes match approved approach
- [ ] Manual testing performed where possible
- [ ] Documentation updated if needed
- [ ] Design decisions recorded

---

## Git Workflow

### Branch Strategy

```
main
  ├── feature/{description}
  ├── fix/{description}
  └── refactor/{description}
```

### Commit Message Convention

```
{type}({scope}): {description}

{body - optional}
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring
- `docs`: Documentation
- `chore`: Maintenance tasks

**Examples**:
```
feat(archive): implement ZIP reading with ZIPFoundation

fix(preview): handle HEIC images correctly

docs: update ARCHITECTURE.md with state management
```

### Commit Language

- Commit messages: **English**
- Code comments: **English**
- Documentation: **English** (README may have Japanese sections)

---

## Documentation Standards

### Document Updates

| Change | Update |
|--------|--------|
| Architecture changes | ARCHITECTURE.md |
| Design decisions | DESIGN.md |
| Process changes | WORKFLOW.md |
| User-facing changes | README.md |
| Version release | CHANGELOG.md |

### Decision Recording

All significant decisions must be recorded in DESIGN.md with:
- Context (what prompted the decision)
- Options considered
- Decision made
- Rationale
- Consequences

### Issue Template (GitHub)

Use consistent format for GitHub Issues:

```markdown
## Description

<What needs to be done / What is the problem>

## Context

<Why this is needed / Background>

## Acceptance Criteria

- [ ] <Criterion 1>
- [ ] <Criterion 2>

## Technical Notes

<Implementation hints, constraints, risks>

## Related

- Issue #X
- LOG#<num>
```

**Labels**:
- `enhancement` - New feature
- `bug` - Something broken
- `docs` - Documentation
- `ai-exp` - AI autonomous work allowed

### LOGBOOK Entry Template

Use consistent format for LOGBOOK entries (fixed during session, evolves between sessions):

```markdown
## YYYY-MM-DD (LOG#<num>: <Session Title>)

### Current Position
- Phase/Status
- Branch/Related Issues

### Decisions
- Decision (→ DESIGN.md reference)
- Rationale

### Insights
- Discoveries, observations

### Learnings
- Technical knowledge gained

### Parked
- [PARKED] <topic> - <description>

### Ideas
- Future possibilities

### Handoff Bridge
- Carry forward items
- Technical notes
- Blockers
```

**Note**: Template is fixed within a session. Changes to template structure happen between sessions via TEMPLATE-FEEDBACK.md.

---

## Development Environment

### Requirements

- macOS 14+ (Sonoma)
- Xcode 15+
- Swift 5.9+

### Setup

```bash
git clone https://github.com/zembutsu/erimil.git
cd erimil
open Erimil.xcodeproj
```

### Dependencies

Managed via Swift Package Manager:
- ZIPFoundation

---

## Testing Strategy

### Phase 1 (MVP)

- Manual testing (primary)
- Test with various ZIP sizes and contents
- Edge cases: empty ZIP, ZIP with no images, corrupted files

### Future

- Unit tests for ArchiveManager, SelectionState
- UI tests for critical flows

---

## Release Process

1. All Phase features complete
2. Manual testing passed
3. CHANGELOG.md updated
4. Version number updated
5. Tag created (`v0.1.0`)
6. GitHub Release with DMG

---

## Document Lifecycle

### Session Start: Setlist Check

Before starting development, review and organize the work:

1. **GitHub Issues Review**
   - Check Open issues: current status, priorities
   - Identify blockers and dependencies
   - Decide which issues to tackle this session

2. **Session Sheet Setup**
   - Create LOG#\<num\> entry (see Session Sheet template below)
   - Record target issues and goals
   - Note any carry-forward from previous Handoff Bridge

3. **Context Loading**
   - Read PROJECT.md - Confirm current Phase goals
   - Read DESIGN.md - Review past decisions
   - Read LOGBOOK.md (latest entry) - Check Handoff Bridge
   - Check ARCHITECTURE.md Technical Constraints (if relevant)

### During Session: Session Sheet

Maintain a real-time record of the session:

```markdown
## LOG#<num>: <Session Title>
Date: YYYY-MM-DD
Issues: #X, #Y, #Z
Actors: Claude, Zem

### Timeline

| Time | Actor | Action | Issue | Status |
|------|-------|--------|-------|--------|
| 14:00 | Zem | Session start, Setlist Check | - | - |
| 14:05 | Claude | Propose approach for #5 | #5 | 🔄 |
| 14:10 | Zem | Approve approach | #5 | ✅ |
| 14:15 | Claude | Implement fix | #5 | 🔄 |
| 14:30 | Zem | Test - still failing | #5 | ❌ |
| 14:35 | Claude | Step back, check constraints | #5 | 🔄 |
| ... | ... | ... | ... | ... |

### Notes
- (Real-time observations, decisions, blockers)

### Outcome
- (Filled at session end)
```

**Status icons**:
- 🔄 In progress
- ✅ Completed
- ❌ Blocked / Failed
- ⏸️ Paused

### Session End: Wrap-up

1. **Session Sheet → LOGBOOK**
   - Extract key decisions, insights, learnings
   - Write Handoff Bridge for next session
   - Record LOG# reference

2. **Setlist Check (closing)**
   - Update GitHub Issue status
   - Close completed issues
   - Add comments to open issues with progress

3. **Document Updates**
   - LOGBOOK.md - Add session entry with LOG# reference
   - DESIGN.md - Add new Decisions (if any)
   - WORKFLOW.md - Add learnings to Development Principles (if any)
   - TEMPLATE-FEEDBACK.md - Add methodology insights (if any)

---

### When to Reference / Update Each Document

| Timing | Reference | Update |
|--------|-----------|--------|
| **Session Start** | PROJECT.md (confirm goals) | - |
| **Design Decisions** | DESIGN.md (check past decisions) | DESIGN.md (add new Decision) |
| **During Implementation** | Official docs, code | - |
| **After Problem Solved** | - | WORKFLOW.md (add learnings) |
| **Session End** | - | DESIGN.md, WORKFLOW.md (batch update) |
| **Phase Complete** | - | ARCHITECTURE.md (if structure changed), CHANGELOG |
| **Release** | All docs (consistency check) | PROJECT.md (update roadmap) |

### Phase Start Checklist

- [ ] Read **PROJECT.md** - Confirm current Phase goals
- [ ] Read **DESIGN.md** - Review past decisions
- [ ] Read **LOGBOOK.md** (latest entry) - Check **Handoff Bridge** for carry-forward items
- [ ] Check **ARCHITECTURE.md** - Understand current structure (if needed)
- [ ] Check **ARCHITECTURE.md Technical Constraints** - If implementing persistence or file access

### During Development

| Situation | Action |
|-----------|--------|
| Design decision needed | Check past decisions in DESIGN.md → Add new Decision (can be deferred) |
| Technical problem occurs | Consult official docs → Add learnings to WORKFLOW.md after resolution |
| Actively coding | Defer documentation, focus on implementation |

### Phase End Checklist

- [ ] **LOGBOOK.md** - Record session: decisions, insights, learnings, **Handoff Bridge**
- [ ] **DESIGN.md** - Add new Decisions made during the phase
- [ ] **WORKFLOW.md** - Add learnings to Development Principles
- [ ] **ARCHITECTURE.md** - Update if structure changed
- [ ] **CHANGELOG.md** - Record changes (before release)
- [ ] **PROJECT.md** - Mark Phase complete in roadmap

---

## Development Principles

### Troubleshooting Approach

When encountering persistent errors:

1. **Stop guessing** - Don't iterate on assumptions
2. **Check official documentation** - Library READMEs, Apple docs
3. **Search Issues** - GitHub issues often have solutions
4. **Minimal reproduction** - Isolate the problem
5. **Add debug logging** - Understand what's actually happening

**Lesson learned (Phase 1)**:
ZIPFoundation `corruptedData` errors were solved by following official examples, not by adding more workarounds.

### Step Back Before Diving Deeper (Phase 2.1)

When small fixes aren't working after 2-3 attempts:

1. **Stop iterating** - More tweaks often waste time
2. **Ask "what's fundamentally different?"** - Compare working vs broken state
3. **Question assumptions** - "Is this the right approach at all?"
4. **Check platform constraints** - Sandbox, permissions, entitlements
5. **Search for standard patterns** - "How is this normally done on macOS?"

**Anti-pattern**:
```
Fix A → doesn't work → Fix B → doesn't work → Fix C → ...
```

**Better**:
```
Fix A → doesn't work → Fix B → doesn't work → STOP
→ "What would an experienced macOS developer do here?"
→ Check ARCHITECTURE.md Technical Constraints
→ Search for standard approach
```

**Lesson learned (Phase 2.1)**:
Folder restoration kept failing with UserDefaults. After multiple debug iterations, stepping back revealed: "Sandbox requires Security-Scoped Bookmarks" - a fundamental constraint, not a bug to fix.

### SwiftUI State Management

**Timing matters**:
```swift
// ❌ Wrong - sheet opens before image is set
DispatchQueue.main.async {
    previewImage = image
    previewEntry = entry  // triggers sheet with nil image
}

// ✅ Correct - synchronous, image set before sheet trigger
previewImage = image
previewEntry = entry
```

**Parent-child state sharing**:
- Use `@Binding` for shared mutable state
- Parent owns the state, child receives binding
- Callbacks (`onExportSuccess`) for child-to-parent events

**State ownership principle (Phase 2)**:
When derived state (`excludedPaths`) causes false positives, use source state (`selectedPaths`) directly.
```swift
// ❌ Wrong - excludedPaths is calculated, mode-dependent
hasUnsavedChanges: !excludedPaths.isEmpty

// ✅ Correct - selectedPaths is user's actual action
hasUnsavedChanges: !selectedPaths.isEmpty
```

### macOS Sandbox

Common permission issues and solutions:

| Issue | Solution |
|-------|----------|
| Cannot write files | Use NSSavePanel + Read/Write entitlement |
| Cannot read user files | Use NSOpenPanel |
| Panel crashes | Check entitlements in Signing & Capabilities |
| Trash files | Use FileManager.trashItem() (works in sandbox) |

### Protocol Abstraction (Phase 2)

When supporting multiple similar sources (ZIP, Folder):

1. **Define protocol early** - Common interface before implementation
2. **Keep protocol minimal** - Only what views actually need
3. **Type-specific logic in implementation** - Not in views
4. **Use `any Protocol`** - For heterogeneous storage

```swift
protocol ImageSource {
    var url: URL { get }
    func listImageEntries() -> [ImageEntry]
    func thumbnail(for: ImageEntry, maxSize: CGFloat) -> NSImage?
    func fullImage(for: ImageEntry) -> NSImage?
}
```

### Finder-style UI (Phase 2)

For tree navigation with content preview:

```swift
// Use List selection binding + OutlineGroup
List(selection: $selectedNodeID) {
    OutlineGroup(nodes, children: \.children) { node in
        NodeRowView(node: node)
            .tag(node.id)  // Required for selection
    }
}
.onChange(of: selectedNodeID) { _, newValue in
    handleSelection(newValue)
}
```

Benefits:
- ▶ disclosure handled automatically
- Row click = selection (not expand)
- Standard macOS behavior

---

## Project-Specific Rules

### Safety Rules

1. **Never implement destructive operations without confirmation**
2. **Original files are read-only until explicit "Confirm"**
3. **All state changes must be undoable until confirmed**

### Code Style

- SwiftUI for all UI
- MVVM-ish (Views + ObservableObject)
- Prefer composition over inheritance
- Explicit error handling (no silent failures)

---

## Template Information

> Based on **Project Documentation Methodology** v0.1.0
> Document started: 2025-12-13
> Last updated: 2025-12-14 (Auto-Judgment, Parking Lot, Templates)
