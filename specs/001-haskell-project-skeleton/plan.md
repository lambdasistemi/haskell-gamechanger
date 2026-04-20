# Implementation Plan: Haskell project skeleton + haskell.nix + CI Build Gate

**Branch**: `feat/issue-5-skeleton` | **Date**: 2026-04-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/001-haskell-project-skeleton/spec.md`
**Ticket**: [#5](https://github.com/lambdasistemi/haskell-gamechanger/issues/5)

## Summary

Stand up the minimum repo state from which tickets #6–#14 can ship. That means: a buildable one-package cabal project with a library, a `hgc` executable stub, and a test suite; a `haskell.nix`-backed flake that exposes `packages / devShells / apps / checks` in the shapes the `new-repository` and `nix` skills assume; a `justfile` with the gate recipes the `workflow` skill expects; and a CI workflow that uses the Build Gate pattern so self-hosted `nixos` runners do not deadlock on the shared Nix store.

No domain code lands. The library exposes one placeholder module `GameChanger`. The test suite is a single trivial check. The point is that ticket #6 can land its first `GameChanger.Script` module by editing only cabal + `src/` — no flake, justfile, or CI edits required (spec SC-004).

## Technical Context

**Language/Version**: GHC 9.6.6 (pinned via haskell.nix). Rationale: recent enough to match what `cardano-api` / `cardano-node-clients` ship in lambdasistemi repos today; conservative enough that `haskell.nix` has warm caches.
**Primary Dependencies**: `base`, `text`, `bytestring`. The skeleton library has no Cardano deps yet — those arrive per-module in later tickets.
**Build backend**: `haskell.nix` via its flake, inputs sourced to match `cardano-utxo-csmt` / `haskell-csmt` so Cachix hits cross-repo.
**Index**: `CHaP` (Cardano Haskell Packages) is wired in from day one — later tickets will need it and it costs nothing to include empty.
**Testing**: `tasty` + `tasty-hunit` for the trivial placeholder. `tasty-quickcheck` not pulled in yet; arrives when #6 needs it.
**Target Platform**: `x86_64-linux` only at first. No mac, no WASM (constitution §8).
**Project Type**: Haskell library + CLI. Single-package cabal project.
**Performance Goals**: N/A — skeleton has no runtime work.
**Constraints**: `just ci` must complete in <5 min cold, <60 s warm (SC-001). CI wall-clock <4 min warm (SC-002).
**Scale/Scope**: ~10 files, ~50 LOC Haskell, plus Nix / CI / justfile scaffolding.

### Dependencies pinned

| Tool       | Version            | Source                               |
|------------|--------------------|--------------------------------------|
| GHC        | 9.6.6              | `haskell.nix` compiler selection     |
| fourmolu   | 0.15.0.0           | `haskell.nix` tool layer             |
| hlint      | 3.8                | `haskell.nix` tool layer             |
| cabal-fmt  | 0.1.12             | `haskell.nix` tool layer             |
| just       | from `nixpkgs`     | dev shell                            |
| cabal-install | 3.10 (bundled via haskell.nix) | dev shell             |

Versions live in `flake.nix` so local and CI match byte-for-byte (spec FR-006).

## Constitution Check

Checking the amended constitution (v0.3.0, §§ relevant to this ticket):

- **§8 Scope** — native-only, no WASM target. ✅ This plan targets `x86_64-linux` via `haskell.nix`; no WASM. The flake's `packages.default` is a native executable. No `arch(wasm32)` conditionals introduced.
- **§11 Intent eDSL** — operational monad only. N/A — no domain code lands here. The skeleton does not prejudice the encoding; it only makes the cabal library a home for `GameChanger.Intent` later.
- **§14 CI gates** — Build Gate pattern mandatory. ✅ Explicit in this plan; see §"CI wiring" below.
- **Governance rule — vertical commits, docs travel with code** — ✅ This ticket is itself vertical (types→build→CI→docs-of-the-skeleton via Haddock on `GameChanger`). No split between "add cabal" and "add CI" — both land in the same PR.

No complexity tracking entries: nothing here deviates from a single-package project.

## Project Structure

### Documentation (this feature)

```text
specs/001-haskell-project-skeleton/
├── spec.md              # feature spec (done)
├── plan.md              # this file
├── research.md          # §Research below as a split-out doc (Phase 0 artefact)
├── quickstart.md        # developer onboarding walkthrough (Phase 1 artefact)
└── tasks.md             # produced by /speckit.tasks
```

No `data-model.md` (skeleton has no domain entities). No `contracts/` directory (skeleton exposes no API). Both are intentionally omitted per the speckit template's "delete unused options" guidance.

### Source code (repository root)

```text
haskell-gamechanger/
├── .github/workflows/
│   ├── ci.yml                # real Build Gate + fan-out (replaces the stub)
│   └── deploy-docs.yml       # unchanged
├── .specify/
│   └── memory/constitution.md
├── app/
│   └── Main.hs               # trivial `hgc` stub — prints version, exits 0
├── src/
│   └── GameChanger.hs        # placeholder module, one export: `version :: Text`
├── test/
│   └── Spec.hs               # tasty entry point; one passing unit test
├── data/rdf/                 # existing — ontology Turtle
├── docs/                     # existing — MkDocs site
├── nix/
│   ├── project.nix           # haskell.nix cabalProject' definition
│   ├── checks.nix            # library / exe / tests / lint check derivations
│   └── apps.nix              # runnable wrappers over checks
├── flake.nix                 # thin wiring — imports from nix/
├── flake.lock
├── cabal.project             # index-state pin, CHaP source-repository-package
├── cabal.project.local       # -O0 -Wwarn (dev only)
├── haskell-gamechanger.cabal # library + exe + test-suite stanzas
├── justfile                  # build / test / format / format-check / hlint / lint / ci
├── CLAUDE.md                 # pointer to workflow skill + constitution
└── README.md                 # unchanged
```

**Structure Decision**: single-package cabal project, one flake, nix code split into `project.nix` / `checks.nix` / `apps.nix` per the `nix` skill's recommended layout. This gives ticket #6 a single cabal file and a single `src/` tree to extend — the skeleton's SC-004 contract.

## Design decisions (Phase 0)

### D1. `haskell.nix` over plain `nixpkgs.haskellPackages`

`haskell.nix` is the pattern in every active lambdasistemi Haskell repo (`cardano-utxo-csmt`, `haskell-csmt`, `mpfs`, `moog`). Using it here gives us:
- CHaP wiring from day one, so #6 / #12 / #13 can pull `cardano-api` / `cardano-node-clients` without a Nix migration;
- shared Cachix cache hits with those repos;
- `shell.additional` escape hatch for public sublibraries (relevant once `cardano-api` enters, not today).

`nixpkgs.haskellPackages` would work for the empty skeleton but would force a migration the moment ticket #6 pulls a Cardano dep. Migrating later is a bigger change than starting there.

### D2. One cabal package, not a multi-package project

Every Scope A module (`GameChanger.Script`, `.Encoding`, `.Intent`, `.QR`, `.Callback`) is a different module in the same library. Splitting them into separate cabal packages would multiply boilerplate without payoff — they compile together, ship together, and have overlapping deps.

The `hgc` executable and the test suite stay in the same cabal file, two separate stanzas.

### D3. One CI workflow file

`ci.yml` carries: `build-gate` → fan-out (`tests`, `lint`). No separate `format.yml` / `lint.yml` / `typos.yml` workflows — they fragment the Build Gate contract. Everything feeds through the `lint` check derivation (fourmolu check + cabal-fmt check + hlint), invoked by the `lint` app.

### D4. `CLAUDE.md` at the repo root

The workflow skill's opening rule is "always load workflow skill at start of coding session when relevant." Adding a `CLAUDE.md` that names the skill + links the constitution means future sessions bootstrap correctly without this being rediscovered each time. One file, ~20 lines.

### D5. No `.github/dependabot.yml`, no release-please

Release automation is out of scope (spec). No Hackage publication path yet. Dependabot against a haskell.nix repo is noisy and low-value. Both are deliberately absent — future tickets can add them.

### D6. `tasty` as the test framework

Every downstream ticket will want property tests (tasty-quickcheck) and golden tests (tasty-golden). Starting on tasty avoids rewriting the test stanza when #6 lands. The skeleton pulls only `tasty` + `tasty-hunit`; others arrive on demand.

## Phase 1 deliverables

### Quickstart (`quickstart.md`)

A one-page walkthrough for a contributor picking up a downstream ticket: clone, `nix develop`, run `just ci`, add a module to the cabal file, rebuild. Lives alongside the spec under `specs/001-haskell-project-skeleton/quickstart.md`. Its existence is the user-testable evidence that Story 1 works end-to-end (spec User Story 1).

### CI wiring (`.github/workflows/ci.yml`)

Three jobs:

1. **build-gate** (`runs-on: nixos`, needs: nothing)
   - `nix build .#checks.x86_64-linux.library`
   - `nix build .#checks.x86_64-linux.exe`
   - `nix build .#checks.x86_64-linux.tests`
   - `nix build .#checks.x86_64-linux.lint`
   - `nix build .#devShells.x86_64-linux.default.inputDerivation`
