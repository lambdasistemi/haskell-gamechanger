{-# LANGUAGE OverloadedStrings #-}

{- | One-shot generator for the resolver-URL fixtures under
@test\/fixtures\/resolver-urls\/@. Invoked by hand:

@
cabal run gen-fixtures
@

Reads each @test\/golden\/*.json@ listed below, encodes it via the
library's 'encodeScript', and writes the URL to @\<name\>.txt@
plus the canonicalised JSON (after @Script@ round-trip) to
@\<name\>.json@. The test harness in "EncodingSpec" consumes the
committed outputs.
-}
module Main (main) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text.IO as TIO
import GameChanger.Encoding (
    Environment (..),
    encodeScript,
    unResolverUrl,
 )
import GameChanger.Script (Script)
import System.Exit (die)

-- | @(source .json, target basename, environment)@ triples.
fixtures :: [(FilePath, FilePath, Environment)]
fixtures =
    [
        ( "test/golden/sign-data.json"
        , "test/fixtures/resolver-urls/sign-data"
        , BetaPreprod
        )
    ,
        ( "test/golden/build-tx.json"
        , "test/fixtures/resolver-urls/build-tx"
        , BetaPreprod
        )
    ,
        ( "test/golden/submit-tx.json"
        , "test/fixtures/resolver-urls/submit-tx"
        , Mainnet
        )
    ]

main :: IO ()
main = mapM_ oneFixture fixtures

oneFixture :: (FilePath, FilePath, Environment) -> IO ()
oneFixture (src, base, env) = do
    bytes <- BSL.readFile src
    script <- case Aeson.eitherDecode bytes :: Either String Script of
        Left e -> die $ src <> ": " <> e
        Right s -> pure s
    let url = unResolverUrl (encodeScript env script)
        -- Canonicalise the JSON via Script round-trip so the .json stays
        -- in sync with what decodeResolverUrl yields.
        canonical = Aeson.encode script
    TIO.writeFile (base <> ".txt") (url <> "\n")
    BSL.writeFile (base <> ".json") (canonical <> "\n")
    putStrLn $ "wrote " <> base <> ".{txt,json}"
