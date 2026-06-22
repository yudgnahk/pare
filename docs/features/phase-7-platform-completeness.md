# Phase 7 — Platform Completeness

Close three specific gaps where App A covers ground Pare doesn't: Docker storage visibility, iOS backup management, and browser data beyond render caches.

## Goals

- Surface Docker's full storage footprint (can't safely delete the VM image; expose it and give a safe cleanup action)
- Detect old iPhone/iPad backups with device-level attribution
- Scan browser history, cookies, and form data as review-risk items alongside existing cache rules

---

## Part 1 — Docker Full Cleanup

### The Constraint

Docker Desktop on Apple Silicon stores all container data inside a single VM disk image:
```
~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
```
This file can grow to 10–60 GB. It **cannot** be safely deleted by path — doing so destroys all Docker images, containers, and volumes. The only safe way to reclaim Docker storage is to run `docker system prune` while Docker is running.

### DockerStorageRule

Replaces or extends the existing `DockerLogsRule`.

**Safe-to-delete paths (add to existing rule):**

| Path | Contents | Risk |
|------|----------|------|
| `~/Library/Containers/com.docker.docker/Data/log/` | Docker Desktop daemon logs | `.safe` |
| `~/Library/Containers/com.docker.docker/Data/lifecycle-server.log*` | Lifecycle log files | `.safe` |
| `~/Library/Group Containers/group.com.docker/log/` | Docker Desktop UI logs | `.safe` |

**Detect-only (`.advanced`) path:**

