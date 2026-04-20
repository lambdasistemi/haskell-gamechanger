# Feature Specification: GameChanger.Intent — operational-monad surface + smart constructors

**Feature Branch**: `005-gamechanger-intent`
**Created**: 2026-04-20
**Status**: Draft
**Tracks**: [#8](https://github.com/lambdasistemi/haskell-gamechanger/issues/8)
**Input**: A typed Haskell surface for authoring GameChanger scripts
using `do`-notation, backed by `Control.Monad.Operational`. This
ticket ships the **surface only** — the GADT of primitives, the
`Program`-based monad, smart constructors, and the `declareExport`
combinator. The compiler from `Intent a` to
`GameChanger.Script.Script` lands in ticket #9; this ticket only
has to produce a `voteOnProposal`-shaped program whose type-checks
are a harness for future compilation.

## User Scenarios & Testing

### User Story 1 — Author a typed flow in `do`-notation (Priority: P1)

A backend author holds the `GameChanger.Script` types from #6 and
the encoder from #7, and wants to write a flow like "get UTxOs,
build a tx against them, sign it, submit it" without copying a
`{get('cache.<name>')}` string into three `detail` fields by hand.
They import `GameChanger.Intent`, open `do`-notation, and each
`<-` binding is a typed handle on the result of an action. Rebinding
the same handle in a later action is a plain Haskell reference —
the wiring is type-checked, not string-matched.

**Why this priority**: The eDSL's entire value proposition is
"stringly-typed wiring becomes typed wiring." Without this story,
the package only exports the JSON boundary and the URL pipeline —
the same thing a JSON writer gets from
[`docs/protocol.md`](../../docs/protocol.md). P1 because it is the
feature.

**Independent Test**: The `voteOnProposal` example from
[`docs/intent-dsl.md`](../../docs/intent-dsl.md) type-checks as a
Haskell module against the shipped `GameChanger.Intent`. A deliberate
typo (e.g. passing `utxos` where an `Address` is expected) is a
compile error, not a runtime failure.

**Acceptance Scenarios**:

1. **Given** the public `GameChanger.Intent` module, **when** an
   author writes
   ```haskell
   voteOnProposal :: Address -> ProposalId -> Vote -> Intent TxId
   voteOnProposal addr pid vote = do
     utxos  <- getUTxOs addr
     tx     <- buildTx (voteConstraints utxos pid vote)
     signed <- signTx tx
     submitTx signed
   ```
   **then** the module type-checks with no orphans and no extensions
   beyond what the library already enables.
2. **Given** the same module, **when** the author accidentally
   writes `signTx utxos` (wrong handle type), **then** GHC rejects
   the program with a type error naming `UTxO` vs `Tx`.
3. **Given** the compiled program, **when** a downstream consumer
   pattern-matches on `Program IntentI a` via
   `Control.Monad.Operational.view`, **then** the cases are exactly
   the five `IntentI` constructors — no typeclass dictionary,
   no free-monad cofunctor.

---

### User Story 2 — Declare an export alongside actions (Priority: P1)

The same author wants the tx id to be delivered back to a callback
URL or shown as a QR. They call `declareExport name source channel`
inside the same `do`-block. Each `Channel` constructor (`Return`,
`Post`, `Download`, `QR`, `Copy`) from `GameChanger.Script.Types` is
reused verbatim — no parallel hierarchy.

**Why this priority**: Exports are the "outputs" half of a
GameChanger script. Shipping actions without exports produces a
surface that can only compile to a `run` map — one half of the
JSON model. The ticket only delivers value end-to-end if it covers
both halves, so P1.

**Independent Test**: An `Intent` program that calls
`declareExport "result" "{get('cache.submit.txHash')}" (Return
"https://example.org/cb")` compiles. A program that passes a typo
for the channel constructor (`Returm`) fails to compile with the
constructor-not-in-scope error.

**Acceptance Scenarios**:

1. **Given** an `Intent a` program, **when** the author calls
   `declareExport "txHash" source (Return url)`, **then** the program
   still has type `Intent a` and the GADT reflects an
   `DeclareExport`-shaped primitive.
2. **Given** a program with two `declareExport` calls for the same
   name, **when** the program is accepted, **then** duplicate
   detection is the compiler's concern (ticket #9) — the surface
   MUST accept duplicates so that the compiler can emit a precise
   error with line numbers.
3. **Given** the `Channel` ADT re-exported from
   `GameChanger.Script.Types`, **when** the author imports
   `GameChanger.Intent` qualified, **then** all five constructors
   are reachable through a single import.

---

### User Story 3 — Reject typeclass-indexed encodings (Priority: P2)

A future contributor, unfamiliar with constitution §11.3, opens a
PR that re-expresses the surface as a `class MonadIntent m where
getUTxOs :: Address -> m [UTxO]; …`. The ticket's test suite
catches the drift: the smoke test imports the operational
constructor names directly and calls `view` on the resulting
`Program`. A typeclass-indexed rewrite would not expose those names
and the test would fail to compile.

**Why this priority**: The constitution forbids final-tagless.
Encoding that rule in a test that fails the CI gate — not just in
prose — makes the rule load-bearing. Not P1 because the test adds
no functionality; it only defends the chosen encoding.

**Independent Test**: `test/GameChangerIntentSpec.hs` imports
`Control.Monad.Operational (view, ProgramView(..))` and pattern
matches on `GetUTxOs addr :>>= k`. Any refactor that removes the
operational encoding breaks this test.

**Acceptance Scenarios**:

1. **Given** the published `GameChanger.Intent`, **when** the
   smoke test pattern matches `view program` against `GetUTxOs addr
   :>>= _`, **then** the case binds `addr :: Address`.
2. **Given** a hypothetical refactor to final-tagless encoding,
   **when** CI runs, **then** the smoke test fails with
   `GetUTxOs is not in scope` (the GADT constructor was removed).

---

### Edge Cases

- **Empty `Intent`** — `return x :: Intent x` must type-check and
  pattern-match against the `Return`-shaped `ProgramView` from
  `Control.Monad.Operational` (not to be confused with the wallet's
  `Return` channel, which is `GameChanger.Script.Types.Return`).
- **Polymorphic return** — `Intent` is a `Monad`; `do { return ();
  return () }` must have a polymorphic unit-friendly type.
- **Multiple exports** — two `declareExport` calls in the same
  program are both preserved in the GADT stream; the surface does
  not deduplicate.
- **Non-ASCII handle names** — handles are Haskell identifiers, so
  non-ASCII names are the compiler's concern, not the DSL's.
- **Orphan instances** — the module MUST NOT define any orphan
  `Monad`/`Applicative`/`Functor` instances; `Program` already
  supplies them via `operational`.

## Requirements

### Functional Requirements

- **FR-001**: A public module `GameChanger.Intent` MUST export
  `IntentI` (GADT) with the five constructors `GetUTxOs`, `BuildTx`,
  `SignTx`, `SignData`, `SubmitTx`, matching the `ActionKind` set
  from `GameChanger.Script.Types`.
- **FR-002**: `GameChanger.Intent` MUST export `type Intent =
  Program IntentI` where `Program` is
  `Control.Monad.Operational.Program`. No newtype wrapper.
- **FR-003**: Smart constructors `getUTxOs`, `buildTx`, `signTx`,
  `signData`, `submitTx` MUST each delegate to
  `Control.Monad.Operational.singleton` on the corresponding GADT
  constructor.
- **FR-004**: A combinator `declareExport :: Text -> Text -> Channel
  -> Intent ()` MUST exist and MUST reuse the `Channel` ADT from
  `GameChanger.Script.Types` — no parallel type. A sixth GADT
  constructor `DeclareExport :: Text -> Text -> Channel -> IntentI
  ()` carries the payload.
- **FR-005**: Typed handle placeholders (`Address`, `UTxO`, `Tx`,
  `SignedTx`, `Signature`, `TxId`, `BuildArgs`, `ProposalId`,
  `Vote`) MUST be exposed as abstract newtypes or `data` stubs
  sufficient to type-check `voteOnProposal`. The JSON semantics for
  these handles is #9's problem; this ticket only requires them to
  exist, be `Eq`, be `Show`, and be distinct at the type level.
- **FR-006**: The module's Haddock header MUST contain the
  `voteOnProposal` example verbatim from `docs/intent-dsl.md`, with
  a `-- >>>` doctest-style block that at minimum type-checks under
  `cabal haddock --haddock-options=--doctest` if doctest is wired
  (otherwise just compiles).
- **FR-007**: The module MUST NOT introduce a `class MonadIntent m`
  or any typeclass-indexed surface — enforced by a smoke test that
  pattern matches on `ProgramView IntentI a`.
- **FR-008**: `voteOnProposal` (or an equivalent 4-action flow)
  MUST live in `test/` as a harness confirming the public surface
  composes end-to-end; the test asserts that `view program` yields
  `GetUTxOs _ :>>= _` as the first step.
- **FR-009**: `GameChanger.Intent` MUST NOT depend on
  `cardano-api`, `cardano-ledger*`, or `plutus-core` (constitution
  §1).
- **FR-010**: The package MUST gain a new Hackage dependency on
  `operational` (or `operational-extra` if its API is strictly a
  superset); the `nix` project's materialisation refresh travels in
  the same PR.

### Key Entities

- **`IntentI a`** — GADT of primitives; one constructor per
  GameChanger action kind, plus `DeclareExport`. Constructors carry
  the inputs and index the return type in the `a` parameter.
- **`Intent a`** — `Program IntentI a`. The monad the user writes
  programs in.
- **Typed handles** — `Address`, `UTxO`, `Tx`, `SignedTx`,
  `Signature`, `TxId`, `BuildArgs`, `ProposalId`, `Vote`. Abstract
  from this ticket's point of view — only the Haskell types matter.
- **`DeclareExport`** — the sixth GADT case, carrying
  `(name :: Text, source :: Text, channel :: Channel)` and indexing
  `()`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: `voteOnProposal` from `docs/intent-dsl.md` compiles
  against the shipped `GameChanger.Intent` in `test/` with
  `-Wall -Werror`.
- **SC-002**: `grep -r 'class Monad' src/GameChanger/Intent*` is
  empty — no typeclass-indexed surface leaked in.
- **SC-003**: The smoke test pattern-matches `view voteProgram`
  against `GetUTxOs _ :>>= _` and the subsequent steps, verifying
  the operational encoding is reachable to consumers.
- **SC-004**: `docs/intent-dsl.md`'s "Status" section is updated
  in the same commit that ships the code, replacing "Design-phase.
  No code yet." with a link to the module and the test harness.
- **SC-005**: `just ci` green (build + tests + format-check +
  hlint) on every commit in the series.

## Assumptions

- **A1** — The `operational` package on Hackage (≥ 0.2.4) provides
  `Program`, `ProgramView`, `singleton`, and `view` with the API
  described in its README. If it has been superseded (e.g. by a
  fork) the plan phase will name the exact package.
- **A2** — Typed handles (`Address`, `UTxO`, …) need no semantics
  in this ticket. The compiler in #9 will define how they are
  rendered into `{get('cache.<name>')}` references and `detail`
  fragments; this ticket only requires type-level distinctness.
- **A3** — The eDSL targets native GHC only (no WASM), as per
  constitution §11 and [`docs/scope.md`](../../docs/scope.md).
- **A4** — `declareExport` takes a plain `Text` source expression
  (the `{get('…')}` template). A typed template language is a
  future concern — not part of this ticket.

## Dependencies

- **D1** — `GameChanger.Script.Types` (#6) for `Channel`,
  `ActionKind`, etc.
- **D2** — `operational` on Hackage.
- **D3** — No dependency on the encoder from #7; `Intent` is pure
  surface and does not reference URLs.
