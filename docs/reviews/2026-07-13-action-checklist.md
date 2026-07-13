# Pare — Action Checklist (from 2026-07-13 review)

Use this as a working checklist. Details live in [2026-07-13-full-project-review.md](./2026-07-13-full-project-review.md).

**Legend:** `[ ]` open · `[x]` done · `[~]` partial / in working tree only

---

## P0 — Must fix before trusting a release

- [~] **H1 / Docker policy** Sparse Docker.raw + advanced excluded from reclaimable totals + never-delete path + prune without `--volumes`  
  - Working tree fixed; **not committed**  
  - Spec: `docs/features/docker-safety.md`  
  - Verify: total ≪ disk size; Docker.raw is `[ADVANCED]` not in reclaimable; clean of `.safe`-mislabeled Docker.raw path is skipped; Maintenance args `system prune -f` only
- [~] **H2** Spotlight project discovery hang  
  - Working tree fixed; **not committed**  
  - Verify: developer/app scan completes; no “continuation leaked” log
- [ ] **H3** Fix 2 failing tests  
  - `testBaselineRuleIncludesKnownRules` (expects 8, actual 12)  
  - `testDeveloperRuleCatalogIncludesPersonaRules` (expects `docker-logs-review-required`)  
  - Goal: `make test` green
- [ ] Re-run full smoke: `make build` · `make test` · `make run-app` (scan → results → cancel once)

---

## P1 — Trust & product clarity

### Scan UX
- [ ] Real scan progress (rule name + index/count, or streaming partial results)
- [ ] Update CHANGELOG: remove or reword “real-time progress”
- [ ] Soften Top files / By Tool for `.advanced` (separate section or default filter)

### Project roots / artifacts
- [ ] Decide single model: Phase 5 manual paths **or** Phase 6 Spotlight (or merge stores)
- [ ] Remove or re-home dead UI: `ProjectRootsView.swift`, `ProjectRootsViewModel.swift`
- [ ] If roots need management: Settings sheet, not main Scan dashboard
- [ ] Clarify header “folder+” button (currently Phase 5 only)

### Catalog hygiene
- [ ] Register `DockerLogsReviewRequiredRule` **or** delete/archive it and fix tests
- [ ] Align docs rule counts: CHANGELOG / CLAUDE / checklist vs `RuleCatalog.all`

---

## P2 — Hardening & polish

- [ ] Fix `AppInventory` Spotlight double-resume race (finished flag)
- [ ] In-app Full Disk Access guidance if scans look empty
- [ ] Rename `CleanMyMacApp.swift` → `PareApp.swift` (or similar)
- [ ] Refresh AppInfo copyright year
- [ ] Sync roadmap checkboxes with reality (bundle id, rule counts)
- [ ] Cap or prioritize huge root sets (~500 roots) for artifact walks
- [ ] Consider excluding advanced sizes from “Large files by category” totals or label clearly

---

## P3 — Performance & architecture

- [ ] Safe parallel rule execution (replace sequential loop carefully)
- [ ] Directory-level rollups for huge cache trees where file-level findings add noise
- [ ] Measure cold vs warm scan with cache; document expected times

---

## P4 — Distribution (Phase 9)

- [ ] Developer ID Application signing (keychain)
- [ ] Run `make release` end-to-end (sign → DMG → notarize → staple)
- [ ] Gatekeeper test on a clean Mac / fresh user
- [ ] GitHub Release `v1.0.0` with signed DMG
- [ ] Manual matrix: macOS 13 / 14 / 15 (roadmap still open)

---

## Doc / claim cleanup (quick wins)

- [ ] CHANGELOG: rule count; drop Project Roots card claim if UI stays removed
- [ ] CLAUDE.md: rule count (~36 registered, not 20)
- [ ] checklist.md: remove “profile selector UI” if app has none
- [ ] Mark always-on “coverage ≥ 80%” as measured or aspirational

---

## Commit grouping suggestion (when you choose to commit)

| PR / commit | Contents |
|-------------|----------|
| **scan-correctness** | Spotlight hang + sparse size + advanced totals + tests |
| **dashboard-hygiene** | Project Roots removed from Scan (already in tree) |
| **catalog-tests** | Fix H3 catalog assertions; docker-logs rule decision |
| **dead-code** | Delete orphaned Project Roots UI / unused rule if decided |

Do **not** mix Phase 9 release machinery with scan fixes unless you want a large review surface.

---

## Verification commands

```bash
make build
make test
# After H1/H2:
.build/debug/pare-cli --profile developer --top 10
# Expect: Total reclaimable on the order of GBs, not TB
make run-app
```

---

## Sign-off

| Check | Owner | Date |
|-------|-------|------|
| P0 complete | | |
| P1 complete | | |
| Ready for notarized beta | | |
| Ready for public v1.0 | | |
