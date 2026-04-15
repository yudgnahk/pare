# Manual Testing - Run Commands

Use these commands from the repository root.

## Quick Start

```bash
make build
make test
make start
make run-app
```

`make start` runs the baseline profile so you can quickly inspect findings.
`make run-app` launches the SwiftUI macOS app target.

## Useful Run Modes

```bash
make run-baseline
make run-developer
make run PROFILE=designer TOP=50
make run PROFILE=video-builder TOP=50
make run PROFILE=developer TOP=50
```

## Suggested Manual Test Checklist

1. Run baseline scan and confirm categories appear with sensible totals.
2. Run developer scan and verify Xcode/package/simulator items appear.
3. Run designer and video-builder scans and verify Adobe/Figma/FCP/Premiere/Resolve cache targets appear.
4. Confirm media-preview-like targets are labeled `REVIEW` in top-files output.
5. Inspect top files output and spot-check paths for safety expectations.
6. Re-run same command and check that output remains stable.

## Phase 2 Parity Validation (Recorded)

Environment: same machine/session, local run on 2026-04-15.

- Baseline profile:
  - CLI total reclaimable: `76.7 MB`
  - Categories observed: User Caches, Logs and Crash Reports
  - Large-file group (`> 50 MB`): none observed
- Developer profile:
  - CLI total reclaimable: `3.88 GB`
  - Categories observed: Developer Package Caches, Developer Build Artifacts, User Caches, Logs and Crash Reports
  - Large-file group (`> 50 MB`): Developer Package Caches with 3 files totaling `222.4 MB`

Use the same profile in app and CLI during manual checks, then confirm:
1. Summary totals match for each profile.
2. Category ranking/order is consistent.
3. Large-file sections reflect the same threshold behavior (`> 50 MB`).

## Optional Direct Swift Commands

```bash
swift run cleanmymac-cli --profile baseline --top 20
swift run cleanmymac-cli --profile developer --top 30
```
