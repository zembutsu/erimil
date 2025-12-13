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
