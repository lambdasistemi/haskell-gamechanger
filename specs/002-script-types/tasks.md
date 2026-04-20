---
description: "Task list for feature 002 — GameChanger.Script types + Aeson codec + golden tests"
---

# Tasks: GameChanger.Script types + Aeson codec + golden tests

**Input**: `specs/002-script-types/{spec.md, plan.md, data-model.md, quickstart.md}`
**Branch**: `002-script-types`
**Ticket**: [#6](https://github.com/lambdasistemi/haskell-gamechanger/issues/6)

## Format: `[ID] [P?] [Story] Description`

- `[P]` — can run in parallel with other `[P]` tasks in the same phase (different files, no dependencies).
- `[Story]` — which user story in `spec.md` the task serves. `[-]` means cross-cutting / phase-scoped.

## Path conventions

Single-package cabal at the repo root. `src/GameChanger/Script/` for the new modules. `test/Golden.hs` for the harness. `test/golden/` for the JSON fixtures. Matches plan.md §"Project Structure".

---

## Phase 1: Setup — cabal wiring

**Purpose**: cabal metadata must accept the new modules and deps before any code lands.

- [ ] T001 [-] Add `tasty-golden >=2.3 && <2.4` to the `test-suite test` `build-depends` in `haskell-gamechanger.cabal`.
- [ ] T002 [-] Extend `library` `exposed-modules:` to include `GameChanger.Script`, `GameChanger.Script.Types`, `GameChanger.Script.Smart`. Re-run `cabal-fmt -i` to keep alignment.
- [ ] T003 [-] Extend `library` `build-depends` with `aeson`, `bytestring`, `containers` (exact bounds: `aeson ^>=2.2`, `bytestring >=0.11 && <0.13`, `containers >=0.6 && <0.8`).

**Checkpoint**: cabal file compiles with empty module stubs in the next phase.

---

## Phase 2: Foundational — module stubs + harness skeleton

**Purpose**: every user story needs the modules to exist and the Aeson harness to be pluggable. This phase creates empty stubs that compile and a harness that runs zero fixtures green.

**⚠️ CRITICAL**: no user story work starts until Phase 2 is complete.

- [ ] T004 [P] [-] Create `src/GameChanger/Script/Types.hs` with module header Haddock and the empty declarations `data Script`, `data Action`, `data ActionKind`, `data Export`, `data Channel` — stub definitions are enough to compile (`data Script = Script deriving (Show, Eq)` style). Export list explicit.
- [ ] T005 [P] [-] Create `src/GameChanger/Script/Smart.hs` with module header Haddock and no exports yet. Imports `GameChanger.Script.Types`.
- [ ] T006 [P] [-] Create `src/GameChanger/Script.hs` that re-exports `GameChanger.Script.Types` and `GameChanger.Script.Smart`.
- [ ] T007 [-] Extend `test/Spec.hs` to invoke a tasty `testGroup` named `"Script"` that currently contains zero tests. Add `test/Golden.hs` exporting `goldenTests :: IO TestTree` that uses `Test.Tasty.Golden.findByExtension` against `test/golden/` and returns an empty tree until fixtures are added.

**Checkpoint**: `just build` and `just test` both succeed against the empty harness.

---

## Phase 3: User Story 1 — round-trip a hand-built Script (Priority: P1) 🎯 MVP

**Goal**: a Haskell caller can build a `Script` with smart constructors, encode it to JSON, decode it back, and get `(==)`-equal value.

**Independent Test**: `cabal repl` session per [quickstart.md](./quickstart.md); `Aeson.eitherDecode (Aeson.encode script) == Right script`.

- [ ] T008 [US1] In `src/GameChanger/Script/Types.hs`, flesh out the records per [data-model.md](./data-model.md): `Script`, `Action`, `ActionKind` (closed sum), `Export`, `Channel` (closed sum with per-constructor record fields). Derive `Show`, `Eq`, `Generic`.
- [ ] T009 [US1] Write `ToJSON`/`FromJSON` for `ActionKind` — tag strings `buildTx` / `signTx` / `signData` / `submitTx` / `getUTxOs`. Decoder MUST reject unknown strings with an `Aeson` error naming the offending value (FR-009).
- [ ] T010 [US1] Write `ToJSON`/`FromJSON` for `Channel` — tag field is `mode` with strings `return` / `post` / `download` / `qr` / `copy`, per-mode descriptor fields flattened into the same object, `Copy` has no extras. `qrOptions` omitted when `Nothing`.
- [ ] T011 [US1] Write `ToJSON`/`FromJSON` for `Export` — flattens `source` and `channel` into a single object (shares the object with the channel's descriptor fields).
- [ ] T012 [US1] Write `ToJSON`/`FromJSON` for `Action` — object shape `{type, namespace, detail}`. `type` from `ActionKind`.
- [ ] T013 [US1] Write `ToJSON`/`FromJSON` for `Script` — object shape `{type:"script", title, description?, run, exports, metadata?}`. Encoder omits `description` / `metadata` when `Nothing`; decoder accepts omission. Decoder rejects a root `type` other than `"script"` with an error naming the offending value.
- [ ] T014 [US1] In `src/GameChanger/Script/Smart.hs` add one smart constructor per action kind: `buildTxAction`, `signTxAction`, `signDataAction`, `submitTxAction`, `getUTxOsAction`. Each takes the minimal required inputs as positional args and returns an `Action` whose `detail` is an `Aeson.Object`. Signatures picked to match the documented detail payloads (FR-005; match the shapes referenced in the published `script-builder` docs).
- [ ] T015 [US1] Re-export the public surface from `src/GameChanger/Script.hs`: the five constructors, all five data types, and the `ActionKind`/`Channel` values. Explicit export list.
- [ ] T016 [US1] Add a tasty-hunit `testCase "round-trip hand-built Script"` in `test/Spec.hs` under the `"Script"` group. Build a `Script` via smart constructors covering at least one of each action kind and each channel mode; assert `Aeson.eitherDecode (Aeson.encode s) == Right s`.

**Checkpoint**: US1 green. MVP achieved — downstream tickets can build + round-trip Scripts.

---

## Phase 4: User Story 2 — golden fixtures round-trip byte-equal (Priority: P1) 🎯 MVP

**Goal**: every fixture in `test/golden/` decodes, re-encodes, and matches its on-disk canonical form.

**Independent Test**: `just test` runs the golden harness and every fixture passes without a manual entry in the harness.

- [ ] T017 [P] [US2] Create `test/golden/sign-data.json` — minimal valid script exercising `signData` + `copy` export. Source from the published docs where possible; otherwise construct by hand and verify against the wallet manually later.
- [ ] T018 [P] [US2] Create `test/golden/build-tx.json` — exercises `buildTx` + `post` export.
- [ ] T019 [P] [US2] Create `test/golden/sign-tx.json` — exercises `signTx` + `return` export.
- [ ] T020 [P] [US2] Create `test/golden/submit-tx.json` — exercises `submitTx` + `post` export.
- [ ] T021 [P] [US2] Create `test/golden/get-utxos.json` — exercises `getUTxOs` + `copy` export.
- [ ] T022 [P] [US2] Create `test/golden/export-return.json`, `export-post.json`, `export-download.json`, `export-qr.json`, `export-copy.json` — each a minimal one-action script whose exports block exercises exactly one channel. Separate files so the harness surfaces which mode fails in isolation.
- [ ] T023 [US2] Implement the harness in `test/Golden.hs`: `findByExtension [".json"] "test/golden"` → for each path produce a `goldenVsStringDiff path diff (canonicalise path) (canonicalise <$> (decode >=> pure . encode) <$> readFile path)` test. `canonicalise :: ByteString -> ByteString` decodes to `Value` then re-encodes via `Aeson.encode` with sorted keys (use `aeson-pretty`'s `encodePretty` with `Config { confIndent = 2, confCompare = compare, ... }` or hand-roll a canonicaliser) — per plan.md D6.
- [ ] T024 [US2] Wire `goldenTests` into `test/Spec.hs`'s `"Script"` group.
- [ ] T025 [US2] Run `just test`; on first run, every fixture may be re-canonicalised — commit the canonical forms. On the second run, all golden cases must report OK.

**Checkpoint**: US2 green. Published-shape regressions trip the harness.

---

## Phase 5: User Story 3 — smart-constructor sanity test (Priority: P2)

**Goal**: a small unit test exercises every smart constructor and asserts the resulting JSON has the expected action-kind tag.

**Independent Test**: add a smart constructor call + an assertion; verify it passes.

- [ ] T026 [US3] Add a tasty-hunit `testCase "smart constructors emit the right type tag"` under `"Script"`. For each constructor, build an `Action`, encode it, decode to `Value`, and assert the `type` field matches the expected string. Catches accidental constructor/tag drift.

**Checkpoint**: US3 green. Refactoring a smart constructor that changes the tag fails loudly.

---

## Phase 6: User Story 4 — regression surface (Priority: P2)

**Goal**: a deliberate field rename trips the golden harness with a clear error.

**Independent Test**: manually rename a field (e.g. `description` → `desc`) locally, run `just test`, observe a failure that names the fixture path and the diverging JSON field. Revert.

- [ ] T027 [US4] No new code. Verify US4 by hand per the manual test above; paste the failing test output into the PR body as evidence (SC-005 also references this kind of evidence).

**Checkpoint**: US4 validated by demonstration.

---

## Phase 7: Polish & cross-cutting

- [ ] T028 [P] [-] Add module-level Haddock headers to `GameChanger.Script.Types` and `GameChanger.Script.Smart` describing the role each plays and linking back to the constitution's §8 (JSON boundary).
- [ ] T029 [P] [-] Run `just format` (fourmolu + cabal-fmt) then `just format-check` to confirm the tree is clean.
- [ ] T030 [-] Run `just hlint` clean. Resolve any hints in-place — no follow-up commit.
- [ ] T031 [-] Manual wallet check (SC-005): feed `sign-data.json` through the docs' script-builder endpoint, confirm the wallet opens the expected confirmation dialog, paste evidence in the PR body.
- [ ] T032 [-] Open PR with title `feat: GameChanger.Script types + Aeson codec + golden tests (#6)`, label `feat`, assign `paolino`. Paste the quickstart recipe in the PR body.
- [ ] T033 [-] Wait for CI green; merge via `mcp__merge-guard__guard-merge method: rebase`. Remove the worktree.
- [ ] T034 [-] Close #6 with landing note; confirm #7 and #9 blockers update in the planner dependency graph.

---

## Dependencies & execution order

### Phase dependencies

- **Phase 1 (Setup)** — no deps; runs first.
- **Phase 2 (Foundational)** — depends on Phase 1. Blocks every user story.
- **Phase 3 (US1)** — depends on Phase 2.
- **Phase 4 (US2)** — depends on Phase 3 (needs the codec from US1 to canonicalise fixtures).
- **Phase 5 (US3)** — depends on Phase 3.
- **Phase 6 (US4)** — depends on Phase 4 (needs a fixture to regress against).
- **Phase 7 (Polish)** — depends on all stories.

### Task-level critical path

```
T001..T003 → T004..T007 → T008..T016 → T017..T025
                                  ↘ T026
                                  ↘ T027 (manual)
                                           → T028..T034
```

### Parallel opportunities

- T004, T005, T006 are different files; run in parallel.
- T017..T022 are all golden fixtures; write in parallel.
- T028, T029 are orthogonal polish; run in parallel.

---

## Implementation strategy

MVP-first: Phase 1 + Phase 2 stand up the scaffolding. Phase 3 (US1) delivers a typed round-trip — the minimum viable value. Phase 4 (US2) adds the golden harness, which is where the published-boundary guarantee actually lives. Phases 5–6 are verification layers. Phase 7 cleans up and ships.

Each phase ends in a green commit. No phase leaves behind a broken build.

---

## Notes

- Every commit must compile and `just ci` clean — bisect-safe per the workflow skill.
- If a golden fixture reveals a JSON shape our records do not model, the fix is in the **records + data-model.md + docs + constitution §8** — one vertical commit per the governance rule, not a one-off fixture tweak.
- Do not introduce `cardano-api`, `cardano-ledger`, or `plutus-core` deps (FR-011). `detail` is `Value` for now.
- `tasty-golden` is new at Phase 1 — expect a modest first-CI build time, cached after.
