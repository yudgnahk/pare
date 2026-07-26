# UV Cache Investigation

**Date:** 2026-07-25  
**Machine:** Kelvin’s macOS (arm64)  
**uv version:** 0.11.32 (Homebrew)  
**Context:** Comparing how Mole and Pare treat `~/.cache/uv` (~20 GB), and what actually fills that space.

---

## Summary

| Question | Answer |
|----------|--------|
| Is `~/.cache/uv` ≈ 20 GB real? | **Yes** (`du` ≈ 20G; `uv cache size` ≈ 21.2e9 bytes) |
| Is this uv’s real cache dir? | **Yes** — `uv cache dir` → `/Users/kelvin/.cache/uv` |
| Does `~/Library/Caches/uv` exist? | **No** (Pare’s current target only) |
| What dominates size? | **`archive-v0` (~19 GB)** — mostly full tool environments |
| Root package driver | **`tree-sitter-language-pack`** via **`code-review-graph`** |
| How Mole treats it | Finds path via CLI; cleans with `uv cache prune` only; dry-run shows no size |
| How Pare treats it today | **Misses it** — only scans `~/Library/Caches/uv` |

---

## 1. Measured layout

### Top-level (`~/.cache/uv`)

| Path | Size | Role |
|------|------|------|
| `archive-v0/` | **~19 GB** | Unpacked archives + **relocatable tool envs** |
| `binaries-v0/` | ~119 MB | Tool binaries (mostly **ruff**) |
| `simple-v20` … `simple-v24` | ~100 MB total | PyPI “simple” index metadata (format versions) |
| `wheels-v*`, `sdists-v*`, `interpreter-v*` | small | Wheels / sdists / interpreter metadata |
| `environments-v2/`, `builds-v0/` | empty / tiny | Other uv cache buckets |

### `archive-v0` classification (386 entries)

| Kind | Count | Size | Marker |
|------|------:|-----:|--------|
| **Full Python envs** | **43** | **~18 GB** | `pyvenv.cfg` present (`relocatable = true`) |
| **Package extracts** | 343 | ~1.1 GB | `*.dist-info` package trees |
| Other | 0 | 0 | — |

Almost all of the 20 GB is **not** “one big mystery file.” It is **~43 near-duplicate virtualenvs** cached under content-hash directory names.

### Sample large env (~461 MB)

Path example: `~/.cache/uv/archive-v0/EMmfohLIg0W6JhQPs_AUB`

```
home = /Users/kelvin/miniconda3/bin
implementation = CPython
uv = 0.11.8
version_info = 3.13.5
include-system-site-packages = false
relocatable = true
```

Entry-point bins include: `code-review-graph`, `fastmcp`, `mcp`, `cyclopts`, etc.  
→ These are **`uv tool` / `uvx`-style tool environments**, not a project’s local `.venv`.

---

## 2. What burns the space: `tree_sitter_language_pack`

### Size across the 43 large envs (≥ 200 MB)

| Package (sum across envs) | Copies | Total size |
|---------------------------|-------:|-----------:|
| **`tree_sitter_language_pack`** | **43** | **~14.7 GB** |
| cryptography | 43 | ~671 MB |
| networkx | 43 | ~540 MB |
| beartype | 35 | ~271 MB |
| tree_sitter_c_sharp | 43 | ~228 MB |
| pygments, pydantic*, fastmcp, mcp, code_review_graph, … | many | remainder |

Per env, `tree_sitter_language_pack` alone is **~350 MB**, almost entirely:

```
…/site-packages/tree_sitter_language_pack/bindings/   (~351 MB)
```

**Math:** ~350 MB × 43 envs ≈ **15 GB** — that is the dominant cost of this cache.

### What is `tree-sitter-language-pack`?

| Field | Value |
|-------|--------|
| PyPI name | `tree-sitter-language-pack` |
| Import name | `tree_sitter_language_pack` |
| Observed version | **0.13.0** |
| Summary | **Comprehensive collection of 160+ tree-sitter language parsers** |
| License | MIT OR Apache-2.0 |
| Upstream | https://github.com/Goldziher/tree-sitter-language-pack |
| Requires-Python | ≥ 3.10 |

