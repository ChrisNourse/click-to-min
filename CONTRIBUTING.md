# Contributing to ClickToMin

Thanks for considering a contribution. ClickToMin is a small macOS
menu-bar utility; the codebase is intentionally modest and tries to
stay that way.

## Requirements

- macOS 13 or later (Ventura+)
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode is
  optional and only useful for interactive debugging
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
  (`brew install swiftformat`) — CI lints with this

## Build & test

The project is pure SwiftPM. No generated Xcode project.

```bash
# Clone
git clone https://github.com/ChrisNourse/click-to-min.git
cd click-to-min

# Build
swift build

# Run tests (fast, no UI)
swift test

# Run locally (menu-bar icon will appear; no app bundle yet)
swift run

# Build a distributable .app bundle
./build.sh
open ClickToMin.app
```

### Using Xcode

Optional, but nice for breakpoints and LLDB:

```bash
open Package.swift
```

Xcode treats `Package.swift` as a workspace. Select the **ClickToMin**
scheme, then:

- `⌘B` — build
- `⌘U` — run tests
- `⌘R` — run (menu-bar app appears; Accessibility permission required)

No project-file generation, no extra setup.

## Code layout

- `Sources/ClickToMin/Core/` — pure logic. No `ApplicationServices`,
  no `AppKit`, no I/O. Fully unit-testable with in-memory fakes.
- `Sources/ClickToMin/IO/` — adapters that wrap AX / NSWorkspace /
  CGEventTap / NSStatusBar. Conform to `Core` protocols.
- `Sources/ClickToMin/` (top-level) — `AppDelegate`, `DockWatcher`
  coordinator. Wires adapters into `runClickPipeline`.
- `Tests/ClickToMinTests/` — XCTest unit tests for `Core` + a few
  integration tests for the coordinator.

The rule that keeps things simple: **branching logic lives only in
`Core/ClickPipeline.swift`**. Everything in `IO/` and the coordinator
is dumb wiring. If you feel the urge to add an `if` to an adapter,
it probably belongs in the pipeline instead.

## Linting

```bash
# Check (same as CI)
swiftformat Sources --lint

# Fix in-place
swiftformat Sources
```

CI runs the `--lint` form and fails the build on any warning.

## Branch & PR flow

- Branch from `main`: `git checkout -b fix/short-description` or
  `feat/short-description`.
- Keep PRs focused; one concern per PR.
- Commit message style: `type: short summary` (`fix:`, `feat:`,
  `diag:`, `lint:`, `docs:`, `chore:`). Body optional but welcome for
  non-trivial changes.
- CI must be green before merge: `build-test`, `lint`, `bundle-check`.
- Squash-merge is the norm.

## Releases

Maintainer-only. Tag-driven:

1. Merge all desired PRs into `main`.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. GitHub Actions builds the `.app`, packages a drag-to-Applications
   DMG via `create-dmg`, and publishes it to the Releases page.

RC tags (`vX.Y.Z-rcN`) are allowed during pre-release testing.

## Code signing

Releases are **ad-hoc signed** (no paid Apple Developer account).
End users must clear the quarantine bit or right-click → Open the
first time. See the README's "Installing an unsigned build" section
for the one-line fix.

If this project ever graduates to Developer ID signing + notarization,
it will be because someone fronts the $99/year or contributes a
signing workflow with access to their own account.

## License

GPL-3.0-or-later. See `LICENSE`. Contributions are accepted under the
same license — by opening a PR you agree to license your contribution
under GPL-3.0-or-later.
