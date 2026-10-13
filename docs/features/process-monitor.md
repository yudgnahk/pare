# Process monitor (Processes tab)

Shows which branch of processes holds memory and CPU, e.g. `Paseo Daemon` → six `Claude Code`
agents → one `code-review-graph serve` and one `gitnexus mcp` each. Slice 1 is view-only.

## Decisions (maintainer, 2026-10-13)

- **View only.** No kill button or menu in slice 1.
- **Memory is `phys_footprint`** (`proc_pid_rusage`, `RUSAGE_INFO_V2`), the figure Activity Monitor
  shows. **Resident** (`ri_resident_size` from the same call, no extra syscall) sits beside it; see
  below. **CPU %** is user + system CPU time between two samples over the wall time between
  them; 100 % is one core. CPU reads "—" until a second sample exists, and a baseline older than 10 s
  (tab left and reopened) is discarded.
- **Current user only:** effective and real uid both equal `getuid()`. Zombies are skipped.
- **Raw command lines are never shown, logged or stored.** `KERN_PROCARGS2` is read once per process
  lifetime, only to derive a name, then dropped. The UI model holds the derived name and executable
  basename only; `ProcessMonitorTests.testModelNeverContainsRawArguments` guards this. Script names
  come only from plain path-like arguments (no URLs, `key=value` or query strings), and only an
  allow-listed subcommand (`serve`, `mcp`, `start`, …) is appended.
- **Paseo is optional.** When `~/.paseo/agents` exists, a `callerAgentId=<uuid>` in an agent's
  arguments is looked up as `~/.paseo/agents/<cwd-slug>/<uuid>.json` (title, cwd, `lastStatus`,
  `lastUserMessageAt`). Missing folder, missing file, symlink, file over 256 KB or bad JSON: shown
  as a plain process, silently. Results are cached per uuid and re-read when the file's mtime changes;
  misses are retried after 30 s.
- **Sampling runs only while the tab is visible** (every 2.5 s); leaving the tab cancels the task.

## Naming

`ProcessNamer`, in order: `claude` → Claude Code, `codex` → Codex; an interpreter (node, bun, deno,
python, ruby, perl, php) running a script → the script name (generic `index`/`main`/`cli` names fall
back to the npm package or folder), plus an allow-listed subcommand; a safe rewritten `argv[0]` title
(Electron's "Paseo Daemon"); the innermost `.app` name; the executable name.

## Tree

`ProcessTreeBuilder` links processes by ppid. A process whose parent is not ours (launchd, another
user) or has exited is a root; a ppid loop is cut at its lowest pid. Branch totals include the
process itself; siblings sort by branch memory.

## Memory vs Resident (2026-10-14)

Memory (footprint) includes pages macOS has compressed or moved to swap; Resident is what is in RAM
right now. On a machine under memory pressure idle processes are mostly compressed, so the two
diverge: a Paseo tree measured 6.22 GB footprint but 3.09 GB resident, and 18 idle
`code-review-graph serve` servers 1.41 GB footprint but 0.09 GB resident. Quitting those servers
frees swap and compressor space, not 1.41 GB of RAM.

- **Two columns, not a "compressed/swapped" column.** Footprint − RSS is not the compressed amount:
  RSS also counts shared pages (frameworks, mapped files) that the footprint leaves out, so the
  difference can be negative or misleading. Both figures are kernel-reported as they are.
- Every row, branch total and the header bar sum both columns. Resident sums can over-count pages
  shared between processes; the column tooltip says so.

## Repeated processes

`ProcessKindSummary` totals processes by derived name (`ProcessNamer` output only, never arguments)
across the whole forest, since MCP servers sit one per agent in different branches. The strip above
the tree shows kinds with at least 2 processes and 100 MB footprint, heaviest first, at most 6: a
single process is already one row in the tree, and small repeats (shells) are noise.

## Slice 2 (not built)

Kill with confirmation, never offered for system processes or for Pare itself. Proposed details, not
yet decided: SIGTERM first and SIGKILL only after a second confirmation; also block launchd, anything
under `/System` or `/usr/libexec`, and Pare's ancestors; re-check pid and start time before signalling.
