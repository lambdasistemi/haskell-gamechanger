# Data Model: GameChanger.GCScript

**Ticket**: #19 | **Date**: 2026-04-20

## Module layout

| Module | Purpose |
| --- | --- |
| `GameChanger.GCScript` | Canonical source: every type + every Aeson instance lives here. All types are defined in this single module because `GCScript`, `RunBlock`, and `FunctionCall` are mutually recursive. |
| `GameChanger.GCScript.Common` | Re-exports `CommonAttrs`, `emptyCommonAttrs`, `RunBlock`, `ReturnMode`, `ReturnSpec` from the canonical module. Import when you only need the cross-cutting pieces. |
| `GameChanger.GCScript.Functions` | Re-exports `FunctionCall` and the per-kind body types from the canonical module. Import when you pattern-match on function calls. |

The alternative — split the types across the three modules with
`hs-boot` files to break the recursion — was rejected as noisier
than the single-module source of truth.

## `GCScript` (root)

```haskell
data GCScript = GCScript
    { gcsTitle            :: !(Maybe Text)
    , gcsDescription      :: !(Maybe Text)
    , gcsRun              :: !RunBlock
    , gcsExportAs         :: !(Maybe Text)
    , gcsArgs             :: !(Maybe Value)
    , gcsArgsByKey        :: !(Maybe (Map Text Value))
    , gcsReturn           :: !(Maybe ReturnSpec)
    , gcsReturnURLPattern :: !(Maybe Text)
    , gcsRequire          :: !(Maybe Value)
    }
    deriving stock (Eq, Show, Generic)
```

JSON shape: always emitted/parsed with `"type": "script"` as the
discriminator, plus the other fields. Fields only appear in the
JSON when `Just`.

## `RunBlock`

```haskell
data RunBlock
    = RunObject !(Map Text FunctionCall)
    | RunArray  ![FunctionCall]
    | RunISL    !Text
    deriving stock (Eq, Show, Generic)
```

Decode rule: try `String → RunISL`; fall back to `Array → RunArray`;
fall back to `Object → RunObject`. Encode mirrors the variant.

## `CommonAttrs`

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
    deriving stock (Eq, Show, Generic)
```

Attached to every `FunctionCall` constructor. A function call with
no common attrs has `CommonAttrs` with every field `Nothing`.

## `ReturnSpec` and `ReturnMode`

```haskell
data ReturnMode = All | None | First | Last | One | Some | Macro
    deriving stock (Eq, Show, Generic, Bounded, Enum)

data ReturnSpec = ReturnSpec
    { rsMode :: !ReturnMode
    , rsKey  :: !(Maybe Text)
    , rsKeys :: !(Maybe [Text])
    , rsExec :: !(Maybe Text)
    }
    deriving stock (Eq, Show, Generic)
```

JSON: `{ "mode": "last" }`, or `{ "mode": "one", "key": "build" }`,
or `{ "mode": "macro", "exec": "{return(get('cache'))}" }`. Mode
strings lowercased.

## `FunctionCall`

```haskell
data FunctionCall
    = FcBuildTx       !CommonAttrs !BuildTxBody
    | FcSignTxs       !CommonAttrs !SignTxsBody
    | FcSubmitTxs     !CommonAttrs !SubmitTxsBody
    | FcBuildFsTxs    !CommonAttrs !BuildFsTxsBody
    | FcSignData      !CommonAttrs !SignDataBody
    | FcVerifySig     !CommonAttrs !VerifySigBody
    | FcQuery         !CommonAttrs !QueryBody
    | FcPlutusScript  !CommonAttrs !PlutusScriptBody
    | FcPlutusData    !CommonAttrs !PlutusDataBody
    | FcNativeScript  !CommonAttrs !NativeScriptBody
    | FcMacro         !CommonAttrs !MacroBody
    | FcScript        !GCScript
    | FcISL           !Text
      -- ^ Bare ISL expression used as a RunObject binding value
      --   (observed in the macro `run` map of 04-pay-me-1-ada).
    | FcUnsupported   !CommonAttrs !Text !Object
      -- ^ Text = the raw "type" tag string
      -- ^ Object = remaining fields (minus common attrs + type)
    deriving stock (Eq, Show, Generic)
```

Decode dispatch:

- `String s` → `FcISL s` (handles bare-ISL values inside a
  `RunObject`).
- `Object o` → read `type :: Text`:
    - `"script"` → `FcScript <$> parseJSON (Object o)`; no
      separate `CommonAttrs` slot because `GCScript` already
      carries the common fields (`gcsTitle`,
      `gcsReturnURLPattern`, etc.).
    - otherwise → strip common attrs into `CommonAttrs`, hand the
      remainder to the per-kind body parser.
- Unknown tag → `FcUnsupported commonAttrs tag remainingObject`.

## Per-kind bodies

For each structured kind, a record of the fields we see in the
corpus. Fields that carry ISL stay `Text`; nested data stays
`Value` until we have a reason to refine.

### `BuildTxBody`

```haskell
newtype BuildTxBody = BuildTxBody { bTxFields :: Object }
    deriving stock (Eq, Show, Generic)
