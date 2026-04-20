# Intent eDSL

`GameChanger.Intent` is the intended *surface* for writing
GameChanger scripts in Haskell. It sits on top of
`GameChanger.Script` (the low-level, JSON-faithful layer) and
compiles down to the same JSON a hand-written script would emit.

It is a **surface, not a semantics.** It does not evaluate wallet
actions, does not simulate transactions, and adds no capability
beyond the published DSL. It only moves errors from
wallet-execution time to compile time.

It is **backend-only.** This library does not target the browser.
See [scope](./scope.md) for why, and
[Integration §6.2 / §6.3](./integration.md) for the topologies this
serves.

## Why an eDSL

Hand-written GameChanger JSON has two rough edges for anything
non-trivial:

1. **Untyped wiring.** Actions reference each other via
   `{get('cache.<name>')}` template expressions — stringly-typed
   across the entire script. A typo in a name is only caught by
   the wallet at run time.
2. **No composition.** "Sign a tx with extra metadata" is a pattern
   you copy-paste between scripts. JSON gives no mechanism to
   factor it out.

An eDSL in Haskell, with a monadic structure, fixes both: typed
bindings for wiring, and ordinary Haskell functions for
composition.

## Shape

The encoding is
[`Control.Monad.Operational`](https://hackage.haskell.org/package/operational).
Primitives are a GADT; the monad is `Program`:

```haskell
data IntentI a where
  GetUTxOs :: Address -> IntentI [UTxO]
  BuildTx  :: BuildArgs -> IntentI Tx
  SignTx   :: Tx -> IntentI SignedTx
  SignData :: Address -> Text -> IntentI Signature
  SubmitTx :: SignedTx -> IntentI TxId

type Intent = Program IntentI
```

User-level flows are ordinary `do`-notation:

```haskell
voteOnProposal :: Address -> ProposalId -> Vote -> Intent TxId
voteOnProposal addr pid vote = do
  utxos  <- getUTxOs addr
  tx     <- buildTx (voteConstraints utxos pid vote)
  signed <- signTx tx
  submitTx signed
```

Each `<-` is a GameChanger action name. Each reference to a bound
variable (`utxos`, `tx`, `signed`) is, after compilation, a
`{get('cache.<name>')}` reference in the emitted JSON. A typo in
wiring no longer compiles.

Operational is a deliberate choice over typeclass-indexed encodings
(final-tagless). The compiler pattern-matches on each `IntentI`
constructor to emit the corresponding `run`-block entry;
operational's `view` exposes exactly that structure. No typeclass
surface is introduced.

## Compilation

A pure interpreter folds an `Intent a` into a
`GameChanger.Script`:

- Each primitive becomes a named entry in the `run` block.
  Compiler-generated names are stable (hash-derived from the
  program structure).
- Each monadic bind becomes a `{get('<namespace>.<name>')}`
  template expression, fed into the next action's `detail` in the
  right positions.
- The final return value, or explicit `declareExport` combinators,
  drive the `exports` clause.

Compilation is **pure and deterministic**: the same `Intent`
produces the same JSON, byte-for-byte.

## Deployment

Native GHC, linked into whatever backend already talks to
`cardano-node`. No WASM, no browser shim.

```
┌─────────────────────────────────────────────┐
│  Your Haskell service (MPFS, MOOG, your app)│
├─────────────────────────────────────────────┤
│  haskell-gamechanger                        │
├─────────────────────────────────────────────┤
│  cardano-api / cardano-node-clients         │
└─────────────────────────────────────────────┘
```

The browser side — the page that opens a resolver URL and receives
a `return` or drives a `post` — is the integrator's responsibility
and is not part of this library. `GameChanger.Script`'s JSON
schema is the published boundary; any language can produce scripts
that the wallet will accept, and any language can consume the
published JSON schema to build its own typed surface.

## Invariants

Recorded formally in the
[constitution §11.3](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md):

1. **Surface-only.** For every `Intent a`, there exists a
   handwritten JSON script with identical wallet behavior.
2. **Deterministic compilation.** Same `Intent` → same JSON.
3. **No runtime effects.** Compilation is pure.
4. **Native-only.** The eDSL and its compiler target native GHC
   against `cardano-api` / `cardano-node-clients`. No WASM target.

## Status

Shipped 2026-04-20 in
[`GameChanger.Intent`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/src/GameChanger/Intent.hs)
and
[`GameChanger.Intent.Handles`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/src/GameChanger/Intent/Handles.hs).
The surface above — `IntentI` GADT, `type Intent = Program IntentI`,
smart constructors, and `declareExport` — is the exact public API.
The type-check harness for the `voteOnProposal` example lives in
[`test/IntentSpec/VoteOnProposal.hs`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/test/IntentSpec/VoteOnProposal.hs).

The compiler that folds `Intent a` into `GameChanger.Script.Script`
is tracked by
[#9](https://github.com/lambdasistemi/haskell-gamechanger/issues/9).
