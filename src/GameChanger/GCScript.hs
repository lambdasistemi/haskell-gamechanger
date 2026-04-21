{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- | Upstream GameChanger GCScript AST plus JSON round-trip.

This module is the canonical shape reference for the GameChanger
wallet's @.gcscript@ files. Corpus-driven: the type tree was
inferred from fifteen curated examples in
@test\/golden\/gcscript\/@, pinned to the upstream sha in
@pinned-commit.txt@. See @specs\/006-gcscript-ast\/data-model.md@
for the design narrative and
@specs\/006-gcscript-ast\/spec.md@ for the feature spec.

Constitution §8: this module is a JSON boundary. Any change to
the encoded form needs a matching update to the golden corpus
(or a deliberate re-pin of the upstream sha).

All type definitions live here; "GameChanger.GCScript.Common"
and "GameChanger.GCScript.Functions" re-export subsets for
downstream import clarity, but the single source of truth is
this module. This is the simplest way to handle the mutual
recursion between 'RunBlock', 'FunctionCall', and 'GCScript'.
-}
module GameChanger.GCScript (
    -- * Root script
    GCScript (..),

    -- * Shared attributes
    CommonAttrs (..),
    emptyCommonAttrs,

    -- * Polymorphic @run@ field
    RunBlock (..),

    -- * Return specifications
    ReturnMode (..),
    ReturnSpec (..),

    -- * Function calls
    FunctionCall (..),

    -- * Structured per-kind bodies
    BuildTxBody (..),
    SignTxsBody (..),
    SubmitTxsBody (..),
    BuildFsTxsBody (..),
    SignDataBody (..),
    VerifySigBody (..),
    QueryBody (..),
    PlutusScriptBody (..),
    PlutusDataBody (..),
    NativeScriptBody (..),
    MacroBody (..),
) where

import Data.Aeson (
    FromJSON (..),
    Object,
    ToJSON (..),
    Value (..),
    object,
    withObject,
    withText,
    (.:),
    (.:?),
    (.=),
 )
import qualified Data.Aeson as Aeson
import Data.Aeson.Key (Key)
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Pair, Parser)
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- ---------------------------------------------------------------------
-- Root

{- | Top-level GameChanger script.

Always emitted and parsed with the @"type": "script"@ JSON
discriminator. All fields except 'gcsRun' are optional at the
JSON layer and appear in the output only when 'Just'.
-}
data GCScript = GCScript
    { gcsTitle :: !(Maybe Text)
    , gcsDescription :: !(Maybe Text)
    , gcsRun :: !RunBlock
    , gcsExportAs :: !(Maybe Text)
    , gcsArgs :: !(Maybe Value)
    , gcsArgsByKey :: !(Maybe (Map Text Value))
    , gcsReturn :: !(Maybe ReturnSpec)
    , gcsReturnURLPattern :: !(Maybe Text)
    , gcsRequire :: !(Maybe Value)
    }
    deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------
-- Common attributes

{- | Optional fields every 'FunctionCall' (except 'FcScript') may
carry. The corpus shows these eight keys appearing at any
function-call level, not just the root script.

Stored separately from per-kind bodies so that (a) unknown
function kinds (see 'FcUnsupported') still get their common
attributes parsed and (b) structured kinds don't duplicate the
eight optional fields across twelve constructors.
-}
data CommonAttrs = CommonAttrs
    { caTitle :: !(Maybe Text)
    , caDescription :: !(Maybe Text)
    , caExportAs :: !(Maybe Text)
    , caArgs :: !(Maybe Value)
    , caArgsByKey :: !(Maybe (Map Text Value))
    , caReturnURLPattern :: !(Maybe Text)
    , caRequire :: !(Maybe Value)
    , caReturn :: !(Maybe ReturnSpec)
    }
    deriving stock (Eq, Show, Generic)

-- | All fields 'Nothing'. Use when a call carries no common attrs.
emptyCommonAttrs :: CommonAttrs
emptyCommonAttrs =
    CommonAttrs
        { caTitle = Nothing
        , caDescription = Nothing
        , caExportAs = Nothing
        , caArgs = Nothing
        , caArgsByKey = Nothing
        , caReturnURLPattern = Nothing
        , caRequire = Nothing
        , caReturn = Nothing
        }