```

The corpus shows `buildTx` with many fields (`tx`, and tx contains
`outputs`, `auxiliaryData`, `options`, `validityIntervalStart`,
`ttl`, `mint`, `certificates`, `withdrawals`, `collateral`,
`requiredSigners`, …). Exhaustively modelling these is out of
scope for #19 — a follow-up ticket will promote `tx` to a typed
record once we need it in #9. For now the body is an `Object`
holding the type-specific fields (common attrs and `type` are
already stripped by the dispatcher).

### `SignTxsBody`

```haskell
data SignTxsBody = SignTxsBody
    { stxTxs                  :: !Value        -- Array of ISL strings or objects
    , stxDetailedPermissions  :: !(Maybe Bool)
    , stxAutoSign             :: !(Maybe Bool)
    , stxExtraPermissions     :: !(Maybe Value)
    }
    deriving stock (Eq, Show, Generic)
```

### `SubmitTxsBody`

```haskell
data SubmitTxsBody = SubmitTxsBody
    { subTxs  :: !Value
    , subMode :: !(Maybe Text)   -- "wait" | "noWait" observed
    }
    deriving stock (Eq, Show, Generic)
```

### `BuildFsTxsBody`

```haskell
newtype BuildFsTxsBody = BuildFsTxsBody { bFsFields :: Object }
    deriving stock (Eq, Show, Generic)
```

### `SignDataBody`

```haskell
data SignDataBody = SignDataBody
    { sdAddress :: !Text          -- often ISL
    , sdDataHex :: !Text          -- often ISL
    }
    deriving stock (Eq, Show, Generic)
```

### `VerifySigBody`

```haskell
data VerifySigBody = VerifySigBody
    { vsAddress       :: !Text
    , vsDataHex       :: !Text
    , vsDataSignature :: !Text
    }
    deriving stock (Eq, Show, Generic)
```

### `QueryBody`

```haskell
newtype QueryBody = QueryBody { qFields :: Object }
    deriving stock (Eq, Show, Generic)
```

### `PlutusScriptBody`, `PlutusDataBody`, `NativeScriptBody`

```haskell
newtype PlutusScriptBody = PlutusScriptBody { psFields :: Object }
newtype PlutusDataBody   = PlutusDataBody   { pdFields :: Object }
newtype NativeScriptBody = NativeScriptBody { nsFields :: Object }
```

Same pattern as `BuildTxBody` — bodies kept as `Object` pending a
later promotion ticket. The fact that they have typed constructors
(rather than falling into `FcUnsupported`) communicates that we
commit to their presence; the body-as-`Object` is a deliberate
deferred refinement.

### `MacroBody`

```haskell
data MacroBody = MacroBody
    { mRun :: !RunBlock
    }
    deriving stock (Eq, Show, Generic)
```

`macro` carries a `run` field that may be an ISL string, an
object, or an array (sharing `RunBlock`). This is the function
kind that justifies `RunISL` existing.

### Recursive `FcScript`

The `Script` function kind is just a nested `GCScript`. The
nested script already carries the common fields directly on
`GCScript` (`gcsTitle`, `gcsExportAs`, `gcsReturnURLPattern`,
etc.), so `FcScript` does *not* take a separate `CommonAttrs`
argument — doing so would duplicate the data and let the two
copies disagree. `type: "script"` is the JSON tag.

## Aeson strategy

- Manual `FromJSON` / `ToJSON` (no `genericParseJSON`): we need
  full control over the `type`-tag dispatch, `CommonAttrs`
  extraction, and the `RunBlock` shape choice.
- Helpers: `commonAttrsFromObject :: Object -> Parser (CommonAttrs, Object)`
  pulls known common keys out and returns the remainder; this way
  per-kind parsers see only type-specific fields.
- Encoding uses `Data.Aeson.Encoding` pairs so field order is
  explicit.
- `ReturnSpec` uses `parseJSON = withObject "ReturnSpec" …` with
  enum-decoding for `mode`.

## Laws / invariants

1. **Decode-encode-decode stability.** `decode bs :: Either String GCScript`,
   then `encode v == encode v` (determinism), then
   `decode (encode v) == Right v` (round-trip). Property-tested
   via QuickCheck at `maxSize 6, tests 100` plus the curated
   corpus goldens.
2. **Structured commitment.** The eleven structured constructors
   never fall back to `Unsupported`. Body types that are still
   opaque (`BuildTxBody`, `BuildFsTxsBody`, `QueryBody`,
   `PlutusScriptBody`, `PlutusDataBody`, `NativeScriptBody`)
   keep the remaining fields in an `Object` so unknown extras
   round-trip verbatim.
3. **Tag collision.** `type = "script"` always decodes to
   `FcScript`, never `Unsupported`. The tag-dispatch table is
   exhaustive-by-inspection.
4. **String at a FunctionCall position → `FcISL`.** A bare JSON
   string where a `FunctionCall` is expected decodes to `FcISL`
   and re-encodes as the same string. Observed inside a macro's
   `run` map (`04-pay-me-1-ada`).

## Deltas vs. legacy `GameChanger.Script`

- `GameChanger.Script.Script` stays; `GCScript` is a new type.
  Zero overlap of exported names (different module, different
  type name).
- `GameChanger.Script` keeps using `signTx` / `getUTxOs`; #21
  retires those later.
- `GameChanger.Script.metadata` stays; #22 drops it later.
- `GameChanger.Script.Channel` stays; #23 replaces it later.
