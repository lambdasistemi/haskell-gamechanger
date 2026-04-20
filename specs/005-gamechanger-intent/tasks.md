# Tasks — GameChanger.Intent (#8)

**Feature**: GameChanger.Intent — operational-monad surface + smart constructors
**Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md) ·
**Research**: [research.md](./research.md) · **Data model**: [data-model.md](./data-model.md) ·
**Quickstart**: [quickstart.md](./quickstart.md)

## Summary

Five phases; implemented strictly in order. Each commit is a
vertical slice that compiles and passes `just ci` in isolation
(bisect-safe). Per the workflow skill, "docs travel with code":
the `docs/intent-dsl.md` update lives in the same commit as the
surface that replaces "Design-phase" status.

## Phase 1 — Setup

- [ ] T001 Add `operational ^>= 0.2.4` to the library's
  `build-depends` in `haskell-gamechanger.cabal` and to the
  `test` suite. Add `exposed-modules: GameChanger.Intent,
  GameChanger.Intent.Handles` to the library. Confirm
  `nix develop -c cabal build` still resolves.

## Phase 2 — Foundational

**Goal**: Land the abstract typed handles needed by every user
story. No surface module yet — just the data types.

- [ ] T002 [P] Create `src/GameChanger/Intent/Handles.hs` with
  `newtype`s for `Address`, `UTxO`, `Tx`, `SignedTx`,
  `Signature`, `TxId`, `ProposalId`, `Vote`, plus the
  placeholder `data BuildArgs { buildArgsSource :: Text }` —
  exactly the shapes specified in [data-model.md](./data-model.md).
  Derive `(Eq, Show, Generic)`. Haddock every export.

## Phase 3 — User Story 1 (P1): Author a typed flow

**Story goal**: An author writes `voteOnProposal` in do-notation
against `GameChanger.Intent`, it type-checks.

**Independent test**: `test/IntentSpec/VoteOnProposal.hs`
type-checks against the shipped module; a deliberate
`signTx utxos` is a type error.

- [ ] T003 [US1] Create `src/GameChanger/Intent.hs` exposing
  `IntentI` (five action constructors: `GetUTxOs`, `BuildTx`,
  `SignTx`, `SignData`, `SubmitTx`), `type Intent = Program
  IntentI`, and the five smart constructors delegating to
  `singleton`. Re-export the `Handles` module. Module-level
  Haddock with the `voteOnProposal` example verbatim from
  `docs/intent-dsl.md`, inside a `-- >>>` block.
- [ ] T004 [US1] Create `test/IntentSpec/VoteOnProposal.hs`
  containing the exact `voteOnProposal` function from
  `docs/intent-dsl.md` as a top-level definition (not a `let`
  binding). Exported so `IntentSpec` can consume the
  `Program`. The compile is the test.
- [ ] T005 [US1] Extend `test/Spec.hs` to include a new
  `IntentSpec` test group. Create `test/IntentSpec.hs` with a
  single HUnit case that pattern-matches `view program`
  against `GetUTxOs _ :>>= _` and asserts success.

## Phase 4 — User Story 2 (P1): Declare an export

**Story goal**: An author calls `declareExport` inside the same
`Intent`-do-block; the sixth GADT constructor is preserved;
`Channel` is the one from `GameChanger.Script.Types`.

**Independent test**: `voteOnProposalWithExport` from the
quickstart type-checks; `view` surfaces a `DeclareExport` step.

- [ ] T006 [US2] Add the sixth GADT constructor
  `DeclareExport :: Text -> Text -> Channel -> IntentI ()` to
  `src/GameChanger/Intent.hs`, import `Channel` from
  `GameChanger.Script.Types`, and re-export `Channel(..)` from
  `GameChanger.Intent`. Add the smart constructor
  `declareExport :: Text -> Text -> Channel -> Intent ()`.
  Haddock it with a one-line `Return`-channel example.
- [ ] T007 [US2] Extend `test/IntentSpec/VoteOnProposal.hs`
  with `voteOnProposalWithExport` (matches the quickstart
  example verbatim). Extend `test/IntentSpec.hs` with an HUnit
  case that walks `view` past the four actions and asserts
  the fifth step is `DeclareExport "txHash" _ _ :>>= _`.

