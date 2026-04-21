{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- | Round-trip harness for the 'GCScript' JSON codec.

Covers:

* @parseOnly@: every curated corpus file decodes to @Right _@
  (US1 AC).
* @determinism@: the encoder produces the same bytes on repeated
  runs (SC-002 component).
* @roundTripGolden@: @decode >>> encode >>> decode@ stabilises on
  the curated corpus (SC-001 / US3 AC).
* @prop_roundTrip@: QuickCheck property over generated scripts
  (SC-002).
* @unsupportedCoverage@: the corpus exercises at least three
  distinct 'FcUnsupported' tags (SC-003).
* @typedAccess@: US4 AC — typed field access on decoded calls
  returns typed Haskell values, not 'Value'.
-}
module GCScriptSpec (
    tests,
) where

import Control.Monad (unless)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BSL
import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import GCScriptSpec.Generators ()
import GameChanger.GCScript (
    FunctionCall (..),
    GCScript (..),
    ReturnMode (..),
    ReturnSpec (..),
    RunBlock (..),
 )
import System.Directory (listDirectory)
import System.FilePath (takeExtension, (</>))
import Test.Tasty (TestTree, localOption, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck (QuickCheckMaxSize (..), QuickCheckTests (..), testProperty)

goldenDir :: FilePath
goldenDir = "test/golden/gcscript"

-- | Top-level test entry — discovers corpus files at run time.
tests :: IO TestTree
tests = do
    files <- listCorpusFiles
    pure $
        testGroup
            "GCScript"
            [ testCase "parseOnly — every curated file decodes" (parseOnly files)
            , testCase "determinism — encode is stable" (determinism files)
            , testCase "roundTripGolden — decode/encode/decode stable" (roundTripGolden files)
            , testCase "unsupportedCoverage — ≥3 distinct tags" (unsupportedCoverage files)
            , testCase "typedAccess — buildTx in minimal demo" typedAccess
            , testCase "returnModeAccess — pay-me-1-ada return mode" returnModeAccess
            , localOption (QuickCheckTests 100) $
                localOption (QuickCheckMaxSize 6) $
                    testProperty "prop_roundTrip — decode . encode == Right" propRoundTrip
            ]

listCorpusFiles :: IO [FilePath]
listCorpusFiles = do
    entries <- listDirectory goldenDir
    pure $ sort [goldenDir </> f | f <- entries, takeExtension f == ".gcscript"]

parseOnly :: [FilePath] -> IO ()
parseOnly files = do
    assertBool "corpus must not be empty" (length files >= 15)
    mapM_ decodeOne files
  where
    decodeOne fp = do
        bs <- BSL.readFile fp
        case Aeson.eitherDecode bs :: Either String GCScript of
            Right _ -> pure ()
            Left err ->
                assertFailure $ "decode " <> fp <> " failed: " <> err

determinism :: [FilePath] -> IO ()
determinism = mapM_ checkOne
  where
    checkOne fp = do
        bs <- BSL.readFile fp
        case Aeson.eitherDecode bs :: Either String GCScript of
            Left err ->
                assertFailure $ "decode " <> fp <> " failed: " <> err
            Right v -> do
                let a = Aeson.encode v
                    b = Aeson.encode v
                unless (a == b) $
                    assertFailure $
                        "determinism violated on " <> fp

roundTripGolden :: [FilePath] -> IO ()
roundTripGolden = mapM_ checkOne
  where
    checkOne fp = do
        bs <- BSL.readFile fp
        case Aeson.eitherDecode bs :: Either String GCScript of
            Left err ->
                assertFailure $ "decode " <> fp <> " failed: " <> err
            Right v ->
                case Aeson.eitherDecode (Aeson.encode v) :: Either String GCScript of
                    Right v' ->
                        unless (v == v') $
                            assertFailure $
                                "round-trip mismatch on " <> fp
                    Left err ->
                        assertFailure $
                            "re-decode " <> fp <> " failed: " <> err

unsupportedCoverage :: [FilePath] -> IO ()
unsupportedCoverage files = do
    tags <- foldr Set.union Set.empty <$> traverse collect files
    assertBool
        ( "expected ≥3 distinct Unsupported tags, got "
            <> show (Set.toList tags)
        )
        (Set.size tags >= 3)
  where
    collect :: FilePath -> IO (Set Text)
    collect fp = do
        bs <- BSL.readFile fp
        case Aeson.eitherDecode bs :: Either String GCScript of
            Left _ -> pure Set.empty
            Right v -> pure (collectTags v)

collectTags :: GCScript -> Set Text
collectTags gcs = runTags (gcsRun gcs)

runTags :: RunBlock -> Set Text
runTags = \case
    RunObject m -> foldr (Set.union . fcTags) Set.empty (Map.elems m)
    RunArray xs -> foldr (Set.union . fcTags) Set.empty xs
    RunISL _ -> Set.empty

fcTags :: FunctionCall -> Set Text
fcTags = \case
    FcUnsupported _ tag _ -> Set.singleton tag
    FcScript inner -> collectTags inner
    _ -> Set.empty

typedAccess :: IO ()
typedAccess = do
    let fp = goldenDir </> "03-minimal-coin-sending-demo.gcscript"
    bs <- BSL.readFile fp
    case Aeson.eitherDecode bs :: Either String GCScript of
        Left err -> assertFailure $ "decode failed: " <> err
        Right v -> case gcsRun v of
            RunArray xs ->
                case [() | FcBuildTx _ _ <- xs] of
                    (_ : _) -> pure ()
                    [] -> assertFailure "expected at least one FcBuildTx in the array run"
            other -> assertFailure $ "expected RunArray, got " <> runShape other

returnModeAccess :: IO ()
returnModeAccess = do
    let fp = goldenDir </> "04-pay-me-1-ada.gcscript"
    bs <- BSL.readFile fp
    case Aeson.eitherDecode bs :: Either String GCScript of
        Left err -> assertFailure $ "decode failed: " <> err
        Right v -> case gcsReturn v of
            Just rs -> rsMode rs @?= Last
            Nothing -> assertFailure "expected a return spec"

runShape :: RunBlock -> String
runShape = \case
    RunObject _ -> "RunObject"
    RunArray _ -> "RunArray"
    RunISL _ -> "RunISL"

propRoundTrip :: GCScript -> Bool
propRoundTrip v =
    Aeson.eitherDecode (Aeson.encode v) == Right v
