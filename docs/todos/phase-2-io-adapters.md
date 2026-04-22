# Phase 2 — I/O Adapters

**Goal**: Implement the thin AppKit / AX / NSWorkspace wrappers listed in PLAN.md §I/O Layer. Keep each adapter small, single-responsibility, and integration-tested manually in Phase 6.

**Parallelism**: All six adapters are independent and can be written in parallel once T-1.1 protocol lands. Fully parallel with Phase 1 implementations and Phase 5.

**Exit criteria**: Each adapter compiles into the executable target; manual smoke of `swift build` succeeds. No unit tests here — these are I/O by design and are tested in Phase 3 (via fakes) and Phase 6 (live).

---

### T-2.1 — `AXDockFrameProvider`
- **Owner**: unassigned
- **Depends on**: T-1.1 (protocol), T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/IO/AXDockFrameProvider.swift`
- **Description**: Conforms to `DockFrameProvider`. Queries live Dock AX bounds. Refreshes on: `didChangeScreenParametersNotification`, Dock relaunch (`didLaunchApplicationNotification` filtered to `com.apple.dock`), and `com.apple.dock.prefchanged` via `DistributedNotificationCenter`. On near-miss click, re-queries once before bailing. Handles auto-hide by widening cached rect to the screen-edge strip (5pt → 10pt → full edge fallback chain).
- **Acceptance criteria**:
  - [ ] Conforms to `DockFrameProvider`
  - [ ] All three refresh observers installed in `init`, removed in `deinit`
  - [ ] Auto-hide detection via `CFPreferencesCopyAppValue("autohide", "com.apple.dock")`
  - [ ] Fallback chain (5pt / 10pt / full edge) documented in code comment
  - [ ] Near-miss re-query logic present
- **Verification step**:
  - Build and manually toggle: Dock resize, move, auto-hide. Log frame changes via `os_log`. Confirm each notification fires and `frame` updates. Record in Phase 6 checklist.
- **Notes**: PLAN.md §I/O Adapters, §Edge Cases.

### T-2.2 — `GlobalClickMonitor`
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/IO/GlobalClickMonitor.swift`
- **Description**: Wraps `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)`. Exposes `start(onClick: (CGPoint) -> Void)` and `stop()`. Must only be installed post-`AXIsProcessTrusted() == true`. Comment both caveats (no own-window clicks; no locked-screen clicks) prominently.
- **Acceptance criteria**:
  - [ ] Only `.leftMouseDown` — right/ctrl-click explicitly excluded with a comment
  - [ ] `start()` idempotent (calling twice doesn't double-register)
  - [ ] `stop()` removes the monitor cleanly
  - [ ] Source comment: "install only after AXIsProcessTrusted, reinstall on re-grant"
- **Verification step**:
  - `print(ev.locationInWindow)` in a dev build; grant Accessibility; click outside all windows; confirm events fire. Revoke Accessibility; confirm `stop()` silences events.
- **Notes**: PLAN.md §Technical Approach, §I/O Adapters.

### T-2.3 — `AXHitTester`
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/IO/AXHitTester.swift`
- **Description**: Holds a reused `AXUIElementCreateSystemWide()` reference. Applies `AXUIElementSetMessagingTimeout(element, 0.25)` on init. Exposes `hitTest(at: CGPoint) -> AXUIElement?`, `dockItemURL(_:) -> URL?` (walks up parent chain to `AXDockItem`, reads `kAXURLAttribute`, nil-guards Finder/Trash/stacks/separators; falls back to `kAXTitleAttribute` matched against frontmost `localizedName`), and `pid(_:) -> pid_t?`.
- **Acceptance criteria**:
  - [ ] System-wide element reused (field, not per-call)
  - [ ] Messaging timeout applied in init
  - [ ] `dockItemURL` walks parents to `AXDockItem`
  - [ ] Nil-guards for Finder/Trash/stacks/separators
  - [ ] Title fallback for Recent Applications section
  - [ ] Preview element (long-press) bails cleanly if no `AXDockItem` ancestor found
- **Verification step**:
  - Manual: long-press a Dock icon to show previews, click a preview. Must not crash, must not minimize. Verified in Phase 6 edge-case checklist.
- **Notes**: PLAN.md §Technical Approach (Dock previews, fallback identifier), §I/O Adapters.

### T-2.4 — `DockPIDCache`
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/IO/DockPIDCache.swift`
- **Description**: Caches `com.apple.dock`'s `pid_t`. Populates on init; refreshes on `didLaunchApplicationNotification` filtered to Dock. Exposes `var pid: pid_t?`. Multi-match tie-break: latest `launchDate`, prefer non-nil `launchDate`, never cache a terminated instance.
- **Acceptance criteria**:
  - [ ] `pid` is O(1) read
  - [ ] Launch observer installed + removed in lifecycle
  - [ ] Tie-break logic implemented (latest launchDate, non-terminated)
  - [ ] A brief window pointing at dying PID is acceptable — documented in code comment
- **Verification step**:
  - `killall Dock` while app is running. Log PID before/after. Confirm cache updates within ~1s.
- **Notes**: PLAN.md §I/O Adapters, §Edge Cases.

### T-2.5 — `WindowMinimizer`
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/IO/WindowMinimizer.swift`
- **Description**: `func minimizeFocusedWindow(of app: NSRunningApplication)`. Creates `AXUIElementCreateApplication(app.processIdentifier)`, applies `AXUIElementSetMessagingTimeout(appElement, 0.25)`, reads `kAXFocusedWindowAttribute`, no-ops if nil, otherwise sets `kAXMinimizedAttribute = true`.
- **Acceptance criteria**:
  - [ ] Per-app AX element messaging timeout = 0.25s
  - [ ] Nil-safe no-op when no focused window
  - [ ] Does not assert post-call visual state (async nature documented in comment)
- **Verification step**:
  - Manual: `kill -STOP <pid>` on Safari, click its Dock icon while frontmost. Pipeline must return within ~300ms (not stall). `kill -CONT` to restore. Phase 6 covers this.
- **Notes**: PLAN.md §I/O Adapters, §Technical Approach (timeout caveat).

### T-2.6 — `FrontmostAppProvider` (protocol + concrete)
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1, T-3.2 (pipeline fakes)
- **Files**: `Sources/ClickToMin/IO/FrontmostAppProvider.swift`
- **Description**: Ship a **protocol + concrete pair** so `DockWatcherPipelineTests` can substitute an in-memory fake without subclassing `NSWorkspace`. Protocol: `FrontmostAppProviding { var frontmost: NSRunningApplication? { get } }`. Concrete: `struct FrontmostAppProvider: FrontmostAppProviding { var frontmost: NSRunningApplication? { NSWorkspace.shared.frontmostApplication } }`. No caching — reads live each call (frontmost-read timing is click-dispatch time per PLAN.md §Coordinator).
- **Acceptance criteria**:
  - [ ] Protocol `FrontmostAppProviding` declared and used by `DockWatcher`'s init signature (not the concrete type)
  - [ ] Concrete `FrontmostAppProvider` conforms
  - [ ] No caching — `frontmost` reads `NSWorkspace.shared.frontmostApplication` on every call
  - [ ] Phase 3 pipeline fake can implement the protocol with a mutable stored `var` to simulate frontmost flipping between pipeline stages
- **Verification step**:
  - In `DockWatcherPipelineTests`, implement a fake with a mutable `frontmost` var; flip it between the hit-test and minimize stages via the shared call-order log's callback; assert the documented "read point" behavior holds.
- **Notes**: PLAN.md §I/O Adapters, §Coordinator. Protocol pair is the explicit fix — the pipeline fake requires it.

---

## Common Failure Patterns (pre-merge check)

- [ ] Adapter caches the AX system-wide element as a stored `var` but recreates it inside methods — defeats the perf claim
- [ ] Notification observers leaked (not removed in `deinit`)
- [ ] `GlobalClickMonitor` installed at app init (pre-permission) — silently yields no events forever
- [ ] `.leftMouseDown` expanded to include right/ctrl-click without updating PLAN.md scope
- [ ] `WindowMinimizer` ignores nil focused window and force-casts — will crash on all-minimized state
- [ ] `DockPIDCache` caches a `terminated == true` instance after race window

## Completed

<!-- Move finished tasks here -->
