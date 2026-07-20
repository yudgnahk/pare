# Homebrew Manager Feature

Manage all Homebrew casks and formulae: list, update, upgrade, uninstall, and recommend migrating existing apps to Homebrew.

## Goals

- Show all installed casks and formulae with metadata
- One-click upgrade for outdated packages (including `auto_updates: true` casks)
- Uninstall with optional `--zap` (removes user data)
- Recommend migrating manually-installed macOS apps to Homebrew casks

---

## Homebrew Process Execution

### Finding the binary

`PATH` in GUI apps does not include `/opt/homebrew/bin`. Detect the prefix explicitly:

```swift
func homebrewPrefix() -> String {
    // Apple Silicon
    if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
        return "/opt/homebrew"
    }
    // Intel
    return "/usr/local"
}

var brewPath: String { homebrewPrefix() + "/bin/brew" }
```

Do NOT run `uname -m` or call `sysctl` from Swift — just check both paths. The first one that exists wins.

### Process wrapper

Every `brew` invocation must:

1. Set `HOMEBREW_NO_AUTO_UPDATE=1` to prevent auto-update hijacking the output
2. Set `HOME` explicitly (may be missing in sandboxed contexts)
3. Read stdout and stderr **concurrently** — macOS pipe buffer is ~64 KB; `brew info --installed` JSON easily exceeds this and will deadlock if you call `readDataToEndOfFile()` sequentially

```swift
func runBrew(_ args: [String]) async throws -> (stdout: Data, stderr: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: brewPath)
    process.arguments = args
    process.environment = [
        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        "PATH": "\(homebrewPrefix())/bin:/usr/bin:/bin",
        "HOMEBREW_NO_AUTO_UPDATE": "1",
    ]
    let outPipe = Pipe(), errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    try process.run()

    // Read concurrently to avoid pipe-buffer deadlock
    async let outData = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }.value
    async let errData = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }.value
    process.waitUntilExit()
    return try await (outData, errData)
}
```

---

## Discovery

### All installed packages

```
brew info --json=v2 --installed
```

Returns a single JSON blob with `formulae` and `casks` arrays. Parse once; all metadata is in-band.

Key fields per formula:
- `name`, `full_name`, `version` (installed), `desc`, `homepage`
- `installed[].installed_on_request` — true = user-installed, false = dependency
- `installed[].time` — ISO8601 install timestamp
- `keg_only` — whether it's in the PATH or not

Key fields per cask:
- `token`, `version`, `desc`, `homepage`
- `installed` (version string or null)
- `auto_updates` — if true, the app self-updates; `brew outdated` skips it by default
- `artifacts` — contains `app` entries with the `.app` names installed to `/Applications`

---

## Outdated Detection

```
brew outdated --json=v2 --greedy
```

`--greedy` is mandatory — without it, casks with `auto_updates: true` (Chrome, VS Code, Slack, etc.) are excluded. We want to show all packages that have a newer version available, even if the app auto-updates itself.

Response fields per outdated entry:
- `name` / `cask` token
- `installed_versions` — array of currently installed versions
- `current_version` — latest available version
- `pinned` — if true, the user has pinned this version; do not offer upgrade

---

## Operations

### Upgrade

```swift
// Single package
try await runBrew(["upgrade", name])                    // formula
try await runBrew(["upgrade", "--cask", token])          // cask

// Upgrade All (default) — formulae + non-auto casks only
// Does NOT pass --greedy, so auto_updates casks (Chrome, VS Code, …) are skipped.
try await runBrew(["upgrade"])

// Optional “self-updating too” (confirm first) — may break open app sessions
try await runBrew(["upgrade", "--greedy"])
```

Outdated discovery still uses `brew outdated --json=v2 --greedy` so self-updating casks remain visible and labeled `auto`. Upgrade All counts only packages Brew will actually touch without `--greedy`.

Show live output in a streaming log sheet (pipe to a `@Published var log: String`).

### Uninstall

```swift
// Formula
try await runBrew(["uninstall", name])

// Cask — without user data
try await runBrew(["uninstall", "--cask", token])

// Cask — with user data (zap stanza)
try await runBrew(["uninstall", "--cask", "--zap", token])
```

