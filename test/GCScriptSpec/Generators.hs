{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

{- | QuickCheck generators for 'GCScript' and friends.

Depth-capped so the QuickCheck state space stays tractable. The
emphasis is exercising every branch of every sum type, not
producing semantically meaningful scripts.
-}
module GCScriptSpec.Generators (
    genGCScript,
    shrinkText,
) where

import Data.Aeson (Object, Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Scientific (scientific)
import Data.Text (Text)
import qualified Data.Text as T
import GameChanger.GCScript (
    BuildFsTxsBody (..),
    BuildTxBody (..),
    CommonAttrs (..),
    FunctionCall (..),
    GCScript (..),
    MacroBody (..),
    NativeScriptBody (..),
    PlutusDataBody (..),
    PlutusScriptBody (..),
    QueryBody (..),
    ReturnMode (..),
    ReturnSpec (..),
    RunBlock (..),
    SignDataBody (..),
    SignTxsBody (..),
    SubmitTxsBody (..),
    VerifySigBody (..),
 )
import Test.QuickCheck (
    Arbitrary (..),
    Gen,
    arbitraryBoundedEnum,
    elements,
    frequency,
    listOf,
    oneof,
    resize,
    sized,
    vectorOf,
 )
import qualified Test.QuickCheck as QC

-- | Shrink 'Text' by dropping characters.
shrinkText :: Text -> [Text]
shrinkText = map T.pack . shrink . T.unpack

-- | Generate a 'GCScript' capped to the QuickCheck 'sized' parameter.
genGCScript :: Gen GCScript
genGCScript = arbitrary

-- ---------------------------------------------------------------------
-- Primitive-ish generators

genIdent :: Gen Text
genIdent = do
    n <- QC.choose (1, 6)
    T.pack <$> vectorOf n (elements ['a' .. 'z'])

genISL :: Gen Text
genISL = do
    name <- genIdent
    pure $ "{get('cache." <> name <> "')}"

-- Small JSON value for body fillers. Strings dominate because
-- the corpus is mostly ISL-string-shaped.
genShallowValue :: Gen Value
genShallowValue = sized $ \n ->
    frequency
        [ (4, String <$> genISL)
        , (3, String <$> genIdent)
        , (2, pure (Bool True))
        , (2, pure (Bool False))
        , (2, Number . scientific 1 <$> QC.choose (0, 6))
        , (1, pure Null)
        , (1, Array . pure . String <$> genIdent)
        ,
            ( if n <= 0 then 0 else 1
            , resize (n `div` 2) $ Object <$> genObject
            )
        ]

{- | 'genShallowValue' without 'Null'. Aeson's '.:?' parser elides
JSON @null@ into 'Nothing', so a @Just Null@ at a @Maybe Value@
field cannot round-trip. The corpus never emits @"args": null@
either: callers omit the key.
-}
genShallowValueNonNull :: Gen Value
genShallowValueNonNull = genShallowValue `QC.suchThat` (/= Null)

-- Generic object for 'Value'-typed positions. Its keys are
-- unrestricted because 'Value' slots (e.g. @gcsArgs@) are parsed
-- opaquely and never subjected to common-attrs stripping.
genObject :: Gen Object
genObject = sized $ \n -> do
    k <- QC.choose (0, min 3 n)
    KeyMap.fromList <$> vectorOf k ((,) . Key.fromText <$> genIdent <*> genShallowValue)

-- Object appearing at a FunctionCall body position (BuildTxBody,
-- QueryBody, FcUnsupported rest, ...). Keys are prefixed with
-- \'k\' so they cannot collide with @type@ or the eight
-- 'CommonAttrs' keys, which would otherwise be stripped into
-- 'CommonAttrs' on decode and break the round-trip.
genBodyObject :: Gen Object
genBodyObject = sized $ \n -> do
    k <- QC.choose (0, min 3 n)
    KeyMap.fromList <$> vectorOf k ((,) <$> genBodyKey <*> genShallowValue)
  where
    genBodyKey = do
        t <- genIdent
        pure $ Key.fromText ("k" <> t)

-- Tag for 'FcUnsupported'. Prefixed with \'x\' so it never
-- matches a recognised function kind (@buildTx@, @signTxs@, ...)
-- or the @script@ discriminator.
genUnsupportedTag :: Gen Text
genUnsupportedTag = T.cons 'x' <$> genIdent

-- ---------------------------------------------------------------------
-- ReturnSpec

instance Arbitrary ReturnMode where
    arbitrary = arbitraryBoundedEnum

instance Arbitrary ReturnSpec where
    arbitrary = do
        mode <- arbitrary
        case mode of
            One ->
                ReturnSpec mode . Just
                    <$> genIdent
                    <*> pure Nothing
                    <*> pure Nothing
            Some ->
                ReturnSpec mode Nothing . Just
                    <$> listOf genIdent
                    <*> pure Nothing
            Macro -> ReturnSpec mode Nothing Nothing . Just <$> genISL
            _ -> pure (ReturnSpec mode Nothing Nothing Nothing)

-- ---------------------------------------------------------------------
-- CommonAttrs

genMaybe :: Gen a -> Gen (Maybe a)
genMaybe g = frequency [(3, pure Nothing), (1, Just <$> g)]

genArgsByKey :: Gen (Map Text Value)
genArgsByKey = do
    n <- QC.choose (0, 3)
    Map.fromList <$> vectorOf n ((,) <$> genIdent <*> genShallowValue)

instance Arbitrary CommonAttrs where
    arbitrary =
        CommonAttrs
            <$> genMaybe genIdent
            <*> genMaybe genIdent
            <*> genMaybe genIdent
            <*> genMaybe genShallowValueNonNull
            <*> genMaybe genArgsByKey
            <*> genMaybe genISL
            <*> genMaybe genShallowValueNonNull
            <*> genMaybe arbitrary

-- ---------------------------------------------------------------------
-- Per-kind bodies

instance Arbitrary BuildTxBody where
    arbitrary = BuildTxBody <$> genBodyObject

instance Arbitrary BuildFsTxsBody where
    arbitrary = BuildFsTxsBody <$> genBodyObject

instance Arbitrary QueryBody where
    arbitrary = QueryBody <$> genBodyObject

instance Arbitrary PlutusScriptBody where
    arbitrary = PlutusScriptBody <$> genBodyObject

instance Arbitrary PlutusDataBody where
    arbitrary = PlutusDataBody <$> genBodyObject

instance Arbitrary NativeScriptBody where
    arbitrary = NativeScriptBody <$> genBodyObject

instance Arbitrary SignTxsBody where
    arbitrary =
        SignTxsBody
            <$> genShallowValueNonNull
            <*> genMaybe arbitrary
            <*> genMaybe arbitrary
            <*> genMaybe genShallowValueNonNull

instance Arbitrary SubmitTxsBody where
    arbitrary =
        SubmitTxsBody
            <$> genShallowValue
            <*> genMaybe (elements ["wait", "noWait"])

instance Arbitrary SignDataBody where
    arbitrary = SignDataBody <$> genIdent <*> genIdent

instance Arbitrary VerifySigBody where
    arbitrary = VerifySigBody <$> genIdent <*> genIdent <*> genIdent

instance Arbitrary MacroBody where
    arbitrary = MacroBody <$> arbitrary

-- ---------------------------------------------------------------------
-- RunBlock / FunctionCall / GCScript (mutually recursive)

instance Arbitrary RunBlock where
    arbitrary = sized $ \n ->
        if n <= 0
            then RunISL <$> genISL
            else
                frequency
                    [ (3, RunISL <$> genISL)
                    , (2, RunArray <$> resize (n `div` 2) (listOf (resize (n `div` 3) arbitrary)))
                    , (2, RunObject <$> genRunObjectMap (n `div` 3))
                    ]

genRunObjectMap :: Int -> Gen (Map Text FunctionCall)
genRunObjectMap n = do
    k <- QC.choose (0, min 3 n)
    Map.fromList <$> vectorOf k ((,) <$> genIdent <*> resize (n `div` 2) arbitrary)

instance Arbitrary FunctionCall where
    arbitrary = sized $ \n -> do
        let structured =
                [ FcBuildTx <$> arbitrary <*> arbitrary
                , FcSignTxs <$> arbitrary <*> arbitrary
                , FcSubmitTxs <$> arbitrary <*> arbitrary
                , FcBuildFsTxs <$> arbitrary <*> arbitrary
                , FcSignData <$> arbitrary <*> arbitrary
                , FcVerifySig <$> arbitrary <*> arbitrary
                , FcQuery <$> arbitrary <*> arbitrary
                , FcPlutusScript <$> arbitrary <*> arbitrary
                , FcPlutusData <$> arbitrary <*> arbitrary
                , FcNativeScript <$> arbitrary <*> arbitrary
                , FcMacro <$> arbitrary <*> arbitrary
                , FcISL <$> genISL
                , FcUnsupported <$> arbitrary <*> genUnsupportedTag <*> genBodyObject
                ]
            recursive = [FcScript <$> resize (n `div` 2) arbitrary]
        oneof (structured ++ if n > 0 then recursive else [])

instance Arbitrary GCScript where
    arbitrary = sized $ \n -> do
        gcsTitle <- genMaybe genIdent
        gcsDescription <- genMaybe genIdent
        gcsRun <- resize (n `div` 2) arbitrary
        gcsExportAs <- genMaybe genIdent
        gcsArgs <- genMaybe genShallowValueNonNull
        gcsArgsByKey <- genMaybe genArgsByKey
        gcsReturn <- genMaybe arbitrary
        gcsReturnURLPattern <- genMaybe genISL
        gcsRequire <- genMaybe genShallowValueNonNull
        pure
            GCScript
                { gcsTitle
                , gcsDescription
                , gcsRun
                , gcsExportAs
                , gcsArgs
                , gcsArgsByKey
                , gcsReturn
                , gcsReturnURLPattern
                , gcsRequire
                }
