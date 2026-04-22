# ClickToMin — Performance Baselines

Regression guard per `PLAN.md` §Performance & Memory Notes and §Testing Layer 3.
Populated by the maintainer before each release cut (see `docs/todos/phase-6-qa-perf.md` T-6.5).

## How to read this file

- **Baseline** = numbers recorded at first shipping build.
- **Current** = numbers from the release being cut now.
- Flag any **>20%** regression vs. baseline in the release notes. If skipped for a release, note the reason in the Skipped column.

## Steady-state metrics

| Metric | Baseline (v0.1.0) | Current (vX.Y.Z) | Delta | Skipped? Reason |
|--------|-------------------|------------------|-------|-----------------|
| Resident memory, idle 5min (MB)          | TBD | TBD | TBD | — |
| CPU %, idle 5min                         | TBD | TBD | TBD | — |
| Click-to-minimize perceptual latency (ms) | TBD | TBD | TBD | — |
| Per-click allocation growth (500 clicks, MB) | TBD | TBD | TBD | — |

## Short-circuit effectiveness (Time Profiler)

| Scenario | Expected | Baseline (v0.1.0) | Current (vX.Y.Z) | Notes |
|----------|----------|-------------------|------------------|-------|
| 1000 clicks **outside** Dock region | `AXUIElementCopyElementAtPosition` not in hot path | TBD | TBD | — |
| 1000 clicks **inside** Dock region  | AX hit-test present, bounded to these clicks only | TBD | TBD | — |

## OS-specific observations

Document anything that required a PLAN.md caveat update here (e.g., system-wide AX messaging timeout being a no-op on a given macOS version).

| macOS version | Observation | Action taken |
|---------------|-------------|--------------|
| TBD | TBD | TBD |

## Release history

| Version | Date | Memory MB | Idle CPU % | Latency ms | Regression flag | Link |
|---------|------|-----------|------------|------------|-----------------|------|
| v0.1.0 (baseline) | TBD | TBD | TBD | TBD | — | — |
