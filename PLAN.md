# ClickToMin — Implementation Plan

## Overview

A macOS menu bar app that minimizes the key window of the active app when you click its Dock icon. Augments the default macOS behavior (which does nothing in that case) without breaking normal Dock interactions.

## Behavior

- Click a Dock icon while that app is **already active**: key (focused) window minimizes
- Click a Dock icon for a **background app**: normal bring-to-front behavior (unaffected)
- Click a Dock icon for an active app with **all windows already minimized**: macOS default restore behavior (we no-op because there is no focused window)
- App itself has **no Dock icon** — lives only in the menu bar with a Quit option

### Confirmed Click Cycle

1. App backgrounded → click Dock icon → macOS brings forward (no interference)
2. App frontmost → click Dock icon → ClickToMin minimizes key window
3. App frontmost with windows minimized → click Dock icon → macOS restores window (no interference)

### Scope Decision: Key Window Only

Only the focused window minimizes, not all windows of the app. This matches user intent (they see the window they just interacted with disappear) and is predictable. If desired later, iterating `kAXWindowsAttribute` and setting `kAXMinimizedAttribute` on each is a one-line change.

## Technical Approach

- **`CGEventTap` at `.cgSessionEventTap` (listen-only)** — passive session-wide click monitor (doesn't consume events). We originally used `NSEvent.addGlobalMonitorForEvents`, but it does not fire for clicks on the Dock process on recent macOS versions; a session-level `CGEventTap` is the reliable replacement. See PR #4.
  - **Modifier/button scope**: tap `.leftMouseDown` only. Right-click and Ctrl-click on Dock items open the context menu; we deliberately ignore them. Document in source so the scope isn't "accidentally expanded" later.
  - **Important**: the tap only creates successfully once Accessibility is granted. Install it *after* `AXIsProcessTrusted()` returns true, and reinstall on re-grant. `CGEvent.tapCreate` returns nil pre-permission.
  - **Self-healing**: when the system disables the tap (e.g., slow callback), the monitor re-enables it on the next event via `tapEnable(tap, enable: true)`.
- **Dock-frame short-circuit**: before any AX call, test whether the click point falls inside the cached Dock screen region. Skip AX entirely otherwise.
- `AXUIElementCopyElementAtPosition` only for clicks inside the Dock region
- Set a short AX messaging timeout via `AXUIElementSetMessagingTimeout` on **both** the system-wide element (hit testing) and the per-app element (minimize call) to avoid stalls on unresponsive apps (full-screen/Stage Manager edge cases)
  - **Caveat**: historically the system-wide element has ignored per-element timeouts on some macOS versions, falling back to the global default. Verify empirically on the target OS during manual testing; if it's a no-op, rely on the per-app timeout alone and rewrite this claim before shipping.
  - **Verification step** (part of Layer 2 manual testing): SIGSTOP a target app (`kill -STOP <pid>`), click its Dock icon while frontmost, confirm the pipeline returns within ~300ms (not stalled). SIGCONT to restore. If the system-wide timeout is a no-op, the hit-test path will stall — in that case, shrink the hot path so only the per-app minimize call touches the frozen process.
- **Cache the Dock's PID** (refresh on `com.apple.dock` launch notification) so per-click PID validation is a single integer compare, not a process lookup
- **Thread contract**: the global monitor fires on the main thread; all AX calls must stay on main (AX APIs have thread affinity). Do not offload the pipeline to a background queue.
- Verify the hit element's PID belongs to `com.apple.dock`
- Walk AX hierarchy to the `AXDockItem`, read `kAXURLAttribute` (bundle URL)
  - **Fallback identifier**: `kAXURLAttribute` is not always populated — notably for "Recent Applications" Dock entries and apps launched from non-standard locations across macOS versions. If the URL is nil but the element is still an `AXDockItem`, fall back to `kAXTitleAttribute` matched against `NSRunningApplication.localizedName` of the frontmost app. Document "Recent Applications Dock section" as best-effort.
  - **Dock previews / long-press**: if the user long-presses to show window previews, the hit element may be a child preview element rather than `AXDockItem`. Walk up the parent chain to find an `AXDockItem`; if none is found, bail cleanly. A manual test case covers this.
- Compare to `NSWorkspace.shared.frontmostApplication?.bundleURL`
- On match: read `kAXFocusedWindowAttribute`, set `kAXMinimizedAttribute = true` (nil-safe no-op if no focused window)

## Architecture: Pure Logic vs. I/O Boundary

To enable unit testing without a live user session, the codebase is split into two layers:

**Pure layer** (no `NSEvent`, `AXUIElement`, `NSWorkspace`, no global state) — fully unit-testable:
- `CoordinateConverter` — NSEvent bottom-left ↔ AX top-left, accepts an injected array of screen frames
- `DockGeometry` — holds a `CGRect` frame, exposes `contains(point:)`; frame supplied by an injected `DockFrameProvider` protocol
- `ClickDebouncer` — per-item timestamp map, accepts an injected clock (`() -> Date`) for deterministic testing. Keyed by **bundle URL string** (not PID) so app relaunches don't bypass debounce. Debounce window is a named constant (`debounceInterval = 0.3` — rapid trackpad double-taps can fire ~200ms apart, so 300ms is the conservative floor; revisit to 250ms if deliberate minimize-then-restore feels sluggish). Implemented as a `final class` (not a `mutating struct`) since the coordinator holds a single shared instance and mutates it from the click closure — reference semantics make the single-owner invariant explicit.
  - **Known sharp edge**: two distinct copies of the same app (e.g., `/Applications/Safari.app` and `~/Downloads/Safari.app`) share a debounce key only if their normalized URLs collide — in practice they don't. Same-URL app running twice (rare) would share a key; acceptable since the user-perceived "app" is singular.
- `BundleURLMatcher` — normalizes and compares two `URL?` values. Calls `standardizedFileURL.resolvingSymlinksInPath()`, handles trailing slash and `file://` form, handles nil. Does **not** case-fold (case-sensitive volumes must compare exactly).

**I/O layer** (thin adapters; integration-tested manually):
- `AXDockFrameProvider` — queries live Dock AX bounds; conforms to `DockFrameProvider`
- `GlobalClickMonitor` — wraps `CGEventTap` at `.cgSessionEventTap` (listen-only, `.leftMouseDown`)
- `AXHitTester` — wraps `AXUIElementCopyElementAtPosition` and attribute reads
- `DockPIDCache` — caches `com.apple.dock`'s PID; refreshes on Dock launch notification
- `WindowMinimizer` — wraps `kAXFocusedWindowAttribute` read + `kAXMinimizedAttribute` set; applies `AXUIElementSetMessagingTimeout(app, 0.25)` to the per-app element
- `FrontmostAppProvider` — wraps `NSWorkspace.shared.frontmostApplication`

`DockWatcher` becomes a coordinator: it wires pure components to I/O adapters and contains no branching logic itself beyond the dispatch pipeline. This keeps it small and keeps the interesting logic testable.

## File Structure

```
click-to-min/
├── Package.swift
├── Sources/
│   └── ClickToMin/
│       ├── AppDelegate.swift           // @main entry point
│       ├── DockWatcher.swift           // coordinator (I/O)
│       ├── IO/
│       │   ├── GlobalClickMonitor.swift
│       │   ├── AXDockFrameProvider.swift
│       │   ├── AXHitTester.swift
│       │   ├── DockPIDCache.swift
│       │   ├── WindowMinimizer.swift
│       │   └── FrontmostAppProvider.swift
│       └── Core/
│           ├── CoordinateConverter.swift
│           ├── DockGeometry.swift
│           ├── ClickDebouncer.swift
│           └── BundleURLMatcher.swift
├── Tests/
│   └── ClickToMinTests/
│       ├── CoordinateConversionTests.swift
│       ├── DockGeometryTests.swift
│       ├── DebounceTests.swift
│       ├── BundleURLEqualityTests.swift
│       └── DockWatcherPipelineTests.swift   // coordinator wiring, using in-memory fakes
├── Resources/
│   └── Info.plist
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── PERF.md
└── build.sh
```

Note: `PERF.md` is committed up front with its **full table schema** (steady-state metrics, short-circuit effectiveness, OS-specific observations, release history), pre-populated with `TBD` values. Committing the schema — not just a placeholder sentence — gives the regression-guard checklist a concrete target shape and prevents "what columns did we agree on?" drift at the first release cut.

## Implementation Steps

### 1. `Package.swift`

- Targets macOS 13+
- Executable target `ClickToMin` at `Sources/ClickToMin`
- **Library target `ClickToMinCore`** containing only `Sources/ClickToMin/Core/*` — no AppKit/AX imports
- Test target `ClickToMinTests` depending on `ClickToMinCore`
- Executable target depends on both `ClickToMinCore` and the I/O sources

This separation enforces the boundary at the compiler level: core can't accidentally import AppKit.

### 2. `Sources/ClickToMin/AppDelegate.swift`

- `@main` attribute — no separate `main.swift` needed
- `NSApp.setActivationPolicy(.accessory)` — no Dock icon. (Redundant with `LSUIElement=YES` in Info.plist; `LSUIElement` is authoritative for `.app` launches, the activation-policy call covers `swift run` / unbundled launches. Comment this in the source so the next reader doesn't "clean up" one or the other.)
- Creates `NSStatusItem` (system icon + "Quit")
- On launch: `AXIsProcessTrusted()` check
- If missing: opens **System Settings → Privacy & Security → Accessibility** and shows an alert
- **Permission re-check strategy**: lightweight 2s `Timer` polls `AXIsProcessTrusted()` while untrusted; stops once trusted. Also re-checks on `NSWorkspace.didWakeNotification`. Relying on wake alone would miss same-session grants.
- Instantiates `DockWatcher` once permission confirmed. `DockWatcher` installs the `GlobalClickMonitor` only at that point (monitor yields no events pre-permission).
- If permission is revoked at runtime, `DockWatcher` tears down the monitor and the poll resumes.

### 3. Core (pure, testable)

**`Core/CoordinateConverter.swift`**
- `struct CoordinateConverter { let screenFrames: [CGRect] }`
- `func toAX(_ nsEventPoint: CGPoint) -> CGPoint`
- No AppKit dependency; takes screen frames as plain `CGRect` values

**`Core/DockGeometry.swift`**
- `protocol DockFrameProvider { var frame: CGRect? { get } }`
- `struct DockGeometry { let provider: DockFrameProvider }`
- `func contains(_ point: CGPoint) -> Bool`

**`Core/ClickDebouncer.swift`**
- `final class ClickDebouncer { let window: TimeInterval; let now: () -> Date }` — reference type so the coordinator's single instance is mutated in place from the click closure
- `static let debounceInterval: TimeInterval = 0.3` — named constant, documented rationale (300ms floor above typical trackpad double-tap interval; tune to 250ms if deliberate minimize-then-restore feels sluggish)
- `func shouldAllow(itemID: String) -> Bool`
- Clock injected for deterministic tests
- `itemID` is the **bundle URL string** (not PID); app relaunches preserve the debounce key

**`Core/BundleURLMatcher.swift`**
- `enum BundleURLMatcher { static func matches(_ a: URL?, _ b: URL?) -> Bool }`
- Normalization: `standardizedFileURL.resolvingSymlinksInPath()`, strips trailing slash, handles `file://` form, handles nil
- Does **not** case-fold — case-sensitive volumes must compare exactly

### 4. I/O Adapters

**`IO/AXDockFrameProvider.swift`**
- Conforms to `DockFrameProvider`
- Queries live Dock AX bounds
- Refreshes on:
  - `NSApplication.didChangeScreenParametersNotification` (resolution/arrangement)
  - Dock relaunch (`NSWorkspace.didLaunchApplicationNotification` filtered to `com.apple.dock`)
  - Dock preference changes — `DistributedNotificationCenter` observing `com.apple.dock.prefchanged` (user resizes Dock, moves it, toggles auto-hide)
- **Fallback**: if a click falls just outside the cached rect, re-query the frame once and re-test before bailing. Cheap, catches cases where the observer missed an update.
- **Auto-hide handling**: if the Dock is auto-hidden (readable via `CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString)`), widen the cached rect to a **5pt screen-edge strip** (macOS's reveal hot-zone width) along the Dock's configured edge so the short-circuit still triggers while the Dock is revealed. Fallback chain if 5pt proves too narrow in testing: escalate to 10pt, then to a full-edge strip (entire screen edge along the Dock's configured side). Full-edge strip widens the false-positive region slightly — acceptable since all it costs is one extra AX hit-test per edge click while the Dock is hidden.

**`IO/GlobalClickMonitor.swift`**
- Wraps a session-level `CGEventTap` (`.cgSessionEventTap`, `.listenOnly`, mask = `1 << CGEventType.leftMouseDown.rawValue`)
- Emits `CGPoint` click locations (in top-left origin) via a closure
- **Install lifecycle**: must be installed only after `AXIsProcessTrusted()` returns true; `CGEvent.tapCreate` returns nil without it. Exposes `start()` / `stop()` so `AppDelegate` can re-install on re-grant.
- **Self-healing**: if the system disables the tap (slow callback), re-enable it inline on the next event via `CGEvent.tapEnable`.
- **History**: originally `NSEvent.addGlobalMonitorForEvents`; that monitor silently drops clicks on the Dock process on recent macOS, so we moved to CGEventTap (PR #4).

**`IO/DockPIDCache.swift`**
- Caches `NSRunningApplication` instances matching `bundleIdentifier == "com.apple.dock"` → `pid_t`
- Populates on init; refreshes on `NSWorkspace.didLaunchApplicationNotification` filtered to Dock
- Exposes `var pid: pid_t?` for O(1) click-time comparison
- Avoids a per-click `runningApplications` scan
- **Multi-match tie-break**: during Dock relaunch, `runningApplications` can transiently return both the old and new Dock processes. Pick the one with the latest `launchDate` (newest); if `launchDate` is nil for one, prefer the non-nil. Never cache a `terminated == true` instance. A brief window where the cache points at the old (dying) PID is acceptable — the PID check simply fails for one click.

**`IO/AXHitTester.swift`**
- Holds a reused `AXUIElementCreateSystemWide()` reference
- Calls `AXUIElementSetMessagingTimeout(element, 0.25)` on init to bound any single AX call
- `func hitTest(at axPoint: CGPoint) -> AXUIElement?`
- `func dockItemURL(_ element: AXUIElement) -> URL?` — walks to `AXDockItem`, reads `kAXURLAttribute`, nil-guards Finder/Trash/stacks/separators
- `func pid(_ element: AXUIElement) -> pid_t?`

**`IO/WindowMinimizer.swift`**
- `func minimizeFocusedWindow(ofPid pid: pid_t, bundleURL: URL?)` — creates `AXUIElementCreateApplication(pid)`, applies `AXUIElementSetMessagingTimeout(appElement, 0.25)`, reads `kAXFocusedWindowAttribute`, no-ops if nil.
- **Already-minimized short-circuit**: reads `kAXMinimizedAttribute` on the focused window; if already true, treats the click as a restore and bails. Prevents the "minimize immediately unminimizes" race where the user clicks the Dock icon to restore.
- **Deferred dispatch**: the actual `kAXMinimizedAttribute = true` set is scheduled via `DispatchQueue.main.asyncAfter(deadline: .now() + postClickDelay)` with `postClickDelay: TimeInterval = 0.18`. Without the delay the Dock's own click handler runs *after* our set and re-activates the window, visually un-minimizing it. 180ms is the empirically-shortest interval that reliably outruns the Dock's handler on Sonoma/Sequoia; shorter values sporadically race.
- Note: `kAXMinimizedAttribute` set is asynchronous — the call returns before the window animates. Do not assert visual state from this call.

**`IO/FrontmostAppProvider.swift`**
- `protocol FrontmostAppProviding { var frontmost: NSRunningApplication? { get } }` — protocol pair so `DockWatcherPipelineTests` can substitute an in-memory fake (including the "frontmost flips between calls" scenario documented in §Coordinator).
- `struct FrontmostAppProvider: FrontmostAppProviding { var frontmost: NSRunningApplication? { NSWorkspace.shared.frontmostApplication } }`
- Trivial wrapper, but keeps `DockWatcher` free of direct `NSWorkspace` calls **and** keeps the pipeline fully mockable without needing to subclass `NSWorkspace`.

### 5. `Sources/ClickToMin/DockWatcher.swift` (coordinator)

No branching logic of its own. Wires components and dispatches on each click:

```
GlobalClickMonitor → CoordinateConverter → DockGeometry.contains?
  → AXHitTester.hitTest → validate PID matches DockPIDCache.pid → AXHitTester.dockItemURL
  → BundleURLMatcher.matches(itemURL, frontmost.bundleURL)?
  → ClickDebouncer.shouldAllow?
  → WindowMinimizer.minimizeFocusedWindow
```

Each arrow is a single method call to a component. The pipeline itself is the only thing in `DockWatcher`, making it trivially reviewable.

**Frontmost-read timing**: `FrontmostAppProvider.frontmost` is read *at click-dispatch time*, not cached. Between the `NSEvent` firing and the read, a fast app switch could change `frontmostApplication` — that's acceptable (user-perceived truth at the moment of the click) and matches macOS's own model. Pipeline test fakes include a "frontmost changed between calls" scenario to lock this behavior in.

### 6. `Resources/Info.plist`

- `LSUIElement = YES`
- `LSMinimumSystemVersion = 13.0` (matches `Package.swift` target)
- `NSAccessibilityUsageDescription`
- `CFBundleIdentifier = com.click-to-min`
- `CFBundleName = ClickToMin`

Note: `LSUIElement` only takes effect when launched from the `.app` bundle.

### 7. `build.sh`

1. `swift build -c release`
2. `mkdir -p ClickToMin.app/Contents/{MacOS,Resources}`
3. Copy binary → `Contents/MacOS/ClickToMin`
4. Copy `Info.plist` → `Contents/`
5. **Ad-hoc codesign**: `codesign --sign - --force --timestamp=none ClickToMin.app` — single-binary bundle, no nested frameworks, so `--deep` (deprecated on macOS 14+) is unnecessary. Sign the inner binary first if a warning appears: `codesign --sign - --force ClickToMin.app/Contents/MacOS/ClickToMin && codesign --sign - --force ClickToMin.app`

### 8. CI/CD (GitHub Actions + Branch Protection)

**Goal**: every change to `main` goes through a PR with green checks. No direct pushes, no force-pushes, no merging a red build.

#### `.github/workflows/ci.yml` — runs on every PR and push to `main`

- **Trigger**: `pull_request` (any branch → `main`) and `push` to `main` (covers the post-merge commit)
- **Runner**: `macos-14` (Sonoma, arm64). Pin to a specific minor image tag (not `macos-latest`) so toolchain drift doesn't silently fail builds. Re-pin deliberately when upgrading.
- **Xcode pin hygiene**: the `sudo xcode-select -s /Applications/Xcode_XX.Y.app` path is tied to whatever Xcode versions GitHub ships on the pinned runner image. Every time the `macos-XX` image is updated, the available Xcode versions shift — the old path can silently disappear. Treat the Xcode selection line as **paired with the runner pin**: when bumping one, audit the other. Include a dated `# pinned <YYYY-MM-DD>, Xcode versions on this runner: <list>` comment immediately above the `xcode-select` step in `ci.yml` so the next maintainer (or Dependabot alert) can spot staleness at a glance. GitHub's runner-image release notes (https://github.com/actions/runner-images) list available Xcode versions per image tag.
- **Jobs**:
  1. **`build-test`**
     - `actions/checkout@v4`
     - Select Xcode: `sudo xcode-select -s /Applications/Xcode_15.4.app` (match the pinned runner's available versions)
     - `swift build -c debug` — compiles both `ClickToMinCore` and executable; fails on any AppKit import leaking into `Core/`
     - `swift test --parallel` — runs the full `ClickToMinTests` target (pure-logic tests, no AX/Dock dependency; fully CI-safe)
     - Upload test results as artifact on failure for post-mortem
  2. **`bundle-check`** (depends on `build-test`)
     - `swift build -c release`
     - Run `build.sh` to assemble `.app`
     - `codesign --verify --verbose ClickToMin.app` — confirms ad-hoc signature is intact
     - `plutil -lint Resources/Info.plist` — catches plist typos before they ship
     - Upload the `.app` as a workflow artifact (7-day retention) so reviewers can grab the exact build for manual Layer 2 testing
  3. **`lint`** (parallel to `build-test`)
     - `swiftformat --lint Sources Tests` — fail on formatting drift (config committed as `.swiftformat`)
     - Optional: `swiftlint` if we add it later; not required for v1

- **Concurrency**: group by PR ref, cancel-in-progress, so force-pushing a new commit to a PR cancels the stale run
- **Cache**: `actions/cache` on `.build/` keyed by `Package.resolved` hash — shaves ~30s off repeat runs
- **Runtime budget**: target <5min end-to-end on a cold cache; flag regressions

#### `.github/workflows/release.yml` — runs on tag push (`v*`)

- **Trigger**: `push` with tag pattern `v*.*.*`
- Builds release `.app`, zips, creates GitHub Release with the artifact attached
- Ad-hoc signed only — no Developer ID / notarization in v1 (user is trusted-local; document Gatekeeper right-click-open workaround in README when it exists). Add notarization later if distributing beyond personal use.

#### Branch Protection on `main` (configured in repo Settings → Branches)

Required settings:
- **Require a pull request before merging**: ON
  - **Require approvals**: 1 (self-review allowed for a solo project — set to 0 if solo; bump to 1+ when collaborators join)
  - **Dismiss stale approvals when new commits are pushed**: ON
  - **Require review from Code Owners**: OFF for v1 (no CODEOWNERS file yet)
- **Require status checks to pass before merging**: ON
  - Required checks: `build-test`, `bundle-check`, `lint`
  - **Require branches to be up to date before merging**: ON (forces rebase/merge of latest `main` before merge, catches semantic conflicts)
- **Require conversation resolution before merging**: ON
- **Require linear history**: ON (forbids merge commits; enforces squash-or-rebase merge strategy)
- **Do not allow bypassing the above settings**: ON (applies to admins too — including the repo owner)
- **Restrict who can push to matching branches**: empty list (nobody pushes directly)
- **Allow force pushes**: OFF
- **Allow deletions**: OFF

#### Merge strategy

- Repo setting: **Allow squash merging** only (disable merge commits and rebase merging at the repo level for consistency)
- Default commit message: **Pull request title and description**
- Keeps `main` history linear and each commit = one reviewed PR

#### PR hygiene (committed templates)

- `.github/pull_request_template.md` — checklist: tests added/updated, Layer 2 manual items relevant to this change are listed, `PERF.md` touched if hot path changed, `log stream` spot-check run
- `.github/CODEOWNERS` — omit for v1 (single maintainer); add when collaborators exist

#### Solo-maintainer nuance

Since this starts as a one-person project, set **required approvals = 0** but keep **required status checks**, **linear history**, and **no direct pushes to main**. This preserves the CI gate (you can't merge a red build even as admin, because `Do not allow bypassing` is on) without blocking on a second reviewer that doesn't exist yet. Bump approvals to 1 the moment a second committer lands.

## Performance & Memory Notes

- **Global monitor is passive** — no event consumption, minimal overhead
- **Dock-frame short-circuit** eliminates AX IPC on ~99% of clicks
- **Lightweight permission poll** (2s timer, only while untrusted) — stops once Accessibility is granted; zero ongoing cost in steady state
- **Reused system-wide AX element** with a 250ms messaging timeout — no per-click allocations, bounded worst-case latency
- **Expected resident memory: <10 MB idle**
- **Layer split has zero runtime cost** — all component calls are direct; no dynamic dispatch on the hot path (structs, not classes, where possible)

## Diagnostics / Logging

Minimal `os_log` instrumentation for post-hoc support (user reports "it stopped working" with no reproducer). Subsystem: `com.click-to-min`. Categories: `lifecycle`, `pipeline`.

Signposts (all `.info` or lower, no PII):
- `lifecycle`: permission granted, permission revoked, monitor installed, monitor torn down, Dock PID refreshed
- `pipeline`: click short-circuited (outside Dock rect), click ignored (PID mismatch / URL mismatch / debounced), minimize dispatched (bundle ID only, not path)

All disabled by default in release via `os_log`'s private/public annotations — user runs `log stream --predicate 'subsystem == "com.click-to-min"'` to surface them when troubleshooting. Near-zero steady-state cost, no configuration surface (set-and-forget).

## Edge Cases Handled

| Case | Handling |
|------|----------|
| Finder / Trash / stacks / Show Desktop | Nil-guard on `kAXURLAttribute`, bail |
| Full-screen / Stage Manager windows | `kAXMinimizedAttribute` set may silently fail; 250ms AX messaging timeout bounds worst case |
| Multiple displays / Dock on secondary | Coordinate conversion tested against `NSScreen.screens[0]` |
| Accessibility revoked at runtime | `DockWatcher` tears down monitor; 2s poll resumes until re-granted |
| Accessibility granted mid-session (no sleep/wake) | 2s poll detects grant and installs monitor |
| Rapid double-clicks | 300ms same-item debounce, keyed by bundle URL string (survives relaunch) |
| App frontmost, no focused window (all minimized) | `kAXFocusedWindowAttribute` nil → no-op, macOS default restore runs |
| Restore-click race (app frontmost, click Dock to restore a minimized window) | `WindowMinimizer` reads `kAXMinimizedAttribute`; already-true → no-op so macOS default restore runs cleanly |
| Minimize immediately un-minimizing | 180ms `postClickDelay` deferred dispatch lets the Dock's own click handler run first, so our `kAXMinimizedAttribute = true` wins |
| Dock process restart | `DockGeometry` refreshes on Dock relaunch notification |
| Screen resolution / arrangement changes | `DockGeometry` refreshes on `didChangeScreenParametersNotification` |
| Dock resized / moved / auto-hide toggled | `DockGeometry` refreshes on `com.apple.dock.prefchanged` distributed notification |
| Auto-hidden Dock | Cached rect widened to full screen-edge strip so short-circuit still fires while Dock is revealed |
| Missed Dock-frame refresh | Fallback: re-query frame once on a near-miss click before bailing |
| Case-sensitive volume with Safari.app at non-canonical case | Bundle URL matcher does not case-fold; exact compare after symlink resolution |
| TCC permission loss on rebuild | Ad-hoc codesign in `build.sh` stabilizes TCC identity |

## Critical Files

| File | Role |
|------|------|
| `Sources/ClickToMin/DockWatcher.swift` | Coordinator: wires Core + I/O into the click pipeline |
| `Sources/ClickToMin/Core/DockGeometry.swift` | Cached Dock frame for fast-path short-circuit |
| `Sources/ClickToMin/IO/AXDockFrameProvider.swift` | Live Dock frame queries + refresh observers |
| `Sources/ClickToMin/IO/DockPIDCache.swift` | Cached Dock PID for O(1) per-click identity check |
| `Sources/ClickToMin/AppDelegate.swift` | Lifecycle, menu bar, accessibility permission check/re-check/poll |
| `Resources/Info.plist` | `LSUIElement`, `LSMinimumSystemVersion`, `NSAccessibilityUsageDescription`, bundle ID |
| `build.sh` | Assembles `.app` bundle + ad-hoc codesign |
| `Package.swift` | Build target definition |

## Testing Plan

### Scope Reality

Global mouse events, Dock AX queries, and TCC permission grants require a live user session with Accessibility approved — **not reproducible in CI**. Testing splits into three layers: automated unit tests for pure logic, a structured manual checklist for AX/Dock integration, and a perf pass to validate the short-circuit claim.

### Layer 1 — Unit Tests (SwiftPM `Tests/ClickToMinTests/`)

Add a test target in `Package.swift`. Factor pure logic out of `DockWatcher` into testable helpers.

**`CoordinateConversionTests.swift`**
- NSEvent bottom-left → AX top-left on single primary screen
- Multi-screen: Dock on secondary display (left of / right of / above / below primary)
- Retina scaling sanity (points, not pixels)
- Negative-origin screens (secondary display left of primary)

**`DockGeometryTests.swift`**
- `contains(point:)` inside / on edge / outside Dock rect
- Dock at bottom / left / right of screen
- Refresh behavior when injected frame changes (use a protocol-based frame provider for testability)

**`DebounceTests.swift`**
- Same item within 300ms → suppressed
- Same item after 300ms → allowed
- Different item within 300ms → allowed (per-item, not global)

**`BundleURLEqualityTests.swift`**
- Trailing slash vs. no trailing slash
- `/Applications/Safari.app` vs. symlinked path
- `file://` URL normalization
- Nil handling (Finder/Trash/stack items)
- Case-sensitive compare: `/Applications/safari.app` ≠ `/Applications/Safari.app` (no case folding)
- System-volume path: apparent `/Applications/<SystemApp>.app` vs. real path under `/System/Volumes/...` — document expected behavior and lock it in

**`DockWatcherPipelineTests.swift`**
- Coordinator wiring with in-memory fakes for every I/O protocol (`DockFrameProvider`, `FrontmostAppProvider`, hit tester, minimizer, Dock PID cache)
- Click outside Dock rect → pipeline stops at `DockGeometry.contains`; hit tester never called
- Click inside Dock rect, hit element PID ≠ cached Dock PID → stops at PID check; `dockItemURL` and minimizer never called
- Click inside Dock rect, cached Dock PID is nil (Dock mid-relaunch) → pipeline aborts safely; minimizer never called
- Click inside Dock, item bundle URL ≠ frontmost → stops at `BundleURLMatcher`; minimizer never called
- Click inside Dock, bundle URL matches, but debouncer suppresses → minimizer never called
- Happy path → minimizer called exactly once with the frontmost app
- Frontmost app changes between hit-test and minimize-dispatch → matcher compares URL from the click moment only; test fake flips `frontmost` between calls and asserts the decision is consistent with the read point documented in `DockWatcher`
- **Call-order assertion**: every I/O fake records its invocation into a shared ordered log. Happy-path test asserts the exact sequence (e.g., `dockFrame → hitTest → pid → dockItemURL → frontmost → debounce → minimize`). Catches reorders that happen to produce the right outcome in a single test but break the contract.
- Guards against future regressions where someone accidentally inverts a branch or reorders the pipeline

### Layer 2 — Manual Test Checklist

Run before every release. Organized by category.

**Smoke**
- [ ] `swift build` compiles cleanly
- [ ] `./build.sh` produces signed `ClickToMin.app`
- [ ] Launch `.app` → menu bar icon appears, Accessibility prompt fires
- [ ] Grant Accessibility in System Settings → Privacy & Security → Accessibility
- [ ] Quit via menu bar item exits cleanly, no lingering process
- [ ] Re-measured memory & idle CPU, updated `PERF.md`, flagged any >20% regression (skip allowed with documented reason)
- [ ] `log stream --predicate 'subsystem == "com.click-to-min"'` shows expected lifecycle signposts on launch

**Core Behavior**
- [ ] Safari active, click Dock icon → key window minimizes
- [ ] Click Dock icon again → window restores (macOS default)
- [ ] Background app Dock click → comes to front normally, no minimize
- [ ] 3-click cycle works: background → foreground → minimize → restore

**Multi-Window**
- [ ] Two TextEdit docs open, one focused, click Dock → only focused minimizes, other stays
- [ ] Focus second doc, click Dock → second minimizes
- [ ] All minimized, click Dock → macOS restores one (no interference)

**Edge Cases**
- [ ] Click Finder Dock icon (active) → no crash, no unintended minimize
- [ ] Click Trash → no crash
- [ ] Click Downloads stack → no crash
- [ ] Click Show Desktop / separator → no crash
- [ ] Full-screen Safari, click Dock → no crash (may no-op; acceptable)
- [ ] Stage Manager enabled → no crash
- [ ] **Frozen app timeout**: `kill -STOP <pid>` a frontmost app, click its Dock icon, confirm pipeline returns within ~300ms (not stalled). `kill -CONT <pid>` to restore. Validates AX messaging timeout. If stall observed, the system-wide timeout is a no-op on this OS — document and rely on per-app timeout alone.
- [ ] **Right-click** Dock icon of frontmost app → context menu opens, no minimize (confirms `.leftMouseDown` scope)
- [ ] **Ctrl-click** Dock icon of frontmost app → context menu opens, no minimize
- [ ] **Long-press** Dock icon to show window previews, then click a preview → no crash, no stray minimize (confirms preview-element parent-walk bails cleanly)
- [ ] "Recent Applications" Dock section enabled, click a Recent app when frontmost → either minimizes via title-fallback identifier, or cleanly no-ops; document observed behavior

**Multi-Display**
- [ ] Dock on primary display → works
- [ ] Dock on secondary display (right of primary) → works
- [ ] Dock on secondary display (left of primary, negative origin) → works
- [ ] Hot-plug: disconnect external display while app is running → no crash, `DockGeometry` refreshes

**Permission Lifecycle**
- [ ] Revoke Accessibility while app is running → subsequent clicks no-op (no crash); monitor torn down
- [ ] Re-grant Accessibility without sleeping → 2s poll detects grant, monitor reinstalls, behavior resumes
- [ ] Sleep/wake cycle → permission re-check fires, still works
- [ ] Fresh install: launch app before granting permission, then grant → monitor starts producing events (validates post-grant install)
- [ ] Rebuild with `./build.sh` → Accessibility permission persists (codesign identity stable)
- [ ] `tccutil reset Accessibility com.click-to-min` → next launch re-prompts cleanly (recovery path documented for users hitting stuck permission state)

**Dock Configuration**
- [ ] Resize Dock via System Settings → short-circuit still works (frame refresh on `com.apple.dock.prefchanged`)
- [ ] Move Dock left/right/bottom → short-circuit still works
- [ ] Enable Dock auto-hide → reveal Dock → click icon → still minimizes
- [ ] Disable Dock auto-hide → frame snaps back to visible rect

**Race Conditions**
- [ ] Rapid double-click Dock icon → exactly one minimize, no oscillation
- [ ] Click Dock icon during app launch animation → no crash

### Layer 3 — Performance Validation

Goal: prove the short-circuit and low-memory claims.

**CPU / short-circuit effectiveness**
- Attach Instruments **Time Profiler** to running ClickToMin
- Script 1000 rapid clicks **outside** the Dock region (e.g., `cliclick` loop, or manual)
- Expected: negligible CPU; `AXUIElementCopyElementAtPosition` should **not** appear in hot path (short-circuit working)
- Repeat with clicks **inside** Dock region → AX call appears, but bounded to Dock-region clicks only

**Memory baseline**
- Instruments **Allocations**: launch app, idle for 5 minutes, confirm resident memory <10 MB
- Click 500 Dock icons, verify no growth (no per-click allocation leak — validates reused system-wide AX element)

**Event latency**
- Manual perceptual test: click-to-minimize should feel instant (<50ms). If sluggish, AX IPC may be the bottleneck; consider caching Dock PID.

**Regression guard**
- Record baseline memory + idle CPU numbers in `PERF.md` after first shipping build
- **Owner**: maintainer runs this manually as part of the Layer 2 pre-release checklist. Not automated (requires live user session). Add a checkbox to the Smoke section: "[ ] Re-measured memory & idle CPU, updated `PERF.md`, flagged any >20% regression." If skipped for a release, note the reason in `PERF.md`.
