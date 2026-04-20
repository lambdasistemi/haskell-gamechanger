{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-partial-fields #-}

{- | Encode / decode @Script@ values as resolver URLs.

The public surface of ticket #7. Turns a 'Script' into a
'ResolverUrl' the live GameChanger wallet accepts, and reverses the
pipeline to recover a 'Script' from an incoming URL.

The wire format is LZMA-alone compression + base64url (unpadded) at
@\/api\/2\/run\/@. See [data-model.md](../../specs/003-gamechanger-encoding-lzma1/data-model.md)
for byte-level details.
-}
module GameChanger.Encoding (
    -- * Environments
    Environment (..),
    environmentHost,

    -- * Resolver URLs
    ResolverUrl,
    unResolverUrl,
    mkResolverUrl,

    -- * Encode / decode
    encodeScript,
    decodeResolverUrl,

    -- * Errors
    DecodeError (..),
) where

import qualified Data.Aeson as Aeson
import qualified Data.Base64.Types as B64T
import qualified Data.ByteString.Base64.URL as B64
import qualified Data.ByteString.Lazy as BSL
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GameChanger.Encoding.LzmaAlone (decode, encode)
import GameChanger.Script (Script)

{- | Which GameChanger wallet deployment a URL targets.

Closed sum — new environments extend this type.
-}
data Environment
    = -- | @wallet.gamechanger.finance@
      Mainnet
    | -- | @beta-wallet.gamechanger.finance@
      BetaMainnet
    | -- | @beta-preprod-wallet.gamechanger.finance@
      BetaPreprod
    deriving stock (Show, Eq, Enum, Bounded)

-- | Host portion of the resolver URL for a given environment.
environmentHost :: Environment -> Text
environmentHost Mainnet = "wallet.gamechanger.finance"
environmentHost BetaMainnet = "beta-wallet.gamechanger.finance"
environmentHost BetaPreprod = "beta-preprod-wallet.gamechanger.finance"

-- | Fixed path segment shared by every wallet environment.
resolverPath :: Text
resolverPath = "/api/2/run/"

-- | Full scheme + host + path prefix for an environment's resolver URLs.
environmentPrefix :: Environment -> Text
environmentPrefix env = "https://" <> environmentHost env <> resolverPath

{- | An opaque wallet resolver URL.

The raw constructor is not exported. Construct via 'encodeScript'
or 'mkResolverUrl'.
-}
newtype ResolverUrl = ResolverUrl {unResolverUrl :: Text}
    deriving stock (Show, Eq)

{- | Parse a 'Text' into a 'ResolverUrl', rejecting strings that don't
start with a known environment's host followed by @\/api\/2\/run\/@.
-}
mkResolverUrl :: Text -> Either DecodeError ResolverUrl
mkResolverUrl t =
    case find (`T.isPrefixOf` t) (map environmentPrefix [minBound .. maxBound]) of
        Just _ -> Right (ResolverUrl t)
        Nothing -> Left (BadResolverPrefix (T.take 64 t))

{- | Encode a 'Script' into a 'ResolverUrl' targeted at the given
environment. Pure; never fails.
-}
encodeScript :: Environment -> Script -> ResolverUrl
encodeScript env s =
    ResolverUrl (environmentPrefix env <> payload)
  where
    jsonBytes = BSL.toStrict (Aeson.encode s)
    compressed = encode jsonBytes
    payload = B64T.extractBase64 (B64.encodeBase64Unpadded compressed)

{- | Decode a 'ResolverUrl' back into a 'Script'. Fails with a
stage-named 'DecodeError' if any pipeline stage rejects the input.
-}
decodeResolverUrl :: ResolverUrl -> Either DecodeError Script
decodeResolverUrl (ResolverUrl url) = do
    payload <- stripPrefix
    raw <- case B64.decodeBase64Untyped (TE.encodeUtf8 payload) of
        Left e -> Left (BadBase64 e)
        Right bs -> Right bs
    json <- case decode raw of
        Left e -> Left (BadCompression e)
        Right bs -> Right bs
    case Aeson.eitherDecodeStrict json of
        Left e -> Left (BadJson (T.pack e))
        Right s -> Right s
  where
    prefixes = map environmentPrefix [minBound .. maxBound]
    stripPrefix =
        case find (`T.isPrefixOf` url) prefixes of
            Just p -> Right (T.drop (T.length p) url)
            Nothing -> Left (BadResolverPrefix (T.take 64 url))

-- | Where in the decoding pipeline a failure occurred.
data DecodeError
    = -- | URL did not match any known environment host + path.
      BadResolverPrefix {errActualPrefix :: Text}
    | -- | Base64url decode failed.
      BadBase64 {errB64Message :: Text}
    | -- | LZMA decode failed (wrong header, corrupt stream, …).
      BadCompression {errLzmaMessage :: Text}
    | -- | JSON parse of the decompressed payload failed.
      BadJson {errJsonMessage :: Text}
    deriving stock (Show, Eq)
