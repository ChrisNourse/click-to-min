# CLAUDE.md — click-to-min

## Behaviour

No preamble. No "Great question!" Fix thing. Do it. Open PR.

CI fail → read logs, find root cause, fix. Don't summarise failure back — user see it.

---

## CI

CI runs build, test, lint, bundle-check. Read logs. Fix errors. Push. Don't re-run locally.

Runner pin `macos-14` (arm64). Intentional. Don't change to `macos-latest`.

---

## Architecture

```
Sources/ClickToMin/Core/   — pure logic. No AppKit, no ApplicationServices, no I/O.
Sources/ClickToMin/IO/     — AX/NSWorkspace/CGEventTap adapters. Conform to Core protocols.
Sources/ClickToMin/        — AppDelegate + DockWatcher coordinator. Wires IO into Core.
Tests/ClickToMinTests/     — XCTest. Tests Core; fakes for IO.
```

Branching logic only in `Core/ClickPipeline.swift`. IO adapters = dumb wiring. `if` in adapter → belongs in pipeline instead.

Protocols in `Core/PipelineProtocols.swift`. IO types in `Core/` = build error. `ClickToMinCore` target excludes `AppKit`/`ApplicationServices` at compiler level.

---

## Conventions

### Notification observer tokens
```swift
if let observer = wakeObserver {
    NSWorkspace.shared.notificationCenter.removeObserver(observer)
}
```
Always `observer`. Not `t`, not `obs`.

### Identifier names
No single-char vars. `lhs`/`rhs` for comparator closures. `observer` for notification tokens. `elem` for loop elements.

### AX/CF force casts
`as!` intentional in IO adapters. `AXUIElement`, `AXValue`, `CFBoolean`, `CFURL` = CF types, no conditional Swift cast possible. Safe by API contract. `force_cast` disabled in `.swiftlint.yml`. Don't re-enable. Don't add per-line suppressions.

### Brace placement
SwiftFormat owns. Allman style on multi-line conditions. `opening_brace` disabled in `.swiftlint.yml`. Don't fight it.

### Logging
`os_log` with categories from `IO/Log.swift` (`Log.lifecycle`, `Log.pipeline`). No `print()`.

### Timing constants
Named constants only. `WindowMinimizer.postClickDelay`, `ClickDebouncer.debounceInterval`. No bare `0.18` or `0.3`.

---

## PR workflow

Branch: `fix/`, `feat/`, `chore/`, `ci/`, `docs/` prefix.

Commit: `type: short summary`. Body optional.

Green before merge: `build-test`, `lint`, `bundle-check`. CodeQL pending = ok.

Squash-merge.
