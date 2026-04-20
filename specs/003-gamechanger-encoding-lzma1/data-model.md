# Data Model: GameChanger.Encoding

**Feature**: 003-gamechanger-encoding-lzma1
**Plan**: [plan.md](./plan.md)

## Types

```haskell
-- | Which GameChanger wallet deployment a URL targets.
-- Closed sum — new environments extend this type.
data Environment
    = Mainnet       -- ^ wallet.gamechanger.finance
    | BetaMainnet   -- ^ beta-wallet.gamechanger.finance
    | BetaPreprod   -- ^ beta-preprod-wallet.gamechanger.finance
    deriving stock (Show, Eq, Enum, Bounded)

environmentHost :: Environment -> Text
environmentHost Mainnet     = "wallet.gamechanger.finance"
environmentHost BetaMainnet = "beta-wallet.gamechanger.finance"
environmentHost BetaPreprod = "beta-preprod-wallet.gamechanger.finance"

-- | An opaque URL. The raw constructor is NOT exported.
-- Construct via 'encodeScript' or 'mkResolverUrl'.
newtype ResolverUrl = ResolverUrl { unResolverUrl :: Text }
    deriving stock (Show, Eq)

-- | Reject strings that don't start with a known environment's
-- host followed by @/api/2/run/@.
mkResolverUrl :: Text -> Either DecodeError ResolverUrl
mkResolverUrl = …

-- | Pure encode. Never fails.
encodeScript :: Environment -> Script -> ResolverUrl

-- | Pure decode. Fails with a typed stage-aware error.
decodeResolverUrl :: ResolverUrl -> Either DecodeError Script

-- | Where in the pipeline decoding failed.
data DecodeError
    = BadResolverPrefix { errActualPrefix :: Text }
    | BadBase64         { errB64Message   :: Text }
    | BadCompression    { errLzmaMessage  :: Text }
    | BadJson           { errJsonMessage  :: Text }
    deriving stock (Show, Eq)
```

## Pipeline

```
Script ──toJSON────► ByteString
       ──alone────► ByteString           (13-byte .lzma header + LZMA1)
       ──base64url─► Text
       ──prefix────► ResolverUrl
```

Reverse:

```
ResolverUrl ──strip prefix───► Text
            ──base64url──────► ByteString       (BadBase64)
            ──alone decode───► ByteString       (BadCompression)
            ──fromJSON───────► Script           (BadJson)
```

## `.lzma` "alone" header (13 bytes)

| Offset | Size | Field              | Value                                |
| ------ | ---- | ------------------ | ------------------------------------ |
| 0      | 1    | properties         | `0x5D` (lc=3, lp=0, pb=2 — defaults) |
| 1      | 4    | dictionary size    | `0x02000000` LE = 32 MiB             |
| 5      | 8    | uncompressed size  | byte length of the JSON payload, LE  |

Followed by the raw LZMA1 stream produced by `liblzma`'s
`lzma_alone_encoder`.