commonAttrKeys :: [Key]
commonAttrKeys =
    [ "title"
    , "description"
    , "exportAs"
    , "args"
    , "argsByKey"
    , "returnURLPattern"
    , "require"
    , "return"
    ]

{- | Read the common-attrs subset of an object, returning the
leftover object (with known keys stripped) for per-kind parsers.
-}
commonAttrsFromObject :: Object -> Parser (CommonAttrs, Object)
commonAttrsFromObject o = do
    ca <-
        CommonAttrs
            <$> o .:? "title"
            <*> o .:? "description"
            <*> o .:? "exportAs"
            <*> o .:? "args"
            <*> o .:? "argsByKey"
            <*> o .:? "returnURLPattern"
            <*> o .:? "require"
            <*> o .:? "return"
    let leftover = foldr KeyMap.delete o commonAttrKeys
    pure (ca, leftover)

{- | Emit the 'Just' components of a 'CommonAttrs' as
@[Pair]@, suitable for merging into a function-call JSON object.
-}
commonAttrsToPairs :: CommonAttrs -> [Pair]
commonAttrsToPairs ca =
    catJust
        [ ("title" .=) <$> caTitle ca
        , ("description" .=) <$> caDescription ca
        , ("exportAs" .=) <$> caExportAs ca
        , ("args" .=) <$> caArgs ca
        , ("argsByKey" .=) <$> caArgsByKey ca
        , ("returnURLPattern" .=) <$> caReturnURLPattern ca
        , ("require" .=) <$> caRequire ca
        , ("return" .=) <$> caReturn ca
        ]

catJust :: [Maybe a] -> [a]
catJust = foldr step []
  where
    step Nothing xs = xs
    step (Just x) xs = x : xs

-- ---------------------------------------------------------------------
-- RunBlock

{- | Polymorphic @run@ field.

The corpus exhibits all three shapes:

* 'RunObject' — named children (cache keys are user-chosen).
* 'RunArray'  — anonymous children (cache keys are @"0"@, @"1"@, …).
* 'RunISL'    — a single inline ISL expression (observed inside
  @macro@, permitted here for any script-ish position).

Decode tries string → array → object in that order. Encode
emits the variant's native shape.
-}
data RunBlock
    = RunObject !(Map Text FunctionCall)
    | RunArray ![FunctionCall]
    | RunISL !Text
    deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------
-- ReturnSpec

{- | The closed set of return modes documented upstream. Encoded
as a lowercase string.
-}
data ReturnMode
    = All
    | None
    | First
    | Last
    | One
    | Some
    | Macro
    deriving stock (Eq, Show, Generic, Bounded, Enum)

-- | A @return@ object on either a root script or a nested script.
data ReturnSpec = ReturnSpec
    { rsMode :: !ReturnMode
    , rsKey :: !(Maybe Text)
    -- ^ Set when @mode=one@.
    , rsKeys :: !(Maybe [Text])
    -- ^ Set when @mode=some@.
    , rsExec :: !(Maybe Text)
    -- ^ ISL expression set when @mode=macro@.
    }
    deriving stock (Eq, Show, Generic)

returnModeTag :: ReturnMode -> Text
returnModeTag = \case
    All -> "all"
    None -> "none"
    First -> "first"
    Last -> "last"
    One -> "one"
    Some -> "some"
    Macro -> "macro"

-- ---------------------------------------------------------------------
-- FunctionCall

{- | A single function call inside a 'RunBlock'.

Twelve structured constructors cover the function kinds this
library commits to; 'FcUnsupported' catches the long tail of
upstream functions (@importAsScript@, @getCurrentAddress@,
@signTx@, …) while preserving their JSON body verbatim.
-}
data FunctionCall
    = FcBuildTx !CommonAttrs !BuildTxBody
    | FcSignTxs !CommonAttrs !SignTxsBody
    | FcSubmitTxs !CommonAttrs !SubmitTxsBody
    | FcBuildFsTxs !CommonAttrs !BuildFsTxsBody
    | FcSignData !CommonAttrs !SignDataBody
    | FcVerifySig !CommonAttrs !VerifySigBody
    | FcQuery !CommonAttrs !QueryBody
    | FcPlutusScript !CommonAttrs !PlutusScriptBody
    | FcPlutusData !CommonAttrs !PlutusDataBody
    | FcNativeScript !CommonAttrs !NativeScriptBody
    | FcMacro !CommonAttrs !MacroBody
    | FcScript !GCScript
    | -- | Bare ISL expression used as a 'RunObject' binding value.
      FcISL !Text
    | FcUnsupported !CommonAttrs !Text !Object
    deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------
