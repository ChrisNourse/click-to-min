# Phase 7 — Inline Menu Settings

**Goal**: Add enable/disable toggle and show/hide menu-bar-icon toggle as inline NSMenu items. Re-launching the app un-hides a hidden icon. Persisted via UserDefaults.

**Exit criteria**:
- `defaults write com.click-to-min com.click-to-min.enabled -bool false` → pipeline stops; clicks pass through
- `defaults write com.click-to-min com.click-to-min.iconHidden -bool true` → icon disappears; re-launch restores it
- Unit tests pass for settings round-trip + change notification
- `qa/06-settings.sh` passes end-to-end

---

### T-7.1 — Settings protocol + keys in Core
- **Owner**: unassigned
- **Depends on**: none
- **Blocks**: T-7.2, T-7.3
- **Files**: `Sources/ClickToMin/Core/Settings.swift`
- **Description**: Pure protocol `SettingsStore` with `enabled: Bool` and `iconHidden: Bool` properties. `SettingsKeys` enum holds UserDefaults key strings. No AppKit.
- **Acceptance criteria**:
  - [x] Compiles in `ClickToMinCore` target (no AppKit import)
  - [x] Protocol is `public`; usable from both test and executable targets

### T-7.2 — UserDefaults adapter (IO)
- **Owner**: unassigned
- **Depends on**: T-7.1
- **Blocks**: T-7.3
- **Files**: `Sources/ClickToMin/IO/UserDefaultsSettings.swift`
- **Description**: `final class UserDefaultsSettings: SettingsStore`. Posts `Notification.Name.settingsChanged` on any mutation. Registers defaults (enabled=true, iconHidden=false).
- **Acceptance criteria**:
  - [x] Round-trips values through UserDefaults
  - [x] Posts notification exactly once per mutation
  - [x] Registers sensible defaults on init

### T-7.3 — MenuBuilder + AppDelegate wiring
- **Owner**: unassigned
- **Depends on**: T-7.1, T-7.2
- **Blocks**: T-7.4
- **Files**: `Sources/ClickToMin/MenuBuilder.swift`, `Sources/ClickToMin/AppDelegate.swift`
- **Description**: Extract menu construction into `MenuBuilder`. Add "Enable ClickToMin" and "Show in menu bar" checkmark items. AppDelegate observes settings changes: toggles `dockWatcher.start()/stop()` on enable flip, toggles `statusItem.isVisible` on icon flip. One-time NSAlert on first hide.
- **Acceptance criteria**:
  - [x] Enable toggle starts/stops DockWatcher without tearing down the instance
  - [x] Show-in-menu-bar toggle hides/shows the status item
  - [x] First hide shows NSAlert; subsequent hides do not (flag in defaults)
  - [x] "About ClickToMin vX.Y.Z" row shows CFBundleShortVersionString

### T-7.4 — Re-launch handler + duplicate-instance handoff
- **Owner**: unassigned
- **Depends on**: T-7.3
- **Blocks**: none
- **Files**: `Sources/ClickToMin/AppDelegate.swift`
- **Description**: `applicationShouldHandleReopen` clears `iconHidden` if set. Duplicate-launch detection posts `com.click-to-min.reopen` via DistributedNotificationCenter, then terminates. Original instance observes and un-hides.
- **Acceptance criteria**:
  - [x] Hidden icon + re-launch from Finder → icon reappears
  - [x] Second instance terminates cleanly (no zombie)
  - [x] Original instance un-hides within 1s of receiving the notification

### T-7.5 — Unit tests
- **Owner**: unassigned
- **Depends on**: T-7.1, T-7.2
- **Blocks**: none
- **Files**: `Tests/ClickToMinTests/SettingsTests.swift`
- **Description**: In-memory fake conforming to `SettingsStore`. Tests: round-trip, default values, change-notification count.
- **Acceptance criteria**:
  - [x] `swift test` passes with new test file
  - [x] Covers default-when-absent, mutation, notification

### T-7.6 — QA script + manual checklist
- **Owner**: unassigned
- **Depends on**: T-7.3, T-7.4
- **Blocks**: none
- **Files**: `qa/06-settings.sh`, `qa/MANUAL-CHECKLIST.md`
- **Description**: Scripted toggle tests via `defaults write` + AXProbe assertions. Manual M4 (hide + relaunch).
- **Acceptance criteria**:
  - [x] `qa/06-settings.sh` passes on a workstation with Accessibility granted
  - [x] M4 documented in MANUAL-CHECKLIST.md
