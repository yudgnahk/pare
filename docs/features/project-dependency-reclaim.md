# Project dependency reclaim

`ProjectDependenciesRule` offers `node_modules`, `venv`, `.venv` and `.bundle` of idle projects as
`.review` findings. CLAUDE.md describes the rule; this page keeps the reasons behind it.

## Why

On 2026-09-30 the maintainer's Mac was 98 % full (4.0 GB free of 228 GB). Deleting three SwiftPM
`.build`, three `.venv` and two `node_modules` folders by hand freed 11 GB, and Pare reported none of
them. `.build` is now a project artifact (#44). Dependency folders had been excluded on purpose,
because removing one breaks the project until a reinstall, so they return only behind a strict gate.

## Rules and why each exists

- **Lockfile required.** Restore must be exact. On 2026-10-07, 15 of 16 real dependency folders had
  a lockfile; manifest-only adds no bytes and is the one case where a reinstall can drift.
- **Project activity, never the folder's own mtime.** The folder mtime is the install date:
  `serena/.venv` was 461 days old in a project touched 51 days ago. Activity is the newest of the git
  markers (`index`, `logs/HEAD`, `FETCH_HEAD`) and every file edit under the project, skipping
  dependency and build folders. A walk that runs out of budget counts as active.
- **Git markers follow worktrees and enclosing repos.** In a worktree `.git` is a file, so activity
  follows `gitdir:`. Nested projects without their own `.git` use the enclosing repo's markers, so an
  active monorepo protects all its sub-projects.
- **Pressure tiers 14 / 7 / 3 days, never under 72 hours.** Low is below 15 % or 25 GB free, critical
  below 5 % or 10 GB. On a 245 GB disk the percentages bind. Every finding is `.review` and never
  preselected, so a lower threshold costs at most one unchecked row.
- **Minimum size 1 MB.** pnpm workspace members are 0–3 MB symlink farms and test fixtures are empty.
- **Never under a `Library` component or inside a `.app`.** App data and bundled runtimes (for example
  `actions-runner/externals/node20/lib/node_modules`) carry their own dependency folders.
- **Git evidence at cleanup.** A tracked or unignored folder may be vendored on purpose, so only
  ignored-and-untracked or not-in-a-repo folders are trashed.
- **In-use check on the whole project.** A dev server's cwd sits in the project, not in the
  dependency folder. With no open-file snapshot the folder is held back.

## Restore commands shown

`pnpm install`, `yarn install`, `bun install`, `npm ci` (Node); `uv sync`, `poetry install`,
`pipenv install` (Python); `bundle install` (Ruby). Mapped from the lockfile in
`ScanPolicy.projectDependencyRestoreCommands`.

## Not built yet

See the Phase 12 open items in `docs/roadmap.md`: broken venvs, manifest-only projects with a drift
warning, a "Save package list" export, and an empty-the-Trash reminder at critical pressure.
