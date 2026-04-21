# GCScript AST

`GameChanger.GCScript` is the **low-level, JSON-faithful** Haskell
representation of the GameChanger wallet's `.gcscript` DSL. It
parses, constructs, and emits the exact JSON shape the wallet
expects. No transforms, no semantic interpretation — the data model
is a Haskell mirror of what the wallet reads.

The higher-level, monadic
[Intent eDSL](./intent-dsl.md) is the surface most callers will
prefer; it compiles down to values of the types described here. Use
`GameChanger.GCScript` directly when you need to:

- decode a GCScript authored outside this library;
- embed or manipulate a `.gcscript` the Intent surface does not
  (yet) cover;
- round-trip an unknown-tag script without loss.

## Modules

| Module | Use when |
|---|---|
| `GameChanger.GCScript` | You need the full AST, all Aeson instances, everything |
| `GameChanger.GCScript.Common` | You only work with the cross-cutting pieces (`CommonAttrs`, `RunBlock`, `ReturnMode`, `ReturnSpec`) |
| `GameChanger.GCScript.Functions` | You pattern-match on `FunctionCall` and per-kind bodies |

`Common` and `Functions` are re-export facades. All types are
defined in `GameChanger.GCScript` because `GCScript`, `RunBlock`,
and `FunctionCall` are mutually recursive and a single module
avoids the `hs-boot` dance.

## Tutorial: a five-minute tour

### 1. Decode an existing script

The curated corpus that gates this library's round-trip tests is
shipped in `test/golden/gcscript/`. Point `aeson` at any of those
files:

```haskell
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BSL
import GameChanger.GCScript (GCScript)

readScript :: FilePath -> IO (Either String GCScript)
readScript fp = Aeson.eitherDecode <$> BSL.readFile fp
```

A successful decode gives a typed `GCScript` value. The top-level
`type: "script"` discriminator is required; any other value at the
root fails with a clear message.

### 2. Inspect the run block

`gcsRun` is tri-shape, matching the DSL:

```haskell
import GameChanger.GCScript
    ( GCScript (..), RunBlock (..) )

describeRun :: GCScript -> String
describeRun gcs = case gcsRun gcs of
    RunObject m -> "named run with " <> show (length m) <> " entries"
    RunArray xs -> "anonymous run with " <> show (length xs) <> " steps"
    RunISL t    -> "single ISL expression: " <> show t
```

### 3. Typed field access on function calls

Each `FunctionCall` constructor carries a typed body. `signDataWithAddress`,
for example, has `address` and `dataHex` as `Text`:

```haskell
import GameChanger.GCScript
    ( FunctionCall (..), SignDataBody (..) )

firstSignAddress :: [FunctionCall] -> Maybe Text
firstSignAddress calls =
    case [ sdAddress body | FcSignData _ body <- calls ] of
        (addr : _) -> Just addr
        []         -> Nothing
```

No `lookup "address" (someObject)` or `as :: Text` — the field is
already of the right type on a successful decode.

### 4. Handle unknown function tags

The GameChanger DSL has a long tail of function kinds — `signTx`,
`certificate`, `deriveKeys`, `importAsScript`, … — that this library
does not yet model structurally. Those land in `FcUnsupported`,
carrying the raw tag and the raw body:

```haskell
unknownTags :: [FunctionCall] -> [Text]
unknownTags calls = [ tag | FcUnsupported _ tag _ <- calls ]
```

`FcUnsupported` round-trips verbatim: the original JSON fields are
preserved byte-for-byte. Writing your own logic against an
as-yet-unknown tag is just `case` matching; promoting a tag to a
structured constructor is a library-side change.

### 5. Emit JSON

Every `FunctionCall` and `GCScript` has a `ToJSON` instance. Typical
pipeline:

```haskell
emit :: GCScript -> BSL.ByteString
emit = Aeson.encode
```

Encoder output is stable: `encode v == encode v` always. This is
not accidental; it is gated by the test suite (SC-002). Feed the
bytes into the existing resolver-URL pipeline
(`GameChanger.Encoding`) to turn it into a wallet-consumable URL.

### 6. Round-trip guarantee

