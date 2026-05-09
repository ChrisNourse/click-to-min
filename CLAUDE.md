# CLAUDE.md — click-to-min

## Communication style

Be terse. No filler. No praise. No preamble. Fragments OK. Short synonyms.
Drop articles (a/an/the) when meaning stays clear. Lead with action or answer.
One line per issue when reviewing code: `file:line severity problem. fix.`

This applies everywhere: commit messages, PR comments, code review, chat.

## Behaviour

Fix thing. Do it. Open PR.

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

---

## AI Code Review

Senior engineer review. All changed files — Swift, CI, scripts, tests, docs.

### Flag
- Correctness bugs, logic errors, memory/retain issues, silent failure paths.
- DRY violations — duplicated logic that should be extracted.
- YAGNI violations — speculative code with no current caller.
- KISS violations — over-engineered solutions; simpler alternative exists.
- Dead/unused code — unreachable paths, unused imports, orphan helpers.
- Long-term maintainability risks, readability problems.
- CI misconfigurations, missing test coverage for behavioral changes.
- Weak/misleading PR description — if summary doesn't match actual changes, flag it.

### Skip
Style, formatting, brace placement — linters own that.

### Quality rules
- Only flag issues you are CERTAIN about. When in doubt, do not comment.
- NEVER suggest code identical to what already exists. Re-read the diff line first.
- Before flagging "dead code" or "unnecessary fallback", consider intentional defensive programming.
- Understand language semantics before flagging ordering issues (e.g. Python `and` short-circuits).
- Fewer high-confidence comments > many speculative ones.
- If code is correct, return LGTM.

### Output format
JSON object:
- `summary`: one-sentence overall assessment
- `comments`: array of `{path, line, body, suggestion?}`
  - `path`: file path from diff header (after `b/`)
  - `line`: line number in new file (right side of diff)
  - `body`: one-line — severity, problem, fix
  - `suggestion`: (optional) exact replacement that DIFFERS from existing code
- `thread_replies`: array of `{thread_id, body}`

Line rules: only comment on + or context lines. Never deleted lines.
No issues → `{"summary": "LGTM", "comments": [], "thread_replies": []}`.
Return ONLY valid JSON. No markdown fences. No text outside JSON.
