# Pare

A safety-first disk cleanup app for macOS 13+, built for people who write code.

Pare finds caches, build output and leftovers you can safely reclaim, explains what each item is,
and moves what you choose to the Trash, where you can undo it.

## What it does

- **Smart Scan**: about 50 rules for app, browser, developer, AI tool and system caches, logs, installers, old app versions and leftovers. Each finding is marked Safe, Review or Advanced.
- **Grouped by owner**: results are listed by app, project and developer tool (or by category, if you prefer). Builds of projects you edited in the last 3 days start unticked.
- **Developer depth**: package manager caches (npm, pnpm, Yarn, Bun, Cargo, CocoaPods, SwiftPM, Homebrew), Xcode, JetBrains and VS Code leftovers, and dependency folders of projects you have stopped working on, checked against git before they are offered.
- **Worth knowing**: notes about problems Pare will not clean for you, such as heavy swap, memory pressure, files held open after deletion, or a launch agent stuck in a restart loop.
- **App Manager**: uninstall apps together with their leftovers.
- **Disk Analyzer**: browse what takes space, and send items to review.
- **Homebrew** and **Maintenance** tools, plus **History** to undo past cleanups.

## Safety model

- Only Safe items are selected for you. Review items need you to tick them; Advanced items are report-only.
- Every path is re-checked against the same policy at cleanup time, not just at scan time.
- Items in use by a running process are skipped.
- Cleanup moves items to the Trash and records them, so History can put them back. The only
  permanent deletions are Maintenance actions such as Docker prune, which run the tool's own command.
- Some things are never touched: Docker's VM disk and volumes, Go's module and build caches, and
  your project folders themselves.

See [`docs/architecture/cleanup-safety.md`](docs/architecture/cleanup-safety.md) for the full model.

## Install

Download the latest `.dmg` from [Releases](https://github.com/yudgnahk/pare/releases), or use Homebrew:

```bash
brew install --cask yudgnahk/tap/pare
```

Builds are universal: Apple silicon and Intel Macs, macOS 13 or later.

Current builds are **ad-hoc signed and not notarized**, so macOS blocks the first launch:

1. Open the app once and dismiss the warning.
2. Go to **System Settings → Privacy & Security**, find "Pare was blocked", click **Open Anyway**.
3. Grant **Full Disk Access** when Pare asks, so it can read protected Library folders.

Only install builds from the official Releases page. See [`docs/distribution-adhoc.md`](docs/distribution-adhoc.md).

## Build from source

Requires macOS 13+ and Swift 5.9+ (Xcode or Command Line Tools).

```bash
make build      # compile
make run-app    # build, sign and launch the app
make test       # run tests (needs Xcode or a swift.org toolchain for XCTest)
make run PROFILE=developer   # command-line scan, for quick diagnostics
```

## License

Source code: [MIT](LICENSE). The Pare name, logo and icon are not covered by the license;
see [TRADEMARK.md](TRADEMARK.md). If you ship a fork, please give it a different name and icon.
