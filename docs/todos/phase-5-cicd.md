# Phase 5 — CI / CD

**Goal**: Every change to `main` goes through a PR with green checks. No direct pushes, no force-pushes, no merging a red build. Tag pushes produce release artifacts.

**Parallelism**: Fully parallel with Phases 1–4. Stub workflows can be committed as soon as Phase 0 completes; `bundle-check` integrates with Phase 4's `build.sh` and can land last.

**Exit criteria**: PRs to `main` show three required green checks (`build-test`, `bundle-check`, `lint`); a `v*.*.*` tag push produces a signed `.app` artifact attached to a GitHub Release; branch protection enforces the rules in PLAN.md §Branch Protection.

---

### T-5.1 — `.github/workflows/ci.yml`
- **Owner**: unassigned
- **Depends on**: T-0.2
- **Blocks**: T-5.4 (branch protection references check names)
- **Files**: `.github/workflows/ci.yml`
- **Description**: Per PLAN.md §CI. Trigger on PR and `push` to `main`. Runner `macos-14` **pinned to a specific minor image tag** (not `macos-latest`). Three jobs: `build-test`, `bundle-check`, `lint`. Concurrency group by PR ref with cancel-in-progress. Cache `.build/` keyed by `Package.resolved` hash.
- **Acceptance criteria**:
  - [ ] Runner pinned to specific tag (comment rationale)
  - [ ] Xcode selected via `sudo xcode-select -s /Applications/Xcode_XX.Y.app` (match the pinned runner's available versions)
  - [ ] **Dated pin comment immediately above the `xcode-select` step**, of the form `# pinned YYYY-MM-DD, Xcode versions on this runner: <list>` — re-dated every time the runner image or Xcode pin is bumped
  - [ ] Comment links to https://github.com/actions/runner-images for the source of truth on available Xcode versions per runner
  - [ ] `build-test` runs `swift build -c debug` then `swift test --parallel`
  - [ ] Test results uploaded as artifact on failure
  - [ ] `bundle-check` depends on `build-test`, runs `./build.sh`, `codesign --verify --verbose`, `plutil -lint`, uploads `.app` artifact (7-day retention)
  - [ ] `lint` parallel to `build-test`, runs `swiftformat --lint Sources Tests`
  - [ ] Concurrency group cancels stale PR runs
  - [ ] `.build/` cache step
- **Verification step**:
  - Open a scratch PR introducing (a) a formatting violation, (b) a failing test, (c) a plist typo. Confirm each of the three jobs fails on the appropriate one. Revert.
  - **Staleness check**: confirm the `Xcode_XX.Y.app` path actually exists on the pinned runner by echoing `ls /Applications | grep Xcode` in a preceding step on the first CI run after the pin is applied. Remove the echo after verification.
- **Notes**: PLAN.md §ci.yml. The runner pin and the Xcode pin are **paired** — bumping one requires auditing the other. The dated comment is the mechanism that makes this pairing visible to the next maintainer.

### T-5.2 — `.github/workflows/release.yml`
- **Owner**: unassigned
- **Depends on**: T-4.2
- **Blocks**: none
- **Files**: `.github/workflows/release.yml`
- **Description**: Trigger `push` with tag pattern `v*.*.*`. Builds release `.app`, zips it, creates GitHub Release with the zip attached. Ad-hoc signed only; no notarization in v1 (PLAN.md).
- **Acceptance criteria**:
  - [ ] Trigger filter: `tags: ['v*.*.*']`
  - [ ] Reuses `build.sh`
  - [ ] Zips `ClickToMin.app` preserving symlinks (`ditto -c -k --keepParent`)
  - [ ] Creates GitHub Release via `softprops/action-gh-release` or equivalent, with zip attached
  - [ ] Workflow notes in comment: "add notarization before distributing beyond personal use"
- **Verification step**:
  - Push a `v0.0.0-test` tag to a scratch branch; confirm the workflow runs, produces an artifact, and creates a draft release. Delete the tag and release after.
- **Notes**: PLAN.md §release.yml. Use `ditto`, not `zip`, to preserve bundle integrity.

### T-5.3 — `.swiftformat` config + lint gate wiring
- **Owner**: unassigned
- **Depends on**: T-0.3
- **Blocks**: none (lint job already in T-5.1)
- **Files**: `.swiftformat`
- **Description**: Commit a minimal, opinionated swiftformat config. The lint job in T-5.1 runs against it.
- **Acceptance criteria**:
  - [ ] `.swiftformat` exists and is respected by `swiftformat --lint`
  - [ ] Config is minimal (a handful of rules; no project-wide rewrite)
  - [ ] README or PR template references `swiftformat` as local hook
- **Verification step**:
  - `swiftformat --lint Sources Tests` locally → matches CI. Introduce a trailing-whitespace line; confirm it flags; revert.
- **Notes**: PLAN.md §ci.yml lint job.

### T-5.4 — Branch protection on `main`
- **Owner**: unassigned (maintainer must apply in Settings)
- **Depends on**: T-5.1 (check names must exist first)
- **Blocks**: none
- **Files**: none (repo Settings)
- **Description**: Apply exact settings from PLAN.md §Branch Protection. Solo-maintainer nuance: approvals = 0 but all other rules stay on, including `Do not allow bypassing` so the admin can't merge a red build.
- **Acceptance criteria**:
  - [ ] Require PR before merging: ON
  - [ ] Required approvals: 0 (solo) — bump to 1+ when collaborators join
  - [ ] Dismiss stale approvals: ON
  - [ ] Required status checks: `build-test`, `bundle-check`, `lint`
  - [ ] Require branches up to date: ON
  - [ ] Require conversation resolution: ON
  - [ ] Require linear history: ON
  - [ ] Do not allow bypassing: ON (applies to admins)
  - [ ] Direct push list: empty
  - [ ] Force pushes: OFF
  - [ ] Deletions: OFF
  - [ ] Repo-level merge settings: squash only (merge + rebase disabled); default commit = PR title + description
- **Verification step**:
  - From a scratch branch, attempt `git push origin HEAD:main` — must be rejected. Attempt to merge a PR with one red check — must be blocked even as admin. Document with screenshots in `docs/` if collaborators join.
- **Notes**: PLAN.md §Branch Protection, §Solo-maintainer nuance.

---

## Common Failure Patterns (pre-merge check)

- [ ] Runner pinned to `macos-latest` — toolchain drift silently fails future builds
- [ ] Xcode version not explicitly selected — runner default shifts, tests break unpredictably
- [ ] Zip uses `zip -r` instead of `ditto` — bundle symlinks corrupted, launch fails
- [ ] Release trigger pattern matches pre-release tags unintentionally (`v*` vs `v*.*.*`)
- [ ] `lint` job fails but doesn't block merge — check name not added to required list
- [ ] Branch protection configured but "Do not allow bypassing" left OFF — solo admin footgun
- [ ] Concurrency group missing → PR CI queues stale runs, burns minutes

## Completed

<!-- Move finished tasks here -->
