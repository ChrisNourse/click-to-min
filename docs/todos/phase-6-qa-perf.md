# Phase 6 — Manual QA + Performance Validation

**Goal**: Run Layer 2 manual checklist and Layer 3 performance validation from PLAN.md §Testing. Populate `PERF.md` with baseline numbers. Gate every release.

**Parallelism**: Serial. Single maintainer executes this before each release cut. Categories within the checklist can be done in any order by one person.

**Exit criteria**: Every checkbox in Layer 2 flipped (or explicitly documented as skipped with reason); `PERF.md` populated with current-release memory + idle CPU baselines; any >20% regression acknowledged in the release notes.

---

### T-6.1 — Layer 2 Smoke
- **Owner**: maintainer
- **Depends on**: T-4.3
- **Blocks**: T-6.2
- **Files**: (checklist execution)
- **Description**: Run the 7 smoke items from PLAN.md §Testing Layer 2 / Smoke.
- **Acceptance criteria**:
  - [ ] `swift build` compiles cleanly
  - [ ] `./build.sh` produces signed `ClickToMin.app`
  - [ ] Launch `.app` → menu bar icon, Accessibility prompt
  - [ ] Grant Accessibility in System Settings
  - [ ] Quit via menu bar exits cleanly (no lingering process via `ps`)
  - [ ] Re-measured memory & idle CPU; `PERF.md` updated; >20% regression flagged
  - [ ] `log stream --predicate 'subsystem == "com.chrisno.click-to-min"'` shows expected lifecycle signposts
- **Verification step**:
  - Capture `log stream` output for 10s post-launch; diff against expected signposts (permission granted, monitor installed, Dock PID refreshed).
- **Notes**: PLAN.md §Layer 2 Smoke.

### T-6.2 — Layer 2 Core Behavior
- **Owner**: maintainer
- **Depends on**: T-6.1
- **Blocks**: T-6.3
- **Files**: (checklist)
- **Description**: 4-item Core Behavior checklist.
- **Acceptance criteria**:
  - [ ] Safari active, click Dock icon → key window minimizes
  - [ ] Click Dock icon again → window restores (macOS default)
  - [ ] Background app Dock click → front, no minimize
  - [ ] Full 3-click cycle: background → foreground → minimize → restore
- **Verification step**:
  - Use stopwatch / perceptual judgment; click-to-minimize must feel <50ms.
- **Notes**: PLAN.md §Layer 2 Core Behavior.

### T-6.3 — Layer 2 Multi-Window, Edge Cases, Multi-Display
- **Owner**: maintainer
- **Depends on**: T-6.2
- **Blocks**: T-6.4
- **Files**: (checklist)
- **Description**: Run Multi-Window (3), Edge Cases (10), Multi-Display (4) items. Includes the frozen-app timeout test (`kill -STOP / -CONT`), right-click / ctrl-click scope confirmation, long-press preview, Recent Applications section behavior, and display hot-plug.
- **Acceptance criteria**:
  - [ ] All Multi-Window checklist items pass
  - [ ] All Edge Cases checklist items pass (frozen-app returns within ~300ms)
  - [ ] All Multi-Display checklist items pass (including negative-origin)
  - [ ] Recent Applications observed behavior documented (minimize via title, or clean no-op)
- **Verification step**:
  - For frozen-app: wrap click + measurement in a stopwatch; log start/end timestamps via `os_log`. If stall observed, document: system-wide AX timeout is a no-op on this OS; update PLAN.md caveat accordingly.
- **Notes**: PLAN.md §Layer 2 Multi-Window / Edge Cases / Multi-Display. Critical verification step for the timeout claim.

### T-6.4 — Layer 2 Permission Lifecycle, Dock Configuration, Race Conditions
- **Owner**: maintainer
- **Depends on**: T-6.3
- **Blocks**: T-6.5
- **Files**: (checklist)
- **Description**: 6 Permission Lifecycle items (including `tccutil reset`), 4 Dock Configuration items (resize/move/auto-hide), 2 Race Condition items.
- **Acceptance criteria**:
  - [ ] Revoke Accessibility while running → clicks no-op, no crash
  - [ ] Re-grant without sleeping → 2s poll detects, monitor reinstalls
  - [ ] Sleep/wake cycle → re-check fires, still works
  - [ ] Fresh install: launch pre-grant, grant after → events start flowing
  - [ ] Rebuild via `./build.sh` → Accessibility persists
  - [ ] `tccutil reset Accessibility com.chrisno.click-to-min` → next launch re-prompts cleanly
  - [ ] Resize / move / auto-hide / disable auto-hide all refresh frame
  - [ ] Rapid double-click → exactly one minimize
  - [ ] Click during app launch animation → no crash
- **Verification step**:
  - `tccutil reset Accessibility com.chrisno.click-to-min && open ClickToMin.app` — confirms full recovery path.
- **Notes**: PLAN.md §Layer 2 Permission Lifecycle / Dock Configuration / Race Conditions.

### T-6.5 — Layer 3 Performance Validation + populate `PERF.md`
- **Owner**: maintainer
- **Depends on**: T-6.4
- **Blocks**: release
- **Files**: `PERF.md`
- **Description**: Run Instruments passes per PLAN.md §Testing Layer 3. Record baselines and regressions.
- **Acceptance criteria**:
  - [ ] Time Profiler: 1000 clicks outside Dock → `AXUIElementCopyElementAtPosition` not in hot path
  - [ ] Time Profiler: clicks inside Dock → AX call present but bounded
  - [ ] Allocations: 5-min idle → resident memory <10 MB
  - [ ] Allocations: 500 Dock clicks → no growth (no per-click leak)
  - [ ] Perceptual latency test: click-to-minimize <50ms
  - [ ] `PERF.md` updated with current-release baseline (memory MB, idle CPU %, latency ms)
  - [ ] Any >20% regression from previous baseline flagged in PR / release notes
- **Verification step**:
  - Attach Instruments Time Profiler to running app, run `cliclick` loop of 1000 clicks outside Dock (e.g., screen corner). Export trace; inspect heaviest stack trace — AX hit-test call must not appear. Repeat inside Dock; call must appear but bounded to those clicks.
- **Notes**: PLAN.md §Layer 3, §Regression Guard. If skipped, note reason in `PERF.md`.

---

## Common Failure Patterns (pre-release check)

- [ ] Checklist skipped silently (all boxes ticked without actually running) — require maintainer initials + date next to completed sections
- [ ] `PERF.md` not updated — regression guard becomes vapor
- [ ] Frozen-app timeout observation lost — if the system-wide AX timeout is a no-op on this OS, PLAN.md claim must be updated
- [ ] Recent Applications section behavior not recorded — blind spot for user reports
- [ ] `tccutil reset` not run — users hitting stuck permission state have no documented recovery
- [ ] >20% regression found but not flagged in release notes — future releases lose context

## Completed

<!-- Move finished tasks here -->
