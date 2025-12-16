# Project Template v0.1.0 Feedback

> Notes from Erimil development experience
> Date: 2025-12-13
> Updated: 2025-12-17 (S003 - State Snapshot, Role Division, macOS Constraints)

## Strengths

- "Game analogy" is intuitive and excellent
- Clear design with PROJECT.md as entry point
- Practical AI collaboration model in WORKFLOW.md
- Helpful document recommendation matrix by project size

## Issues (for v0.2.0)

| # | Issue | Description |
|---|-------|-------------|
| 1 | Duplication | `project-docs-methodology.md` contains template examples, overlapping with `templates/`. Separate methodology explanation from templates |
| 2 | Missing | No `CHANGELOG-template.md` |
| 3 | Missing | LICENSE mentioned but no template provided |
| 4 | Inconsistent | "Template Information" position varies (end vs beginning) |
| 5 | ADR | No scaffold for docs/adr/ structure |
| 6 | Usability | A `{placeholder}` list to replace after copying would be helpful |

## Additional Proposals

- [ ] Quick Start shell script (template copy & rename)
- [ ] .gitignore template
- [ ] GitHub Issue/PR templates

---

## Phase 1 Practice Feedback (2025-12-13)

### Actual Usage Patterns

| Document | Reference Frequency | Update Frequency | Value |
|----------|---------------------|------------------|-------|
| PROJECT.md | Session start only | Phase completion | High (clear goals) |
| DESIGN.md | When making decisions | Session end | **Highest** (decision records persist) |
| ARCHITECTURE.md | Rarely referenced | Phase completion only | Medium (useful for major changes) |
| WORKFLOW.md | When problems occur | Session end | High (learnings accumulate) |

### Discovered Issues

| # | Issue | Discovery Context | Response |
|---|-------|-------------------|----------|
| 7 | Update timing unclear | Confused about when to update which document | Added Document Lifecycle section to WORKFLOW.md |
| 8 | Cannot update during implementation | Updating docs while coding is unrealistic | Rule: "Defer during implementation, batch record at end" |
| 9 | ARCHITECTURE.md positioning | Rarely viewed during development | Limited to large projects or structural changes only |

### Added Operational Rules

Added "Document Lifecycle" section to WORKFLOW.md:

1. **Phase Start Checklist** - Documents to read at start
2. **During Development** - Action table by situation
3. **Phase End Checklist** - Documents to update at end

### Proposals for v0.2.0

1. **Standardize Document Lifecycle**
   - Include in templates by default
   - Make customizable by project size

2. **Center on DESIGN.md**
   - Highest value document
   - Enhance Decision templates

3. **Make ARCHITECTURE.md Optional**
   - May not be needed for small projects
   - "Create when structure becomes complex" is acceptable

4. **Standardize Development Principles Section**
   - Place in WORKFLOW.md for accumulating learnings

---

## Phase 2.1 Practice Feedback (2025-12-14)

### Problem Encountered

**"Folder restoration" feature took the longest time**

Expected: Simple feature (save path to UserDefaults → restore on launch)

Actual flow:
```
1. Save to UserDefaults → OK
2. Read on launch → Empty (why?)
3. Add debug logs → Can read after save, disappears after restart
4. Check Bundle ID → Correct
5. Realize sandbox constraint → children count: 0
6. Discover Security-Scoped Bookmarks required
7. Discover Entitlements configuration required
8. Can't find Entitlements location in Xcode → Screenshot exchanges
9. Encounter UserDefaults not persisting in Xcode debug
10. Change to file-based storage (Application Support) → Resolved
```

### Root Cause Analysis

**What Bebop documents were missing:**

| Gap | Impact |
|-----|--------|
| **Technical Constraints** | AI didn't know platform constraints, started with wrong approach |
| **Development Setup** | Time wasted explaining Xcode setup steps |
| **Technical Risks in Issue** | Couldn't pre-identify traps in "seemingly simple" features |
| **Troubleshooting** | No resolution patterns when problems occurred |

### New Issues (for v0.2.0)

