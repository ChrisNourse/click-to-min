# Phase 0 — Scaffolding

**Goal**: Establish the project skeleton so every downstream phase has somewhere to land code.

**Parallelism**: Serial. Must complete before Phases 1–5 begin (Phase 5 can spawn stub workflows as soon as the repo exists).

**Exit criteria**: `swift build` succeeds on an empty project; directory layout matches `PLAN.md` §File Structure; CI can checkout and run `swift build` without failure.

---

### T-0.1 — Initialize Swift package ✅
- **Owner**: unassigned
- **Depends on**: none
- **Blocks**: T-0.2, T-0.3, T-1.*, T-2.*
- **Files**: `Package.swift`
- **Description**: Create the SwiftPM manifest with three targets per PLAN.md §1: executable `ClickToMin`, library `ClickToMinCore` (pure, no AppKit), test `ClickToMinTests` depending on `ClickToMinCore`. Target macOS 13+.
- **Acceptance criteria**:
  - [x] `Package.swift` declares `platforms: [.macOS(.v13)]`
  - [x] `ClickToMinCore` target compiles from `Sources/ClickToMin/Core` only
  - [x] Executable target depends on `ClickToMinCore` and the I/O sources
  - [x] `ClickToMinTests` target depends on `ClickToMinCore` (not the executable)
  - [x] `swift build` succeeds on an empty source tree with placeholder files
- **Verification step**:
  - Run `swift build -c debug` and `swift build -c release`. Attempt `import AppKit` inside a Core file — the build must fail, proving the boundary. Revert the experiment.
- **Notes**: Boundary enforcement is the whole point of the library split (PLAN.md §Architecture).

### T-0.2 — Create directory skeleton with placeholder files ✅
- **Owner**: unassigned
- **Depends on**: T-0.1
- **Blocks**: T-1.*, T-2.*, T-3.*
- **Files**: all paths listed in PLAN.md §File Structure
- **Description**: Create `Sources/ClickToMin/{AppDelegate.swift,DockWatcher.swift,IO/*,Core/*}`, `Tests/ClickToMinTests/*`, `Resources/`, `.github/workflows/`. Each Swift file contains a minimal `// TODO: Phase N` stub that compiles.
- **Acceptance criteria**:
  - [x] Every file in PLAN.md §File Structure exists
  - [x] Every Swift stub compiles (empty `enum Placeholder {}` or similar)
  - [x] `swift build` succeeds
  - [x] `swift test` runs zero tests and exits 0
- **Verification step**:
  - `find Sources Tests Resources .github -type f | sort` — diff against the PLAN.md §File Structure list; must match exactly (no extras, no omissions).
- **Notes**: Common failure: forgetting the `Resources/` directory or the CI workflows dir. Both are required by later phases.

### T-0.3 — Commit `PERF.md` (full schema) and `.swiftformat` stubs ✅
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-5.3 (lint job), T-6.5 (perf baseline)
- **Files**: `PERF.md`, `.swiftformat`
- **Description**: `PERF.md` is committed with its **full table schema** (steady-state metrics, short-circuit effectiveness, OS-specific observations, release history) pre-populated with `TBD` so Phase 6 has a concrete target shape, not just a placeholder paragraph. `.swiftformat` contains the committed config used by the CI lint job.
- **Acceptance criteria**:
  - [x] `PERF.md` exists with all four sections from PLAN.md §File Structure note (steady-state metrics, short-circuit effectiveness, OS observations, release history)
  - [x] Each table has its full header row and at least one `TBD` row
  - [x] `.swiftformat` exists and parses (`swiftformat --lint .` exits without a config error)
- **Verification step**:
  - `swiftformat --lint .` — must not error on config parsing (style drift reports are fine).
  - Open `PERF.md` in a markdown previewer; confirm all four tables render with headers.
- **Notes**: Committing the **schema** — not just a placeholder — is the fix for the regression-guard drift risk. PLAN.md §File Structure note (updated).

### T-0.4 — Commit PR template ✅
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-5.1
- **Files**: `.github/pull_request_template.md`
- **Description**: PR template with the checklist from PLAN.md §PR Hygiene: tests added/updated, Layer 2 items relevant to this change, `PERF.md` touched if hot path changed, `log stream` spot-check run.
- **Acceptance criteria**:
  - [x] File exists at the canonical GitHub path
  - [x] Contains all four checklist items from PLAN.md §PR Hygiene
- **Verification step**:
  - Open a draft PR in a scratch branch; confirm GitHub auto-populates the body with the template.
- **Notes**: CODEOWNERS deliberately omitted for v1 per PLAN.md §Solo-maintainer nuance.

---

## Common Failure Patterns (pre-merge check)

- [x] Core target accidentally imports AppKit (try it, must fail)
- [x] Test target accidentally depends on executable (circular; must not)
- [x] Placeholder files left with non-compiling content
- [x] Missing `Resources/Info.plist` directory — Phase 4 will silently break

## Completed

<!-- Move finished tasks here -->
