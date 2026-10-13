# Phase 6 — Developer Ecosystem Breadth

Polyglot package-manager caches, Spotlight project discovery, and project artifacts.

## Package-manager caches

All `.safe` unless noted; the installed runtimes and binaries next to them are never touched.

| Rule | Targets | Never touched |
|---|---|---|
| `PythonCachesRule` | `~/Library/Caches/pip`, `pypoetry`, `~/.pyenv/cache` | `~/.pyenv/versions`, `site-packages` |
| `UvCacheRule` | every uv cache root, `.advanced` (see below) | — |
| `RubyCachesRule` | `~/.gem/ruby/*/cache`, `~/.bundle/cache`, `~/.rbenv/cache` | `~/.gem/ruby/*/gems`, `~/.rbenv/versions` |
| `JavaBuildCachesRule` | `~/.gradle/caches`, `~/.gradle/wrapper/dists`, `~/.ivy2/cache`; `~/.m2/repository` is `.review` | — |
| `RustCachesRule` | `~/.cargo/registry/{cache,src}`, `~/.cargo/git/{db,checkouts}`, `~/.rustup/downloads` | `~/.cargo/bin`, `~/.rustup/toolchains` |
| `GoCachesRule` | `~/Library/Caches/go-build`, `~/go/pkg/mod`, `.advanced` working set | always never-clean |

`~/.m2/repository` is `.review` because some teams publish internal artifacts there, and deleting
them breaks offline builds.

## uv

Homebrew's uv uses `~/.cache/uv`, not `~/Library/Caches/uv`, so the first Python rule missed
multi-GB caches. `UvCacheRule` finds every root (see CLAUDE.md) and reports it `.advanced`: uv must
clean its own cache to respect locks. It rejects dangerous roots (`/`, direct children of `/`, bare
home, bare `~/Library`) and validates tool output (one absolute line, no NUL, bounded length).

## Project discovery — `ProjectRootDiscovery`

- Spotlight (`NSMetadataQuery`, home scope, 10 s timeout, partial results kept) looks for signal
  files: `Package.swift`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `setup.py`, `Gemfile`, `pom.xml`,
  `build.gradle(.kts)`, `package.json`, `pubspec.yaml`, `composer.json`, `Package.resolved`.
- `*.xcodeproj` is not a signal: Xcode creates them inside DerivedData. Spotlight does not index `.git`.
- Paths through `Library`, `System`, `Applications`, `node_modules`, `vendor`, venvs, Trash,
  `site-packages`, `go/pkg/mod`, `.pub-cache`, Cargo registry and git, `fvm/versions` and runner
  toolchains (`_work/_tool`) are dropped.
- Nested roots collapse into the outermost one, unless more than 3 components deeper.
- Roots persist in `~/Library/Application Support/Pare/project-roots.json`, refresh every 24 h or on
  Rescan, and can be unchecked or added by hand in the Project Roots card.

## Project artifacts — `ProjectArtifactsRule`

Walks confirmed roots (depth 8) and reports whole folders, never descending into a match:
`__pycache__`, `.cache`, `.parcel-cache`, `.turbo`, `.nx`, `.next`, `.nuxt`, `.gradle`, `.pytest_cache`,
`.mypy_cache`, `.ruff_cache`, `.tox`, `.eggs`, `target`, `build`, `dist`, `coverage`, and the hidden
caches below.

- **7-day age gate** on the newest of the folder and its direct children, since builds rewrite files inside (e.g. `.build/build.db`).
- **`build`, `dist`, `target`, `coverage` need git evidence**: ignored and nothing tracked inside,
  checked with one git query per scan and again at cleanup. `build` and `dist` stay `.review`
  because some projects commit release output.
- **Hidden caches need their manifest beside them**: `.build` (`Package.swift`), `.dart_tool`
  (`pubspec.yaml`), `.angular` (`angular.json`), `.svelte-kit` / `.vite` / `.expo` (`package.json`),
  `.serverless` (`serverless.*`). `.swiftpm` (committed schemes) and `.terraform` (backend state) are
  deliberately absent.
- Dependency folders (`node_modules`, `venv`, `.venv`, `.bundle`) are not artifacts. They have their
  own rule: `docs/features/project-dependency-reclaim.md`.
