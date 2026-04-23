# Phase 1 — Core (Pure Logic)

**Goal**: Ship all pure, unit-testable logic with zero AppKit / AX / NSWorkspace dependencies.

**Parallelism**: All implementation tasks (T-1.2 – T-1.5) are parallel **after** T-1.1 (protocols) lands. Fully parallel with Phase 2 and Phase 5.

**Critical early subtask**: T-1.1 commits the `DockFrameProvider` protocol first so Phase 2's `AXDockFrameProvider` can start in parallel.

**Exit criteria**: `swift test` runs the `ClickToMinTests` target with ≥ the test count listed per task below, all green.

---

### T-1.1 — Commit Core protocols (unblocks Phase 2) ✅
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-1.3 (needs protocol), T-2.1 (AXDockFrameProvider conforms)
- **Files**: `Sources/ClickToMin/Core/DockGeometry.swift` (protocol only)
- **Description**: Define `protocol DockFrameProvider { var frame: CGRect? { get } }` in the Core target so Phase 2 can start. Leave the `DockGeometry` struct as a stub for T-1.3.
- **Acceptance criteria**:
  - [x] Protocol compiles inside `ClickToMinCore`
  - [x] No AppKit/AX imports
  - [x] Symbol visible to Phase 2 I/O target (confirm via a throwaway conformance in I/O)
- **Verification step**:
  - In a scratch branch, add `extension AXDockFrameProvider: DockFrameProvider {}` and confirm it compiles. Revert.
- **Notes**: This is the single sequencing point that lets Track A/B work in parallel.

### T-1.2 — `CoordinateConverter` ✅
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1 (coordinator uses it)
- **Files**: `Sources/ClickToMin/Core/CoordinateConverter.swift`, `Tests/ClickToMinTests/CoordinateConversionTests.swift`
- **Description**: `struct CoordinateConverter { let screenFrames: [CGRect]; func toAX(_ p: CGPoint) -> CGPoint }`. Converts NSEvent bottom-left coords to AX top-left. No AppKit.
- **Acceptance criteria**:
  - [x] Accepts injected `[CGRect]` — no `NSScreen.screens` read in Core
  - [x] Handles single screen (bottom-left → top-left)
  - [x] Handles multi-screen (Dock on secondary left/right/above/below primary)
  - [x] Handles negative-origin screens (PLAN.md §Testing Layer 1)
  - [x] Retina: returns points, not pixels
- **Verification step**:
  - `swift test --filter CoordinateConversionTests` — all 4 documented scenarios pass. Add an edge test: point on exact screen seam → deterministic (document which screen wins).
- **Notes**: PLAN.md §Core, §Testing Layer 1.

### T-1.3 — `DockGeometry` ✅
- **Owner**: unassigned
- **Depends on**: T-1.1
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/Core/DockGeometry.swift` (struct + tests), `Tests/ClickToMinTests/DockGeometryTests.swift`
- **Description**: `struct DockGeometry { let provider: DockFrameProvider }`; exposes `contains(_: CGPoint) -> Bool`. Nil frame → returns false (click falls through to AX, which will bail).
- **Acceptance criteria**:
  - [x] `contains` returns true strictly inside, true on edge, false outside
  - [x] Nil frame from provider → returns false
  - [x] Test covers Dock at bottom / left / right
  - [x] Test covers frame change between two calls (injected provider mutates)
- **Verification step**:
  - `swift test --filter DockGeometryTests`. Include an explicit off-by-one boundary test (`frame.maxX` vs `frame.maxX - 1`).
- **Notes**: PLAN.md §Core, §Testing.

### T-1.4 — `ClickDebouncer` ✅
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/Core/ClickDebouncer.swift`, `Tests/ClickToMinTests/DebounceTests.swift`
- **Description**: `final class ClickDebouncer { let window: TimeInterval; let now: () -> Date; func shouldAllow(itemID: String) -> Bool }`. Reference type (single-owner invariant). Clock injected. `itemID` is the **bundle URL string** so relaunches keep the key.
- **Acceptance criteria**:
  - [x] `static let debounceInterval: TimeInterval = 0.3` exists
  - [x] Same item within 300ms → suppressed
  - [x] Same item after 300ms → allowed
  - [x] Different item within 300ms → allowed
  - [x] Injected clock used (no `Date()` in impl)
  - [x] Key is the bundle URL string (test renames/relaunches reuse key)
- **Verification step**:
  - `swift test --filter DebounceTests`. Add a boundary test at exactly 300ms — document and lock behavior (suppress or allow; must be deterministic).
- **Notes**: PLAN.md §Core, §Edge Cases. Class not struct — rationale documented in source per PLAN.

### T-1.5 — `BundleURLMatcher` ✅
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-3.1
- **Files**: `Sources/ClickToMin/Core/BundleURLMatcher.swift`, `Tests/ClickToMinTests/BundleURLEqualityTests.swift`
- **Description**: `enum BundleURLMatcher { static func matches(_ a: URL?, _ b: URL?) -> Bool }`. Normalizes via `standardizedFileURL.resolvingSymlinksInPath()`, handles trailing slash, `file://`, nil. **Does not** case-fold.
- **Acceptance criteria**:
  - [x] Trailing slash normalization: `/A/Safari.app/` == `/A/Safari.app`
  - [x] Symlink resolution: symlinked path == real path
  - [x] `file://` form normalized
  - [x] Nil on either side → false (never crash)
  - [x] Case-sensitive: `/A/safari.app` != `/A/Safari.app`
  - [x] System-volume path behavior locked with an explicit test + comment
- **Verification step**:
  - `swift test --filter BundleURLEqualityTests`. Add a property test: `matches(x, x)` true for any non-nil `x`; `matches(nil, x)` false for any `x`.
- **Notes**: PLAN.md §Core, §Edge Cases, §Testing Layer 1. Case-sensitive volumes require exact compare — covered by tests.

---

## Common Failure Patterns (pre-merge check)

- [x] Any Core file imports AppKit, AX, or Foundation/NSWorkspace — compile-time forbidden by target split, but verify visually
- [x] `Date()` or `CFAbsoluteTime` used directly in debouncer — must use injected clock
- [x] `NSScreen.main` read inside `CoordinateConverter` — must be injected
- [x] Test uses real wall-clock `Thread.sleep` for debounce timing — must use the injected clock closure
- [x] Case-folding snuck into URL matcher (`lowercased()` anywhere) — explicit anti-goal

## Completed

<!-- Move finished tasks here -->
