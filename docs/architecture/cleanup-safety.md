# Cleanup safety: how `CleanupEngine` decides

`CleanupEngine.clean` re-checks every finding at cleanup time, whatever the scan said. The first
gate that refuses wins. Order matters: an early refusal must never be undone by a later allow-list.

## Gate order (per item)

1. **User exclusions** (`ExclusionList.blocksRemoval`). Exclusions added after the scan still apply.
2. **Docker VM data** (`isDockerNeverDeletePath`): `Docker.raw` and `…/data/vms/…`. See `docs/features/docker-safety.md`.
3. **Never-clean** (`isNeverCleanPath`): Go build and module caches (plus the `go env` locations),
   OpenCode user data, Google identity caches. Runs before every allow-list, because project-artifact
   evidence would otherwise admit paths such as `go/pkg/mod/…/build`.
4. **Search-index stores** (`isSearchIndexSensitivePath`): deleting them forces a costly reindex.
5. **`.advanced` risk or the `.diagnostics` category**: report-only, whatever the label.
6. **Exclusive routing.** The first class that matches decides. Each class passes only through its own
   fail-closed predicate, never through the generic allow-lists:
   1. backup-named paths → `isReclaimableUpgradeBackup`
   2. version-sibling members → `isReclaimableVersionSibling` (one `ps` snapshot per batch; none = refuse)
   3. pnpm store or pnpm home → `isReclaimableOldPnpmStore` (active store re-resolved per batch) or wrong-platform
   4. dependency folders (`node_modules`, `venv`, `.venv`, `.bundle`) → `isReclaimableProjectDependency`
      with the tier re-read from free space, then git evidence (ignored and untracked, or not in a repo)
   5. Codex staging leftovers → allowed only while Codex and ChatGPT are not running
   6. everything else → `policyRejection`: project artifacts need a registered root and, for
      `build`/`dist`/`target`/`coverage`, git-ignore evidence; other paths must match a low-impact,
      persona, wrong-platform or installer allow-list.
7. **Still exists, no symlink component.**
8. **Minimum age** for the category. Unreadable dates refuse. Dependency folders skip it (project
   activity already decided) and so do wrong-platform paths (inert on macOS).
9. **In use** (one `lsof` snapshot per batch, re-taken after 30 s). Any open file at or under the path
   blocks it. Dependency folders check the whole project and refuse when no snapshot exists. Without a
   snapshot, other items fail closed only for `*.incomplete`, SQLite files under `Library/Caches` and
   caches of a running app; the result card then says the check was unavailable.
10. Symlink re-check, then Trash. The undo record is saved incrementally.

## Decisions behind the gates

- **Shape, not origin.** Version-sibling, backup, pnpm and dependency routing match on the path, not
  on which rule reported it. A mislabelled finding can only be refused, never widened.
- **Google and Mozilla cache prefixes are scan-time only.** `userCacheProtectedFolderPrefixes` keeps
  `com.google.*` / `org.mozilla.*` out of `UserCachesRule`. Promoting them to never-clean would break
  `ProductivityCachesRule`'s deliberate `com.google.drivefs.finderext` cleanup. The real hazards
  (`GIPPseudonymousID`, `CCTClearcutLogger`, rewritten at about 50 MB/s) are never-clean.
- **Native commands delete directly.** `CleanupEngine` always uses the Trash. Maintenance and Homebrew
  actions (`docker system prune -f`, `docker builder prune`, `brew cleanup`) run the tool's own
  command behind a fresh preview and a confirmation, with no Undo.
