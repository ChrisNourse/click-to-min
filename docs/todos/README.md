# ClickToMin — Implementation Todo Index

Source of truth: [`../../PLAN.md`](../../PLAN.md).

## Active work

| Phase | File | Status |
|-------|------|--------|
| 6 — QA automation | [phase-6-qa-automation.md](phase-6-qa-automation.md) | in progress |
| 7 — Inline menu settings | [phase-7-settings.md](phase-7-settings.md) | complete |
| 8 — Homebrew cask distribution | [phase-8-brew-distribution.md](phase-8-brew-distribution.md) | complete |
| 9 — Persistent self-signed codesign in CI | [phase-9-persistent-codesign.md](phase-9-persistent-codesign.md) | complete |

## Completed phases (archived)

Phases 0 through 5 are archived under [`completed/`](completed/).

| Archived file | What it covered |
|---------------|-----------------|
| [completed/phase-0-scaffolding.md](completed/phase-0-scaffolding.md) | Swift package, directory skeleton, PERF.md stub, PR template |
| [completed/phase-1-core.md](completed/phase-1-core.md) | Pure Core layer: `CoordinateConverter`, `DockGeometry`, `ClickDebouncer`, `BundleURLMatcher` |
| [completed/phase-2-io-adapters.md](completed/phase-2-io-adapters.md) | I/O adapters: `AXDockFrameProvider`, `GlobalClickMonitor`, `AXHitTester`, `DockPIDCache`, `WindowMinimizer`, `FrontmostAppProvider` |
| [completed/phase-3-coordinator-app.md](completed/phase-3-coordinator-app.md) | `DockWatcher` coordinator + pipeline tests + `AppDelegate` |
| [completed/phase-4-packaging.md](completed/phase-4-packaging.md) | `Info.plist`, `build.sh`, launch smoke |
| [completed/phase-5-cicd.md](completed/phase-5-cicd.md) | GitHub Actions CI + release workflow + `.swiftformat` + branch protection |

## Task Spec Format

Every task uses this shape:

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
3. When all acceptance items are `[x]` **and** the verification step passes, mark the task's heading with ✅ or move it to the `## Completed` section at the bottom of the phase file.
4. Any change to scope or new work discovered during implementation → add a follow-up task in the same phase file (or a new phase file if out of scope).
5. When a whole phase is done, move the file into `completed/` and update the table above.