-- Per-kind bodies

{- | Body of @buildTx@. Kept as an 'Object' — typed refinement
happens in a follow-up ticket that crosses #9.
-}
newtype BuildTxBody = BuildTxBody {bTxFields :: Object}
    deriving stock (Eq, Show, Generic)

-- | Body of @signTxs@.
data SignTxsBody = SignTxsBody
    { stxTxs :: !Value
    -- ^ Array of ISL strings or typed objects.
    , stxDetailedPermissions :: !(Maybe Bool)
    , stxAutoSign :: !(Maybe Bool)
    , stxExtraPermissions :: !(Maybe Value)
    }
    deriving stock (Eq, Show, Generic)

-- | Body of @submitTxs@.
data SubmitTxsBody = SubmitTxsBody
    { subTxs :: !Value
    , subMode :: !(Maybe Text)
    -- ^ @"wait"@ or @"noWait"@ in the observed corpus.
    }
    deriving stock (Eq, Show, Generic)

-- | Body of @buildFsTxs@. Kept opaque pending a later refinement.
newtype BuildFsTxsBody = BuildFsTxsBody {bFsFields :: Object}
    deriving stock (Eq, Show, Generic)

-- | Body of @signDataWithAddress@.
data SignDataBody = SignDataBody
    { sdAddress :: !Text
    , sdDataHex :: !Text
    }
    deriving stock (Eq, Show, Generic)

-- | Body of @verifySignatureWithAddress@.
data VerifySigBody = VerifySigBody
    { vsAddress :: !Text
    , vsDataHex :: !Text
    , vsDataSignature :: !Text
    }
    deriving stock (Eq, Show, Generic)

-- | Body of @query@.
newtype QueryBody = QueryBody {qFields :: Object}
    deriving stock (Eq, Show, Generic)

-- | Body of @plutusScript@. Kept opaque pending a later refinement.
newtype PlutusScriptBody = PlutusScriptBody {psFields :: Object}
    deriving stock (Eq, Show, Generic)

-- | Body of @plutusData@. Kept opaque pending a later refinement.
newtype PlutusDataBody = PlutusDataBody {pdFields :: Object}
    deriving stock (Eq, Show, Generic)

-- | Body of @nativeScript@. Kept opaque pending a later refinement.
newtype NativeScriptBody = NativeScriptBody {nsFields :: Object}
    deriving stock (Eq, Show, Generic)

-- | Body of @macro@ — carries a 'RunBlock' (object, array, or ISL).
newtype MacroBody = MacroBody {mRun :: RunBlock}
    deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------
-- JSON: ReturnMode / ReturnSpec

instance ToJSON ReturnMode where
    toJSON = Aeson.String . returnModeTag

instance FromJSON ReturnMode where
    parseJSON = withText "ReturnMode" $ \case
        "all" -> pure All
        "none" -> pure None
        "first" -> pure First
        "last" -> pure Last
        "one" -> pure One
        "some" -> pure Some
        "macro" -> pure Macro
        other ->
            fail $
                "unknown return mode "
                    <> show other
                    <> " (expected all, none, first, last, one, some, macro)"

instance ToJSON ReturnSpec where
    toJSON rs =
        object $
            ("mode" .= rsMode rs)
                : catJust
                    [ ("key" .=) <$> rsKey rs
                    , ("keys" .=) <$> rsKeys rs
                    , ("exec" .=) <$> rsExec rs
                    ]

instance FromJSON ReturnSpec where
    parseJSON = withObject "ReturnSpec" $ \o ->
        ReturnSpec
            <$> o .: "mode"
            <*> o .:? "key"
            <*> o .:? "keys"
            <*> o .:? "exec"

-- ---------------------------------------------------------------------
-- JSON: RunBlock

instance FromJSON RunBlock where
    parseJSON v = case v of
        String t -> pure (RunISL t)
        Array _ -> RunArray <$> parseJSON v
        Object _ -> RunObject <$> parseJSON v
        _ ->
            fail $
                "expected run block to be object, array, or string, got "
                    <> describeJson v

instance ToJSON RunBlock where
    toJSON = \case
        RunObject m -> toJSON m
        RunArray xs -> toJSON xs
        RunISL t -> toJSON t