| # | Issue | Description | Priority |
|---|-------|-------------|----------|
| 10 | **Technical Constraints missing** | No place to document platform-specific constraints | **High** |
| 11 | **Development Setup missing** | No IDE/environment setup procedures | **High** |
| 12 | **Technical Risks in Issue** | Issue template lacks technical risk section | Medium |
| 13 | **Troubleshooting missing** | No place for common problems and solutions | Medium |

### Actions Taken

- [x] Added Technical Constraints section to ARCHITECTURE.md
- [x] Added Development Setup section to ARCHITECTURE.md
- [x] Added Troubleshooting section to ARCHITECTURE.md
- [x] Added **Handoff Bridge** section to LOGBOOK.md (session-to-session handoff)
- [x] Added **Step Back Before Diving Deeper** principle to WORKFLOW.md
- [x] Added Handoff Bridge check to WORKFLOW.md Session Checklist
- [ ] Add Technical Risks section to Issue template (TODO)

### Learnings

**1. "Design" and "Constraints" are different**
- Bebop method is strong at design discussions (DESIGN.md)
- But platform constraint documentation was missing
- → Standardize constraints section in ARCHITECTURE.md

**2. AI cannot infer unknown constraints**
- Without documentation, AI starts with wrong approach
- Starting with UserDefaults is natural without macOS sandbox knowledge
- → Document project-specific constraints explicitly

**3. "Seemingly simple" features are dangerous**
- Implementation difficulty and actual time often diverge
- Technical risk pre-check list needed
- → Add Technical Risks to Issue template

**4. Xcode operations don't convey through words alone**
- "Open Build Settings..." is ambiguous
- Screenshots + step-by-step needed
- → Document specific procedures in Development Setup

**5. Step back rather than myopic fixes**
- Small fixes repeated actually took more time
- After 2-3 failed attempts, step back and see the whole picture
- → Added "Step Back Before Diving Deeper" principle to WORKFLOW.md

**6. Session-to-session handoff needed**
- Learnings and cautions weren't passed to next session
- Standardize handoff section in LOGBOOK.md
- → Added **Handoff Bridge** to LOGBOOK.md template

### Additional Proposals for v0.2.0

1. **Add to ARCHITECTURE.md template**
   - Technical Constraints (platform constraints)
   - Development Setup (environment setup)
   - Troubleshooting (common problems)

2. **Add Technical Risks section to Issue template**
   ```markdown
   ## Technical Risks
   - [ ] Sandbox/permission constraints?
   - [ ] Platform-specific API usage?
   - [ ] Race condition in async processing?
   - [ ] External dependency additions needed?
   ```

3. **Standardize Platform Checklist**
   - macOS: Sandbox, Entitlements, Notarization
   - iOS: App Store Guidelines, Privacy
   - Web: CORS, CSP, Browser compatibility

4. **Add Handoff Bridge section to LOGBOOK.md template**
   ```markdown
   ### Handoff Bridge
   - Carry forward to next session
   - Cautions, things to verify
   ```
   - Explicitly pass learnings and cautions between sessions
   - Context and rationale contained in same file

5. **Standardize Step Back principle in WORKFLOW.md**
   ```markdown
   ### Step Back Before Diving Deeper
   When small fixes aren't working after 2-3 attempts:
   1. Stop iterating
   2. Ask "what's fundamentally different?"
   3. Question assumptions
   4. Check platform constraints
   5. Search for standard patterns
   ```

6. **Add Handoff Bridge check to WORKFLOW.md Session Checklist**
   ```markdown
   ### Session Start Checklist
   - [ ] Read LOGBOOK.md (latest entry) - Check Handoff Bridge
   - [ ] Check ARCHITECTURE.md Technical Constraints (if relevant)
   ```

---

## Key Insights from Practice (2025-12-14)

Ideas discovered during Phase 2.1 session retrospective for Bebop method's next evolution.

### Session Management Challenges

**Current problems**:
- No record of "who is doing what now" during sessions
- GitHub Issue numbers alone don't show context flow
- Tracking breaks down when multiple sessions run in parallel

**Discovery trigger**:
- Confusion about which issues were complete vs incomplete during closure check
- #5 (fullscreen) and #7 (black screen) status got mixed up

### Proposal: LOG#\<num\> Session Tracking

