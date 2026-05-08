# Open Todo — Streamline the local codesigning setup

**Status**: open, not scheduled
**Owner**: unassigned
**Depends on**: none
**Blocks**: nothing functional; blocks a one-command dev-machine setup

## Context

`build.sh` now prefers a stable self-signed codesigning identity named
`ClickToMin Local Dev` so TCC Accessibility grants survive rebuilds. If the
identity is missing, it falls back to ad-hoc (and loses the grant on every
build).

Creating that identity is currently a manual, multi-step Keychain Access
dance: Certificate Assistant → Create a Certificate → pick Code Signing →
"Always Trust" the cert → open the private key → Access Control → "Allow
all applications". Documented in `qa/README.md` and `clicktomin-vm-setup.md`,
but it is a full 10-minute setup per dev machine and trips up every
first-time contributor.

## What we want

A single-command path to a working local signing identity. Candidates:

1. **Homebrew formula** — `brew install clicktomin-dev-signing` that:
   - generates a self-signed cert via `openssl`
   - imports it into the login keychain
   - sets the codesign partition list + ACL allow-all so `codesign` can use
     the key non-interactively over SSH (this is the part that bites people)
   - writes `$CLICKTOMIN_SIGN_ID` guidance into the shell profile

2. **`scripts/setup-signing.sh`** — committed in-repo equivalent of the
   above, invoked once via `./scripts/setup-signing.sh`. No Homebrew
   dependency. Downside: every dev has to `chmod +x` a shell script.

3. **CI-generated ephemeral identity** — for CI only, not local dev, generate
   and trust a throwaway cert per run. Doesn't solve local-dev friction;
   orthogonal.

## Questions to resolve before implementing

- Do we want a **single shared identity** (same SubjectKeyID across all dev
  machines, so a grant on machine A is portable) or a **per-machine
  identity** (each dev gets their own)? Shared = simpler onboarding but
  sharing a private key is a footgun; per-machine = each dev regrants TCC
  once.
- Is Homebrew worth the overhead of publishing + maintaining a tap, or is a
  repo script enough? A repo script keeps the dependency inside this repo.
- How does the setup script interact with `security set-key-partition-list`
  on first run? That command prompts for the keychain password — can we
  avoid it with `security unlock-keychain` first, the way `.zshenv`
  auto-unlock does on the VM?

## Acceptance criteria (when we get to it)

- [ ] `./scripts/setup-signing.sh` (or `brew install …`) on a clean macOS
      machine produces a working `ClickToMin Local Dev` identity such that
      `./build.sh` immediately signs without warnings
- [ ] Re-runs are idempotent — running twice doesn't create duplicate
      identities or orphan private keys
- [ ] Script self-documents what it did (echoes the cert name + key
      partition list it touched) so a curious dev can audit it
- [ ] CI reference: document how to make the same identity on a self-hosted
      runner, if we ever add one for AX-dependent QA

## Notes

- The ad-hoc fallback in `build.sh` is fine as a failsafe; don't remove it
  when the setup script lands. Devs who just want to build once without
  preserving TCC grants should still be able to `./build.sh` with zero
  setup.
- See `clicktomin-vm-setup.md` on the UTM test VM for the current manual
  recipe — that's the source material for the script.
