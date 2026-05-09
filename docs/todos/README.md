# ClickToMin — Implementation Todo Index

Source of truth: [`PLAN.md`](../../PLAN.md).

This directory splits the plan into phase files so work can be parallelized and tracked independently. Each phase file uses the **task spec format** defined below.

## Active work

| Phase | File | Status |
|-------|------|--------|
| 7 — Inline menu settings | [phase-7-settings.md](phase-7-settings.md) | in progress |
| 8 — Homebrew cask distribution | [phase-8-brew-distribution.md](phase-8-brew-distribution.md) | in progress (depends on 9) |
| 9 — Persistent self-signed codesign in CI | [phase-9-persistent-codesign.md](phase-9-persistent-codesign.md) | in progress |
| — — signing setup streamlining | [signing-streamlining.md](signing-streamlining.md) | open, unscheduled |

## Completed phases (archived)

Phases 0 through 6 are archived under [`completed/`](completed/).

## Task Spec Format

Every task across every phase uses this shape:

```markdown
### T-<phase>.<n> — <short title>
- **Owner**: <unassigned | @handle>
- **Depends on**: <T-ids or "none">
- **Blocks**: <T-ids or "none">
- **Files**: <paths touched/created>
- **Description**: <what + why, 1-3 sentences>
- **Acceptance criteria**:
  - [ ] <testable condition 1>
  - [ ] <testable condition 2>
- **Verification step**:
  - <command to run / manual check / test to execute that proves the acceptance criteria hold, including common failure-pattern checks>
- **Notes**: <edge cases, references back to PLAN.md section>
```

## Status Legend

- `[ ]` — not started
- `[~]` — in progress
- `[x]` — complete
- `[!]` — blocked (add a note with blocker)

## How to Update

1. Claim a task by setting `Owner`.
2. Flip acceptance checkboxes as each is verified.
3. When all acceptance items are `[x]` **and** the verification step passes, mark the task's heading with ✅ or move it to a `## Completed` section at the bottom of the phase file.
4. Any change to scope or new work discovered during implementation → add a follow-up task in the same phase file (or the next phase if out of scope).