```
LOG#001: Phase 2.1 UX Improvements
├─ issues: [#2, #3, #4, #6]
├─ depends_on: []
├─ status: completed
└─ handoff: [LOG#002, LOG#003]

LOG#002: ★ Export          LOG#003: Bug fixes
├─ issues: [#11]           ├─ issues: [#5, #7]
├─ depends_on: [LOG#001]   ├─ depends_on: [LOG#001]
└─ ...                     └─ ...
```

**Benefits**:
- Separate GitHub Issues (feature-level) from LOG# (session-level)
- Explicit dependencies (depends_on, blocks)
- Parallel work tracking possible

### Proposal: Session Sheet (Real-time Recording)

Format for "who does what on which Issue" during session:

```markdown
| Time | Actor | Action | Issue | Status |
|------|-------|--------|-------|--------|
| 14:00 | Zem | Session start | - | - |
| 14:05 | Claude | Propose approach | #5 | 🔄 |
```

**Benefits**:
- Decision trail is traceable
- Easy to write out to LOGBOOK at session end
- Multi-actor collaboration visible

### Proposal: Setlist Check (Issue Review)

Routine to check GitHub Issues at session start/end:
- Check Open Issues status
- Decide which Issues to tackle today
- Update status at end

**Bebop term**: Setlist (list of songs to play today)

### Future: bebop CLI Tool

```bash
$ bebop start --issues "#5,#7"
→ LOG#002 created

$ bebop status
LOG#002 [active] - #5 ★Export, #7 Black screen

$ bebop graph
LOG#001 ──┬──→ LOG#002 (active)
          └──→ LOG#003 (pending)

$ bebop sync
→ GitHub Issues updated with LOG# references
```

### v0.2.0+ Proposals

| Priority | Proposal | Description |
|----------|----------|-------------|
| High | Setlist Check | Issue review routine at session start/end |
| High | Session Sheet template | Real-time recording format |
| High | Parking Lot mechanism | Immediate record of out-of-scope topics |
| High | Unified templates | Fixed Issue / LOGBOOK format (within session) |
| High | Auto-Judgment Scope | Explicit AI autonomy boundaries (typo, debug log, minor fix) |
| Medium | LOG#\<num\> numbering | Session-level tracking |
| Medium | `ai-exp/` prefix | Naming convention for AI experimental repos |
| Low | bebop CLI | Future automation tool |

These are stepping stones from "solo performance" to "ensemble".

### Additional Proposal: Scope Control and AI Autonomy (2025-12-15 evening)

Proposals added during Phase 2.1 session-end review.

**1. Parking Lot Mechanism**

When out-of-scope topics emerge during session:
- Immediately mark as "Parked"
- Route to Issue / LOGBOOK / Later
- Return to session focus

Purpose: Prevent context bloat, prevent attention drift

**2. Unified Templates**

- Issue template (Description, Context, Acceptance Criteria, Technical Notes, Related)
- LOGBOOK entry template (fixed within session, evolves between sessions)

**3. Auto-Judgment Scope**

Operations AI/System can execute without human approval:
- Typo fixes
- Debug log addition
- Minor bugfix (obvious ones)
- Code formatting

Operations requiring human approval:
- New features
- Design changes
- Dependency changes

**Repository naming convention**: `ai-exp/<n>` to indicate AI experimental projects

---

## Essential Insights on Bebop Method (2025-12-14)

Bebop method's essence and possibilities discovered through post-Phase 2.1 session discussion.

### Beyond Human-AI Collaboration

Bebop method was born in AI-driven development context, but **applicable to human-only development too**.

| Aspect | Vibe Coding | SDD | AI-driven | **Bebop** |
|--------|-------------|-----|-----------|-----------|
| Lead | Leave to AI | Specs | AI | Session participants |
| Records | None | Pre-design | Logs | LOGBOOK (asset) |
| Evolution | None | Planned | None | Natural emergence from practice |
| Coordination | None | Synchronous | None | Handoff Bridge |

### Jazz Session Metaphor

```
Jazz Session
├─ Anyone can join (open)
├─ But read the room (protocol)
├─ Take solo only when you're good (spot contribution)
├─ Pass via Trading (asynchronous coordination)
└─ Everyone is leader and follower (autonomous distributed)
```

**道場破り (Dojo Breaker)** ≠ **Session Participation**