## Phase 5 — User Story 3 (P2): Enforce the operational encoding

**Story goal**: CI fails if anyone refactors to a
typeclass-indexed surface.

**Independent test**: `test/IntentSpec.hs` must import
`Control.Monad.Operational (view, ProgramView(..))` and
pattern-match GADT constructors by name — removing them from
the public surface breaks the build.

- [ ] T008 [US3] Add a comment-free assertion to
  `test/IntentSpec.hs` that imports `GetUTxOs` and
  `DeclareExport` constructors from `GameChanger.Intent` and
  uses them in a `case … of` that mentions all six
  constructors (wildcard cases are banned — the exhaustiveness
  check is the drift sentinel). `-Wincomplete-patterns` MUST
  keep its `-Werror` teeth.

## Phase 6 — Polish & cross-cutting

- [ ] T009 Update `docs/intent-dsl.md` "Status" section — replace
  "Design-phase. No code yet." with a link to
  `src/GameChanger/Intent.hs` and the test harness, dated
  2026-04-20. The `voteOnProposal` code block in the doc and the
  one in the Haddock header MUST be byte-for-byte identical
  (the test harness file is the reference). Goes in the SAME
  commit as T003 (vertical slice — docs travel with code).
- [ ] T010 Run `nix develop -c just ci`. Fix any fourmolu /
  hlint / Haddock warnings. Confirm `-Wall -Werror` green.

## Dependencies

```text
T001 ─▶ T002 ─▶ T003 ─▶ T004 ─▶ T005 ─▶ T006 ─▶ T007 ─▶ T008 ─▶ T010
                 └── co-committed with T009 ──┘
```

User stories share the same surface module, so there is no
inter-story parallelism — US1 is a strict prerequisite of US2
and US3. Parallelism exists only at the data-model level (T002
is `[P]` because it touches only `Handles.hs`).

## Commit shape (vertical slices)

| Commit | Tasks | Message | Bisect-safe? |
|---|---|---|---|
| 1 | T001 | `build(#8): add operational dep + Intent modules` | Yes — stub modules first, cabal resolves. |
| 2 | T002 | `feat(#8): typed Intent handles (Phase 2)` | Yes — pure newtypes. |
| 3 | T003, T004, T005, T009 | `feat(#8): GameChanger.Intent operational surface (Phase 3, US1)` | Yes — flagship example compiles; docs link updated. |
| 4 | T006, T007 | `feat(#8): declareExport + Channel re-export (Phase 4, US2)` | Yes — extends the GADT non-destructively. |
| 5 | T008 | `test(#8): operational-encoding drift sentinel (Phase 5, US3)` | Yes — test-only. |
| 6 | T010 | (only if fixes needed) `style(#8): …` | n/a if commit 5 left CI green. |

## Independent test criteria

- **US1**: `cabal build lib:haskell-gamechanger test:test` green; `voteOnProposal` compiles; `view program` matches `GetUTxOs _ :>>= _`.
- **US2**: `declareExport` is in scope; `view` of `voteOnProposalWithExport` surfaces `DeclareExport _ _ _`.
- **US3**: CI fails if any constructor is removed from `IntentI`'s export list (exhaustiveness check).

## Suggested MVP

**Phase 3 alone** (US1) is a viable MVP: authors can write
`Intent` programs, `view` them, and hand them off to #9's
compiler when it lands. Phases 4 and 5 add the export path and
the drift sentinel.

## Notes

- Test layout: a single `IntentSpec.hs` driving HUnit cases,
  plus `IntentSpec/VoteOnProposal.hs` as the compile-only
  example. No hspec, no golden tests (the module has no
  published JSON boundary yet).
- No QuickCheck on `Intent a` in this ticket — there is no
  "expected output" to compare against until #9.
- `other-modules` in the cabal `test-suite` stanza must be
  extended to include `IntentSpec` and `IntentSpec.VoteOnProposal`.
