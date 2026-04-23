# Phase 3 — Coordinator & App Shell

**Goal**: Wire Core + I/O into the click pipeline (`DockWatcher`) and the app lifecycle (`AppDelegate`). Pipeline tests with in-memory fakes lock the contract.

**Parallelism**: Sequential within phase. T-3.1 (DockWatcher) and T-3.2 (pipeline tests) can be written together by the same engineer (TDD). T-3.3 (AppDelegate) depends on T-3.1.

**Exit criteria**: `swift test` green including `DockWatcherPipelineTests`; app launches, prompts for Accessibility, installs monitor post-grant, minimizes on Dock click of frontmost app.

---

### T-3.1 — `DockWatcher` coordinator ✅
- **Owner**: unassigned
- **Depends on**: T-1.2, T-1.3, T-1.4, T-1.5, T-2.1, T-2.2, T-2.3, T-2.4, T-2.5, T-2.6
- **Blocks**: T-3.2, T-3.3
- **Files**: `Sources/ClickToMin/DockWatcher.swift`
- **Description**: Coordinator with **no branching logic of its own**. Wires components and dispatches on each click per PLAN.md §Coordinator. All work on main thread (AX thread affinity). Frontmost read at click-dispatch time, not cached.
- **Acceptance criteria**:
  - [x] Pipeline matches PLAN.md §Coordinator exactly
  - [x] No `if`/`switch` beyond early-returns (`guard`) in pipeline
  - [x] All AX calls on main thread (comment + `MainActor` isolation or `dispatchPrecondition`)
  - [x] `FrontmostAppProvider.frontmost` read at click-time
  - [x] `ClickDebouncer` keyed by bundle URL string (not PID)
  - [x] Public `start()` / `stop()` for AppDelegate re-grant/revoke cycle
- **Verification step**:
  - Add `dispatchPrecondition(condition: .onQueue(.main))` at the top of the click handler. Run `swift test` and the live app. If the precondition trips, fix before merge.
- **Notes**: PLAN.md §Architecture, §Coordinator, §Thread Contract.

### T-3.2 — `DockWatcherPipelineTests` with fakes ✅
- **Owner**: unassigned
- **Depends on**: T-3.1
- **Blocks**: T-3.3 (release gate)
- **Files**: `Tests/ClickToMinTests/DockWatcherPipelineTests.swift`
- **Description**: In-memory fakes for every I/O protocol (`DockFrameProvider`, `FrontmostAppProvider`, hit tester, minimizer, Dock PID cache). Every fake records invocations into a shared ordered log. Tests assert both behavior **and exact call sequence**.
- **Acceptance criteria**:
  - [x] Fake for each protocol dependency (at least 5 fakes)
  - [x] Shared invocation log for call-order assertions
  - [x] Test: click outside Dock → stops at `DockGeometry.contains`, hit tester never called
  - [x] Test: click inside Dock, PID mismatch → stops at PID check
  - [x] Test: Dock PID nil (mid-relaunch) → pipeline aborts safely
  - [x] Test: URL mismatch → minimizer never called
  - [x] Test: URL match, debouncer suppresses → minimizer never called
  - [x] Test: happy path → minimizer called exactly once with correct `NSRunningApplication`
  - [x] Test: frontmost flips between calls → decision consistent with documented read point
  - [x] Happy-path test asserts exact sequence `dockFrame → hitTest → pid → dockItemURL → frontmost → debounce → minimize`
- **Verification step**:
  - `swift test --filter DockWatcherPipelineTests`. Intentionally reorder two pipeline steps in `DockWatcher`; call-order test must fail. Revert.
- **Notes**: PLAN.md §Testing Layer 1 (DockWatcherPipelineTests bullet). This is the regression guard for the pipeline contract.

### T-3.3 — `AppDelegate` lifecycle ✅
- **Owner**: unassigned
- **Depends on**: T-3.1, T-3.2
- **Blocks**: T-4.*, T-6.*
- **Files**: `Sources/ClickToMin/AppDelegate.swift`
- **Description**: `@main`. Sets `.accessory` activation policy (redundant with `LSUIElement`; comment rationale). Creates `NSStatusItem` with icon + Quit. `AXIsProcessTrusted()` check on launch; opens System Settings → Privacy & Security → Accessibility if missing. 2s `Timer` polls `AXIsProcessTrusted()` while untrusted; stops when trusted. Re-checks on `NSWorkspace.didWakeNotification`. Installs `DockWatcher` post-grant; tears down on revoke.
- **Acceptance criteria**:
  - [x] `@main` attribute, no `main.swift`
  - [x] `.accessory` activation policy set + commented
  - [x] Status bar item with Quit
  - [x] Initial permission check opens System Settings deep link if missing
  - [x] 2s timer polls while untrusted, invalidated when granted
  - [x] Wake notification triggers re-check
  - [x] `DockWatcher.start()` called only post-grant
  - [x] `DockWatcher.stop()` called on revoke detected by poll
- **Verification step**:
  - Manual: launch unsigned debug build with Accessibility not granted → alert + Settings opens. Grant permission without quitting → within 2s, click behavior activates. Revoke permission → clicks no-op without crash. Covered by Phase 6 Permission Lifecycle section.
- **Notes**: PLAN.md §AppDelegate, §Technical Approach (post-permission install).

---

## Common Failure Patterns (pre-merge check)

- [x] `DockWatcher` contains branching logic beyond `guard` early-returns — violates PLAN.md "coordinator is only the pipeline"
- [x] Click handler dispatches to a background queue — AX thread affinity violation
- [x] Frontmost cached at `DockWatcher.init` — must be read at click time
- [x] Debouncer keyed by PID — app relaunch would bypass debounce (PLAN.md Known Sharp Edge)
- [x] `AppDelegate` installs `GlobalClickMonitor` before `AXIsProcessTrusted() == true` — silent failure
- [x] Timer not invalidated on grant — wasted cycles forever
- [x] Permission revoke path not tested — app silently does nothing but user doesn't know why
- [x] Pipeline test asserts behavior but not call order — reorder regressions slip through

## Completed

<!-- Move finished tasks here -->