"PRs that don't read the room" seen in OSS are Dojo Breakers (道場破り - Japanese term for someone who barges into a dojo uninvited to challenge). Bebop reads context via Setlist Check, passes via Trading Notes.

### Comparison with Traditional Models

| Aspect | Sprint | OSS (current) | Bebop |
|--------|--------|---------------|-------|
| Time unit | Fixed (2 weeks) | None | Session (variable) |
| Participation | Assignment | PR throwing | Session joining |
| Coordination | Daily standup | Async review | Handoff Bridge |
| Context sharing | Tickets | Issue comments | LOGBOOK + LOG# |
| Room reading | Not needed | Can't read | Read (Setlist Check) |

### Implications for New Economic Activity

```
Traditional Employment
└─ Fixed time, fixed place, fixed team

Bebop-style Participation
├─ Only when you have time (time-sharing)
├─ Only your specialty (skill-matching)
├─ Contribute per session (spot work)
└─ Contributions trackable via LOG# (value visualization)
```

In the context of spot work and gig economy, **contribution recording and context inheritance** become possible.

### Connection to Autonomous Distributed Control

```
ROS2 Node              Bebop Actor
├─ Operates independently  ├─ Works in independent sessions
├─ Communicates via topics ├─ Communicates via LOGBOOK/Handoff
├─ Subscribes as needed    ├─ Joins only interested Issues
└─ No central control      └─ No central control
```

Bebop method may be applicable not only to software development but also as **coordination protocol for autonomous distributed systems**.

### Key Realizations

1. **Born from practice** - Not copying someone, but result of hands-on work
2. **Reproducible** - Not Erimil-specific, applicable to other projects
3. **Applies to Human-AI-Human all** - Form of collaboration doesn't matter
4. **Methodology itself evolves** - TEMPLATE-FEEDBACK is the proof



## S002 Practice Feedback (2025-12-16)