For every script the wallet accepts, the library guarantees:

```haskell
Aeson.eitherDecode (Aeson.encode v) == Right v
```

This is checked on fifteen curated corpus files pinned to the
upstream wallet sha recorded in
`test/golden/gcscript/pinned-commit.txt`, plus a QuickCheck property
over generated scripts (`prop_roundTrip`, 100 tests, `maxSize 6`).

## AST at a glance

See [the data model](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/specs/006-gcscript-ast/data-model.md)
for the authoritative reference. The sketch:

```
GCScript
├── gcsTitle / gcsDescription / gcsExportAs / gcsArgs /
│   gcsArgsByKey / gcsReturn / gcsReturnURLPattern /
│   gcsRequire            -- all optional, all at the root
└── gcsRun :: RunBlock
        ├── RunObject (Map Text FunctionCall)
        ├── RunArray [FunctionCall]
        └── RunISL Text

FunctionCall = structured (with CommonAttrs + typed body)
             | FcScript !GCScript       -- nested script
             | FcISL !Text              -- bare ISL as a RunObject value
             | FcUnsupported ca tag obj -- forward-compat fallback
```

Structured kinds covered: `buildTx`, `signTxs`, `submitTxs`,
`buildFsTxs`, `signDataWithAddress`, `verifySignatureWithAddress`,
`query`, `plutusScript`, `plutusData`, `nativeScript`, `macro`.

`CommonAttrs` is an eight-field record (`title`, `description`,
`exportAs`, `args`, `argsByKey`, `returnURLPattern`, `require`,
`return`) every structured `FunctionCall` carries. `FcScript` does
*not* take a separate `CommonAttrs` — a nested `GCScript` already
has those fields on the record itself.

`ReturnSpec` names a `ReturnMode` (`All | None | First | Last | One |
Some | Macro`, lowercase-encoded) and the mode-specific fields
(`key`, `keys`, `exec`).

## Edge cases worth knowing

### JSON `null` is not `Just Null`

Aeson's `.:?` treats a JSON `null` at an optional field as absent.
A Haskell value of `Just Null` at a `Maybe Value` position cannot
round-trip. The upstream corpus never emits `"args": null` — it
omits the key instead — so this is only a concern when
hand-constructing values. If you need to express "the field is
present and null", that is not representable in this codec
(matching upstream semantics).

### String at a `FunctionCall` position

A bare JSON string where a `FunctionCall` is expected decodes to
`FcISL`. This is observed inside a macro's `run` map, for example
in `04-pay-me-1-ada.gcscript`:

```json
"finally": {
  "type": "macro",
  "run": {
    "txHash": "{get('cache.build.txHash')}"
  }
}
```

On decode, the `txHash` binding is `FcISL "{get('cache.build.txHash')}"`.

### Forward compatibility via `FcUnsupported`

The library commits to preserving unknown kinds verbatim. When the
upstream DSL grows a new tag, existing decoded scripts keep
round-tripping; only callers that want typed access to the new tag
need a library bump.

## Relationship to the other layers

- **`GameChanger.Script`** (legacy) — the hand-rolled, narrow
  script type used by the initial library bootstrap. It remains in
  place for existing callers; `GameChanger.GCScript` supersedes it
  for new code.
- **`GameChanger.Intent`** — the monadic surface documented in
  [Intent eDSL](./intent-dsl.md). It compiles to `GCScript` values.
  Most application code should start there and drop down to
  `GCScript` only when it needs to.
- **`GameChanger.Encoding`** — the LZMA-alone + base64url resolver
  URL pipeline. It takes the JSON emitted by `GCScript`'s `ToJSON`
  and produces the wallet-loadable URL.

## Links

- [Data model](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/specs/006-gcscript-ast/data-model.md)
- [Spec (#19)](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/specs/006-gcscript-ast/spec.md)
- [Curated corpus](https://github.com/lambdasistemi/haskell-gamechanger/tree/main/test/golden/gcscript)
- [Intent eDSL](./intent-dsl.md) — the surface that compiles to `GCScript`
- [Protocol](./protocol.md) — where `.gcscript` files fit in the wider wallet flow
