# Phase 7 — Platform Completeness

Docker storage, iOS backups, and browser data beyond render caches.

## Docker

`Docker.raw` is a sparse VM disk holding every image, container and volume. It is never a scan
finding and never deleted by path. `DockerStorageRule` reports only aged Docker Desktop logs (`.safe`):

- `~/Library/Containers/com.docker.docker/Data/log/`
- `~/Library/Group Containers/group.com.docker/log/`

Reclaim goes through Maintenance (`docker system prune -f`, `docker builder prune` by age). Binding
policy: [`docker-safety.md`](./docker-safety.md).

## iOS / iPadOS backups — `MobileSyncBackupsRule`

Scans `~/Library/Application Support/MobileSync/Backup/` (one folder per backup) and reads each
`Info.plist` for device name, model, iOS version, last backup date and serial number. With no
readable `Info.plist`, the folder name is the identifier.

- Backups are grouped by serial number. The newest backup of each device is never flagged.
- Any older backup over 30 days old is `.review`.
- A device's only backup is flagged once it is over 180 days old, advising a fresh backup first.
- Category `.deviceBackups`, always `.review` (personal data), confidence 0.90.
- The Scan tab shows a Device Backups card: device, iOS version, date, size.

## Browser review data — `BrowserReviewDataRule`

History, cookies, form data, local storage, IndexedDB and WebSQL, kept separate from the `.safe`
`BrowserCachesRule` so Quick Clean never touches personal data. Always `.review`, 30-day minimum age,
category `.browserCaches`, confidence 0.88. See also [`browser-local-storage-policy.md`](./browser-local-storage-policy.md).

| Browser | Targets |
|---|---|
| Safari | `~/Library/Safari/History.db`, `Cookies.binarycookies`, `Databases/`, `LocalStorage/` |
| Chromium (Chrome, Brave, Edge, Arc, Opera) | per profile: `History`, `Cookies`, `Web Data`, `IndexedDB/`, `databases/` |
| Firefox | per profile: `places.sqlite`, `cookies.sqlite`, `webappsstore.sqlite`, `indexedDB/` |

Chromium base folders under `~/Library/Application Support/`: `Google/Chrome`,
`BraveSoftware/Brave-Browser`, `Microsoft Edge`, `Arc`, `com.operasoftware.Opera`.
