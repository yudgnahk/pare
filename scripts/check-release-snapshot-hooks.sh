#!/usr/bin/env bash
# Fails if the DEBUG-only snapshot renderer or its hooks leak into a release PareApp binary.
# CI-only: a release build is too heavy for the local build loop.
set -euo pipefail

swift build -c release --product PareApp
BIN="$(swift build -c release --show-bin-path)/PareApp"

SYMBOLS="$(nm "$BIN")"
# Positive control: an unstripped binary must list real app symbols, or the check below proves nothing.
if ! grep -q "ScanDashboardViewModel" <<<"$SYMBOLS"; then
  echo "No app symbols found in $BIN; cannot verify snapshot hooks are compiled out." >&2
  exit 1
fi

LEAKS="$(grep -E "SnapshotRenderer|SnapshotFixtures|applySnapshot|snapshotStatusOverride|snapshotTransactions" <<<"$SYMBOLS" || true)"
if [[ -n "$LEAKS" ]] || strings "$BIN" | grep "PARE_SNAPSHOT_DIR" >/dev/null; then
  echo "DEBUG snapshot hooks found in the release binary:" >&2
  echo "$LEAKS" >&2
  exit 1
fi
echo "Release binary contains no snapshot hooks."