Always ask before `--zap`. Show a confirmation sheet listing what the zap stanza will remove (fetch from `brew info --cask --json=v2 <token>`, parse `artifacts[].zap`).

### Leave Homebrew (detach, keep app)

Inverse of Migrate / `--adopt`. Stops Brew from managing a cask without deleting the application — so terminal `brew upgrade --greedy` cannot replace the bundle.

```swift
// Implemented by CaskLeaveHomebrew:
// 1. Resolve app paths under /Applications and ~/Applications
// 2. Refuse if running (or force-quit when confirmed)
// 3. Stage .app copy aside
// 4. brew uninstall --cask <token>   // never --zap
// 5. Restore .app to original path
```

Orphaned casks (receipt, no app): only step 4. UI: per-cask **Leave Homebrew** with confirmation.
### Hide dependencies

By default show only user-requested formulae (`installed_on_request: true`). Provide a toggle to show all (including dependencies).

---

## Migrate to Homebrew

Recommend that manually-installed apps (discovered by App Manager) can be managed by Homebrew.

### Matching algorithm

1. Fetch full cask catalog: `https://formulae.brew.sh/api/cask.json` (cache for 24 h)
2. For each cask, extract app name from `artifacts[].app[]` values (e.g. `"Visual Studio Code.app"`)
3. For each installed app (from App Manager), match against cask artifact names
4. Secondary match: compare cask bundle IDs — each cask's `artifacts[].uninstall[].quit` values contain bundle IDs; match against the installed app's `CFBundleIdentifier`
5. Filter out apps already installed via Homebrew (check `$(brew --caskroom)/<token>/` exists)

### Recommendation UI

Show a "Move to Homebrew" section in the Homebrew Manager. Each row:
- App name + current version
- Matched cask token + Homebrew version
- "Migrate" button → runs: `brew install --cask <token>` (Homebrew installs the new copy, then `brew uninstall` removes the old one if you used `--adopt` flag)

```swift
// Adopt the already-installed app into Homebrew management without reinstalling
try await runBrew(["install", "--cask", "--adopt", token])
```

`--adopt` (Homebrew 3.5+) tells Homebrew to take ownership of an already-installed app without re-downloading it. This is the preferred migration path.

---

## Architecture

New module: `Sources/PareCore/HomebrewManager/`

```
HomebrewManager/
  BrewRunner.swift            # Process wrapper, prefix detection
  BrewInventory.swift         # Discovery (actor)
  BrewOutdatedChecker.swift   # Outdated detection
  MigrationAdvisor.swift      # Cask catalog fetch + app matching
  Models/
    BrewFormula.swift         # Decoded from brew info JSON
    BrewCask.swift
    OutdatedPackage.swift
    MigrationCandidate.swift  # installedApp + matchedCask
```

---

## SwiftUI Integration

Tab alongside App Manager. Split view:
- Left sidebar: Formulae / Casks / Outdated / Migrate (segments)
- Right: package list with sort/filter

`HomebrewManagerViewModel` (`@MainActor ObservableObject`) — same ViewModel pattern as `ScanDashboardViewModel`.

Operations (upgrade/uninstall/migrate) open a `BrewOperationSheet` showing streaming log output.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Homebrew not installed | Check `brewPath` exists before any operation; show "Homebrew not installed" placeholder with install instructions |
| Pipe deadlock on large JSON | Always read stdout + stderr concurrently (see process wrapper above) |
| `--adopt` requires Homebrew ≥ 3.5 | Check `brew --version` at startup; fall back to standard install + manual trash if older |
| Cask catalog fetch fails (offline) | Cache previous response; show "Last updated X ago" and proceed with cached data |
| `--zap` deletes too much | Always preview zap artifacts before confirming; never zap without explicit user confirmation |
| Auto-updating apps show false positives | Respect `pinned: true` in outdated results; mark `auto_updates: true` casks with an "(auto)" badge |
| Sandbox restrictions | `PareApp` is not sandboxed (disk access required). Ensure entitlements include `com.apple.security.temporary-exception.files.home-relative-path.read-write` if notarizing |
