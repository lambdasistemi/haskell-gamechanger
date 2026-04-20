{-# LANGUAGE OverloadedStrings #-}

{- | Tests for "GameChanger.Encoding.LzmaAlone".

Covers the byte-level invariants of the LZMA-alone codec — this is
the layer the wallet is most picky about, so we catch any format
drift here before the pipeline test in "GameChanger.Encoding" sees
it.
-}
module EncodingSpec (
    tests,
) where

import Arbitrary ()
import qualified Data.ByteString as BS
import GameChanger.Encoding (
    decodeResolverUrl,
    encodeScript,
 )
import qualified GameChanger.Encoding.LzmaAlone as LzmaAlone
import GameChanger.Script (Script)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, testCase, (@?=))
import Test.Tasty.QuickCheck (
    forAll,
    testProperty,
    withMaxSuccess,
    (===),
 )
import qualified Test.Tasty.QuickCheck as QC

tests :: TestTree
tests =
    testGroup
        "Encoding"
        [ testGroup
            "LzmaAlone"
            [ roundTripSynthetic
            , headerLayoutRegression
            ]
        , testGroup
            "ResolverUrl"
            [ roundTripProperty
            ]
        ]

{- | For every 'Environment', `decodeResolverUrl . encodeScript env ≡
Right`. 1000 cases per environment. 'Arbitrary' instances live in
"Arbitrary".
-}
roundTripProperty :: TestTree
roundTripProperty =
    testGroup "encodeScript / decodeResolverUrl round-trip" $
        map perEnv [minBound .. maxBound]
  where
    perEnv env =
        testProperty (show env) $
            withMaxSuccess 1000 $
                forAll (QC.arbitrary :: QC.Gen Script) $ \s ->
                    decodeResolverUrl (encodeScript env s) === Right s

{- | Encoding then decoding a synthetic payload yields the original
bytes. The input mixes ASCII and non-ASCII UTF-8 bytes to exercise
the codec over the full byte range.
-}
roundTripSynthetic :: TestTree
roundTripSynthetic = testCase "round-trip synthetic payload" $ do
    let payload = BS.concat (replicate 16 sample)
        sample =
            BS.pack
                [ 0x68
                , 0x65
                , 0x6c
                , 0x6c
                , 0x6f
                , 0x20
                , 0xe4
                , 0xb8
                , 0x96
                , 0xe7
                , 0x95
                , 0x8c -- "hello 世界"
                ]
    case LzmaAlone.decode (LzmaAlone.encode payload) of
        Left e ->
            error $ "decode failed: " <> show e
        Right decoded ->
            decoded @?= payload

{- | The first 13 bytes of every encoded stream are the canonical
@.lzma@ alone header: properties byte @0x5D@, 4-byte dictionary size
@0x02000000@ (32 MiB, little-endian), 8-byte uncompressed size
(little-endian).

This is the byte layout the GameChanger wallet's decoder expects.
If a future liblzma or cabal bump changes this, we catch it here.
-}
headerLayoutRegression :: TestTree
headerLayoutRegression = testCase "header bytes match .lzma alone spec" $ do
    let payload = BS.replicate 100 0x41 -- 100 'A' bytes
        encoded = LzmaAlone.encode payload
        expectedHeader =
            BS.pack
                [ 0x5D -- properties
                , 0x00
                , 0x00
                , 0x00
                , 0x02 -- dict size LE = 0x02000000
                , 0x64
                , 0x00
                , 0x00
                , 0x00
                , 0x00
                , 0x00
                , 0x00
                , 0x00 -- uncompressed size LE = 100
                ]
    assertEqual "13-byte header" expectedHeader (BS.take 13 encoded)
