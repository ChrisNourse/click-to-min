# AXProbe

Tiny Swift CLI for asserting AX state from bash. Used by `qa/*.sh`.

## Build

```bash
swift build -c release --package-path qa/harness/AXProbe
```

Binary path: `qa/harness/AXProbe/.build/release/axprobe`.

## Grant Accessibility

`axprobe` needs its own Accessibility grant, separate from `ClickToMin.app`.

System Settings -> Privacy & Security -> Accessibility -> `+` ->
navigate to `qa/harness/AXProbe/.build/release/axprobe` and enable.

Verify: `./axprobe is-trusted; echo $?` should print `0`.

## Subcommands

- `is-trusted` — exit 0 if granted, 3 otherwise.
- `frontmost-bundle-id` — print current frontmost app's bundle id.
- `is-minimized <bundle-id>` — print `minimized=true|false` for focused window.
- `window-count <bundle-id>` — print visible window count.
- `wait-until-minimized <bundle-id> [--timeout SECS]` — poll at 25ms.
- `dock-item-frame <bundle-id>` — print `x= y= w= h=` for the Dock tile.

## Test

```bash
swift test --package-path qa/harness/AXProbe
```

Tests use a `FakeAXReader`; no live AX required, safe in CI.
