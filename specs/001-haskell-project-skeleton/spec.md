# Feature Specification: Haskell project skeleton + haskell.nix + CI Build Gate

**Feature Branch**: `feat/issue-5-skeleton`
**Created**: 2026-04-20
**Status**: Draft
**Input**: Ticket [#5](https://github.com/lambdasistemi/haskell-gamechanger/issues/5). Stand up a minimal Haskell library + executable layout so the rest of Scope A (tickets #6–#14) can build on it. No domain code yet.

## User Scenarios & Testing

The "users" of this feature are the next nine Scope A tickets and the project itself — not humans running a CLI. Each user story describes a capability a later ticket, a maintainer, or CI will rely on.

### User Story 1 — A later ticket can add a module and ship it (Priority: P1)

A contributor working on a downstream ticket (e.g. #6 `GameChanger.Script`) clones the repo, enters `nix develop`, creates a new module under a fresh or existing namespace, and builds and tests it. They do not need to set up tooling, wire CI, or decide on versions — the skeleton already covers all of that.

**Why this priority**: every subsequent Scope A ticket is blocked on this one; if the skeleton is not usable end-to-end, nothing else can start.

**Independent Test**: check out the merged branch, run `nix develop -c just build` and `nix develop -c just test`, confirm both succeed with an empty library and a placeholder test.

**Acceptance Scenarios**:

1. **Given** a clean clone of the repo at the head of this feature, **When** a contributor runs `nix develop -c just build`, **Then** the build succeeds and produces the library + executable + test suite derivations.
2. **Given** the same clone, **When** a contributor runs `nix develop -c just test`, **Then** the placeholder test suite runs and reports success.
3. **Given** a contributor adds a new module to the library section of the cabal file, **When** they rebuild, **Then** the new module is picked up without further configuration.

---

### User Story 2 — CI exercises the Build Gate pattern (Priority: P1)

On every PR and every push to main, CI runs a single `Build Gate` job that builds all flake-exposed derivations (library, executable, test suite, lint, dev-shell inputDerivation). Downstream jobs (tests, formatting, hlint) depend on `Build Gate` and reuse its Nix store via Cachix, so they run against a warmed cache.

**Why this priority**: self-hosted `nixos` runners share a Nix store; without the gate, parallel jobs deadlock on evaluation locks (see `new-repository` skill). Every later ticket adds checks or jobs — they all assume the gate exists.

**Independent Test**: open a throwaway PR that only bumps a README character, observe CI: Build Gate runs, downstream jobs wait for it, all succeed, total wall time is dominated by Build Gate.

**Acceptance Scenarios**:

1. **Given** a PR against main, **When** CI runs, **Then** exactly one `Build Gate` job is scheduled and all downstream Haskell-related jobs (tests, formatting, hlint) declare `needs: build-gate`.
2. **Given** a green Build Gate run, **When** a downstream job starts, **Then** it does not re-evaluate the flake from cold and its `nix build` steps resolve from cache within seconds.
3. **Given** a push to main that breaks the build, **When** CI runs, **Then** Build Gate fails and downstream jobs do not start, matching the pre-merge signal.

---

### User Story 3 — `just` recipes are the one way to run local checks (Priority: P1)

A maintainer runs the same commands locally that CI runs, by invoking `just` recipes inside `nix develop`. The recipes cover: build, test, format, format-check, hlint, lint (all three quality gates), and a `ci` recipe that runs what CI will run. No recipe silently fixes files; `format-check` fails on violations.

**Why this priority**: the `workflow` skill requires `just ci` to pass before every push. This recipe must exist from day one or the rule cannot be followed on this repo.

**Independent Test**: in `nix develop`, run `just ci` on a clean checkout; observe that it runs build, tests, format-check, hlint, and lint in order, and exits non-zero if any of them fail.

**Acceptance Scenarios**:

1. **Given** the dev shell is entered, **When** `just --list` is run, **Then** it shows recipes: `build`, `test`, `format`, `format-check`, `hlint`, `lint`, `ci`.
2. **Given** a working tree with a formatting violation, **When** `just format-check` runs, **Then** it exits non-zero and names the offending file.
3. **Given** a green working tree, **When** `just ci` runs, **Then** it completes with exit code 0 and prints the name of each gate as it runs.

---

### User Story 4 — Flake outputs are discoverable and CI-shaped (Priority: P2)

The flake exposes: `packages.<system>.default` (the executable), `devShells.<system>.default`, `apps.<system>.{hgc, tests, lint}`, and `checks.<system>.{library, exe, tests, lint}`. These names match the shapes the `new-repository` and `nix` skills assume, so the CI workflow file can be copy-adapted without surprise.

**Why this priority**: gets us a consistent surface across the org's repos; not strictly blocking later Scope A tickets but noticeable friction if it is missing.

**Independent Test**: run `nix flake show` against the repo; confirm every expected output is present with the expected type.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** `nix flake show` is run, **Then** it lists `packages.default`, `devShells.default`, at least one `apps.*`, and at least four `checks.*` entries.
2. **Given** a CI workflow adapted from the `new-repository` skill template, **When** the workflow references `.#checks.x86_64-linux.<name>` for each name, **Then** every reference resolves to an existing derivation.

---

### User Story 5 — Docs CI stays green after the skeleton lands (Priority: P2)

The existing `Docs (strict build + PR preview)` workflow continues to pass with no changes. The skeleton does not break the doc site, the shared preview deploys correctly on PRs, and `mkdocs build --strict` remains part of the PR gate set.

**Why this priority**: the current CI has exactly two jobs (Build Gate stub + Docs). This ticket replaces the Build Gate stub with real substance; it must not collaterally break Docs.

**Independent Test**: open the PR for this ticket, confirm both CI checks remain green and the shared preview renders the existing site.

**Acceptance Scenarios**:

1. **Given** the PR for this ticket, **When** CI runs, **Then** the Docs check is green and a shared preview URL is posted as a sticky comment.
2. **Given** the PR is merged, **When** the deploy-docs workflow runs on main, **Then** the GitHub Pages site at `lambdasistemi.github.io/haskell-gamechanger` updates without error.

---

### Edge Cases

- **Empty library with no modules**: cabal must still be able to build it. The `GameChanger` top-level module is the single placeholder.
- **Empty test suite**: one trivial test (e.g. `assertEqual "sanity" 1 1`) so the test derivation is real, not a no-op.
- **Version drift between local fourmolu / hlint / cabal-fmt and CI**: pin the versions in the dev shell; CI uses the same dev shell so they cannot diverge.
- **`nix develop -c` does not run shellHook**: any env vars set in the shell hook are unavailable inside `just` recipes called through `nix develop -c`; recipes must not depend on shellHook-only state.
- **Parallel CI jobs on the same self-hosted runner**: Build Gate must complete before the fan-out, enforced via `needs: build-gate`. No downstream job runs `nix` commands concurrently with Build Gate.
- **CACHIX_AUTH_TOKEN missing from a fork**: the Cachix action must be configured to treat an absent token as a warning, not a hard failure, so fork PRs still build (they just don't write to the cache).

## Requirements

### Functional Requirements

- **FR-001**: The repository MUST contain a `haskell-gamechanger.cabal` file with three stanzas: a library, one executable named `hgc`, and one test-suite.
- **FR-002**: The library stanza MUST expose exactly one module, `GameChanger`, as a placeholder. The module MUST contain no domain logic.
- **FR-003**: The test-suite MUST contain at least one trivial test that passes.
- **FR-004**: The repository MUST contain `cabal.project` and `cabal.project.local`. `cabal.project.local` MUST set `-O0` and `-Wwarn` for fast dev builds.
- **FR-005**: The repository MUST contain a `flake.nix` whose outputs include:
  - `packages.<system>.default` — the `hgc` executable
  - `devShells.<system>.default` — a shell with GHC, cabal, fourmolu, hlint, cabal-fmt, just
  - `apps.<system>.{hgc, tests, lint}` — runnable wrappers
  - `checks.<system>.{library, exe, tests, lint}` — sandboxed CI-shaped checks
- **FR-006**: The dev shell MUST pin fourmolu, hlint, and cabal-fmt to specific versions so local runs match CI byte-for-byte.
- **FR-007**: The repository MUST contain a `justfile` with recipes: `build`, `test`, `format`, `format-check`, `hlint`, `lint`, `ci`.
- **FR-008**: `just format-check` MUST fail (exit non-zero) on any formatting violation. It MUST NOT silently rewrite files.
- **FR-009**: `just ci` MUST run build, tests, format-check, hlint, and lint in order and exit non-zero if any gate fails.
- **FR-010**: The CI workflow at `.github/workflows/ci.yml` MUST include a `build-gate` job that builds every check derivation and every runnable flake output used by downstream jobs.
- **FR-011**: Every CI job that invokes `nix` MUST declare `needs: build-gate`.
- **FR-012**: The CI workflow MUST run on `runs-on: nixos` and use `cachix/cachix-action@v15` with the `paolino` cache.
- **FR-013**: Downstream CI jobs MUST include at minimum: build + test (runs `nix run .#tests`), formatting (runs `nix run .#lint`), hlint (part of `lint` or its own job). These MAY be combined under a single `lint` derivation per the `nix` skill.
- **FR-014**: The `lint` check MUST invoke fourmolu in check mode, cabal-fmt in check mode, and hlint with CI's fail level on every source file under the project's CI-scoped paths.
- **FR-015**: The existing `deploy-docs.yml` workflow MUST continue to function unchanged. No skeleton change may require editing it.
- **FR-016**: The repository MUST contain a top-level `CLAUDE.md` pointing at the `workflow` skill and the constitution, so future sessions load context consistently.

### Key Entities

- **Skeleton**: the union of cabal files, module stub, flake outputs, dev shell, justfile, and CI workflow — the buildable artefact other tickets extend.
- **Build Gate**: the CI job that evaluates and builds all flake outputs once, warming the shared Nix store for downstream jobs.
- **Check derivation**: a sandboxed Nix-built verification artefact (`checks.library`, `checks.tests`, `checks.lint`). Produced by the flake; consumed by CI.
- **App wrapper**: a Nix `app` output that runs a check binary with stdout visible, so CI logs are readable.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A contributor cloning the repo and running `nix develop -c just ci` on a fresh machine completes the gate in under 5 minutes (cold first build), under 60 seconds (warm rebuild).
- **SC-002**: Opening a PR that changes a single `.hs` file in the library triggers exactly one Build Gate run and at most three downstream jobs. Total CI wall-clock time is under 4 minutes with a warm Cachix cache.
- **SC-003**: `nix flake show` lists all outputs named in FR-005 on the first try; no missing outputs.
- **SC-004**: The next ticket to start (#6) requires zero edits to `flake.nix`, `justfile`, or `.github/workflows/ci.yml` to add its module — only cabal file edits and new source files.
- **SC-005**: On a violation (formatting, hlint, or build failure), `just ci` and CI both fail with a message naming the offending file within one terminal screen of output.

## Assumptions

- The `paolino` Cachix cache is writable from `lambdasistemi/haskell-gamechanger` CI (the `CACHIX_AUTH_TOKEN` secret is already configured on the repo).
- Self-hosted `nixos` runners are available and healthy; no GitHub-hosted-runner fallback is required.
- The chosen GHC version is 9.6.x (LTS-ish), matching what the downstream tickets will need for `cardano-api` / `cardano-node-clients`. This is a default — revisit in the plan step.
- `haskell.nix` is the build backend. Source `haskell.nix` and `CHaP` from the same inputs the rest of the lambdasistemi Haskell repos use, to maximise cache hit rate.
- The library and executable live at the repo root under `src/` and `app/`. The test suite lives under `test/`. No multi-package Cabal project — a single cabal file keeps the scaffolding as small as possible.
- Speckit scaffolding produced a branch `001-haskell-project-skeleton`; this has been renamed to `feat/issue-5-skeleton` to match the workflow skill's naming convention.

## Out of scope

- Any GameChanger domain types (Script, Encoding, Intent, QR, Callback) — those are later tickets.
- Any network-touching integration tests — the placeholder test is purely internal.
- A multi-package cabal project — this is one library + one exe + one test.
- Release automation (release-please, hackage upload) — handled separately once the shape is proven.
- Cross-compilation or WASM targets — explicitly out of scope per the constitution.
