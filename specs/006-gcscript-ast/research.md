# Research: GameChanger.GCScript AST + codec

**Ticket**: #19 | **Date**: 2026-04-20

## R1 — Source of truth for the upstream shape

**Decision**: the published example corpus at
[`GameChangerFinance/gamechanger.wallet/examples`](https://github.com/GameChangerFinance/gamechanger.wallet/tree/main/examples)
is the canonical shape reference, pinned by commit sha. The prose
docs under `docs/gcscript/` (`syntax.md`, `overview.md`, `ISL.md`)
name fields and values but do not enumerate the function universe
or field-level shapes exhaustively.

**Rationale**: the `overview.md` explicitly names only `script` and
`data`, while `syntax.md` lists the root `script` fields. The
complete function catalogue and per-function field lists live in
the wallet's in-browser API reference
(`https://beta-wallet.gamechanger.finance/doc/api/v2/`), which 403s
to CLI fetchers. The 94-example corpus is the highest-resolution
ground truth we can consume mechanically.

**Alternatives rejected**:

- Scraping the in-browser API reference via a headless browser —
  heavier than needed; the corpus gives us concrete ground truth.
- Requesting a JSON schema from upstream — none published as of
  2026-04-20.

**Pin policy**: we copy each of the 15 curated files into
`test/golden/gcscript/` and record the upstream commit sha in
`pinned-commit.txt`. Re-pinning to a newer upstream sha is a
deliberate action, not a passive drift.

## R2 — `run` as a polymorphic field

**Decision**: `RunBlock` is a sum:

```haskell
data RunBlock
    = RunObject (Map Text FunctionCall)
    | RunArray  [FunctionCall]
    | RunISL    Text
    deriving (Eq, Show, Generic)
```

**Rationale**: corpus inspection confirmed all three shapes occur:

- Object (`Pay me 1 ADA.gcscript`): named children, cache keys are
  the user-chosen names.
- Array (`Minimal Coin Sending Demo.gcscript`,
  `Simple Script No Export No Return URL.gcscript`): anonymous
  children, cache keys are `"0"`, `"1"`, ….
- ISL string (`macro` calls like `CIP-8 Data Signing ...`'s
  `"run": "{getAddressInfo(get('cache...'))}"`): a single inline
  ISL expression. Only legal inside `macro` per our reading of the
  corpus, but we let the type permit it in any `script`-ish
  position and rely on upstream validation.

**Alternatives rejected**:

- Normalize arrays into objects on decode. Loses the ability to
  emit the compact array form the user wrote. Breaks round-trip.
- Force array indices into `"0"`, `"1"` keys. Same problem: the
  emit shape would not match the input shape.
- Model ISL-as-run only on `macro`. Requires coupling
  `FunctionCall`'s `Macro` constructor to a different `run` type
  than `Script`. Adds complexity for a corner case; the
  `RunBlock` sum absorbs it uniformly.

## R3 — `CommonAttrs` record

**Decision**: every `FunctionCall` carries an optional
`CommonAttrs` record:

```haskell
data CommonAttrs = CommonAttrs
    { caTitle            :: !(Maybe Text)
    , caDescription      :: !(Maybe Text)
    , caExportAs         :: !(Maybe Text)
    , caArgs             :: !(Maybe Value)
    , caArgsByKey        :: !(Maybe (Map Text Value))
    , caReturnURLPattern :: !(Maybe Text)
    , caRequire          :: !(Maybe Value)
    , caReturn           :: !(Maybe ReturnSpec)
    }
```

**Rationale**: the corpus shows these eight fields appearing
across many function kinds (root `script`, `buildTx`, nested
`script`, `macro`, etc.), not just on the root. Collapsing them
into a shared record avoids duplicating eight optional fields per
constructor.

**Alternatives rejected**:

- Fields per constructor. Massive duplication (~8 × 12 = 96
  field declarations). Each new function kind repeats the same
  block.
- Name `Attrs` (generic). `CommonAttrs` names the intent
  precisely and doesn't collide with `aeson` conventions.

## R4 — `Unsupported` fallback

**Decision**: a single `Unsupported { fnName :: Text, fnBody ::
Object }` constructor captures any function-call whose `type` tag
is not one of our twelve structured kinds. The `Object` is the
raw JSON with the `type` field intact, so round-trip is trivial.

**Rationale**:

- The corpus uses `importAsScript`, `getCurrentAddress`,
  `getStakingPublicKey`, `getName`, `getMainAddress`,
  `saveConfig`, `loadConfig`, `encrypt`, `decrypt`, `deriveKeys`,
  and more. Structuring all of them up front is wasted effort if
  `Intent` (#9) only needs the twelve we named.
- Promoting any of these to structured later is a two-step
  change: add a constructor, shift the decoder, run the goldens.
  Round-trip never regresses because we control both halves.

**Alternatives rejected**:

- Model all 43 up front. Too much speculative surface for
  functions no downstream caller uses.
- Refuse to decode anything outside the twelve. Fails on most
  of the real corpus.

## R5 — Deterministic JSON emit

**Decision**: emit via `Aeson.encode` with
`Data.Aeson.Encoding.pairs` threaded explicitly by the `ToJSON`
instance, so field order is under our control. For inner
`Map Text FunctionCall` values (the `RunObject` case), we preserve
insertion order using `Data.Map.Strict.toAscList` (lexicographic
on keys). For the `Object` payload inside `Unsupported`, we
re-encode via `Aeson.encode` on the raw `Object`, which sorts
alphabetically in aeson 2.x.

**Rationale**:

- `aeson` 2.x `KeyMap` retains insertion order on decode, but
  `encode` on a plain `Value` uses alphabetical ordering (verified
  against the `aeson-2.2` changelog). So round-trip via `Value`
  would reorder, which is fine for our `decode → encode → decode`
  target.
- For structured constructors we control the pair order.

**Emit target**: byte-for-byte parity against the upstream file is
NOT a goal. Round-trip parity (`decode >>> encode >>> decode`
stable) is.

## R6 — `ReturnSpec` vs raw `return` Value

**Decision**: a small typed record for `return`:

```haskell
data ReturnSpec = ReturnSpec
    { rsMode :: !ReturnMode
    , rsKey  :: !(Maybe Text)
    , rsKeys :: !(Maybe [Text])
    , rsExec :: !(Maybe Text)  -- ISL for mode=macro
    }

data ReturnMode
    = All | None | First | Last | One | Some | Macro
```

**Rationale**: the documented modes are a closed set with
mode-specific side fields (`one` → `key`, `some` → `keys`,
`macro` → `exec`). Typing them makes consumers' lives easier.
Unknown modes fall back to… an error on decode; the set is
documented as closed. If upstream adds a mode we'll update this
type in a new ticket.

**Alternatives rejected**:

- `ReturnSpec = Value`. Consumers (starting with #9) would have
  to re-parse. No gain from the untyped form.

## R7 — No `ISL.Expr` yet

**Decision**: ISL-carrying fields (`txs`, `tx.outputs.*`, `dataHex`,
`get('cache.*')` strings everywhere) stay as `Text`. Parsing into
an `ISL.Expr` typed tree is #20's job.

**Rationale**: #19 is large enough. Adding ISL parsing inflates
the surface and couples two concerns. #20 will later do a
non-breaking field-level swap where appropriate.

## R8 — Property generator strategy

**Decision**: `Arbitrary GCScript` generator in
`test/GCScriptSpec/Generators.hs` that produces:

- A recursive tree with depth-capped shrinking (avoid exploding
  the state space).
- Random `RunBlock` shape (object / array / ISL-string).
- Random `CommonAttrs` sparsity (each field independently present
  or absent).
- Random mix of structured and `Unsupported` function kinds.
- ISL-style fields: plain string generator; we don't generate
  well-formed ISL (that's #20), just representative noise.

**Property**: `decode (encode v) == Right v`, at `depth <= 4`,
with `QuickCheck.maxSuccess = 100`.

**Why this is enough**: the 15 hand-picked golden files cover the
real-world patterns; the property generator catches accidental
asymmetries in our codec that the fixed goldens might miss.

## R9 — Curated corpus selection (locked)

Files selected from upstream `examples/`:

| # | File | Why |
| --- | --- | --- |
| 01 | Simple Script No Export No Return URL | baseline: `run` as array of `data` |
| 02 | Simple Export | `exportAs`, getter-style functions |
| 03 | Minimal Coin Sending Demo | array `run`, `buildTx`/`signTxs`/`submitTxs` |
| 04 | 🚀 Pay me 1 ADA | object `run`, ISL, `macro`, `return.mode=last` |
| 05 | CIP-8 Data Signing and Encrypting Demo | nested `script`, `signDataWithAddress`, `require` |
| 06 | Subroutines Demo | `importAsScript` (Unsupported), `argsByKey` |
| 07 | Arguments and ISL | `args` as ISL-carrying object |
| 08 | Plutus Script Parametrization | `plutusScript` fields |
| 09 | Run Plutus V3 Script | `plutusData`, `plutusScript` |
| 10 | Complex Native Scripts | `nativeScript` |
| 11 | Query Beacon Tokens | `query` |
| 12 | Script Return Modes Demo | exercises every `return.mode` |
| 13 | Stake Delegation | Unsupported fallback |
| 14 | Transaction Pipeline | longer realistic pipeline |
| 15 | Using console | `macro` with `console(...)` ISL |

Pin: upstream `main` at the sha captured in
`test/golden/gcscript/pinned-commit.txt` on the day the corpus is
copied. Re-pinning is a deliberate follow-up ticket.
