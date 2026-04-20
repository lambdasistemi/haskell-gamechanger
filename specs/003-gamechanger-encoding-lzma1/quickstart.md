# Quickstart: GameChanger.Encoding

```haskell
import GameChanger.Script
import GameChanger.Encoding

-- Build any Script (see #6 quickstart for helpers)
example :: Script
example = Script
    { title       = "Sign a message"
    , description = Nothing
    , run         = Map.singleton "m"
        (signDataAction "cache" "addr_test1..." "hello")
    , exports     = Map.singleton "out"
        (Export "{get('cache.m')}" (Return "https://example.com/cb"))
    , metadata    = Nothing
    }

-- Encode for the mainnet wallet
url :: ResolverUrl
url = encodeScript Mainnet example

-- unResolverUrl url
-- "https://wallet.gamechanger.finance/api/2/run/XQAAAAJNBAAAA..."

-- Round-trip
roundTripped :: Either DecodeError Script
roundTripped = decodeResolverUrl url
-- Right example
```

## Targeting a different wallet deployment

```haskell
encodeScript BetaPreprod example
-- ResolverUrl "https://beta-preprod-wallet.gamechanger.finance/api/2/run/…"
```

## Parsing an incoming URL from a callback

```haskell
case mkResolverUrl incomingString >>= decodeResolverUrl . id of
    Left  (BadResolverPrefix p) -> rejectWith ("unknown host/path: " <> p)
    Left  (BadBase64       m)  -> rejectWith ("bad base64: "        <> m)
    Left  (BadCompression  m)  -> rejectWith ("bad compression: "   <> m)
    Left  (BadJson         m)  -> rejectWith ("bad JSON: "          <> m)
    Right script               -> process script
```