describeJson :: Value -> String
describeJson = \case
    Null -> "null"
    Bool _ -> "boolean"
    Number _ -> "number"
    String _ -> "string"
    Array _ -> "array"
    Object _ -> "object"

-- ---------------------------------------------------------------------
-- JSON: per-kind bodies

instance FromJSON BuildTxBody where
    parseJSON = withObject "BuildTxBody" (pure . BuildTxBody)

instance ToJSON BuildTxBody where
    toJSON = Object . bTxFields

instance FromJSON BuildFsTxsBody where
    parseJSON = withObject "BuildFsTxsBody" (pure . BuildFsTxsBody)

instance ToJSON BuildFsTxsBody where
    toJSON = Object . bFsFields

instance FromJSON QueryBody where
    parseJSON = withObject "QueryBody" (pure . QueryBody)

instance ToJSON QueryBody where
    toJSON = Object . qFields

instance FromJSON PlutusScriptBody where
    parseJSON = withObject "PlutusScriptBody" (pure . PlutusScriptBody)

instance ToJSON PlutusScriptBody where
    toJSON = Object . psFields

instance FromJSON PlutusDataBody where
    parseJSON = withObject "PlutusDataBody" (pure . PlutusDataBody)

instance ToJSON PlutusDataBody where
    toJSON = Object . pdFields

instance FromJSON NativeScriptBody where
    parseJSON = withObject "NativeScriptBody" (pure . NativeScriptBody)

instance ToJSON NativeScriptBody where
    toJSON = Object . nsFields

instance FromJSON SignTxsBody where
    parseJSON = withObject "SignTxsBody" $ \o ->
        SignTxsBody
            <$> o .: "txs"
            <*> o .:? "detailedPermissions"
            <*> o .:? "autoSign"
            <*> o .:? "extraPermissions"

instance ToJSON SignTxsBody where
    toJSON b =
        object $
            ("txs" .= stxTxs b)
                : catJust
                    [ ("detailedPermissions" .=) <$> stxDetailedPermissions b
                    , ("autoSign" .=) <$> stxAutoSign b
                    , ("extraPermissions" .=) <$> stxExtraPermissions b
                    ]

instance FromJSON SubmitTxsBody where
    parseJSON = withObject "SubmitTxsBody" $ \o ->
        SubmitTxsBody
            <$> o .: "txs"
            <*> o .:? "mode"

instance ToJSON SubmitTxsBody where
    toJSON b =
        object $
            ("txs" .= subTxs b)
                : catJust [("mode" .=) <$> subMode b]

instance FromJSON SignDataBody where
    parseJSON = withObject "SignDataBody" $ \o ->
        SignDataBody
            <$> o .: "address"
            <*> o .: "dataHex"

instance ToJSON SignDataBody where
    toJSON b =
        object
            [ "address" .= sdAddress b
            , "dataHex" .= sdDataHex b
            ]

instance FromJSON VerifySigBody where
    parseJSON = withObject "VerifySigBody" $ \o ->
        VerifySigBody
            <$> o .: "address"
            <*> o .: "dataHex"
            <*> o .: "dataSignature"

instance ToJSON VerifySigBody where
    toJSON b =
        object
            [ "address" .= vsAddress b
            , "dataHex" .= vsDataHex b
            , "dataSignature" .= vsDataSignature b
            ]

instance FromJSON MacroBody where
    parseJSON = withObject "MacroBody" $ \o ->
        MacroBody <$> o .: "run"

instance ToJSON MacroBody where
    toJSON b = object ["run" .= mRun b]

-- ---------------------------------------------------------------------
-- JSON: FunctionCall

{- | Merge a JSON body (expected to be an 'Object') with a type tag
and common-attrs pairs into a single 'Object'. Later keys win on
duplicates, but by construction the sets are disjoint (common
attrs are stripped before the per-kind body sees the input).
-}
mergeCallObject :: Text -> CommonAttrs -> Value -> Value
mergeCallObject tag ca body =
    let bodyMap = case body of
            Object km -> km
            _ -> KeyMap.empty
        common = pairsToKeyMap (commonAttrsToPairs ca)
        typeKm = KeyMap.singleton "type" (toJSON tag)
     in Object (typeKm `KeyMap.union` common `KeyMap.union` bodyMap)

