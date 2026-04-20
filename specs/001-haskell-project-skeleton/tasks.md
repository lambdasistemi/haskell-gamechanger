---
description: "Task list for feature 001 — Haskell project skeleton + haskell.nix + CI Build Gate"
---

# Tasks: Haskell project skeleton + haskell.nix + CI Build Gate

**Input**: `specs/001-haskell-project-skeleton/{spec.md, plan.md, quickstart.md}`
**Branch**: `feat/issue-5-skeleton`
**Ticket**: [#5](https://github.com/lambdasistemi/haskell-gamechanger/issues/5)

## Format: `[ID] [P?] [Story] Description`

- `[P]` — can run in parallel with other `[P]` tasks in the same phase (different files, no dependencies).
- `[Story]` — which user story in `spec.md` the task serves.
- `[-]` — task crosses stories (infrastructure) or is phase-scoped.

## Path conventions

Single-package cabal project at the repo root. Haskell under `src/`, `app/`, `test/`. Nix split under `nix/`. See `plan.md` §"Project Structure".

---

## Phase 1: Setup (shared infrastructure)

**Purpose**: files that every user story needs before any Haskell code compiles.

- [ ] T001 [-] Create `cabal.project` at repo root pinning `index-state`, wiring CHaP as a `source-repository-package`, and setting `tests: True`.
- [ ] T002 [-] Create `cabal.project.local` with `-O0` and `-Wwarn` for dev builds (gitignored).
- [ ] T003 [-] Create `haskell-gamechanger.cabal` with three stanzas:
  - `library` exposing `GameChanger`, hs-source-dirs: `src`, build-depends: `base, text`
  - `executable hgc` with `main-is: Main.hs`, hs-source-dirs: `app`
  - `test-suite test` using `exitcode-stdio-1.0`, hs-source-dirs: `test`, build-depends: `base, tasty, tasty-hunit, haskell-gamechanger`
- [ ] T004 [-] Add `CLAUDE.md` at the repo root pointing at the workflow skill and linking the constitution (spec FR-016).
- [ ] T005 [-] Extend `.gitignore` for `dist-newstyle/`, `cabal.project.local`, `.ghc.environment.*`, `result`, `result-*`.

**Checkpoint**: cabal file exists but is not yet buildable (no source files).

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: minimum Haskell source so `cabal build` has something to compile, and flake inputs so `nix build` can resolve `haskell.nix`.

**⚠️ CRITICAL**: no user story work can start until Phase 2 is complete.

- [ ] T006 [P] [-] Create `src/GameChanger.hs` exporting `version :: Text` with the current cabal version (read at compile time via `CPP` or hard-coded for now — keep it trivial).
- [ ] T007 [P] [-] Create `app/Main.hs` that prints `hgc <version>` and exits 0. No `optparse-applicative` yet — a `--version` flag check on `args` is enough.
- [ ] T008 [P] [-] Create `test/Spec.hs` with a single `tasty-hunit` test asserting `GameChanger.version` is non-empty.
- [ ] T009 [-] Rewrite `flake.nix` as a thin wrapper: inputs (`nixpkgs`, `haskell-nix`, `flake-utils`, `CHaP`), outputs per system via `flake-utils.lib.eachSystem` for `x86_64-linux`, importing `./nix/project.nix`, `./nix/checks.nix`, `./nix/apps.nix` and exposing:
  - `packages.default = project.hsPkgs.haskell-gamechanger.components.exes.hgc`
  - `devShells.default = project.shell`
  - `checks = import ./nix/checks.nix { ... }`
  - `apps = import ./nix/apps.nix { ... }`
- [ ] T010 [-] Create `nix/project.nix` defining a `haskell.nix` `cabalProject'` pinned to GHC 9.6.6, referencing CHaP as an extra input-map, declaring the dev shell with `fourmolu`, `hlint`, `cabal-fmt`, `just`, `cabal-install` as `tools`, and using `shell.withHoogle = false` to keep startup fast.
- [ ] T011 [-] Create `nix/checks.nix` exposing `library`, `exe`, `tests`, and `lint` (a `pkgs.writeShellApplication` running fourmolu check + cabal-fmt check + hlint across `src app test`).
- [ ] T012 [-] Create `nix/apps.nix` wrapping the runnable checks (`exe`, `tests`, `lint`) via `pkgs.lib.getExe` so `nix run .#hgc`, `nix run .#tests`, `nix run .#lint` all work.
- [ ] T013 [-] Run `nix flake update` once, commit the resulting `flake.lock`.

**Checkpoint**: `nix develop -c cabal build all` and `nix build .#checks.x86_64-linux.library` both succeed from a fresh clone.

---

## Phase 3: User Story 1 — A later ticket can add a module and ship it (P1) 🎯 MVP

**Goal**: `nix develop -c just build` and `nix develop -c just test` work on a fresh clone with the empty library; adding a module to cabal picks it up without further config.

**Independent test**: clone the branch, run the two commands, verify they succeed.

- [ ] T014 [US1] Create `justfile` with recipes: `default` (→ `build`), `build` (`cabal build all`), `test` (`nix run .#tests`), `format` (in-place fourmolu + cabal-fmt), `format-check` (check-only fourmolu + cabal-fmt), `hlint` (hlint src app test), `lint` (`nix run .#lint`), `ci` (build + test + format-check + hlint).
- [ ] T015 [US1] Verify `nix develop -c just build` succeeds on a clean worktree.
- [ ] T016 [US1] Verify `nix develop -c just test` succeeds and the trivial test runs.
- [ ] T017 [US1] Verify adding a dummy module `GameChanger.Smoke` to `src/` and to `exposed-modules:` picks it up on `just build` without any flake / justfile / CI edits (spec SC-004). Revert the dummy module before committing.

**Checkpoint**: Story 1 green. Any downstream ticket can now extend the library by editing only cabal + `src/`.

---

## Phase 4: User Story 2 — CI exercises the Build Gate pattern (P1)

**Goal**: CI runs `build-gate` first, fans out to `tests` and `lint`, all three pass on a freshly pushed PR; downstream jobs benefit from the warm store.

**Independent test**: push the branch, open a draft PR, observe the workflow topology and completion time.

- [ ] T018 [US2] Replace the stub `.github/workflows/ci.yml` with a workflow whose `build-gate` job runs on `nixos`, uses `cachix/cachix-action@v15` with the `paolino` cache and `CACHIX_AUTH_TOKEN` secret, and runs `nix build --quiet .#checks.x86_64-linux.{library,exe,tests,lint} .#devShells.x86_64-linux.default.inputDerivation`.
- [ ] T019 [US2] Add a `tests` job in the same workflow, `needs: build-gate`, running `nix run .#tests --quiet`.
- [ ] T020 [US2] Add a `lint` job in the same workflow, `needs: build-gate`, running `nix run .#lint --quiet`.
- [ ] T021 [US2] Add `concurrency: group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true` at the workflow top level.
- [ ] T022 [US2] Push the branch, wait for CI, confirm all three jobs succeed and wall-clock is within SC-002 (<4 min warm).

**Checkpoint**: Story 2 green. CI matches the `new-repository` skill template and the shared-runner invariant holds.

---

## Phase 5: User Story 3 — `just` recipes are the one way to run local checks (P1)

**Goal**: `just ci` runs every gate CI runs, in the same order. `format-check` fails on violations rather than silently fixing.

**Independent test**: `just --list` shows the expected recipes; `just ci` green on clean tree; `just format-check` red after introducing a formatting violation.

- [ ] T023 [US3] Sanity-check the `justfile` from T014 matches FR-007: recipes `build`, `test`, `format`, `format-check`, `hlint`, `lint`, `ci` all present.
- [ ] T024 [US3] Add a malformed Haskell file (extra trailing space, misindented `do` block) temporarily to `src/`; run `just format-check`; assert it fails with a non-zero exit and names the file. Revert the malformation.
- [ ] T025 [US3] Run `just ci` on a clean tree; assert exit 0 and that each gate name is printed as it runs.

**Checkpoint**: Story 3 green. `just ci` is the local analogue of the CI workflow.

---

## Phase 6: User Story 4 — Flake outputs are discoverable and CI-shaped (P2)

**Goal**: `nix flake show` lists `packages.default`, `devShells.default`, at least one `apps.*`, and at least four `checks.*` entries.

**Independent test**: run `nix flake show` and inspect.

- [ ] T026 [US4] Run `nix flake show` on the branch; capture output; confirm:
  - `packages.x86_64-linux.default` present and typed as `package`
  - `devShells.x86_64-linux.default` present
  - `apps.x86_64-linux.{hgc, tests, lint}` present
  - `checks.x86_64-linux.{library, exe, tests, lint}` present
- [ ] T027 [US4] Cross-reference the `apps` names against CI workflow `nix run .#<name>` invocations in `.github/workflows/ci.yml`; assert every CI reference resolves.

**Checkpoint**: Story 4 green.

---

## Phase 7: User Story 5 — Docs CI stays green (P2)

**Goal**: the existing `deploy-docs.yml` workflow still runs and passes on the PR; the surge preview deploys as before.

**Independent test**: open the PR, check the `Docs (strict build + PR preview)` check and the surge sticky-comment URL.

- [ ] T028 [US5] Confirm `.github/workflows/deploy-docs.yml` is unchanged by this branch's diff.
- [ ] T029 [US5] After pushing, confirm the Docs check is green on the PR and that a surge preview URL appears as a sticky comment.
- [ ] T030 [US5] Manually browse the preview URL and verify the Scope / Intent eDSL / Protocol pages render.

**Checkpoint**: Story 5 green.

---

## Phase 8: Polish & cross-cutting concerns

- [ ] T031 [P] [-] Add short Haddock headers to `GameChanger.hs`, `app/Main.hs`, `test/Spec.hs` — one sentence each describing the module's role in the skeleton.
- [ ] T032 [P] [-] Verify `fourmolu -m check` and `hlint` are clean against the skeleton (resolve any warnings here, not in a follow-up commit).
- [ ] T033 [-] Open the PR with title `feat: haskell project skeleton + haskell.nix + CI Build Gate (#5)`, label `chore`, assign `paolino`. Include the quickstart commands in the PR body as the reviewer's verification recipe.
- [ ] T034 [-] Wait for CI green; merge via `mcp__merge-guard__guard-merge` with `method: rebase`; remove the worktree after merge.
- [ ] T035 [-] Close ticket #5; confirm issue-dependency graph unblocks #6 and #8 on the planner board.

---

## Dependencies & execution order

### Phase dependencies

- **Phase 1 (Setup)** — no dependencies; can start immediately.
- **Phase 2 (Foundational)** — depends on Phase 1. Blocks all stories.
- **Phase 3 (US1)** — depends on Phase 2.
- **Phase 4 (US2)** — depends on Phase 2 and Phase 3 (needs working `just` recipes for local sanity before touching CI).
- **Phase 5 (US3)** — depends on Phase 3 (justfile exists).
- **Phase 6 (US4)** — depends on Phase 2.
- **Phase 7 (US5)** — depends on Phase 4 (PR must exist to observe the Docs workflow running).
- **Phase 8 (Polish)** — depends on all stories.

### Task-level critical path

```
T001..T005 → T006..T008 (parallel) → T009..T012 → T013
                                       ↓
                                     T014 → T015,T016 → T017
                                       ↓
                                     T018..T022
                                       ↓
                                     T023..T025, T026..T027, T028..T030
                                       ↓
                                     T031,T032 (parallel) → T033 → T034 → T035
```

### Parallel opportunities

- T006, T007, T008 operate on different files; run in parallel.
- T031, T032 operate on different concerns; run in parallel.
- Stories 3, 4, 6 are orthogonal once Phase 2 + T014 are done; a second contributor could pick up US4 while US2 is in flight.

---

## Implementation strategy

MVP-first: complete Phases 1–3, stop and validate User Story 1 (an empty library that builds locally end-to-end). Only then layer on CI (Phase 4), justfile polish (Phase 5), flake discoverability (Phase 6), docs verification (Phase 7). Polish (Phase 8) is the last thing before opening the PR.

Each phase ends in a green commit. No phase leaves behind a broken build, per the `workflow` skill bisect-safety rule.

---

## Notes

- Every commit must compile and `just ci` clean — bisect-safe per the workflow skill.
- Use `stg` if the commit history needs reshaping before the PR.
- Push the branch after Phase 3 so the spec + plan + quickstart + first working skeleton are all browsable; do not batch.
- Do not add release-please, dependabot, or typos workflows in this ticket — explicitly out of scope (plan D5).
- Do not pull `cardano-api` / `cardano-node-clients` into cabal deps here — they arrive with the tickets that need them.
