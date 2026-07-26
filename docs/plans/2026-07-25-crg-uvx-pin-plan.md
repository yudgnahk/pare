# Plan: Pin code-review-graph MCP (stop floating `uvx` env churn)

**Status:** Draft for review (do not implement until approved)  
**Date:** 2026-07-25  
**Owner:** Kelvin / Pare + local agent tooling  
**Related investigation:** [`UV_INVESTIGATION.md`](../../UV_INVESTIGATION.md)  
**Companion plan:** [`2026-07-25-pare-uv-cache-scan-plan.md`](./2026-07-25-pare-uv-cache-scan-plan.md)

---

## 1. Problem statement

`code-review-graph` (CRG) is launched as an MCP server via:

```text
uvx code-review-graph serve
```

On this machine that has produced **~43 full virtualenvs** under `~/.cache/uv/archive-v0/`, totaling **~18 GB**, dominated by **`tree-sitter-language-pack` 0.13.0** (~350 MB × 43 copies). Project graph data (`.code-review-graph/graph.db`) is **separate** and safe; the bloat is **tool install cache only**.

### Root cause (not a CRG “install bug”)

| Layer | Behavior |
|-------|----------|
| MCP config | `command: uvx`, `args: [code-review-graph, serve]` |
| uv | Each distinct resolution → new **cached env archive**; old ones kept until `prune`/`clean` |
| CRG | Depends on full multi-language Tree-sitter pack (large fixed cost per env) |
| Host tools | **Grok** currently spawns CRG this way; Claude plugin still defines the same pattern; Codex/OpenCode/Antigravity do **not** |

### Observed live usage (2026-07-25)

- **Grok** parent processes spawn: `uv tool uvx code-review-graph serve`
- Multiple concurrent Grok sessions → multiple concurrent `serve` processes
- Env birth dates span **2026-03 → 2026-07** (continuous use, not only historical Claude)
- **Codex:** MCP = `gitnexus` via `npx` — no CRG
- **OpenCode:** MCP = `gitnexus` only
- **Antigravity:** no CRG config found
- **Claude Code:** plugin still present with `uvx` MCP; user reports little recent use

### Config sources that still say `uvx`

| Location | Content |
|----------|---------|
| Grok marketplace cache (CRG plugin) | `.mcp.json` → `uvx code-review-graph serve` |
| `~/Projects/yudgnahk/resume/.mcp.json` | same |
| Akzo project `.mcp.json` | same |
| Claude plugin `~/.claude/plugins/.../code-review-graph/.mcp.json` | same |
| `~/.grok/config.toml` | **no** explicit CRG section today (CRG arrives via project / import / merge — see Grok MCP docs) |

Grok MCP merge order (from `~/.grok/docs/user-guide/07-mcp-servers.md`):

```text
config.toml > Claude > Cursor > .mcp.json
```

Higher priority wins on name conflict. **User-level `~/.grok/config.toml` is the preferred pin point** so it overrides floating project `.mcp.json` entries named `code-review-graph`.

---

## 2. Goals

1. **One durable install** of CRG at an exact, intentionally selected version.
2. MCP starts with a **stable executable path**. A bare `uvx` / `uv tool run` invocation may reuse the installed tool, but direct binary execution is clearer and avoids the uv wrapper.
3. **Preserve** existing repo graphs under `.code-review-graph/`.
4. **Reclaim** disk with measured `uv cache prune` after cutover; reserve full clean for deliberate invalidation.
5. Document how to **upgrade CRG intentionally**.
6. Optionally clarify **gitnexus vs CRG** (both graph MCPs) — decision only, not mandatory removal.

### Non-goals

- Changing CRG upstream packaging / tree-sitter dependency (out of scope).
- Removing gitnexus (separate product; used by Pare AGENTS.md and Codex).
- Implementing Pare scan logic (see companion plan).
- Forcing all machines/teams to the same pin without their consent.

---

## 3. Proposed solution

### 3.1 Install CRG as a uv tool (primary)

```bash
# Pin a known-good version at cutover (example — use current desired release)
uv tool install "code-review-graph==2.3.7"

# Verify
uv tool list
command -v code-review-graph
uv tool dir --bin
code-review-graph --help   # or: code-review-graph serve --help
```

Expected layout (uv defaults on this machine):

| Item | Path |
|------|------|
| Tool env | `~/.local/share/uv/tools/...` (uv-managed) |
| Shim / binary | typically `~/.local/bin/code-review-graph` (ensure `~/.local/bin` is on `PATH`) |

**Why this works:** `uv tool install` creates a persistent environment under uv's tools directory. With an exact constraint, the selected version changes only when it is explicitly reinstalled with a new constraint.