2. **tests** (`needs: build-gate`) — `nix run .#tests`
3. **lint** (`needs: build-gate`) — `nix run .#lint`

Cachix configured with `paolino` cache and `CACHIX_AUTH_TOKEN` secret. Concurrency group `${{ github.workflow }}-${{ github.ref }}`, cancel in progress. No `continue-on-error`, no `if: always()`. `deploy-docs.yml` untouched.

### Justfile

```
default: build
build:       cabal build all
test:        nix run .#tests
format:      fourmolu -i src app test; cabal-fmt -i haskell-gamechanger.cabal
format-check: fourmolu -m check src app test; cabal-fmt -c haskell-gamechanger.cabal
hlint:       hlint src app test
lint:        nix run .#lint
ci:          just build && just test && just format-check && just hlint
```

`ci` runs the same steps CI runs, in the same order, so `just ci` green ⇒ CI green (barring network / runner issues).

### Lint check derivation

`nix/checks.nix` exposes `lint` as a `pkgs.writeShellApplication` that runs fourmolu (check), cabal-fmt (check), hlint — the composite of FR-014. CI consumes this via `.#checks.lint` (build gate) and `.#apps.lint` (stdout-visible in CI log).

## Re-check of Constitution after Phase 1

All checks from §"Constitution Check" still pass; nothing in the Phase 1 deliverables introduces a WASM surface, a typeclass-indexed DSL, or a non-native build target. No new complexity entries.

## Rollout

1. Land spec on `feat/issue-5-skeleton` (done).
2. Land plan + quickstart on same branch (this step).
3. `/speckit.tasks` to produce `tasks.md`.
4. `/speckit.implement` per task.
5. Open PR, label `chore`, assign paolino, CI green, merge via rebase.
6. Close ticket #5. The issue-dependency graph unblocks #6 and #8 simultaneously.

## Complexity Tracking

No violations. Table omitted.
