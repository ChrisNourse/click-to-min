# Manual QA Checklist

Items that can't be automated. Run before every release tag. Initial
and date each row in the run log.

## Pre-run

- [ ] Target machine runs a supported macOS version (`>= 13.0`).
- [ ] Build produced by a clean `./build.sh` on a fresh checkout.
- [ ] `qa/run-all.sh` has been executed successfully against this build.

## Manual items

### M1 — First-grant flow (revoked state)

Validates the onboarding path a first-time user sees.

1. Remove ClickToMin from System Settings → Privacy & Security → Accessibility.
2. Launch `ClickToMin.app`. The app should run (permission poller active) but
   click interception is inert.
3. `log stream --predicate 'subsystem == "com.click-to-min"'` should show
   `permission missing, polling started`.
4. Open System Settings, grant Accessibility to `ClickToMin.app`.
5. Within 5 seconds the log should emit `permission granted, DockWatcher installed`
   followed by `global click monitor installed (CGEventTap)`.
6. Click a Dock tile for the frontmost app → it minimizes.

Result (initial / date): ________________

### M2 — Sleep / wake cycle

Validates that AX-driven caches remain valid across sleep.

1. Start `ClickToMin.app` and verify a Dock-click minimize works for one app.
2. Put the machine to sleep (close lid on laptop, or Apple menu → Sleep).
3. Wait ≥ 60 s. Wake the machine.
4. Do not relaunch ClickToMin.
5. Dock-click the same app's tile. It must minimize within 500 ms.
6. Dock-click a **different** app's tile (one whose Dock frame may have
   changed if Dock repositioned). Must minimize.
7. `log stream` during the first post-wake click should show `dock PID refreshed`
   if the Dock process restarted; otherwise a normal pipeline trace.

Result (initial / date): ________________

### M3 — Display hot-plug / resolution change

Validates AXDockFrameProvider re-queries after screen reconfiguration.

1. Start `ClickToMin.app` on primary display.
2. Attach or detach an external display (or toggle resolution in System
   Settings → Displays).
3. Dock may relocate to the new display. Without relaunching, Dock-click a
   tile. Must minimize.
4. `log stream` should show at least one `dock frame refreshed:` line shortly
   after the display change.

Result (initial / date): ________________

### M4 — Hide icon + relaunch from Applications

Validates the re-launch-to-unhide escape hatch.

1. Start `ClickToMin.app`. Menu bar icon visible.
2. Click "Show in menu bar" toggle in the menu to hide.
3. Icon disappears from menu bar.
4. Open `/Applications/ClickToMin.app` (Finder or Spotlight).
5. Menu bar icon reappears within 2 s.
6. All menu items functional (Enable toggle, Quit, etc.).

Result (initial / date): ________________

### M5 — Clean brew install (no Gatekeeper warning)

Validates cask postflight clears quarantine xattr.

1. On a machine that has never had ClickToMin installed:
   `brew install --cask chrisnourse/clicktomin/click-to-min`
2. Launch ClickToMin from Applications.
3. No Gatekeeper warning / "unidentified developer" dialog should appear.
4. Accessibility permission prompt fires normally.

Result (initial / date): ________________

### M6 — brew upgrade preserves TCC grant

Validates that persistent codesign identity keeps Accessibility across upgrades.

1. Install current version via brew cask. Grant Accessibility.
2. Verify minimize works.
3. Cut a new release (or simulate by manually updating the cask to a new version).
4. `brew upgrade --cask click-to-min`.
5. Launch ClickToMin — it should work **without** re-granting Accessibility.

Result (initial / date): ________________

### M7 — Codesign identity stable across releases

Validates the persistent self-signed cert produces the same Identifier.

1. `codesign -dvv /Applications/ClickToMin.app 2>&1 | grep -E "Authority|Identifier"`
2. Note `Identifier=com.click-to-min` and `Authority=ClickToMin Release Signing`.
3. After `brew upgrade --cask click-to-min`, repeat step 1.
4. Both fields must be identical.

Result (initial / date): ________________

## Notes / bugs observed

(Free-form; attach log excerpts if any step failed.)
