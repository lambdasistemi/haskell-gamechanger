{-# LANGUAGE OverloadedStrings #-}

{- | Throwaway probe for issue #25 open question Q2.

Builds a resolver URL for a @signDataWithAddress@ action whose
@returnURLPattern@ points at @http://localhost:8080/?r={result}@.
Running the URL through the beta-preprod GameChanger wallet and
observing whether the browser follows the redirect answers
whether the library's callback module can rely on plain
@http://localhost@ URLs.

Wired into @haskell-gamechanger.cabal@ as the @q2-probe@
executable. To run:

> nix develop -c cabal run q2-probe -- <preprod-bech32-address>

Removed together with the cabal stanza once Q2 is resolved.
-}
module Main where

import qualified Data.Aeson as Aeson
import qualified Data.Base64.Types as B64T
import qualified Data.ByteString.Base64.URL as B64
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import GameChanger.Encoding.LzmaAlone (encode)
import GameChanger.GCScript (
    CommonAttrs (..),
    FunctionCall (..),
    GCScript (..),
    ReturnMode (..),
    ReturnSpec (..),
    RunBlock (..),
    SignDataBody (..),
    emptyCommonAttrs,
 )
import System.Environment (getArgs)

-- "hello" as hex
helloHex :: Text
helloHex = "68656c6c6f"

callbackPattern :: Text
callbackPattern = "http://localhost:8080/?r={result}"

hostPrefix :: Text
hostPrefix = "https://beta-preprod-wallet.gamechanger.finance/api/2/run/"

probe :: Text -> IO ()
probe addr = do
    let ca = emptyCommonAttrs{caReturnURLPattern = Just callbackPattern}
        body = SignDataBody{sdAddress = addr, sdDataHex = helloHex}
        gcs =
            GCScript
                { gcsTitle = Just "Q2 probe: localhost returnURLPattern"
                , gcsDescription = Just "Signs literal 'hello' to test wallet's acceptance of http://localhost"
                , gcsRun = RunObject (Map.fromList [("sig", FcSignData ca body)])
                , gcsExportAs = Just "ProbeResult"
                , gcsArgs = Nothing
                , gcsArgsByKey = Nothing
                , gcsReturn = Just (ReturnSpec{rsMode = Last, rsKey = Nothing, rsKeys = Nothing, rsExec = Nothing})
                , gcsReturnURLPattern = Nothing
                , gcsRequire = Nothing
                }
        jsonBytes = BSL.toStrict (Aeson.encode gcs)
        compressed = encode jsonBytes
        payload = B64T.extractBase64 (B64.encodeBase64Unpadded compressed)
        url = hostPrefix <> payload
    TIO.putStrLn "--- script JSON ---"
    BSL.putStr (Aeson.encode gcs)
    TIO.putStrLn ""
    TIO.putStrLn "--- resolver URL ---"
    TIO.putStrLn url

main :: IO ()
main = do
    args <- getArgs
    case args of
        [addr] -> probe (T.pack addr)
        _ -> TIO.putStrLn "usage: q2-probe <preprod-bech32-address>"
