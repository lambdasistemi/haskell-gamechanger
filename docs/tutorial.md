# Tutorial

An end-to-end walk through `haskell-gamechanger` as a caller
would use it: build a script, turn it into a resolver URL, send
the URL to a user's browser, receive the wallet's response. The
library does not sign — keys live in the wallet — so the
tutorial stops at the point the URL is ready for delivery and
resumes at the point the result comes back.

Every example compiles against the modules documented here
(`GameChanger.Script`, `GameChanger.Intent`, `GameChanger.GCScript`,
`GameChanger.Encoding`). Copy-paste into a `.hs` file in a
project depending on `haskell-gamechanger`.

## What you'll end up with

A `signData` flow: your backend asks the user to sign a text
message at a given address, and the wallet posts the CIP-8
signature back to an HTTP endpoint you control.

```
backend ──build──► GCScript ──encode──► resolver URL
                                           │
                                           ▼
                                      user's browser
                                           │
                                           ▼ (user approves)
                                       signature
                                           │
          backend ◄───────post body────────┘
                  (JSON with signature bytes)
```

Same shape applies to `buildTx` + `signTx` + `submitTx` flows;
the tutorial uses `signData` because it is the shortest end-to-
end example that still hits every layer.

## 1. Pick your layer

| Layer | Module | Use when |
|---|---|---|
| Low-level record | `GameChanger.Script` | You want a small, hand-rolled script with exports. Legacy. |
| AST mirror | `GameChanger.GCScript` | You need the full upstream DSL shape — decoding arbitrary wallet scripts, round-trip fidelity, forward-compat for unknown tags. See [GCScript AST](./gcscript.md). |
| Monadic eDSL | `GameChanger.Intent` | You want typed wiring between actions (`tx` from `buildTx` flows into `signTx` with no stringly-typed template expressions). See [Intent eDSL](./intent-dsl.md). |

The rest of this tutorial uses `GameChanger.Script` because
it is the simplest path to a working URL. When you outgrow it
— you want typed wiring, or you need to parse/emit the full
upstream DSL — move up one layer.

## 2. Build a script

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Demo where

import qualified Data.Map.Strict as Map
import GameChanger.Script
    ( Channel (..)
    , Export (..)
    , Script (..)
    , signDataAction
    )

demoScript :: Script
demoScript =
    Script
        { title = "Sign a message"
        , description = Just "Proves control of the given address."
        , run = Map.fromList
            [ ("sig", signDataAction "sig" "{get('args.address')}" "hello world")
            ]
        , exports = Map.fromList
            [ ( "signature"
              , Export
                  { source = "{get('cache.sig')}"
                  , channel = Post "https://example.org/gc/callback"
                  }
              )
            ]
        , metadata = Nothing
        }
```

The `run` map names each action; the `exports` map names each
result channel and how the wallet should deliver it.
`{get('cache.sig')}` is the wallet's template language — it
references the `sig` entry of `run`. You write template
strings by hand at this layer; the Intent eDSL generates them
from typed bindings.

## 3. Turn it into a resolver URL

```haskell
import qualified Data.Text.IO as TIO
import GameChanger.Encoding
    ( Environment (..)
    , encodeScript
    , unResolverUrl
    )

main :: IO ()
main = TIO.putStrLn (unResolverUrl (encodeScript BetaPreprod demoScript))
```

`encodeScript` picks the environment host, serialises the
script as JSON, compresses with LZMA-alone, and base64url-
encodes the result. Output:

```
https://beta-preprod-wallet.gamechanger.finance/api/2/run/XQAA...
```

Three supported environments: `Mainnet`, `BetaMainnet`,
`BetaPreprod`. They differ only in host.

## 4. Deliver the URL

How the user opens the URL is outside this library. Common
choices:

- Render the URL as a QR code (`qrencode` at the CLI, or
  `haskell-qrcode` in a web backend) and show it on a page
  the user scans with their phone.
- Embed the URL in an HTML page as an `<a href="...">` link.
- Print it in a terminal for a CLI tool with a local user.

Whatever the transport, the wallet loads the URL, the user
approves the action, and the wallet posts the result to the
`postUrl` from the export channel.

## 5. Receive the wallet's response

The response is an HTTP POST from the wallet to the URL you
gave in `exports`. The body is JSON; its `signature` field is
the CIP-8 COSE Sign1 signature. Pattern:

```haskell
{-# LANGUAGE OverloadedStrings #-}
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import Network.Wai (Request, requestBody)

data CallbackBody = CallbackBody { signature :: Text }
    deriving stock Show

-- Aeson decodes the POST body into CallbackBody;
-- wire into your web framework of choice.
```

The library does not prescribe a web framework. The contract
is just: "a POST with a JSON body." Servant, Wai, Scotty all
work.

## 6. Decode an inbound URL (reverse direction)

Sometimes you receive a resolver URL authored elsewhere and
want to see what it will do. `decodeResolverUrl` reverses the
pipeline:

```haskell
import GameChanger.Encoding
    ( DecodeError (..), decodeResolverUrl, mkResolverUrl )

describe :: Text -> Either DecodeError Script
describe raw = do
    url <- mkResolverUrl raw
    decodeResolverUrl url
```

Errors are stage-named (`BadResolverPrefix`, `BadBase64`,
`BadCompression`, `BadJson`), so you can tell the user whether
the URL is for the wrong environment, was corrupted in
transit, or carries invalid JSON.

## 7. When to move up to Intent

The script in §2 references actions by name
(`"{get('cache.sig')}"`). A typo there is invisible to the
compiler and only surfaces at wallet-execution time. If the
script grows past one or two actions — `buildTx` → `signTx` →
`submitTx`, for example — the Intent eDSL pays for itself:

```haskell
import Control.Monad.Operational (Program)
import GameChanger.Intent

payFlow :: Address -> Intent TxId
payFlow addr = do
    utxos  <- getUTxOs addr
    tx     <- buildTx (mkArgs utxos)
    signed <- signTx tx
    submitTx signed
```

Each `<-` becomes a run-block entry; each reference to a bound
variable becomes a `{get('cache.<name>')}` expression in the
emitted JSON. Typos stop compiling. See
[Intent eDSL](./intent-dsl.md) for the full surface.

## 8. When to move up to GCScript

If you need to decode arbitrary upstream scripts — including
ones using DSL features the library does not model
structurally — use `GameChanger.GCScript`. It preserves
unknown function kinds verbatim (`FcUnsupported`) and round-
trips every file in the curated corpus. See
[GCScript AST](./gcscript.md) for the tutorial on that layer.

## What this library does not do

- **Sign.** Keys live in the wallet. The backend composes the
  request and consumes the result; it never holds a key.
- **Submit transactions by itself.** If you use `post`-channel
  submission, the wallet submits. If you want the backend to
  submit (e.g. because it is aggregating multiple signatures),
  skip `submitTxAction` in the script and submit via your
  existing node-clients path after receiving the signed tx.
- **Run in the browser.** This is a native-backend library.
  See [scope](./scope.md).

## Links

- [Protocol](./protocol.md) — the wire format and export modes
- [Integration](./integration.md) — canonical topologies
- [Intent eDSL](./intent-dsl.md) — the typed monadic surface
- [GCScript AST](./gcscript.md) — the JSON-faithful AST
- [Security](./security.md) — threat model and attack surface
