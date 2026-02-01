# Project List

Centralized tracking of all projects with status, priority, and dependencies.

> **Quick Reference**: See `codev/resources/workflow-reference.md` for stage diagrams and common commands.

## Project Lifecycle

Every project goes through stages. Not all projects reach completion:

**Active Lifecycle:**
1. **conceived** - Initial idea captured. Spec file may exist but is not yet approved. **AI agents must stop here after writing a spec.**
2. **specified** - Specification approved by human. **ONLY the human can mark a project as specified.**
3. **planned** - Implementation plan created (codev/plans/NNNN-name.md exists)
4. **implementing** - Actively being worked on (one or more phases in progress)
5. **implemented** - Code complete, tests passing, PR created and awaiting review
6. **committed** - PR merged to main branch
7. **integrated** - Merged to main, deployed to production, validated, reviewed (codev/reviews/NNNN-name.md exists), and **explicitly approved by project owner**. **ONLY the human can mark a project as integrated** - AI agents must never transition to this status on their own.

**Terminal States:**
- **abandoned** - Project canceled/rejected, will not be implemented (explain reason in notes)
- **on-hold** - Temporarily paused, may resume later (explain reason in notes)

## Format

```yaml
projects:
  - id: "NNNN"              # Four-digit project number
    title: "Brief title"
    summary: "One-sentence description of what this project does"
    status: conceived|specified|planned|implementing|implemented|committed|integrated|abandoned|on-hold
    priority: high|medium|low
    files:
      spec: codev/specs/NNNN-name.md       # Required after "specified"
      plan: codev/plans/NNNN-name.md       # Required after "planned"
      review: codev/reviews/NNNN-name.md   # Required after "integrated"
    dependencies: []         # List of project IDs this depends on
    tags: []                # Categories (e.g., auth, billing, ui)
    notes: ""               # Optional notes about status or decisions
```

## Numbering Rules

1. **Sequential**: Use next available number (0001-9999)
2. **Reservation**: Add entry to this file FIRST before creating spec
3. **Renumbering**: If collision detected, newer project gets renumbered
4. **Gaps OK**: Deleted projects leave gaps (don't reuse numbers)

## Archiving Completed Projects

Once projects are `integrated` or `abandoned` for 3+ days, move them to `projectlist-archive.md`:

```
codev/
  projectlist.md          # Active projects (conceived → committed)
  projectlist-archive.md  # Completed projects (integrated, abandoned)
```

**Why archive?**
- Keeps daily work file small and fast
- Full history still versioned in git
- Can grep across both files when needed

**Archive format**: Same YAML format, sorted by ID (historical record).

## Usage Guidelines

### When to Add a Project

Add a project entry when:
- You have a concrete idea worth tracking
- The work is non-trivial (not just a bug fix or typo)
- You want to reserve a number before writing a spec

### Status Transitions

```
conceived → [HUMAN] → specified → planned → implementing → implemented → committed → [HUMAN] → integrated
     ↑                                                                                   ↑
Human approves                                                                    Human approves
   the spec                                                                      production deploy

Any status can transition to: abandoned, on-hold
```

**Human approval gates:**
- `conceived` → `specified`: Human must approve the specification
- `committed` → `integrated`: Human must validate production deployment

### Priority Guidelines

- **high**: Critical path, blocking other work, or significant business value
- **medium**: Important but not urgent, can wait for high-priority work
- **low**: Nice to have, polish, or speculative features

### Tags

Use consistent tags across projects for filtering:
- `auth`, `security` - Authentication and security features
- `ui`, `ux` - User interface and experience
- `api`, `architecture` - Backend and system design
- `testing`, `infrastructure` - Development and deployment
- `billing`, `credits` - Payment and monetization
- `features` - New user-facing functionality

---

## Projects

```yaml
projects:
  - id: "0002"
    title: "Chunked Audio Streaming"
    summary: "Stream audio progressively so playback starts <500ms regardless of text length"
    status: committed
    priority: high
    files:
      spec: codev/specs/0002-chunked-audio-streaming.md
      plan: codev/plans/0002-chunked-audio-streaming.md
      review: codev/reviews/0002-chunked-audio-streaming.md
    dependencies: []
    tags: [ux, performance, audio]
    notes: "PR #1 merged 2026-02-01. O(1) ring buffer, RT-safe locking, 21 tests. Race conditions fixed in review."

  - id: "0003"
    title: "Multi-Language Support (Romance Languages)"
    summary: "Add 36 voices: 28 English + 8 Romance (Spanish, Italian, Portuguese) with rule-based G2P"
    status: integrated
    priority: high
    files:
      spec: codev/specs/0003-multi-language-support.md
      plan: codev/plans/0003-multi-language-support.md
      review: codev/reviews/0003-multi-language-support.md
    dependencies: []
    tags: [features, i18n, voices]
    notes: "Integrated 2026-02-01. Pure Swift rule-based G2P, no GPL dependencies. All tests passing."
```

## Next Available Number

**0004** - Reserve this number for your next project

---

## Quick Reference

### View by Status
To see all projects at a specific status, search for `status: <status>` in this file.

### View by Priority
To see high-priority work, search for `priority: high`.

### Check Dependencies
Before starting a project, verify its dependencies are at least `implemented`.

### Protocol Selection
- **SPIDER**: Most projects (formal spec → plan → implement → review)
- **TICK**: Small, well-defined tasks (< 300 lines) or amendments to existing specs
- **EXPERIMENT**: Research/prototyping before committing to a project
