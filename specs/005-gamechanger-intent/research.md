# Phase 0 — Research: GameChanger.Intent

## R1 — Which `operational` package?

**Decision**: `operational ^>= 0.2.4`.

**Rationale**:

- Heinrich Apfelmus's `operational` package (Hackage) provides
  `Program`, `ProgramView`, `singleton`, `view`, `viewT`, and the
  `:>>=` pattern synonym. Its API has been stable since 2012 — no
  recent churn, no breaking changes in the 0.2.x series.
- The package has zero runtime deps beyond `base`, `mtl`, and
  `transformers` — all already in the ghc distribution. No new
  transitive surface.
- Nix/`haskell.nix` materialisation already pulls `operational`
  as an indirect dep of `pipes`, so the Hackage index refresh is
  a no-op. Confirmed by grepping
  `nix/materialized/**/default.nix` (done in plan phase).

**Alternatives considered**:

- **`operational-alacarte`** — adds a "data types à la carte"
  flavour that doesn't fit constitution §11: the GADT is fixed,
  not open.
- **`freer-simple` / `polysemy` / `fused-effects`** — all are
  typeclass-indexed ("effect interpreters"). Directly forbidden
  by §11.1. Rejected.
- **Roll our own `Program` type** — ~15 LOC, trivial, but loses
  the battle-tested `viewT` implementation and forces us to
  reinvent `Applicative` and `Monad` instances. `operational` is
  a better trade for the dep cost.

## R2 — Typed handles: phantom-wrapped `Text`, or abstract `data`?

**Decision**: Abstract `data` (empty data declarations plus a
smart-constructor/stringly-input combo kept minimal).

```haskell
newtype Address   = Address   Text
newtype UTxO      = UTxO      Text  -- placeholder; #9 may refine
newtype Tx        = Tx        Text
newtype SignedTx  = SignedTx  Text
newtype Signature = Signature Text
newtype TxId      = TxId      Text
data BuildArgs    = BuildArgs { … }  -- opaque record, #9 refines
newtype ProposalId = ProposalId Text
newtype Vote      = Vote Text
```

**Rationale**:

- Spec FR-005 requires handles to be `Eq`, `Show`, and
  distinct at the type level. `newtype` over `Text` gives all
  three cheaply, and `deriving (Eq, Show)` satisfies the
  requirement with zero boilerplate.
- The spec explicitly says JSON semantics are #9's concern. Using
  `Text` as the carrier mirrors how the wallet actually refers
  to bound names (`{get('cache.<name>')}`), so #9 can swap the
  internal representation to something hash-derived without
  changing the public API.
- Constructors are exported so tests can build fixture values;
  #9 will hide them behind smart constructors when it lands
  stable-name generation.

**Alternatives considered**:

- **Phantom-tagged `Handle tag` type** — elegant, but introduces
  a single generic carrier that would constrain #9's design
  (e.g. stable-name generation would have to thread through a
  phantom everywhere). Rejected.
- **`data Address` with no constructor** — zero-width, but kills
  the ability to write `voteOnProposal` examples because we
  can't construct an `Address` value for the test. Rejected.
- **Re-use `Data.Aeson.Value`** — couples the surface to aeson
  prematurely. The Intent module should not import `aeson` at
  all — `aeson` enters at the JSON boundary (#9's compiler).
  Rejected.

## R3 — Where does `declareExport` live?

**Decision**: `declareExport` is a smart constructor in
`GameChanger.Intent`; the sixth GADT constructor is
`DeclareExport :: Text -> Text -> Channel -> IntentI ()`.

**Rationale**:

- §11.2 mentions `declareExport` as the combinator driving the
  `exports` clause. Putting it in `GameChanger.Intent` (next to
  the action smart constructors) keeps the surface coherent —
  one module, one import.
- Reusing `Channel` from `GameChanger.Script.Types` prevents the
  parallel-hierarchy smell the spec's US2 warns against.
- Indexing the GADT constructor at `()` (rather than at an
  "export handle") signals that exports are side effects on the
  `run`/`exports` split of the compiled `Script`, not values the
  program can branch on.

**Alternatives considered**:

- **Separate `Export` module** with its own monad — overkill;
  adds an import and buys nothing because exports don't
  compose independently of actions.
- **`declareExport` as a pure post-compilation combinator on
  `Script`** — works, but loses the guarantee that the export
  was declared in the author's `do`-block. Losing that guarantee
  means authors could "forget" to declare exports in #9's
  compiler and get a runtime wallet error instead of a
  type error.

## R4 — Haddock-as-test

**Decision**: Use `-- >>>` doctest-style blocks in the Haddock
header, but do **not** wire doctest into `cabal test` in this
ticket.

**Rationale**:

- Adding doctest changes the test story across the repo.
  Constitution §governance implies docs-and-code travel together,
  but "docs wiring" is itself a scope creep we can skip: the
  `voteOnProposal` example also lives in
  `test/IntentSpec/VoteOnProposal.hs` where it IS compiled by
  the normal `cabal test` pipeline.
- Once doctest is added repo-wide (separate ticket), the
  existing `-- >>>` blocks will start running automatically —
  zero-churn migration.

**Alternatives considered**:

- **Wire doctest now** — rejected; scope creep.
- **No example in Haddock** — rejected; the module header MUST
  carry the flagship example for the module to be usable
  without opening the docs site (FR-006).

## R5 — What about `MonadIO`/`MonadFail`/`Alternative` instances?

**Decision**: None. `Program` provides `Functor`, `Applicative`,
and `Monad` out of the box; no other instances are exported.

**Rationale**:

- `Intent` is a pure AST. `MonadIO` makes no sense — there is
  no IO to lift into the surface (constitution §11.3.3).
- `MonadFail` would let authors call `fail "…"` inside a `do`
  block; that has no sensible JSON encoding. Leaving it out
  makes the compiler in #9 total.
- `Alternative`/`MonadPlus` — no `empty`/`choice` semantics in
  the wallet DSL. The `run` block is an ordered map, not a
  choice tree.

**Alternatives considered**:

- **Reexport `MonadFail Program` via `orphan` instance** —
  rejected; orphans are forbidden by the spec's edge-case rule.
