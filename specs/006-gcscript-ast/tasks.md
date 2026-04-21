---

description: "Task list for #19 — GameChanger.GCScript AST + JSON round-trip"
---

# Tasks: GameChanger.GCScript — upstream AST + JSON round-trip

**Input**: Design documents in `/specs/006-gcscript-ast/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[quickstart.md](./quickstart.md).

**Tests**: Required. SC-001 / SC-002 / SC-003 (spec.md §Success
Criteria) mandate golden corpus + QuickCheck property + Unsupported
coverage. Test tasks are **not** optional for this feature.

**Organization**: by user story (US1 parse, US2 emit, US3 round-trip
corpus, US4 typed access). US1+US2+US3 are P1 and share the MVP
increment; US4 is P2 and depends on US1+US2 already working.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no ordering
  dependency)
- **[Story]**: which user story this task belongs to
- Task descriptions include exact file paths.

## Path conventions

Paths from [plan.md §Project Structure](./plan.md). Repo root:
`/code/haskell-gamechanger-issue-19/`.

- Library source: `src/GameChanger/GCScript*.hs`
- Test source: `test/GCScriptSpec*.hs`
- Golden corpus: `test/golden/gcscript/*.gcscript`

---

## Phase 1: Setup (shared infrastructure)

**Purpose**: cabal wiring, golden directory bootstrap. Runs before
any AST code.

- [ ] T001 Add `GameChanger.GCScript`, `GameChanger.GCScript.Common`,
  and `GameChanger.GCScript.Functions` to the `exposed-modules` list
  in `haskell-gamechanger.cabal`. Add `containers`, `vector` to
  `build-depends` if not already present.
- [ ] T002 [P] Add `test/GCScriptSpec.hs` and
  `test/GCScriptSpec/Generators.hs` to the test-suite's
  `other-modules` in `haskell-gamechanger.cabal`. Add
  `tasty-golden`, `tasty-quickcheck` to test `build-depends`.
- [ ] T003 [P] Create `test/golden/gcscript/` directory and commit a
  `pinned-commit.txt` recording the upstream
  `GameChangerFinance/gamechanger.wallet` sha the corpus is pulled
  from (see research.md R9).

**Checkpoint**: `cabal build` compiles the (empty) new modules and
`cabal test` discovers the (empty) new test suite.

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: the shared types every user story depends on. No US
work can begin until these compile. Organized per
[data-model.md](./data-model.md).

- [ ] T004 [P] Implement `RunBlock` type in
  `src/GameChanger/GCScript/Common.hs` (sum of `RunObject`,
  `RunArray`, `RunISL`). Per data-model.md §`RunBlock`.
- [ ] T005 [P] Implement `ReturnMode` enum + `ReturnSpec` record in
  `src/GameChanger/GCScript/Common.hs`. Per data-model.md
  §`ReturnSpec and ReturnMode`.
- [ ] T006 [P] Implement `CommonAttrs` record + `emptyCommonAttrs`
  helper in `src/GameChanger/GCScript/Common.hs`. Per data-model.md
  §`CommonAttrs`.
- [ ] T007 Implement per-kind body types in
  `src/GameChanger/GCScript/Functions.hs`: `BuildTxBody`,
  `SignTxsBody`, `SubmitTxsBody`, `BuildFsTxsBody`, `SignDataBody`,
  `VerifySigBody`, `QueryBody`, `PlutusScriptBody`,
  `PlutusDataBody`, `NativeScriptBody`, `MacroBody`. Per
  data-model.md §`Per-kind bodies`. Depends on T004 (MacroBody uses
  RunBlock).
- [ ] T008 Implement `FunctionCall` sum in
  `src/GameChanger/GCScript/Functions.hs` with all thirteen
  constructors (`FcBuildTx`, `FcSignTxs`, `FcSubmitTxs`,
  `FcBuildFsTxs`, `FcSignData`, `FcVerifySig`, `FcQuery`,
  `FcPlutusScript`, `FcPlutusData`, `FcNativeScript`, `FcMacro`,
  `FcScript`, `FcUnsupported`). Per data-model.md §`FunctionCall`.
  Depends on T006, T007. `FcScript` requires the forward-declared
  `GCScript`, so introduce a small `.hs-boot` or rearrange modules
  to resolve the cycle — see T009.
- [ ] T009 Implement the `GCScript` record in
  `src/GameChanger/GCScript.hs` (per data-model.md §`GCScript`) and
  resolve the mutual recursion between `GCScript` and
  `FunctionCall` (FcScript carries `GCScript`). Acceptable shapes:
  (a) put both types in one module, (b) use a `.hs-boot` for one
  side. Depends on T008.

**Checkpoint**: AST types compile. No codec yet. `cabal build`
succeeds.

---

## Phase 3: User Story 1 — Parse upstream JSON (Priority: P1) 🎯 MVP part 1

**Goal**: `eitherDecode` accepts real corpus files and produces
typed `GCScript` values (spec.md §US1).

**Independent Test**: spec.md §US1 — every curated corpus file
returns `Right _`.

### Tests for US1

- [ ] T010 [P] [US1] Copy 15 curated corpus files from upstream
  `GameChangerFinance/gamechanger.wallet/examples` into
  `test/golden/gcscript/` using the filenames from plan.md
  §Project Structure. Record the sha in
  `test/golden/gcscript/pinned-commit.txt` (from T003).
- [ ] T011 [P] [US1] Write
  `test/GCScriptSpec/Generators.hs` with QuickCheck `Arbitrary`
  instances for `GCScript`, `RunBlock`, `CommonAttrs`,
  `ReturnSpec`, `FunctionCall`, and all body types. Depth-capped
  per research.md §R8. Not yet exercised — T024 consumes it.
- [ ] T012 [US1] Write a `parseOnly` tasty test in
  `test/GCScriptSpec.hs` that iterates every file in
  `test/golden/gcscript/*.gcscript`, runs `eitherDecode`, and
  asserts `isRight`. Expected to FAIL at this point (no FromJSON
  yet).

### Implementation for US1

- [ ] T013 [P] [US1] `FromJSON` instance for `ReturnMode` +
  `ReturnSpec` in `src/GameChanger/GCScript/Common.hs`. Mode
  string is lowercase; mode-specific fields per data-model.md.
- [ ] T014 [P] [US1] `FromJSON` instance for `CommonAttrs` in
  `src/GameChanger/GCScript/Common.hs`, plus a helper
  `commonAttrsFromObject :: Object -> Parser (CommonAttrs, Object)`
  per data-model.md §Aeson strategy. Depends on T013.
- [ ] T015 [P] [US1] `FromJSON` instance for `RunBlock` in
  `src/GameChanger/GCScript/Common.hs`. Try String → RunISL,
  Array → RunArray, Object → RunObject, per data-model.md
  §`RunBlock` decode rule. Requires `FromJSON FunctionCall` (T017)
  — wire via `.hs-boot` or by putting instances in a separate
  module if necessary.
- [ ] T016 [US1] `FromJSON` instances for each per-kind body
  (`BuildTxBody`, `SignTxsBody`, `SubmitTxsBody`, `BuildFsTxsBody`,
  `SignDataBody`, `VerifySigBody`, `QueryBody`, `PlutusScriptBody`,
  `PlutusDataBody`, `NativeScriptBody`, `MacroBody`) in
  `src/GameChanger/GCScript/Functions.hs`. Each takes the
  `Object` remaining after `commonAttrsFromObject` has stripped
  common keys.
- [ ] T017 [US1] `FromJSON` instance for `FunctionCall` in
  `src/GameChanger/GCScript/Functions.hs`: reads `type`, strips
  `CommonAttrs`, dispatches to the per-kind body parser or falls
  back to `FcUnsupported tag remainingObject`. Depends on T014,
  T016.
- [ ] T018 [US1] `FromJSON` instance for `GCScript` in
  `src/GameChanger/GCScript.hs`: requires `type == "script"`,
  reads the root-level fields, recursively parses `run` as a
  `RunBlock`. Depends on T015, T017.
- [ ] T019 [US1] Run the T012 `parseOnly` test — every curated
  file decodes to `Right _`.

**Checkpoint**: every curated `.gcscript` file parses. US1 AC-1,
AC-2, AC-3 all pass.

---

## Phase 4: User Story 2 — Emit JSON (Priority: P1) 🎯 MVP part 2

**Goal**: encode a `GCScript` to bytes that re-decode equal
(spec.md §US2). This is the other half of the round-trip.

**Independent Test**: spec.md §US2 — encode any decoded value,
re-decode, get the same value.

### Tests for US2

- [ ] T020 [US2] Add a `determinism` tasty test in
  `test/GCScriptSpec.hs`: for each corpus file, decode, encode
  twice, assert the two byte-strings are identical. Expected to
  FAIL (no ToJSON yet). Depends on T019.

### Implementation for US2

- [ ] T021 [P] [US2] `ToJSON` instances for `ReturnMode`,
  `ReturnSpec`, `CommonAttrs`, `RunBlock` in
  `src/GameChanger/GCScript/Common.hs`. `CommonAttrs` emits only
  `Just` fields. `RunBlock` emits the variant's shape. Per
  data-model.md §Aeson strategy.
- [ ] T022 [P] [US2] `ToJSON` instances for each per-kind body in
  `src/GameChanger/GCScript/Functions.hs`. Per-kind bodies emit
  their typed fields (omitting `Nothing`s).
- [ ] T023 [US2] `ToJSON` instance for `FunctionCall` in
  `src/GameChanger/GCScript/Functions.hs`: emits the `type` tag,
  merges `CommonAttrs` fields, merges per-kind body fields.
  `FcUnsupported` emits the stored `Object` plus the `type` tag
  plus `CommonAttrs`. Depends on T021, T022.
- [ ] T024 [US2] `ToJSON` instance for `GCScript` in
  `src/GameChanger/GCScript.hs`. Emits `type: "script"` plus
  root-level fields plus `run`. Depends on T023.
- [ ] T025 [US2] Run T020 `determinism` test — encode is stable
  across runs.

**Checkpoint**: encode is implemented and deterministic. US2 AC-1
and AC-2 pass.

---

## Phase 5: User Story 3 — Round-trip the curated corpus (Priority: P1) 🎯 MVP acceptance gate

**Goal**: `decode >>> encode >>> decode` returns the same value on
every curated file (spec.md §US3). This is the SC-001 acceptance
gate.

**Independent Test**: spec.md §US3 — tasty golden suite asserts
equality.

### Tests for US3

- [ ] T026 [US3] Add a `roundTripGolden` tasty test in
  `test/GCScriptSpec.hs` that iterates
  `test/golden/gcscript/*.gcscript`, runs
  `decode >>> encode >>> decode`, asserts the second decode equals
  the first. Depends on T024.
- [ ] T027 [P] [US3] Add a QuickCheck property
  `prop_roundTrip :: GCScript -> Property` in
  `test/GCScriptSpec.hs` asserting `decode (encode v) == Right v`.
  Uses the generators from T011. `maxSuccess = 100`, depth
  capped. SC-002 acceptance gate. Depends on T024.
- [ ] T028 [P] [US3] Add an `unsupportedCoverage` tasty test in
  `test/GCScriptSpec.hs` asserting that decoded corpus files
  together contain at least three distinct `FcUnsupported` tags.
  SC-003 acceptance gate. Depends on T019.

### Implementation for US3

No new implementation needed — the tests hit the existing decoder
and encoder. Any failure gets fixed in T017 / T023 as a bug fix
and the tests re-run.

**Checkpoint**: SC-001, SC-002, SC-003 green. MVP is shippable.
Paste commit counts: everything through here is one working
`GameChanger.GCScript` module that meets the P1 spec.

---

## Phase 6: User Story 4 — Typed access (Priority: P2)

**Goal**: downstream code can read `buildTx.tx`, `signTxs.txs`,
`script.exportAs`, `return.mode` without `Aeson.Value` spelunking
(spec.md §US4).

**Independent Test**: spec.md §US4 — direct record-field access
returns typed Haskell values.

### Tests for US4

- [ ] T029 [P] [US4] Add a `typedAccess` unit test in
  `test/GCScriptSpec.hs` that decodes
  `test/golden/gcscript/03-minimal-coin-sending-demo.gcscript`,
  extracts the `buildTx` call from its `RunArray`, and asserts
  the `BuildTxBody` field is an `Object`-shaped `Value` (not
  `Null`, not `String`). Tests typed access works end-to-end.
- [ ] T030 [P] [US4] Add a `returnModeAccess` unit test that
  decodes
  `test/golden/gcscript/04-pay-me-1-ada.gcscript`, extracts
  `gcsReturn`, asserts `rsMode == Last`.

### Implementation for US4

No new implementation — T007/T008 already exposed typed record
fields. US4 validates they work.

**Checkpoint**: US4 AC-1 and AC-2 pass. Downstream consumers (#9)
can pattern-match on constructors and project record fields.

---

## Phase 7: Polish & cross-cutting

- [ ] T031 [P] Haddock headers on
  `GameChanger.GCScript`,
  `GameChanger.GCScript.Common`,
  `GameChanger.GCScript.Functions`. Module-level docs should link
  back to spec.md and data-model.md by relative path.
- [ ] T032 [P] Run `fourmolu -m check` on the three source files
  and the two test files. Must pass with no diff. SC-005
  component.
- [ ] T033 [P] Run `cabal-fmt -c haskell-gamechanger.cabal`. Must
  pass. SC-005 component.
- [ ] T034 [P] Run `hlint src/GameChanger/GCScript.hs
  src/GameChanger/GCScript/*.hs test/GCScriptSpec.hs
  test/GCScriptSpec/Generators.hs`. Zero hints. SC-005 component.
- [ ] T035 Grep the library code for `System.IO` /
  `unsafePerformIO` / `Debug.Trace`. Must all be absent. SC-004
  component.
- [ ] T036 Run the quickstart tour from
  [quickstart.md](./quickstart.md) against the real module and
  confirm every snippet type-checks (put them in a commented-out
  `ghci` transcript or a scratch `Main` to verify — do not commit
  the scratch).
- [ ] T037 Run `just ci` end-to-end on the PR branch. Must pass.
  SC-005 final gate.

---

## Dependencies & execution order

### Phase dependencies

- Phase 1 (Setup): no dependencies.
- Phase 2 (Foundational): depends on Phase 1. Blocks all user
  stories.
- Phase 3 (US1 parse) + Phase 4 (US2 emit): both depend on
  Phase 2. US2 does not logically depend on US1, but the tests in
  US2 reuse decoded corpus values, so in practice US1 lands first.
- Phase 5 (US3 round-trip): depends on US1 and US2 being green.
  This is the MVP acceptance phase — no new implementation, only
  tests + bug fixes.
- Phase 6 (US4 typed access): depends on Phase 2's typed records
  (T007, T008) and Phase 3's decoder (T018) being live.
- Phase 7 (Polish): after Phase 5 at the earliest; Phase 6 nice to
  have before final `just ci`.

### Within a user story

- Tests-first: T012 is written before T013–T018 such that the
  decoder is built green-against-red. Same for T020 (US2) and
  T026–T028 (US3).
- Common modules before dependent modules: `Common.hs` codecs
  before `Functions.hs` codecs before `GCScript.hs` codec.
- Story complete before moving on.

### Parallel opportunities

- T002, T003 in Phase 1.
- T004, T005, T006 in Phase 2 (independent types, same file —
  still edit in one go; marked [P] on the understanding that
  their definitions are independent even if co-located).
- T010, T011 in Phase 3 (different files, independent).
- T013, T014, T015 in Phase 3 implementation (Common.hs has
  enough structure to separate instances, but they share the
  file — sequence them if co-located).
- T021, T022 in Phase 4 (different files).
- T027, T028 in Phase 5.
- T029, T030 in Phase 6.
- T031, T032, T033, T034 in Phase 7.

---

## Parallel example: Phase 2 foundational

```text
# Can be worked in one sitting — same module, independent types:
T004 RunBlock             (Common.hs)
T005 ReturnMode/ReturnSpec (Common.hs)
T006 CommonAttrs          (Common.hs)

# Then sequentially:
T007 per-kind bodies       (Functions.hs)   — depends on T004
T008 FunctionCall sum      (Functions.hs)   — depends on T007
T009 GCScript + cycle fix  (GCScript.hs)    — depends on T008
```

---

## Implementation strategy

### MVP (P1 only)

1. Phase 1 (setup) — one commit.
2. Phase 2 (foundational types) — one commit.
3. Phase 3 (US1 parse + tests) — one commit.
4. Phase 4 (US2 emit + tests) — one commit.
5. Phase 5 (US3 corpus round-trip + property + unsupported
   coverage) — one commit.

Five commits delivers the MVP. STOP and verify: golden suite
green, QuickCheck green, `just ci` green.

### Incremental polish

6. Phase 6 (US4 typed access tests) — one commit.
7. Phase 7 (polish / docs / lint) — one commit.

Seven commits total, each a vertical slice per the workflow
skill's "one commit per concern" rule.

---

## Notes

- [P] = different files or independent changes, free to reorder.
- [Story] labels map tasks to user stories for traceability
  against spec.md.
- Each user story is independently testable per spec.md.
- Commit after each task group or phase checkpoint. See workflow
  skill's vertical-commit discipline.
- Avoid: touching `src/GameChanger/Script.hs` (FR-013); adding
  `cardano-api` (FR-011); promoting ISL to `ISL.Expr` (FR-012,
  ticket #20 territory).