pairsToKeyMap :: [Pair] -> Object
pairsToKeyMap = KeyMap.fromList

instance ToJSON FunctionCall where
    toJSON = \case
        FcBuildTx ca body -> mergeCallObject "buildTx" ca (toJSON body)
        FcSignTxs ca body -> mergeCallObject "signTxs" ca (toJSON body)
        FcSubmitTxs ca body -> mergeCallObject "submitTxs" ca (toJSON body)
        FcBuildFsTxs ca body -> mergeCallObject "buildFsTxs" ca (toJSON body)
        FcSignData ca body -> mergeCallObject "signDataWithAddress" ca (toJSON body)
        FcVerifySig ca body -> mergeCallObject "verifySignatureWithAddress" ca (toJSON body)
        FcQuery ca body -> mergeCallObject "query" ca (toJSON body)
        FcPlutusScript ca body -> mergeCallObject "plutusScript" ca (toJSON body)
        FcPlutusData ca body -> mergeCallObject "plutusData" ca (toJSON body)
        FcNativeScript ca body -> mergeCallObject "nativeScript" ca (toJSON body)
        FcMacro ca body -> mergeCallObject "macro" ca (toJSON body)
        FcScript gcs -> toJSON gcs
        FcISL t -> String t
        FcUnsupported ca tag rest ->
            Object
                ( KeyMap.singleton "type" (toJSON tag)
                    `KeyMap.union` pairsToKeyMap (commonAttrsToPairs ca)
                    `KeyMap.union` rest
                )

instance FromJSON FunctionCall where
    parseJSON (String t) = pure (FcISL t)
    parseJSON v = ($ v) $ withObject "FunctionCall" $ \o -> do
        tag <- o .: "type"
        case (tag :: Text) of
            "script" -> FcScript <$> parseJSON (Object o)
            _ -> do
                (ca, rest0) <- commonAttrsFromObject o
                let rest = KeyMap.delete "type" rest0
                case tag of
                    "buildTx" -> FcBuildTx ca <$> parseJSON (Object rest)
                    "signTxs" -> FcSignTxs ca <$> parseJSON (Object rest)
                    "submitTxs" -> FcSubmitTxs ca <$> parseJSON (Object rest)
                    "buildFsTxs" -> FcBuildFsTxs ca <$> parseJSON (Object rest)
                    "signDataWithAddress" -> FcSignData ca <$> parseJSON (Object rest)
                    "verifySignatureWithAddress" -> FcVerifySig ca <$> parseJSON (Object rest)
                    "query" -> FcQuery ca <$> parseJSON (Object rest)
                    "plutusScript" -> FcPlutusScript ca <$> parseJSON (Object rest)
                    "plutusData" -> FcPlutusData ca <$> parseJSON (Object rest)
                    "nativeScript" -> FcNativeScript ca <$> parseJSON (Object rest)
                    "macro" -> FcMacro ca <$> parseJSON (Object rest)
                    other -> pure (FcUnsupported ca other rest)

-- ---------------------------------------------------------------------
-- JSON: GCScript

instance ToJSON GCScript where
    toJSON gcs =
        object $
            [ "type" .= ("script" :: Text)
            , "run" .= gcsRun gcs
            ]
                <> catJust
                    [ ("title" .=) <$> gcsTitle gcs
                    , ("description" .=) <$> gcsDescription gcs
                    , ("exportAs" .=) <$> gcsExportAs gcs
                    , ("args" .=) <$> gcsArgs gcs
                    , ("argsByKey" .=) <$> gcsArgsByKey gcs
                    , ("returnURLPattern" .=) <$> gcsReturnURLPattern gcs
                    , ("require" .=) <$> gcsRequire gcs
                    , ("return" .=) <$> gcsReturn gcs
                    ]

instance FromJSON GCScript where
    parseJSON = withObject "GCScript" $ \o -> do
        tag <- o .: "type"
        case (tag :: Text) of
            "script" ->
                GCScript
                    <$> o .:? "title"
                    <*> o .:? "description"
                    <*> o .: "run"
                    <*> o .:? "exportAs"
                    <*> o .:? "args"
                    <*> o .:? "argsByKey"
                    <*> o .:? "return"
                    <*> o .:? "returnURLPattern"
                    <*> o .:? "require"
            other ->
                fail $
                    "expected top-level type \"script\", got "
                        <> T.unpack other
