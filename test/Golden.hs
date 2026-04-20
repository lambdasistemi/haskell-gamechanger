{-# LANGUAGE OverloadedStrings #-}

{- | Golden round-trip harness for 'GameChanger.Script'.

For every @test/golden/*.json@ fixture:

1. decode the on-disk JSON to 'Aeson.Value' — the canonical form;
2. decode the same JSON to 'Script' via the library's 'FromJSON';
3. re-encode that 'Script' via 'ToJSON' and decode back to 'Value';
4. compare the two 'Value's for structural equality.

Any drift between the committed fixture and the round-tripped
output fails the test with the fixture's path, so the failing
fixture is named directly in the output.
-}
module Golden (goldenTests) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBSC
import GameChanger.Script (Script)
import System.FilePath (takeBaseName)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (findByExtension)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

goldenTests :: IO TestTree
goldenTests = do
    paths <- findByExtension [".json"] "test/golden"
    pure $ testGroup "Golden" (map oneFixture paths)

oneFixture :: FilePath -> TestTree
oneFixture path = testCase (takeBaseName path) $ do
    bytes <- LBS.readFile path
    original <- case Aeson.eitherDecode bytes :: Either String Aeson.Value of
        Left e -> assertFailure $ "fixture is not valid JSON: " <> e
        Right v -> pure v
    script <- case Aeson.eitherDecode bytes :: Either String Script of
        Left e ->
            assertFailure $
                "fixture decoded as Value but failed to decode as Script: "
                    <> e
                    <> "\noriginal: "
                    <> LBSC.unpack (Aeson.encode original)
        Right s -> pure s
    let reencoded = Aeson.encode script
    roundtrip <- case Aeson.eitherDecode reencoded :: Either String Aeson.Value of
        Left e -> assertFailure $ "re-encoded Script is not valid JSON: " <> e
        Right v -> pure v
    roundtrip @?= original
