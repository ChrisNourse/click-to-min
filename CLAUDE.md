# CLAUDE.md — click-to-min

## Behaviour rules

No preamble. No "Great question!" or "Sure, I can help with that." Start with the fix or the answer.

When asked to fix something: fix it, commit it, open a PR. Don't explain what you're about to do — just do it.

When CI fails: read the logs, identify root cause, fix it. Don't summarise the failure back at the user — they can see it.

---

## Build & test

```bash
swift build -c debug          # build
swift test --parallel         # run tests
swiftformat Sources           # fix formatting in-place
swiftformat Sources --lint    # check only (same as CI)
swiftlint lint --strict --config .swiftlint.yml Sources  # lint (same as CI)
./build.sh                    # assemble ClickToMin.app
```

CI runs on `macos-14` (arm64). Runner pin is intentional — do not change to `macos-latest`.

---

## Architecture

```
Sources/ClickToMin/Core/   — pure logic. No AppKit, no ApplicationServices, no I/O.
Sources/ClickToMin/IO/     — AX/NSWorkspace/CGEventTap adapters. Conform to Core protocols.
Sources/ClickToMin/        — AppDelegate + DockWatcher coordinator. Wires IO into Core.
Tests/ClickToMinTests/     — XCTest. Tests Core directly; fakes for IO.
```

**The rule that keeps things simple:** branching logic lives only in `Core/ClickPipeline.swift`. IO adapters are dumb wiring. If you want to add an `if` to an IO adapter, it probably belongs in the pipeline instead.

Protocols live in `Core/PipelineProtocols.swift`. IO types in `Core/` is a build error — the `ClickToMinCore` target excludes `ApplicationServices` and `AppKit` at the compiler level.

---

## Coding conventions

### Notification observer variables
Always name the unwrapped token `observer`:
```swift
if let observer = wakeObserver {
    NSWorkspace.shared.notificationCenter.removeObserver(observer)
}
```

### Identifier names
No single-character variables except loop indices (`i`) and standard math (`x`, `y` — already excluded by SwiftLint config). Use descriptive names: `lhs`/`rhs` for comparator closures, `observer` for notification tokens, `elem` for loop elements.

### AX/CF force casts
`as!` is intentional in IO adapters. `AXUIElement`, `AXValue`, `CFBoolean`, `CFURL` are CF types that don't support conditional Swift casts. The cast is safe by API contract. `force_cast` is disabled in `.swiftlint.yml` for this reason — don't re-enable it, don't add per-line suppressions.

### Brace placement
SwiftFormat owns this. It uses Allman style for multi-line conditions (brace on its own line). `opening_brace` is disabled in `.swiftlint.yml` to prevent the two tools conflicting. Don't fight it.

### What SwiftLint/SwiftFormat already enforce
Don't manually check or comment on: trailing whitespace, import ordering, brace spacing, line length (up to 160), TODOs. The linters catch all of these in CI.

### Logging
Use `os_log` with the categories defined in `IO/Log.swift` (`Log.lifecycle`, `Log.pipeline`). No `print()`.

### Delays and timing
Magic numbers for timing go in named constants (`WindowMinimizer.postClickDelay`, `ClickDebouncer.debounceInterval`). Never inline a bare `0.18` or `0.3`.

---

## PR workflow

Branch naming: `fix/short-description`, `feat/short-description`, `chore/short-description`.

Commit style: `type: short summary` — `fix:`, `feat:`, `chore:`, `docs:`, `ci:`. Body optional.

CI must be green before merge: `build-test`, `lint`, `bundle-check`. `Analyze (Swift)` (CodeQL) is allowed to be pending.

Squash-merge is the norm.