Current uv also documents that bare `uvx code-review-graph` / `uv tool run code-review-graph` uses an already installed tool by default unless a version is requested or `--isolated` is passed. That means installing the pinned tool should also stabilize compatible existing bare-`uvx` configs. Direct binary execution is still preferred for MCP because it is unambiguous and removes the wrapper process.

### 3.2 Point Grok MCP at the pinned binary

Add to **`~/.grok/config.toml`** (user scope — highest merge priority among common sources):

```toml
[mcp_servers.code-review-graph]
command = "/Users/kelvin/.local/bin/code-review-graph"
args = ["serve"]
enabled = true
# Optional if CRG itself needs more startup time:
# startup_timeout_sec = 60
```

Notes:

- Prefer **absolute path** to avoid PATH differences across iTerm/GUI launches.
- If the shim moves, use `uv tool dir --bin`, `uv tool list`, and `command -v code-review-graph` to locate and update it.
- Supported alternative:

```toml
[mcp_servers.code-review-graph]
command = "/opt/homebrew/bin/uv"
args = ["tool", "run", "code-review-graph", "serve"]
```

`uv tool run` and `uvx` are aliases. With no requested version and no `--isolated`, current uv uses the installed tool environment by default. Keep a verification test because this is uv behavior rather than a property of CRG.

### 3.3 Align project `.mcp.json` files (secondary)

Update known floaters so non-Grok clients that only read `.mcp.json` invoke the stable binary directly:

| File | Change |
|------|--------|
| `~/Projects/yudgnahk/resume/.mcp.json` | `command` → absolute pinned binary; `args` → `["serve"]` |
| Akzo `.../gql-catalog-mw-akzonobel-hosting/.mcp.json` | same |
| Any other `.mcp.json` found with `uvx` + `code-review-graph` | same |

**Portable alternative for shared repos** (if committing):

```json
{
  "mcpServers": {
    "code-review-graph": {
      "command": "code-review-graph",
      "args": ["serve"]
    }
  }
}
```

Requires every developer to have `uv tool install` + PATH. Absolute path is fine for **personal** configs; prefer name-on-PATH for **committed** project files.

This alignment is desirable for clarity, but it is not required solely to obtain installed-tool reuse: current uv already lets a bare `uvx code-review-graph` use the installed version. Configs that request `@latest`, an explicit different version, `--from` with different constraints, or `--isolated` must still be changed.

### 3.4 Claude Code (optional / low priority)

If Claude remains unused:

- Option A: leave plugin alone (harmless if Claude not launched).
- Option B: disable plugin / document that MCP should use pinned binary if Claude is re-enabled.
- Do **not** rely on Claude as the primary fix — Grok is the active spawner.

### 3.5 Cache reclaim (after pin works)

```bash
# Confirm the new pinned MCP starts, then close all old uvx-launched CRG sessions.
# Verify no `uv tool uvx code-review-graph serve` parent remains before cleanup.
uv cache prune     # gentle
# or full reclaim once pin is verified:
uv cache clean
du -sh ~/.cache/uv
```

**Safety:**

- Use uv's commands; never move or delete the uv cache directory directly.
- uv locks cache-modifying operations against active uv commands. Old long-lived `uvx` MCP parents must be stopped first or cleanup may wait and time out.
- Neither command deletes `<repo>/.code-review-graph/`.
- `uv cache clean` removes disposable cache environments, but not a persistently installed tool environment under `uv tool dir`.
- Prefer `uv cache prune` first and measure reclaimed bytes. Use full `uv cache clean` only for deliberate full invalidation.

### 3.6 Upgrade runbook (document for user)

```bash
# Exact pins do not advance with `uv tool upgrade`; replace the constraint:
uv tool install "code-review-graph==X.Y.Z"
# Restart Grok sessions so MCP respawns
code-review-graph --version
```

Optional periodic hygiene:

```bash
uv cache prune
# Full clean is exceptional, not routine:
# uv cache clean
```

---

## 4. Decision: gitnexus vs code-review-graph

Both are connected in some Grok workspaces:

| Server | Stack | Role |
|--------|--------|------|
| **gitnexus** | Node (`gitnexus mcp` / `npx`) | Pare’s AGENTS.md / impact analysis graph |
| **code-review-graph** | Python + Tree-sitter pack | Multi-language structural graph + MCP review tools |

**Recommendation for this plan:**

- **Keep both** unless the user confirms CRG tools are unused in Grok.
- Pinning CRG does **not** require removing gitnexus.
- If later CRG is unused: set `enabled = false` on `[mcp_servers.code-review-graph]` or remove project `.mcp.json` entries — separate decision.

Open question for reviewer / user: **Do you still want CRG tools in Grok, or is gitnexus enough for Pare?**

