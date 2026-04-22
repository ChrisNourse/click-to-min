# ClickToMin — Implementation Todo Index

Source of truth: [`PLAN.md`](../../PLAN.md).

This directory splits the plan into phase files so work can be parallelized and tracked independently. Each phase file uses the **task spec format** defined below.

## Phase Map & Parallelism

```
          ┌──────────────────────────┐
          │ Phase 0 — Scaffolding    │   (serial — blocks everything)
          └─────────────┬────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
 ┌─────────────┐ ┌─────────────┐ ┌────────────────┐
 │ Phase 1     │ │ Phase 2     │ │ Phase 5        │   (all 3 parallel
 │ Core (pure) │ │ I/O Adapters│ │ CI/CD          │    once Phase 0 is done)
 └──────┬──────┘ └──────┬──────┘ └────────┬───────┘
        └───────┬───────┘                 │
                ▼                         │
     ┌────────────────────────┐           │
     │ Phase 3 — Coordinator  │           │
     │ + AppDelegate          │           │
     └──────────┬─────────────┘           │
                ▼                         │
     ┌────────────────────────┐           │
     │ Phase 4 — Packaging    │◄──────────┘  (Phase 5 CI can begin with
     │ (build.sh, Info.plist) │               stub workflows; integrates
     └──────────┬─────────────┘               with real build in Phase 4)
                ▼
     ┌────────────────────────┐
     │ Phase 6 — Manual QA +  │
     │ Perf Validation (L2+L3)│
     └────────────────────────┘
```

### Parallel vs. Serial

| Phase | File | Depends On | Can Parallel With |
|-------|------|------------|-------------------|
| 0 | [phase-0-scaffolding.md](phase-0-scaffolding.md) | — | (none — must finish first) |
| 1 | [phase-1-core.md](phase-1-core.md) | 0 | Phase 2, Phase 5 |
| 2 | [phase-2-io-adapters.md](phase-2-io-adapters.md) | 0, Phase 1 **protocols only** (`DockFrameProvider`) | Phase 1 implementations, Phase 5 |
| 3 | [phase-3-coordinator-app.md](phase-3-coordinator-app.md) | 1, 2 | Phase 5 |
| 4 | [phase-4-packaging.md](phase-4-packaging.md) | 3 | Phase 5 |
| 5 | [phase-5-cicd.md](phase-5-cicd.md) | 0 (stub workflows); 4 (bundle-check job) | 1, 2, 3, 4 |
| 6 | [phase-6-qa-perf.md](phase-6-qa-perf.md) | 4 | — (release gate) |

### Parallel-Track Recommendations

- **Track A (Core engineer)**: Phase 0 → Phase 1 → join Phase 3
- **Track B (I/O engineer)**: wait on Phase 0 + Phase 1 protocol stubs → Phase 2 → join Phase 3
- **Track C (Infra)**: Phase 0 → Phase 5 in parallel; finalize bundle-check job once Phase 4 lands
- **Release gate**: Phase 6 is single-threaded, run by the maintainer before every release

### Critical Serial Constraint

Phase 1's **protocol definitions** (`DockFrameProvider`) must land early so Phase 2's `AXDockFrameProvider` has something to conform to. Recommended: commit protocol stubs as the **first** task in Phase 1 to unblock Phase 2 immediately.

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
