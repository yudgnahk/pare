# Homebrew Manager

Lists formulae and casks, upgrades, uninstalls, migrates manually installed apps to Homebrew, detaches
casks, and runs `brew cleanup`. Code: `Sources/PareCore/Homebrew/`.

## Running `brew`

- GUI apps don't have `/opt/homebrew/bin` on `PATH`, so `BrewRunner` checks `/opt/homebrew/bin/brew`
  then `/usr/local/bin/brew`. No `uname`/`sysctl` needed.
- Every call sets `HOMEBREW_NO_AUTO_UPDATE=1` and `HOME`.
- stdout and stderr are read concurrently: `brew info --json=v2 --installed` exceeds the 64 KB pipe
  buffer and deadlocks a sequential read.

## Inventory and outdated

- One `brew info --json=v2 --installed` call. Formulae default to user-requested only
  (`installed_on_request`), with a toggle for dependencies.
- Outdated uses `brew outdated --json=v2 --greedy` so self-updating casks (`auto_updates: true`) stay
  visible, badged "(auto)". Pinned packages are never offered.

## Upgrade policy

- **Upgrade All runs plain `brew upgrade`, not `--greedy`.** Upgrading a self-updating cask swaps the
  bundle under a running app and can break its session. "Self-updating too" (`--greedy`) is opt-in
  behind a confirmation. Upgrade All counts only what plain `brew upgrade` touches.
- Uninstall never passes `--zap`.

## Review before mutations

Every mutating action, single row or bulk, opens a review sheet first: operation, packages, command,
and the restart warning for self-updating casks. Bulk runs go one item at a time and keep a
success/failure summary. Selection survives filtering and clears only when the inventory refreshes.

## Last Used

Casks show `kMDItemLastUsedDate` of the matched app: "Never" when missing, "Orphaned" when no app is
matched. Formulae have no Last Used on purpose: Homebrew keeps no reliable execution history, and Pare
does not guess from shell history or file dates.

## Migrate to Homebrew

`MigrationAdvisor` matches installed apps against `https://formulae.brew.sh/api/cask.json` (24-hour
disk cache) by artifact app name, then by bundle IDs in `uninstall[].quit`, skipping apps Homebrew
already manages. Migration runs `brew install --cask --adopt <token>`, which takes over the existing
app without reinstalling it.

## Leave Homebrew

The inverse of adopt: stop Homebrew managing a cask but keep the app, so a terminal
`brew upgrade --greedy` can't replace it. `CaskLeaveHomebrew` refuses while the app runs (or
force-quits after confirmation), stages the `.app` aside, runs `brew uninstall --cask` (never `--zap`)
and puts the app back. Orphaned casks only get the uninstall. Per cask only, never bulk.

## `brew cleanup`

`BrewCleanup` previews with `brew cleanup -n` and runs only after confirmation. Before running it
re-runs the preview and refuses when nothing is left. Never `--prune=all`, never sudo. It deletes
directly, not through the Trash, and has no Undo: Homebrew owns those files, and moving kegs behind
its back would leave stale links.