**In plain language:**

[Tree-sitter](https://tree-sitter.github.io/tree-sitter/) is a library that builds **syntax trees** (ASTs) for source code. Each programming language needs a **grammar/parser** (often shipped as native bindings).

`tree-sitter-language-pack` is a **single Python package that bundles parsers for 160+ languages** so tools do not depend on dozens of separate `tree-sitter-python`, `tree-sitter-go`, … packages. That convenience is why it is large: it ships many compiled/native **bindings** in one wheel.

It is **not**:

- Your project source code  
- A model weight / Hugging Face download  
- Something you install for its own sake in normal app development  

It **is** infrastructure for tools that must **parse multi-language codebases**.

### Why you have it: `code-review-graph`

You use **code-review-graph** heavily. From a cached install (`code-review-graph` **2.3.2**):

```
Requires-Dist: tree-sitter-language-pack<1,>=0.3.0
Requires-Dist: tree-sitter<1,>=0.23.0
Requires-Dist: networkx<4,>=3.2
Requires-Dist: fastmcp<3,>=2.14.0
Requires-Dist: mcp<2,>=1.0.0
…
Keywords: claude-code, code-review, knowledge-graph, mcp, tree-sitter
```

**What code-review-graph does with it:**

1. Walks a repo and parses files with **Tree-sitter** (via the language pack).  
2. Builds a **structural graph** (functions, classes, imports, calls, etc.).  
3. Serves that graph over **MCP** so AI tools (e.g. Claude Code) get **blast radius / minimal context** instead of re-reading the whole tree.

So every time uv materializes a **tool environment** for `code-review-graph` (install, upgrade, `uvx`, version bump), it can snapshot a **full env** into `archive-v0`, including another full copy of the language pack.

Heavy use + many tool env versions → **43 copies × ~350 MB** → ~15 GB from this dependency alone.

---

## 3. How Mole treats uv cache

**Source (Mole 1.47.1 Homebrew):** `lib/clean/dev.sh` → `clean_uv_cache`  
**Call chain:** `mo clean` → Developer tools → `clean_developer_tools` → `clean_dev_python` → `clean_uv_cache`

```bash
# Conceptual flow
uv_cache_path="$HOME/.cache/uv"
if uv is available:
  uv_cache_path=$(uv cache dir)   # dynamic discovery
  clean_tool_cache "uv cache" "$uv_cache_path" -- uv cache prune
else:
  safe_clean "$HOME/.cache/uv"/*
```

| Behavior | Detail |
|----------|--------|
| Path discovery | Default `~/.cache/uv`; prefers **`uv cache dir`** |
| Real clean command | **`uv cache prune`** (dangling / unused only) |
| Not used | **`uv cache clean`** (full wipe) |
| Dry-run UI | `uv cache · would clean` — **no byte size** |
| `clean-list.txt` | Tool-cache path **not exported** with size |
| Dry-run total | User run: **8.91 GB** — **did not include** the ~20 GB uv cache |
| Default whitelist | uv is **listed** as optional protectable (`$HOME/.cache/uv/*`) but **not** in default protected set |

**Implication:** Mole *can* target the right directory, but:

1. Dry-run **hides impact** (no size / not in preview list).  
2. Actual clean is **conservative** (`prune`), so most of the 20 GB may remain.

---

## 4. How Pare treats uv cache (current)

**Rule:** `Sources/PareCore/Rules/PythonCachesRule.swift`

Targets only:

- `~/Library/Caches/pip`
- `~/Library/Caches/pypoetry`
- `~/Library/Caches/uv`  ← **absent on this machine**
- `~/.pyenv/cache`

**Not targeted:**

- `~/.cache/uv` (actual location from `uv cache dir`)
- `~/.cache/pip`, etc.

**Policy:** `ScanPolicy.reconstructibleCachePathMarkers` has **no** `/.cache/uv` entry (has things like `/.cache/opencode`, Homebrew, npm, etc.).

**Result:** Pare would **not report** this ~20 GB today.

---

## 5. Solutions for “diff caches” in Pare

Tools often store caches in **either** macOS `~/Library/Caches/<tool>` **or** XDG `~/.cache/<tool>` (or a path from `TOOL_CACHE_DIR` / CLI). Hard-coding only one root misses real bloat (this case).

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **A. Multi-root catalog** | For each tool, list both roots (e.g. uv: Library + `~/.cache/uv`) | Simple, testable, fits Pare rules | Catalog can lag new tools |
| **B. CLI discovery** | If tool on PATH, run `uv cache dir` / `pip cache dir` (short timeout), then size that folder | Follows user config | Process spawn; need fallbacks |
| **C. Parent scan** | Enumerate `~/.cache/*` top-level dirs; known names → `.safe`, unknown → `.review` or skip | Catches drift | Needs allow/block policy |
| **D. Convention** | Prefer dirs with `CACHEDIR.TAG` under cache parents | Standards-based | Incomplete adoption |
| **Full-disk largest folders** | Walk home/disk for size | High recall | Wrong as primary **safe** auto-clean |

**Recommended Pare posture:**

1. **Multi-root** for Python (and similar) package managers.  
2. Optional **`uv cache dir`** when `uv` exists.  
3. Optional **`~/.cache/<known-name>`** safety net.  
4. Add `/.cache/uv` (and siblings) to **reconstructible** markers; whole-folder findings; risk `.safe`; age gate **0**.  
5. Do **not** rely on blind full-disk scan for safe cleanup.

---

## 6. User actions to reclaim space

```bash
uv cache dir              # confirm path
uv cache prune            # what Mole runs — may free little
uv cache clean            # full wipe of the cache (~20 GB)
# or remove the directory after closing tools that use it
```

After `uv cache clean` / deleting the cache:

- Next `uv tool install` / `uvx code-review-graph` / upgrades will **re-download** and rebuild.  
- Your **installed tool** under uv’s tools home (if any) is separate from this **cache**; still, reinstall if something breaks.

To reduce **future** growth:

- Prefer fewer `uv tool upgrade` churn environments when possible.  
- Periodically `uv cache prune` or `uv cache clean`.  
- Understand that **code-review-graph’s** dependency on the full language pack makes **each** tool-env snapshot expensive (~0.4 GB+).

---

## 7. Key takeaways

1. **~20 GB is correct** and is uv’s real cache at `~/.cache/uv`.  
2. **~18 GB** is **43 relocatable tool envs** in `archive-v0`, not one corrupt blob.  
3. **~15 GB** is **`tree-sitter-language-pack` × 43**, pulled in by **`code-review-graph`** for multi-language Tree-sitter parsing.  
4. **Mole** finds the path but dry-run under-reports; clean only **prunes**.  
5. **Pare** currently only looks under **`~/Library/Caches/uv`** and **misses** XDG-style caches — fix with multi-root + policy markers (± CLI discovery).

---

## Appendix: Commands used

```bash
du -sh ~/.cache/uv
uv cache dir
uv cache size   # experimental
du -sh ~/.cache/uv/*
# Classify archive-v0: pyvenv.cfg vs package extracts
# Aggregate site-packages sizes across envs ≥ 200 MB
# Read METADATA from tree_sitter_language_pack and code_review_graph dist-info
```

**Mole references:**  
`/opt/homebrew/opt/mole/libexec/lib/clean/dev.sh` (`clean_uv_cache`, `clean_tool_cache`)  
`lib/manage/whitelist.sh` (uv protectable pattern)

**Pare references:**  
`Sources/PareCore/Rules/PythonCachesRule.swift`  
`Sources/PareCore/Scanning/ScanPolicy.swift` (`reconstructibleCachePathMarkers`)
