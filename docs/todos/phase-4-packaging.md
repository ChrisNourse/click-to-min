# Phase 4 — Build & Packaging

**Goal**: Ship a runnable `ClickToMin.app` bundle assembled from the SwiftPM executable, with ad-hoc codesign for stable TCC identity.

**Parallelism**: Serial within phase. Fully parallel with Phase 5 (CI). The Phase 5 `bundle-check` job integrates with artifacts produced here.

**Exit criteria**: `./build.sh` produces `ClickToMin.app` that launches, shows menu bar icon, prompts for Accessibility, and survives rebuild without losing TCC permission.

---

### T-4.1 — `Resources/Info.plist`
- **Owner**: unassigned
- **Depends on**: T-3.3
- **Blocks**: T-4.2, T-5.2 (bundle-check)
- **Files**: `Resources/Info.plist`
- **Description**: Per PLAN.md §Info.plist: `LSUIElement = YES`, `LSMinimumSystemVersion = 13.0`, `NSAccessibilityUsageDescription`, `CFBundleIdentifier = com.chrisno.click-to-min`, `CFBundleName = ClickToMin`. Comment why `LSUIElement` and `NSApp.setActivationPolicy(.accessory)` both exist.
- **Acceptance criteria**:
  - [ ] All 5 keys present with correct types
  - [ ] `plutil -lint Resources/Info.plist` returns OK
  - [ ] Bundle identifier exactly `com.chrisno.click-to-min`
  - [ ] Minimum version matches `Package.swift` (13.0)
- **Verification step**:
  - `plutil -lint Resources/Info.plist` — must report OK. Run after every edit.
- **Notes**: PLAN.md §Info.plist. Drift between `Package.swift` macOS version and plist will cause launch failures on older systems.

### T-4.2 — `build.sh`
- **Owner**: unassigned
- **Depends on**: T-4.1
- **Blocks**: T-5.2, T-6.1
- **Files**: `build.sh`
- **Description**: Bash script per PLAN.md §build.sh: `swift build -c release`; create `ClickToMin.app/Contents/{MacOS,Resources}`; copy binary; copy Info.plist; ad-hoc codesign with the two-step fallback (sign inner binary first if a warning appears). `set -euo pipefail`.
- **Acceptance criteria**:
  - [ ] `set -euo pipefail` at top
  - [ ] Idempotent — removes prior `ClickToMin.app` before rebuild
  - [ ] Ad-hoc codesign step present, no `--deep` (deprecated per PLAN.md)
  - [ ] Two-step fallback codified (inner-binary sign, then bundle)
  - [ ] `chmod +x build.sh` committed
- **Verification step**:
  - `./build.sh && codesign --verify --verbose ClickToMin.app && open ClickToMin.app` — bundle signs, verifies, launches. Repeat a second time without cleaning — must still succeed.
- **Notes**: PLAN.md §build.sh, §Edge Cases (TCC identity stability).

### T-4.3 — Launch smoke
- **Owner**: unassigned
- **Depends on**: T-4.2
- **Blocks**: T-6.1
- **Files**: (none — manual gate)
- **Description**: Launch the assembled `.app` manually. Confirm menu bar icon, Accessibility prompt, Quit, no lingering process.
- **Acceptance criteria**:
  - [ ] Menu bar icon appears
  - [ ] Accessibility prompt fires on first launch
  - [ ] Quit menu item exits cleanly (`ps -A | grep ClickToMin` empty after)
  - [ ] `log stream --predicate 'subsystem == "com.chrisno.click-to-min"'` shows `lifecycle` signposts
- **Verification step**:
  - Perform steps above on the Phase 4 machine; paste terminal + `log stream` output into the commit / PR description.
- **Notes**: This is the gate into Phase 6. If this fails, do not proceed to Phase 6 QA.

---

## Common Failure Patterns (pre-merge check)

- [ ] `LSUIElement` mismatch with `NSApp.setActivationPolicy(.accessory)` — works unbundled but Dock icon appears on bundled launch
- [ ] `CFBundleIdentifier` mismatch across plist / signing / TCC — Accessibility grant keeps getting revoked
- [ ] `build.sh` not idempotent — stale files from prior build leak into new bundle
- [ ] Codesign uses deprecated `--deep` — works today, breaks on future macOS
- [ ] Script missing `set -e` — a failed `cp` silently continues, producing a broken bundle
- [ ] `plutil -lint` not run — silent plist typos ship

## Completed

<!-- Move finished tasks here -->
