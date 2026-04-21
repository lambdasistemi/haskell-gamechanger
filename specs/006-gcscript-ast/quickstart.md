# Quickstart: GameChanger.GCScript

**Ticket**: #19 | **Date**: 2026-04-20

This file is an executable-style tour of `GameChanger.GCScript` for
reviewers: what the public surface looks like, what a round-trip
session looks like, what a hand-constructed AST looks like.

## Public surface

```haskell
import GameChanger.GCScript
    ( GCScript (..)
    , RunBlock (..)
    , CommonAttrs (..)
    , ReturnMode (..)
    , ReturnSpec (..)
    , FunctionCall (..)
    , emptyCommonAttrs
    )
import GameChanger.GCScript.Functions
    ( BuildTxBody (..)
    , SignTxsBody (..)
    , SubmitTxsBody (..)
    , MacroBody (..)
    , SignDataBody (..)
    , VerifySigBody (..)
    )

import Data.Aeson (decode, encode, eitherDecode)
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Map.Strict       as Map
```

## 1. Decode a real corpus file

```haskell
decodeCorpus :: FilePath -> IO (Either String GCScript)
decodeCorpus path = eitherDecode <$> BSL.readFile path

-- ghci> decodeCorpus "test/golden/gcscript/04-pay-me-1-ada.gcscript"
-- Right (GCScript { gcsTitle = Just "🚀 Pay me 1 ADA", ..., gcsRun = RunObject (…) })
```

The decoder:

- reads `"type": "script"` as the root discriminator
- strips `CommonAttrs` fields from the root
- dispatches `run` to `RunObject` / `RunArray` / `RunISL`
- recurses into each child `FunctionCall`

## 2. Encode a hand-constructed script

```haskell
hello :: GCScript
hello = GCScript
    { gcsTitle            = Just "Hello script"
    , gcsDescription      = Nothing
    , gcsRun              = RunArray
        [ FcBuildTx emptyCommonAttrs (BuildTxBody payload)
        , FcSignTxs emptyCommonAttrs (SignTxsBody
            { stxTxs                 = jsonArray ["{get('cache.0.txHex')}"]
            , stxDetailedPermissions = Nothing
            , stxAutoSign            = Just True
            , stxExtraPermissions    = Nothing
            })
        , FcSubmitTxs emptyCommonAttrs (SubmitTxsBody
            { subTxs  = jsonArray ["{get('cache.1.witnessedTxHex')}"]
            , subMode = Just "wait"
            })
        ]
    , gcsExportAs         = Nothing
    , gcsArgs             = Nothing
    , gcsArgsByKey        = Nothing
    , gcsReturn           = Just (ReturnSpec Last Nothing Nothing Nothing)
    , gcsReturnURLPattern = Nothing
    , gcsRequire          = Nothing
    }

-- ghci> BSL.putStr (encode hello)
-- {"type":"script","title":"Hello script","run":[ … ],"return":{"mode":"last"}}
```

`emptyCommonAttrs` = every field `Nothing`; use it when a call has no
title/description/etc.

## 3. Round-trip a corpus file

```haskell
roundTrip :: FilePath -> IO Bool
roundTrip path = do
    Right v  <- eitherDecode <$> BSL.readFile path
    let re   = encode (v :: GCScript)
    let v'   = eitherDecode re
    pure (v' == Right v)

-- ghci> mapM roundTrip =<< listDirectory "test/golden/gcscript"
-- [True, True, True, True, True, True, True, True, True, True,
--  True, True, True, True, True]
```

Byte-for-byte parity vs the upstream file is **not** the target — we
do not preserve alphabetical vs authoring-order key layout. Decode-
encode-decode stability **is** the target and is property-tested.

## 4. Build a nested script

```haskell
nested :: GCScript
nested = GCScript
    { gcsTitle = Just "Parent"
    , gcsDescription = Nothing
    , gcsRun = RunObject $ Map.fromList
        [ ("preflight", FcQuery emptyCommonAttrs
              (QueryBody (object ["from" .= (["addr…"] :: [Text])])))
        , ("inner", FcScript emptyCommonAttrs inner)
        ]
    , gcsExportAs         = Nothing
    , gcsArgs             = Nothing
    , gcsArgsByKey        = Nothing
    , gcsReturn           = Nothing
    , gcsReturnURLPattern = Nothing
    , gcsRequire          = Nothing
    }
  where
    inner = GCScript
        { gcsTitle = Just "Child"
        , gcsRun   = RunArray
            [ FcBuildTx emptyCommonAttrs (BuildTxBody Null) ]
        , gcsDescription      = Nothing
        , gcsExportAs         = Just "child"
        , gcsArgs             = Nothing
        , gcsArgsByKey        = Nothing
        , gcsReturn           = Nothing
        , gcsReturnURLPattern = Nothing
        , gcsRequire          = Nothing
        }
```

Note the nested `GCScript` appears under `FcScript` and keeps its own
`exportAs`. The emitted JSON for the child has `"type": "script"`.

## 5. `Unsupported` fallback

```haskell
-- Corpus snippet:
--   { "type": "importAsScript", "from": ["abc…"], "exportAs": "util" }
-- Decodes as:
FcUnsupported
    (emptyCommonAttrs { caExportAs = Just "util" })
    "importAsScript"
    (KeyMap.fromList [("from", Array [...])])
```

The `CommonAttrs` are still pulled out normally; the remainder lives in
the raw `Object`. Re-encoding produces
`{"type":"importAsScript","exportAs":"util","from":[...]}` — round-trip
safe even though we never modelled `importAsScript`.

## 6. Macro with ISL-as-run

```haskell
justRunISL :: FunctionCall
justRunISL = FcMacro emptyCommonAttrs
    (MacroBody (RunISL "{console(get('cache'))}"))

-- encode → {"type":"macro","run":"{console(get('cache'))}"}
```

The `RunBlock` sum makes this a natural variant rather than a special
case.

## 7. Where to go from here

- `#20` — swap ISL-carrying `Text` fields for `ISL.Expr` without
  changing any structural types here.
- `#9` — write `Intent.Compile` targeting this AST. The five Intent
  primitives map 1:1 to the five function kinds they each need; the
  recursive `FcScript` carries nested Intent blocks.
- `#21` / `#22` / `#23` — retire legacy `GameChanger.Script` surface
  piece by piece now that the replacement is shipped.
