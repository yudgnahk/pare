# Pare 2026.10 — release candidate (ad-hoc signed, not notarized)

> This build is signed ad-hoc and is **not notarized** (no Apple Developer account yet).
> macOS will block the first launch — see "Install" below. Only install a copy you built yourself
> or downloaded from the official yudgnahk/pare release page.

## Highlights
- **Faster, lighter Smart Scan.** On the integration branch the full scan dropped from ~35 s to ~15 s warm (debug build), and peak memory from ~550–700 MB to ~120–145 MB. Projects are no longer discovered inside `$HOME` itself, app bundles, SDKs or toolchain trees; the Go module cache size is remembered for 24 h; results appear without the post-scan stall (#37, #71).
- **Safer cleanup.**
  - Build, `dist` and `target` folders are reclaimed only when git ignores them (#41); the git check now has a 20 s total deadline and fails closed (#72).
  - A folder that holds something Pare only reports, or never deletes (Go caches, protected app data, Docker VM disk), is never moved to the Trash as a whole (#39, #72).
  - Items another process has open are skipped (#50).
  - Go caches, OpenCode data and Google identity caches are never cleaned (#46, #49).
  - `brew cleanup`, uninstall and upgrade from the Homebrew tab no longer auto-remove formulae you did not see in the preview (`HOMEBREW_NO_AUTOREMOVE=1`) (#64, #74).
- **New findings for review:** old upgrade backups (#56), old app/runtime versions kept side by side (#57), unused pnpm store versions (#61), abandoned Codex staging folders (#59), SwiftPM `.build` and other hidden build caches (#44).
- **Diagnostics (explain-only):** deleted-but-open files and swap (#51), crash loops and runaway logs (#52), recent memory pressure (#53), launch agents in a restart loop (#55), folders of tiny files (#62).
- **App:** real space freed after cleanup (#54), purgeable/swap/snapshot breakdown in the disk meter (#60), "grew since last scan" (#66), cache activity labels (#67), clear warning when a scan stops early (#40, #58).

## Not in this build
- Reclaiming dependency folders (`node_modules`, `venv`…) of inactive projects (#69) ships **disabled** until its policy is decided (#68).

## Install
1. Open the DMG and drag **Pare** to Applications (or unzip the `.zip`).
2. Open Pare. macOS says it cannot verify the developer → click **Done**.
3. **System Settings → Privacy & Security**, scroll to "Pare was blocked…", click **Open Anyway**, confirm with your password.
4. Optional: grant **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access → add Pare), then quit and reopen Pare.

**After every update** of an ad-hoc build you must grant Full Disk Access again: macOS ties the permission to the app's code signature, and an ad-hoc signature changes with every build. Remove the old Pare entry first (select it, click –), then add the new app.

## Verify the download
`shasum -a 256 -c SHA256SUMS` in the folder with the zip/DMG.
