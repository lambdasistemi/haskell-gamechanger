# Intent eDSL

`GameChanger.Intent` is the intended *surface* for writing
GameChanger scripts in Haskell. It sits on top of
`GameChanger.Script` (the low-level, JSON-faithful layer) and
compiles down to the same JSON a hand-written script would emit.

It is a **surface, not a semantics.** It does not evaluate wallet
actions, does not simulate transactions, and does not add any
capability the protocol does not already support. It only moves
errors from wallet-execution time to compile time.

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

An eDSL in Haskell, with the right monadic structure, fixes both:
typed bindings for wiring, and ordinary Haskell functions for
composition.

## Shape

The underlying machinery is
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
`{get('cache.<name>')}` reference in the emitted JSON. A typo no
longer compiles.

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

The eDSL + encoder build both natively (for Haskell backends) and
as WASM (for browser pages). The compiler does not perform IO, does
not touch keys, and has no platform-specific code — so the two
builds share 100% of the source.

This unlocks all three integration topologies from a single
library:

| Topology | Where the eDSL runs | What it emits |
|---|---|---|
| Client-only ([§6.1](integration.md#1-client-only)) | In-browser via WASM | Resolver URL for `window.open` |
| Client + backend callback ([§6.2](integration.md#2-client-backend-callback)) | In the Haskell backend | Resolver URL with a `post` export |
| Backend-only issuer ([§6.3](integration.md#3-backend-only-issuer)) | In the Haskell backend | Resolver URL, rendered as QR or printed |

## Invariants

Recorded formally in the [constitution §11.3](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md):

1. **Surface-only.** For every `Intent a`, there exists a
   handwritten JSON script with identical wallet behavior.
2. **Deterministic compilation.** Same `Intent` → same JSON.
3. **No runtime effects.** Compilation is pure.
4. **WASM-neutral.** Identical under native GHC and
   `wasm32-wasi-ghc`.

## Status

Design-phase. No code yet. The shape described above is the target
surface; implementation follows once the
[constitution](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md) and this page
stabilize.