Session focused on bug investigation (#7) which revealed issue was already fixed. Primary outcome was documentation and process refinement.

### Discoveries

| # | Issue | Description |
|---|-------|-------------|
| 14 | **"No work needed" is valid outcome** | Bug investigation revealed issue already fixed by cache changes. Documentation-only session is legitimate work. |
| 15 | **Side-effect fixes require hypothesis** | When closing issues fixed unintentionally, record hypothesis of what fixed it. Provides breadcrumbs for regression tracking. |
| 16 | **Versioning discipline** | Don't bump version for internal milestones. Phase-based versioning for 0.x.x development reduces overhead. |
| 17 | **Session End Checklist needed** | Wrap-up had implicit steps. Explicit numbered checklist with delegation scope improves handoff quality. |

### New Issues Identified

| # | Issue | Description | Priority |
|---|-------|-------------|----------|
| 18 | **Session End Checklist missing** | WORKFLOW.md lacked explicit wrap-up checklist with numbered items | High |
| 19 | **Delegation scope unclear** | Which wrap-up tasks can AI prepare vs Human must execute? | High |
| 20 | **"Already Fixed" pattern undocumented** | No template for closing issues fixed as side-effect | Medium |

### Actions Taken

- [x] Added Session End Checklist to WORKFLOW.md with numbered items
- [x] Added Delegatable column to checklist (AI can prepare, Human executes)
- [x] Added Decision 16 (Phase-based Versioning) to DESIGN.md
- [x] Created S002 session logs (en/ja)

### Proposals for v0.2.0

1. **Numbered Session End Checklist**
   
   Explicit numbered items enable:
   - Clear completion tracking
   - Future automation (AI delegation)
   - Consistent wrap-up quality

   ```markdown
   | # | Item | Scope | Delegatable |
   |---|------|-------|-------------|
   | 1 | Session log created | Required | ✅ Yes |
   | 2 | Handoff Bridge written | Required | ✅ Yes |
   | 3 | Issues closed/updated | Required | ❌ No (GitHub) |
   | ...
   ```

2. **Delegation Scope Column**
   
   Mark which tasks AI/System can prepare:
   - ✅ Yes = AI prepares file/content, Human commits
   - ❌ No = Human must execute (GitHub, Git, Xcode)
   
   Future: As tooling evolves, more items become fully delegatable.

3. **"Already Fixed" Issue Close Pattern**
   
   Template for closing issues fixed as side-effect:
   ```markdown
   ## Resolution
   
   Issue no longer reproduces as of [date].
   
   ## Hypothesis
   
   Likely fixed by [related change] because [reasoning].
   
   ## If Regression Occurs
   
   Check [specific areas to investigate].
   
   Closing as fixed. Will reopen if regression occurs.
   ```

4. **Versioning Guidelines in WORKFLOW.md**
   
   Add section:
   ```markdown
   ### Versioning Strategy
   
   During 0.x.x development:
   - Phase completion → minor version bump
   - Sub-phase completion → no bump, accumulate in [Unreleased]
   - Bug fixes → no bump unless critical
   - 1.0.0 → public release, compatibility guarantees begin
   ```

### Key Insight: Delegation as First-Class Concept

The distinction between "AI can prepare" and "Human must execute" is fundamental to Bebop method. Making this explicit in checklists:

1. **Clarifies collaboration boundaries**
2. **Enables future automation** - numbered items + delegation scope = automatable
3. **Reduces cognitive load** - Human knows exactly what requires their action
4. **Documents technical constraints** - Why can't AI do GitHub operations? (No credentials)

This connects to ADC's "Boundary, Not Control" principle: define what's delegatable, let AI operate freely within those boundaries.

---

## Licks Discovered (S002)

| # | Type | Content |
|---|------|---------|
| 8 | 💡 Discovery | Session End Checklist with numbered items + delegation scope |
| 9 | 💡 Discovery | "Already Fixed" close pattern for side-effect fixes |
| 10 | 🔥 Important | Delegation scope as explicit column in process checklists |
| 11 | ⚠️ Caution | Don't bump version for sub-phase completions |

---

## S003 Practice Feedback (2025-12-17)

Session focused on Phase 2.2 implementation (Slide Mode). Major architectural pivot required when fullScreenCover() discovered to be iOS-only. Primary outcomes: feature implementation + significant process improvements.

### Discoveries

| # | Issue | Description |
|---|-------|-------------|
| 21 | **Platform availability not always documented** | fullScreenCover() is iOS-only but many tutorials don't mention this. Always check Apple official docs for platform availability. |
| 22 | **Context loss is dual-sided** | Both Claude (context window compression) and Human (interruptions, task switching) lose context. Mitigation needed for both. |
| 23 | **Role division should be dynamic** | Not fixed "Claude does X, Human does Y" but "who is faster AND more accurate for THIS specific task?" |
| 24 | **Park→Issue conversion needs formalization** | Parked items accumulated but conversion to Issues was ad-hoc. Need explicit classification and conversion flow. |

### New Issues Identified

| # | Issue | Description | Priority |
|---|-------|-------------|----------|
| 25 | **State Snapshot mechanism needed** | Long sessions lose context; need periodic state capture | High |
| 26 | **Park metadata missing** | Who parked, when, in what context - not tracked | High |
| 27 | **macOS-specific patterns undocumented** | NSWindow cleanup, fullscreen constraints not in WORKFLOW.md | Medium |

### Actions Taken

- [x] Added State Snapshot Mechanism to WORKFLOW.md
- [x] Added Park Metadata format to WORKFLOW.md
- [x] Added Park→Issue Conversion flow to WORKFLOW.md
- [x] Added macOS Fullscreen Constraints to WORKFLOW.md Development Principles
- [x] Added NSWindow Cleanup Pattern to WORKFLOW.md Development Principles
- [x] Added Build Cache Awareness to WORKFLOW.md Development Principles
- [x] Created 5 new GitHub Issues (#14-#18) from session parks

### Key Learning: State Snapshot Mechanism

**Problem**: Context lost due to:
- Claude's context window compression (happened twice in S003)
- Human interruptions or task switching
- Long sessions with many steps

**Solution**: Write state snapshots at step boundaries:

```markdown
## [STATE] S003 / Step 3 Complete / 05:35

### Position
- Phase: 2.2, Step: 3/4
- Branch: feature/5-quick-look-navigation

### Completed
- [x] Step 1: ImageViewerCore
- [x] Step 2: a/d navigation
- [x] Step 3: Slide Mode

### Current State
- Files modified: 4 files
- Key decision: D005 (NSWindow for fullscreen)

### Next
- Step 4: z/c favorite navigation
```

**Future application**: Foundation for parallel processing (multiple Claudes, Human+Claude parallel work).

### Key Learning: Role Division by Task Characteristics

**Observation**: Effective Human-AI collaboration requires dynamic role division:

| Task Characteristics | Preferred Actor | Reason |
|---------------------|-----------------|--------|
| Large documentation with many dependencies | Claude | Consistency, accuracy across files |
| Official doc references + verification | Claude | Systematic checking |
| Few lines, 1-2 dependencies | Human | Faster for simple tasks |
| Complex judgment calls | Human | Context and intent |
| Repetitive accurate work | Claude | No fatigue, precision |

**Principle**: "Who is faster AND more accurate for THIS specific task?"

This is not fixed roles but dynamic allocation. Human explicitly requested Claude handle large doc updates in S003 because:
- Many files with interdependencies
- Consistency across files matters
- Verification of cross-references needed

### Key Learning: Park Metadata

**Before**: `[PARKED] Topic - Description`

**After**: `[PARKED/Who/Session/Context] Topic - Description`

Examples:
- `[PARKED/Claude/S003/Step4] Duplicate code - goToPreviousFavorite in 3 places`
- `[PARKED/Human/S003] Feature idea - Grid-Preview sync`

**Benefits**:
- Know who raised the item
- Know when it was raised
- Know what context triggered the observation
- Cross-session/project learning possible

### Key Learning: Park→Issue Conversion

At session end, classify parked items:

| Category | Action |
|----------|--------|
| Code quality / Refactor | → GitHub Issue (`refactor`, `ai-exp`) |
| Feature request | → GitHub Issue (`enhancement`) |
| Bug discovered | → GitHub Issue (`bug`) |
| Performance issue | → GitHub Issue (`enhancement`, `performance`) |
| Process improvement | → WORKFLOW.md |
| Philosophy / Insight | → LOGBOOK.md |

**S003 result**: 12 parked items → 5 Issues (#14-#18) + 3 WORKFLOW.md additions + 4 Later/LOGBOOK

### Proposals for v0.2.0

1. **State Snapshot in Session Sheet template**
   
   Add snapshot format and triggers:
   ```markdown
   ### [STATE] S{NNN} / Step {N} {Status} / {Timestamp}
   - Position: Phase X.Y, Step N/M
   - Completed: [list]
   - Current: [state]
   - Next: [action]
   ```

2. **Role Division Guidelines in WORKFLOW.md**
   
   Add section:
   ```markdown
   ### Dynamic Role Division
   
   Allocate tasks based on characteristics:
   | Characteristic | Preferred Actor |
   |----------------|-----------------|
   | High volume, many dependencies | Claude |
   | Simple, 1-2 dependencies | Human |
   | Consistency across files needed | Claude |
   | Complex judgment required | Human |
   ```

3. **Platform-Specific Patterns in WORKFLOW.md**
   
   Add macOS-specific section:
   - fullScreenCover() is iOS-only
   - NSWindow cleanup pattern
   - Build cache awareness

4. **Park Metadata as Standard**
   
   Update Parking Lot Mechanism:
   ```markdown
   Format: [PARKED/Who/Session/Context] Topic - Description
   ```

---

## Licks Discovered (S003)

| # | Type | Content |
|---|------|---------|
| 12 | 🔧 Technical | fullScreenCover() unavailable on macOS - always check platform availability |
| 13 | 🔧 Technical | NSWindow cleanup: contentView = nil → orderOut → close → nil reference |
| 14 | 🔧 Technical | Build cache issues with singleton - Clean Build (Cmd+Shift+K) resolves |
| 15 | 📋 Process | State Snapshot mechanism for context preservation across steps |
| 16 | 📋 Process | Park metadata: [PARKED/Who/Session/Context] format for traceability |
| 17 | 📋 Process | Park→Issue conversion flow at session end with category classification |
| 18 | 🤝 Collaboration | Role division by task characteristics (volume, dependencies, consistency) |
| 19 | 💡 Insight | "Who is faster AND more accurate for THIS task?" as allocation principle |
| 20 | 💡 Insight | Context loss is dual-sided - both AI and Human need mitigation strategies |
