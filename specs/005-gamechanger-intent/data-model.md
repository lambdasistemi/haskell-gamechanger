# Phase 1 — Data model: GameChanger.Intent

## Module layout

| Module | Role | Exports |
|---|---|---|
| `GameChanger.Intent` | Public surface | `IntentI(..)`, `Intent`, `getUTxOs`, `buildTx`, `signTx`, `signData`, `submitTx`, `declareExport`, and re-exports `Channel(..)` from `GameChanger.Script.Types`. |
| `GameChanger.Intent.Handles` | Typed placeholders | `Address(..)`, `UTxO(..)`, `Tx(..)`, `SignedTx(..)`, `Signature(..)`, `TxId(..)`, `BuildArgs(..)`, `ProposalId(..)`, `Vote(..)`. Re-exported from `GameChanger.Intent`. |

## `IntentI` — the GADT

```haskell
data IntentI a where
  GetUTxOs      :: Address -> IntentI [UTxO]
  BuildTx       :: BuildArgs -> IntentI Tx
  SignTx        :: Tx -> IntentI SignedTx
  SignData      :: Address -> Text -> IntentI Signature
  SubmitTx      :: SignedTx -> IntentI TxId
  DeclareExport :: Text -> Text -> Channel -> IntentI ()
```

**Constructor → `ActionKind`** (for the future compiler in #9):

| GADT constructor | `ActionKind` (#6) | Detail shape (informative) |
|---|---|---|
| `GetUTxOs addr` | `GetUTxOs` | `{ "address": addr }` |
| `BuildTx args` | `BuildTx` | `{ …args… }` (#9 owns) |
| `SignTx tx` | `SignTx` | `{ "tx": {get('cache.<bind>.tx')} }` |
| `SignData addr msg` | `SignData` | `{ "address": addr, "message": msg }` |
| `SubmitTx tx` | `SubmitTx` | `{ "tx": {get('cache.<bind>')} }` |
| `DeclareExport name src ch` | — (driver of `exports` clause) | see `Channel` |

`DeclareExport` is the only constructor that doesn't correspond
to an `ActionKind`; it drives the `exports` map.

## `Intent`

```haskell
type Intent = Program IntentI
```

No newtype wrapper. Consumers import `Control.Monad.Operational`
and can call `view`/`viewT` directly — the spec's US3 depends on
this.

## Smart constructors

```haskell
getUTxOs      :: Address -> Intent [UTxO]
buildTx       :: BuildArgs -> Intent Tx
signTx        :: Tx -> Intent SignedTx
signData      :: Address -> Text -> Intent Signature
submitTx      :: SignedTx -> Intent TxId
declareExport :: Text -> Text -> Channel -> Intent ()
```

Each is a one-liner: `singleton (Constr args)`.

## Typed handles

All `newtype` over `Text`, deriving `Eq`, `Show`, `Generic`:

```haskell
newtype Address    = Address    Text
newtype UTxO       = UTxO       Text
newtype Tx         = Tx         Text
newtype SignedTx   = SignedTx   Text
newtype Signature  = Signature  Text
newtype TxId       = TxId       Text
newtype ProposalId = ProposalId Text
newtype Vote       = Vote       Text
```

`BuildArgs` is a placeholder record; #9 refines:

```haskell
data BuildArgs = BuildArgs
  { buildArgsSource :: Text  -- opaque JSON source fragment
  }
  deriving stock (Eq, Show, Generic)
```

The single `buildArgsSource` field is enough to carry
`voteConstraints utxos pid vote` as a `Text` expression in the
test harness; #9 may introduce a structured record later.

## Channel — re-exported

`GameChanger.Intent` re-exports `Channel(..)` from
`GameChanger.Script.Types` (§FR-004). Constructors:

- `Return { returnUrl :: Text }`
- `Post   { postUrl   :: Text }`
- `Download { downloadName :: Text }`
- `QR     { qrOptions :: Maybe Value }`
- `Copy`

No re-export of `Script`, `Action`, or `Export` types — authors
writing `Intent` programs don't need them.

## Invariants preserved in types

1. Any `Intent a` is a `Program IntentI a`. Walking it with
   `view` exposes exactly the six GADT constructors.
2. Smart constructors never return `IO` anything; the surface
   is pure (constitution §11.3.3, enforced by types).
3. `declareExport` takes a `Channel` by value, not by name —
   eliminating string-match wiring between exports and run
   outputs would require #9's stable-name generator, which is
   out of scope.

## Relationship to existing modules

```text
GameChanger.Intent  ──imports──▶  GameChanger.Script.Types  (Channel only)
GameChanger.Intent  ──imports──▶  GameChanger.Intent.Handles
GameChanger.Intent  ──imports──▶  Control.Monad.Operational
```

No dependency cycle. `GameChanger.Script.Types` does NOT import
anything from `GameChanger.Intent.*` (would be a cycle and a
layering violation).
