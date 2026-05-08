# Phase 9 — Persistent Self-Signed Codesign in CI

**Goal**: Every release built in CI is signed with the same persistent identity so TCC Accessibility grants survive `brew upgrade` (and any other in-place app replacement). No Apple Developer Program required.

**Lands before Phase 8** so the first cask publication already carries the stable identity.

**Exit criteria**:
- `release.yml` imports a persistent self-signed cert from GitHub secrets
- `codesign -dvv ClickToMin.app` shows `Authority=ClickToMin Release Signing` and `Identifier=com.click-to-min` on CI-built artifacts
- Two sequential release builds produce the same Identifier + Authority (TCC-stable)
- Recovery path documented for key loss

---

### T-9.1 — Certificate generation script
- **Owner**: unassigned
- **Depends on**: none
- **Blocks**: T-9.2
- **Files**: `scripts/generate-signing-cert.sh`
- **Description**: Generates a 2048-bit RSA key + 20-year self-signed cert (CN=ClickToMin Release Signing). Wraps in .p12. Prints base64 to stdout for pasting into GitHub secrets. Idempotent (refuses to overwrite).
- **Acceptance criteria**:
  - [ ] Running once produces a valid .p12 that `security import` accepts
  - [ ] Running twice refuses to overwrite and exits non-zero
  - [ ] Output includes instructions for adding secrets to GitHub

### T-9.2 — release.yml: import cert + sign
- **Owner**: unassigned
- **Depends on**: T-9.1
- **Blocks**: T-9.3
- **Files**: `.github/workflows/release.yml`
- **Description**: Add a step that decodes `MACOS_SIGNING_P12_BASE64`, imports into a temporary keychain, sets partition list for codesign access, exports `CLICKTOMIN_SIGN_ID` env var. `build.sh` already uses this var.
- **Acceptance criteria**:
  - [ ] CI release build signs with `ClickToMin Release Signing` (not ad-hoc)
  - [ ] Temporary keychain is created + destroyed within the job
  - [ ] No plaintext secrets appear in job logs

### T-9.3 — Secrets bootstrap + recovery doc
- **Owner**: unassigned
- **Depends on**: T-9.1
- **Blocks**: none
- **Files**: `docs/todos/phase-9-persistent-codesign.md` (this file, updated with completion notes)
- **Description**: Document: (1) how to run the generation script, (2) how to add the two secrets to GitHub, (3) how to verify a signed release, (4) recovery path if the private key is lost.
- **Acceptance criteria**:
  - [ ] Step-by-step instructions exist in this file or a linked doc
  - [ ] Recovery scenario documented (generate new cert, users re-grant once)
  - [ ] Offline backup recommendation noted

### T-9.4 — Verification release
- **Owner**: unassigned
- **Depends on**: T-9.2, secrets configured
- **Blocks**: Phase 8
- **Files**: none (tag push test)
- **Description**: Push a test tag (e.g. `v0.1.1-rc1`), verify the resulting artifact is signed with the persistent identity. Compare `codesign -dvv` output against expectations.
- **Acceptance criteria**:
  - [ ] `Authority=ClickToMin Release Signing` in output
  - [ ] `Identifier=com.click-to-min` in output
  - [ ] DMG contains properly signed .app
