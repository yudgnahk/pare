# Homebrew Manager Feature

Manage all Homebrew casks and formulae: list, update, upgrade, uninstall, and recommend migrating existing apps to Homebrew.

## Goals

- Show all installed casks and formulae with metadata
- One-click upgrade for outdated packages (including `auto_updates: true` casks)
- Multi-select bulk uninstall for casks
- Detect orphaned casks (Homebrew record exists but app already deleted from disk)
- Detect pkg-based casks that need admin privileges to uninstall
- Recommend migrating manually-installed macOS apps to Homebrew casks

---

## Process Execution

### Finding the binary

`PATH` in GUI apps does not include `/opt/homebrew/bin`. Detect the prefix explicitly:

```swift
// BrewRunner.init()
if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
    brewPath = "/opt/homebrew/bin/brew"   // Apple Silicon
} else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
    brewPath = "/usr/local/bin/brew"      // Intel
} else {
    brewPath = nil
}
```

### Pipe deadlock prevention

`brew info --json=v2 --installed` JSON output exceeds the ~64 KB macOS pipe buffer.
Sequential `waitUntilExit()` + `readDataToEndOfFile()` deadlocks. The fix:

- Drain both pipes on `DispatchQueue.global` OS threads (not the Swift cooperative pool)
- Use `terminationHandler` instead of `waitUntilExit()` so blocking reads never starve the runtime
- Set `standardInput = FileHandle.nullDevice` so brew never becomes the foreground process group and intercepts keystrokes

### Streaming output

`BrewRunner.stream(_:)` yields lines from both stdout and stderr as they arrive via `AsyncThrowingStream`, using `FileHandleForReading.bytes.lines` inside a `withTaskGroup`.

### Privileged execution for pkg-based casks

Homebrew refuses to run as root (`"Running Homebrew as root is extremely dangerous"`), so `osascript` with `with administrator privileges` cannot be used — brew exits immediately.

Instead, `BrewRunner.streamPrivileged(_:password:)`:

1. Creates a temporary directory with a `sudo` wrapper script (permissions `0o700`):
   ```sh
   #!/bin/sh
   printf '%s\n' 'PASSWORD' | /usr/bin/sudo -S "$@"
   ```
2. Prepends the temp dir to `PATH` — brew finds this wrapper before `/usr/bin/sudo`
3. Streams brew output normally; brew runs as the current user
4. Deletes the temp dir via `defer` when the stream closes

The password is never written to a persistent location.

---

## Discovery

### All installed packages

```
brew info --json=v2 --installed
```

Returns a single JSON blob with `formulae` and `casks` arrays.

Key formula fields: `name`, `desc`, `installed[].version`, `installed[].installed_on_request`, `installed[].time`, `pinned`, `dependencies`

Key cask fields: `token`, `version`, `auto_updates`, `installed_time`, `artifacts`

### Orphaned cask detection

A cask is **orphaned** when Homebrew records it as installed but the app is no longer on disk (deleted manually without `brew uninstall --cask`).

Two artifact formats require different detection strategies:

**App-based casks** (`artifacts[].app[]`): check each app name in `/Applications`, `~/Applications`, `/System/Applications`.

**Pkg-based casks** (no `app` artifact; Microsoft Teams, TeamViewer, etc.): the installed `.app` path appears in `artifacts[].uninstall[].delete[]`. Check those full paths directly.

```swift
// BrewInventory.isOrphaned(appNames:directPaths:searchDirs:)
if !directPaths.isEmpty {
    return !directPaths.contains { FileManager.default.fileExists(atPath: $0) }
}
guard !appNames.isEmpty else { return false }
return !appNames.contains { appName in
    searchDirs.contains { dir in
        FileManager.default.fileExists(atPath: "\(dir)/\(appName)")
    }
}
```

### `requiresSudo` detection

A cask requires sudo if its uninstall stanza contains:
- `pkgutil` entries (`pkgutil --forget` needs root to modify the package receipt database)
- `delete` paths starting with `/Library/` (system directories, not `~/Library/`)

Detected at parse time in `BrewInventory.parseCasks`; stored as `BrewCask.requiresSudo`.

