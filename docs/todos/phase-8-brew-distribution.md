# Phase 8 — Homebrew Cask Distribution

**Goal**: Ship ClickToMin via a private Homebrew tap so users install with `brew install --cask chrisnourse/clicktomin/click-to-min` and update with `brew upgrade`. Cask postflight clears quarantine xattr — no Gatekeeper warning on first launch.

**Depends on**: Phase 9 (persistent codesign) lands first so the initial cask ships with a stable identity.

**Exit criteria**:
- `brew install --cask chrisnourse/clicktomin/click-to-min` installs to `/Applications/ClickToMin.app`
- First launch: no Gatekeeper warning; Accessibility prompt fires
- `brew upgrade --cask click-to-min` preserves TCC grant (same codesign identity)
- Tag push triggers cask-bump action that auto-updates the tap

---

### T-8.1 — Tap repo + initial cask
- **Owner**: unassigned
- **Depends on**: Phase 9 merged
- **Blocks**: T-8.2
- **Files**: `ChrisNourse/homebrew-clicktomin` repo: `Casks/click-to-min.rb`
- **Description**: Create new public repo. Cask fetches zip from GitHub Releases, installs .app, runs `xattr -dr com.apple.quarantine` in postflight. `zap` block removes preferences plist.
- **Acceptance criteria**:
  - [ ] `brew tap chrisnourse/clicktomin && brew install --cask click-to-min` works on a clean machine
  - [ ] No Gatekeeper warning on first launch
  - [ ] `brew uninstall --cask click-to-min` removes app + symlink

### T-8.2 — release.yml: zip artifact + cask-bump job
- **Owner**: unassigned
- **Depends on**: T-8.1
- **Blocks**: none
- **Files**: `.github/workflows/release.yml`
- **Description**: Produce a `.zip` alongside the DMG. Add `update-cask` job using `macauley/action-homebrew-bump-cask@v1`. Requires `HOMEBREW_TAP_PAT` secret (fine-grained PAT with contents:write on tap repo).
- **Acceptance criteria**:
  - [ ] Tag push produces both DMG and zip in the GitHub Release
  - [ ] Cask-bump action opens a commit/PR on the tap repo with updated version + sha256
  - [ ] `brew upgrade --cask click-to-min` picks up the new version after tap sync

### T-8.3 — README install instructions
- **Owner**: unassigned
- **Depends on**: T-8.1
- **Blocks**: none
- **Files**: `README.md`
- **Description**: Add `brew install --cask chrisnourse/clicktomin/click-to-min` as the recommended install path. Keep DMG as fallback with documented xattr workaround for Sequoia.
- **Acceptance criteria**:
  - [ ] README shows brew as primary install method
  - [ ] DMG path documented with Gatekeeper workaround

### T-8.4 — Manual QA (M5, M6, M7)
- **Owner**: unassigned
- **Depends on**: T-8.1, T-8.2
- **Blocks**: none
- **Files**: `qa/MANUAL-CHECKLIST.md`
- **Description**: M5 (clean brew install, no warning), M6 (brew upgrade preserves TCC), M7 (codesign -dvv shows same Identifier before/after upgrade).
- **Acceptance criteria**:
  - [ ] All three items documented in MANUAL-CHECKLIST.md
  - [ ] Verified on at least one clean machine before merge
