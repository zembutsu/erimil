# Session Sheet Template

> Real-time record of a development session
> Part of Bebop Style Development methodology

---

## LOG#\<num\>: \<Session Title\>

**Date**: YYYY-MM-DD  
**Duration**: HH:MM - HH:MM  
**Issues**: #X, #Y, #Z  
**Actors**: Claude, Zem  
**Depends on**: LOG#\<prev\> (if any)

---

### Setlist (Session Goals)

- [ ] Issue #X: \<goal\>
- [ ] Issue #Y: \<goal\>
- [ ] \<other task\>

---

### Timeline

| Time | Actor | Action | Issue | Status |
|------|-------|--------|-------|--------|
| HH:MM | Zem | Session start, Setlist Check | - | - |
| HH:MM | Claude | Propose approach | #X | 🔄 |
| HH:MM | Zem | Review & approve | #X | ✅ |
| HH:MM | Claude | Implement | #X | 🔄 |
| HH:MM | Zem | Test | #X | ✅/❌ |
| ... | ... | ... | ... | ... |

**Status icons**:
- 🔄 In progress
- ✅ Completed
- ❌ Blocked / Failed
- ⏸️ Paused
- 💡 Insight / Discovery

---

### Notes

> Real-time observations, decisions, blockers, discoveries

- 
- 
- 

---

### Parked (Out of Scope)

> Ideas or topics that emerged but are out of scope for this session

| Topic | Description | Destination |
|-------|-------------|-------------|
| \<topic\> | \<one-line\> | Issue / LOGBOOK / Later |

---

### Outcome

**Completed**:
- [ ] Issue #X: \<result\>
- [ ] Issue #Y: \<result\>

**Remaining**:
- [ ] Issue #Z: \<reason\>

**Discoveries**:
- \<unexpected findings\>

---

### Handoff Bridge

**Carry forward to next session**:
- 
- 

**Technical notes**:
- 

**Blockers**:
- 

---

### → LOGBOOK Entry

> Copy key points to LOGBOOK.md after session ends

```markdown
## YYYY-MM-DD (LOG#<num>: <Session Title>)

### 📍 Current Position
- 

### ⚓ Decisions
- 

### 💡 Insights
- 

### 📚 Learnings
- 

### ⏸️ Parked
- 

### 🌊 Ideas
- 

### 🌉 Handoff Bridge
- 
```

---

## Usage Notes

1. **Start of session**: Copy this template, fill in header and Setlist
2. **During session**: Update Timeline in real-time
3. **Out of scope topic**: Immediately add to Parked section, then return to focus
4. **End of session**: Fill Outcome, Handoff Bridge, then extract to LOGBOOK
5. **Archive**: Save as `sessions/LOG-<num>-<title>.md` (optional)

## Scope Control

When off-topic ideas emerge:

```
"That's interesting, but out of scope"
    ↓
Add to Parked table with destination
    ↓
Return to Setlist focus
```

**Destinations**:
- `Issue` - Create GitHub Issue after session
- `LOGBOOK` - Record in Ideas section
- `Later` - Revisit in future session

## Naming Convention

```
LOG#001 - First session
LOG#002 - Second session
...
LOG#NNN - N-th session
```

Sequential numbering, project-wide unique.
