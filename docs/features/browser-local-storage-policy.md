# Browser Local Storage & personal data policy

**Status:** binding product policy  
**Updated:** 2026-07-13  

## Summary

**Pare never includes browser Local Storage, cookies, history, or autofill in Quick Clean.**

Those paths may be shown as **REVIEW** findings so users can reclaim space deliberately. In the selective-clean UI they are **unchecked by default**.

## Why

| Store | Typical contents | Auto-delete risk |
|-------|------------------|------------------|
| **Local Storage** | Site data, PWA state, **session/auth tokens** for web apps | Forced logout, lost drafts, broken offline apps |
| **Cookies** | Session cookies, tracking IDs | Logout, lost preferences |
| **History / Web Data** | URLs, autofill | Privacy + form data loss |
| **IndexedDB** | App databases (often regenerable, sometimes not) | REVIEW — user choice |

Local Storage is **not** macOS Keychain, but it is **credential-adjacent**. Large browser reclaim comes primarily from **HTTP cache** and **Service Worker** caches—not from default-wiping Local Storage.

## What Pare cleans by default (SAFE)

- `~/Library/Caches/Google/Chrome/**` (and other browsers’ Cache trees)  
- Chromium **Service Worker** caches under Application Support profiles  
- Shader / GPU / Code caches that regenerate automatically  

## What stays REVIEW (default off in selection)

- Local Storage  
- Cookies  
- History  
- Autofill / Web Data  
- Sessions (session restore)  
- IndexedDB / WebSQL (when aged)  

## Implementation notes

- Rules: `BrowserCachesRule` (SAFE), `BrowserExtendedArtifactsRule` (SAFE + REVIEW), `BrowserReviewDataRule` (REVIEW).  
- `CleanupEngine.quickClean` only accepts `.safe`.  
- UI: selection defaults = all SAFE checked, all REVIEW unchecked.  

## User-facing copy (suggested)

> **Browser personal data** may sign you out of websites. Leave these unchecked unless you know you want them removed.