| Path | Contents | Risk |
|------|----------|------|
| `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | VM disk image | `.advanced` |

Report `Docker.raw` as a single `.advanced` finding. The size can be large (10–60 GB), making it worth surfacing in the "Large Files" card. Reason: "Docker VM disk image — use 'docker system prune' to reclaim space safely."

`CleanupEngine` hard-blocks `.advanced` findings from deletion, so this is purely informational.

### Maintenance Tab Integration (Phase 8)

The practical cleanup action — `docker system prune -f` — lives in the Maintenance tab (see Phase 8). The scan result for `Docker.raw` links to it: "Run Docker system prune in Maintenance tab →".

---

## Part 2 — iOS / iPadOS Backup Management

iPhone and iPad backups are stored locally when the user syncs with Finder (or the old iTunes). A user who has upgraded devices over several years can accumulate 3–5 outdated backups totalling 50–200 GB.

### MobileSyncBackupsRule

Uses `customScan`.

**Scan location:**
```
~/Library/Application Support/MobileSync/Backup/
```
Each subdirectory is one backup, named with a UUID-like identifier.

**Per-backup metadata (from `Info.plist` inside each backup directory):**

| Key | Field |
|-----|-------|
| `Display Name` | Device name (e.g. "Kelvin's iPhone 15") |
| `Product Name` | iOS device model |
| `Product Version` | iOS version at backup time |
| `Last Backup Date` | Backup timestamp |
| `Serial Number` | Device serial (used as stable device ID) |

If `Info.plist` is absent or unreadable, fall back to the directory name as the identifier.

**Findings logic:**

1. Group backups by `Serial Number` (same device, multiple backups).
2. Within a group, sort by `Last Backup Date` descending.
3. The most-recent backup for each device is never flagged.
4. Any backup that is **not** the most recent AND is older than 30 days → flag as `.review`.
5. If a device has only one backup and it is older than 180 days → flag as `.review` with reason "Only backup is 6+ months old — consider making a fresh backup before deleting."

**Finding per backup:**
- Path: the backup directory
- Category: `DeviceBackups` (new category, icon: `iphone`)
- Risk: `.review` (never `.safe` — personal data)
- Reason: device name + backup date + size
- Confidence: 0.90

### New Scan Category

Add `deviceBackups` to the `ScanCategory` enum:
- Display name: "Device Backups"
- Color: system indigo (distinct from existing categories)
- Register in `ScanReportAnnotator.appRollups` attribution as the source app "Finder" or "MobileSync"

### UI

A "Device Backups" card appears in the Scan tab results section when any backup findings exist. It shows per-device rows with:
- Device name and iOS version
- Backup date
- Size
- "Keep / Discard" toggle (maps to the exclusion list vs. quick clean)

---

## Part 3 — Browser Review Data

The existing `BrowserCachesRule` covers render and GPU caches only. This part adds a separate rule for personal browser data (history, cookies, form data, local storage) at `.review` risk.

### BrowserReviewDataRule

**Targets per browser:**

#### Safari
| Path | Contents |
|------|----------|
| `~/Library/Safari/History.db` | Browsing history |
| `~/Library/Safari/Cookies.binarycookies` | Cookies |
| `~/Library/Safari/Databases/` | WebSQL databases |
| `~/Library/Safari/LocalStorage/` | LocalStorage / IndexedDB |

#### Chrome (and Chromium-based: Brave, Arc, Edge, Opera)
Base path for each browser (see table below). Within each profile directory:
| Relative Path | Contents |
|---------------|----------|
| `Default/History` | Browsing history |
| `Default/Cookies` | Cookies |
| `Default/Web Data` | Autofill form data |
| `Default/IndexedDB/` | IndexedDB |
| `Default/databases/` | WebSQL |

Browser base paths:
| Browser | Path |
|---------|------|
| Chrome | `~/Library/Application Support/Google/Chrome/` |
| Brave | `~/Library/Application Support/BraveSoftware/Brave-Browser/` |
| Edge | `~/Library/Application Support/Microsoft Edge/` |
| Arc | `~/Library/Application Support/Arc/` |
| Opera | `~/Library/Application Support/com.operasoftware.Opera/` |

#### Firefox
| Path | Contents |
|------|----------|
| `~/Library/Application Support/Firefox/Profiles/*/places.sqlite` | History + bookmarks |
| `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite` | Cookies |
| `~/Library/Application Support/Firefox/Profiles/*/webappsstore.sqlite` | LocalStorage |
| `~/Library/Application Support/Firefox/Profiles/*/indexedDB/` | IndexedDB |

**Rule properties:**
- Risk: `.review` for all targets (personal data; user must confirm via Deep Clean)
- Minimum age gate: 30 days — don't surface data from current browsing sessions
- Confidence: 0.88
- Category: `browserCaches` (shares the existing category; they are complementary)

**Separation from BrowserCachesRule:**

`BrowserCachesRule` remains `.safe` and is unchanged. `BrowserReviewDataRule` is a distinct rule so they can be controlled independently. A user who wants to clean browser caches automatically (Quick Clean) can do so without being forced to also review their history and cookies.

---

## Architecture

```
Sources/PareCore/
  Rules/
    DockerStorageRule.swift          # extends DockerLogsRule; adds .advanced Docker.raw detection
    MobileSyncBackupsRule.swift      # customScan; Info.plist parsing; device grouping
    BrowserReviewDataRule.swift      # .review browser personal data

  Models/
    ScanCategory.swift               # add .deviceBackups case
```

---

## Test Plan

| Test | What it verifies |
|------|-----------------|
| `DockerStorageRuleTests` — Docker.raw detected | `.advanced` finding emitted with correct path |
| `DockerStorageRuleTests` — log paths are safe | Log directory findings are `.safe` |
| `MobileSyncBackupsRuleTests` — most-recent not flagged | Only older backups emit findings |
| `MobileSyncBackupsRuleTests` — age gate | Backup < 30 days since last backup not flagged |
| `MobileSyncBackupsRuleTests` — single old backup | One backup > 180 days emits `.review` with advisory reason |
| `MobileSyncBackupsRuleTests` — missing Info.plist | Falls back to directory name gracefully |
| `BrowserReviewDataRuleTests` — Safari paths | History.db, Cookies emitted as `.review` |
| `BrowserReviewDataRuleTests` — age gate | Files < 30 days old not emitted |
| `BrowserReviewDataRuleTests` — only installed browsers | Non-existent browser paths produce no findings |
| `BrowserReviewDataRuleTests` — distinct from BrowserCachesRule` | `.safe` and `.review` findings are separate rules |
