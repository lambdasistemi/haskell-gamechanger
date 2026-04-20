{-# LANGUAGE DerivingStrategies #-}
{-# OPTIONS_GHC -Wno-partial-fields #-}

{- | Encode / decode @Script@ values as resolver URLs.

The public surface of ticket #7. Turns a 'Script' into a
'ResolverUrl' the live GameChanger wallet accepts, and reverses the
pipeline to recover a 'Script' from an incoming URL.

The wire format is LZMA-alone compression + base64url (unpadded) at
@\/api\/2\/run\/@. See [data-model.md](../../specs/003-gamechanger-encoding-lzma1/data-model.md)
for byte-level details.

Bodies are stubbed with 'undefined' in the initial commit and filled
in by phases 2–5 of the task list. The module compiles so that the
rest of the tree stays bisect-safe while the encoder lands.
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

import Data.Text (Text)
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
environmentHost = undefined -- NOTE: stub, filled in by T010

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
mkResolverUrl = undefined -- NOTE: stub, filled in by T011

{- | Encode a 'Script' into a 'ResolverUrl' targeted at the given
environment. Pure; never fails.
-}
encodeScript :: Environment -> Script -> ResolverUrl
encodeScript = undefined -- NOTE: stub, filled in by T012

{- | Decode a 'ResolverUrl' back into a 'Script'. Fails with a
stage-named 'DecodeError' if any pipeline stage rejects the input.
-}
decodeResolverUrl :: ResolverUrl -> Either DecodeError Script
decodeResolverUrl = undefined -- NOTE: stub, filled in by T013

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