---

## Outdated Detection

```
brew outdated --json=v2 --greedy
```

`--greedy` is mandatory — without it, `auto_updates: true` casks (Chrome, VS Code, Slack, etc.) are excluded. We show all packages with a newer version available regardless.

---

## Operations

### Upgrade

```swift
runOperation(label: "…", args: ["upgrade", name])            // formula
runOperation(label: "…", args: ["upgrade", "--cask", token]) // cask
runOperation(label: "…", args: ["upgrade", "--greedy"])      // all
```

### Uninstall (standard)

```swift
runOperation(label: "…", args: ["uninstall", name])
runOperation(label: "…", args: ["uninstall", "--cask", token])
```

### Uninstall (requires sudo)

When `cask.requiresSudo` is true:
1. `PasswordPromptSheet` is shown (SecureField, auto-focused)
2. On confirm: `runPrivilegedOperation(label:args:password:)` calls `BrewRunner.streamPrivileged`
3. Live output streams into `BrewOperationSheet` as normal

### Bulk uninstall (multi-select)

Users can check any number of cask rows. A selection bar shows count + "Uninstall N Casks". The batch runs as one `brew uninstall --cask token1 token2 …` command. If any selected cask has `requiresSudo`, the whole batch goes through the privileged path — one password prompt for all.

### Migrate to Homebrew

```swift
runOperation(label: "…", args: ["install", "--cask", "--adopt", token])
```

`--adopt` (Homebrew 3.5+) takes ownership of an already-installed app without re-downloading.

---

## Migration Advisor

1. Fetch `https://formulae.brew.sh/api/cask.json` — 24-hour on-disk cache
2. Match by bundle ID first (`artifacts[].uninstall[].quit`), then by app name (`artifacts[].app[]`)
3. Exclude apps already managed by Homebrew
4. Deduplicate by cask token; exclude generic component names

---

## UI Details

### Tab picker

Uses plain `Button` views instead of `Picker(.segmented)`. `NSSegmentedControl` (the underlying AppKit control) auto-grabs macOS keyboard focus and swallows keystrokes before `TextField` sees them, breaking the search field.

### Cask badges

| Badge | Condition |
|-------|-----------|
| `orphaned` (amber) | App bundle not found on disk |
| `admin` (muted) | `requiresSudo == true` |
| `auto` (accent) | `autoUpdates == true` |

Orphaned casks sort to the top and receive an amber row background. The "Orphaned only" filter toggle is disabled only when count == 0 AND the toggle is already off.

### Selection state

`HomebrewManagerViewModel.selectedCaskTokens: Set<String>` tracks checked rows. `allFilteredCasksSelected` drives the header checkbox. Selection clears on operation dismiss.

---

## Architecture

```
Sources/PareCore/Homebrew/
  BrewRunner.swift              # Process wrapper, privileged execution
  BrewInventory.swift           # Discovery actor
  BrewOutdatedChecker.swift     # Outdated detection
  MigrationAdvisor.swift        # Cask catalog fetch + matching
  Models/
    BrewFormula.swift
    BrewCask.swift              # isOrphaned, requiresSudo
    BrewOutdatedPackage.swift
    MigrationCandidate.swift

Sources/PareApp/
  ViewModels/HomebrewManagerViewModel.swift
  Views/HomebrewManagerView.swift   # + PasswordPromptSheet, BrewOperationSheet
```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Homebrew not installed | Check `brewPath != nil`; show placeholder with install link |
| Pipe deadlock on large JSON | `DispatchQueue` drain + `terminationHandler`; never `waitUntilExit()` before reading |
| NSSegmentedControl steals focus | Custom Button-based tab picker |
| `brew` run as root fails | `streamPrivileged` keeps brew as current user; only internal `sudo` calls are intercepted |
| Password exposure | Temp wrapper deleted by `defer`; password never persisted |
| Orphaned detection misses pkg casks | `uninstall[].delete[]` paths checked directly for casks without `app` artifacts |
| `--adopt` requires Homebrew ≥ 3.5 | Released 2022 — safe assumption for current installs |
