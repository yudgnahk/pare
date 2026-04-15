# Manual Testing - Run Commands

Use these commands from the repository root.

## Quick Start

```bash
make build
make test
make start
```

`make start` runs the baseline profile so you can quickly inspect findings.

## Useful Run Modes

```bash
make run-baseline
make run-developer
make run PROFILE=developer TOP=50
```

## Suggested Manual Test Checklist

1. Run baseline scan and confirm categories appear with sensible totals.
2. Run developer scan and verify Xcode/package/simulator items appear.
3. Inspect top files output and spot-check paths for safety expectations.
4. Re-run same command and check that output remains stable.

## Optional Direct Swift Commands

```bash
swift run cleanmymac-cli --profile baseline --top 20
swift run cleanmymac-cli --profile developer --top 30
```