---

## 5. Implementation steps (ordered)

1. Record current state: `uv tool list`, `du -sh ~/.cache/uv`, `ps` for both uv wrapper and `code-review-graph serve` processes.
2. `uv tool install "code-review-graph==<chosen-version>"`.
3. Verify binary: absolute path + `serve` help / dry smoke.
4. Add `[mcp_servers.code-review-graph]` to `~/.grok/config.toml` with absolute `command`.
5. Restart Grok (or reconnect MCP); close old sessions and confirm:
   - tools still listed
   - process is the **pinned binary** under the tools directory, not `archive-v0`
   - no old `uv tool uvx code-review-graph serve` parent remains
   - no unexpected duplicate MCP definition is spawning a second server
6. Update personal/project `.mcp.json` floaters.
7. (Optional) Claude plugin note or disable.
8. After stability ≥ one successful session and zero old uvx parents: run `uv cache prune`, record reclaimed bytes, and use `uv cache clean` only if a full wipe is still wanted.
9. Document upgrade + PATH requirements in a short ops note (or append to `UV_INVESTIGATION.md`).

---

## 6. Test / verification plan

| # | Check | Pass criteria |
|---|--------|----------------|
| T1 | Install | `uv tool list` shows `code-review-graph` |
| T2 | Binary | `~/.local/bin/code-review-graph` (or documented path) executes |
| T3 | Grok MCP | Tools from CRG available in a Grok session |
| T4 | Process | Preferred config shows the tools-directory binary directly; alternative bare `uvx` / `uv tool run` is proven to reuse that installed version |
| T5 | Graphs intact | Existing `pare/.code-review-graph/graph.db` (and other repos) still readable by CRG |
| T6 | Multi-session | Two Grok sessions: expect multiple **serve** processes OK; should **share** tool install, not create 2× 400 MB new archives |
| T7 | Cache reclaim | With old uvx parents stopped, record `prune` before/after; after optional full clean, installed MCP still starts without reinstall |
| T8 | Override | Project `.mcp.json` still `uvx` must **not** win over user `config.toml` (per Grok merge order) |

---

## 7. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Absolute path breaks on another machine | Use PATH-based command in committed configs; absolute only in user `config.toml` |
| `~/.local/bin` not on GUI PATH | Absolute path in Grok config; or fix login PATH |
| Persistent tool still uses disk | One intentional environment under the tools directory; prune disposable cache entries separately |
| Version pin too old | Document upgrade; pin known-good then upgrade deliberately |
| Duplicate MCP name conflicts | User config.toml wins; remove duplicate definitions if confusing |
| Cache cleanup races active uvx MCPs | Stop old uv wrapper processes; use `uv cache prune/clean`, never filesystem deletion |
| Exact pin does not move on `uv tool upgrade` | Reinstall with a new explicit `==X.Y.Z` constraint |
| User wants zero CRG | `enabled = false` + cache clean — simpler path |

---

## 8. Rollback

1. Restore previous `[mcp_servers.code-review-graph]` or remove section (fall back to `.mcp.json` / Claude import).
2. Or set command back to `uvx` with args `["code-review-graph", "serve"]`.
3. `uv tool uninstall code-review-graph` if desired.
4. Graphs in repos unchanged throughout.

---

## 9. Success metrics

- New large envs under `~/.cache/uv/archive-v0` for CRG **stop accumulating** on normal daily Grok use (same CRG version).
- `du -sh ~/.cache/uv` drops significantly after clean (order of **tens of GB** on this machine).
- CRG MCP tools still work; repo graphs intact.
- Upgrade is an **explicit** user action.

---

## 10. Open questions for reviewer

1. Confirm **exact version** `==2.3.7` as the initial known-good pin?
2. Prefer **absolute binary** (recommended) vs installed-tool reuse through bare `uvx` / `uv tool run`?
3. Keep **both** gitnexus and CRG, or disable CRG for Pare-only workflows?
4. Should project `.mcp.json` files be updated in-repo (portable `command: code-review-graph`) or left alone because user `config.toml` overrides?
5. Include Claude plugin cleanup in the same PR/change set or defer?

---

## 11. References

- Investigation: `UV_INVESTIGATION.md`
- Grok MCP docs: `~/.grok/docs/user-guide/07-mcp-servers.md` (merge order, stdio config, `startup_timeout_sec` for cold `uvx`)
- CRG plugin pattern: `"command": "uvx", "args": ["code-review-graph", "serve"]`
- uv tool behavior: https://docs.astral.sh/uv/concepts/tools/
- uv cache safety and cleanup: https://docs.astral.sh/uv/concepts/cache/
- CRG releases: https://pypi.org/project/code-review-graph/
