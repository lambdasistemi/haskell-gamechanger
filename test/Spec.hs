{-# LANGUAGE OverloadedStrings #-}

{- | Test entry point.

Wires the Script round-trip harness (unit round-trips + goldens)
into tasty. The per-suite content lives in 'Golden' and in the
inline test cases below.
-}
module Main (
    main,
) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified EncodingSpec
import GameChanger (version)
import GameChanger.Script
import qualified Golden
import qualified IntentSpec
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

main :: IO ()
main = do
    goldens <- Golden.goldenTests
    encoding <- EncodingSpec.tests
    defaultMain $
        testGroup
            "haskell-gamechanger"
            [ testCase "version is non-empty" $
                assertBool "version should not be empty" (not (T.null version))
            , testGroup
                "Script"
                [ roundTripHandBuilt
                , smartConstructorTags
                , goldens
                ]
            , encoding
            , IntentSpec.tests
            ]

roundTripHandBuilt :: TestTree
roundTripHandBuilt = testCase "round-trip hand-built Script" $ do
    let s =
            Script
                { title = "round-trip test"
                , description = Just "exercises every action kind and every channel mode"
                , run =
                    Map.fromList
                        [ ("u", getUTxOsAction "cache")
                        , ("b", buildTxAction "cache" (Aeson.Object mempty))
                        , ("s", signTxAction "cache" "{get('cache.b.tx')}")
                        , ("m", signDataAction "cache" "addr_test1..." "hello")
                        , ("x", submitTxAction "cache" "{get('cache.s')}")
                        ]
                , exports =
                    Map.fromList
                        [ ("ret", Export "{get('cache.m')}" (Return "https://example.invalid/cb"))
                        , ("post", Export "{get('cache.s')}" (Post "https://example.invalid/cb"))
                        , ("dl", Export "{get('cache.b')}" (Download "tx.cbor"))
                        , ("qr", Export "{get('cache.u')}" (QR Nothing))
                        , ("cp", Export "{get('cache.m')}" Copy)
                        ]
                , metadata = Nothing
                }
    case Aeson.eitherDecode (Aeson.encode s) of
        Left e -> assertFailure $ "decode failed: " <> e
        Right s' -> s' @?= s

smartConstructorTags :: TestTree
smartConstructorTags =
    testGroup "smart constructors emit the right type tag" $
        map
            check
            [ ("buildTx", buildTxAction "n" (Aeson.Object mempty))
            , ("signTx", signTxAction "n" "{ref}")
            , ("signData", signDataAction "n" "addr" "msg")
            , ("submitTx", submitTxAction "n" "{ref}")
            , ("getUTxOs", getUTxOsAction "n")
            ]
  where
    check (tag, action) = testCase (T.unpack tag) $
        case Aeson.toJSON action of
            Aeson.Object km -> case KeyMap.lookup "type" km of
                Just (Aeson.String t) -> t @?= tag
                other -> assertFailure $ "type field missing or wrong: " <> show other
            other -> assertFailure $ "Action encoded to non-object: " <> show other
