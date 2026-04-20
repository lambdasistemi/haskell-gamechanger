# Protocol

A tour of the GameChanger protocol: its script DSL, how scripts are
encoded into URLs, and how results come back through export modes.

This page is derivative of the
[constitution](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md) —
if the two diverge, the constitution wins and this page is updated.

## The script is the protocol

Everything the wallet does is driven by a single **JSON script**.
Scripts are data, not code: the wallet interprets them against a
fixed, bounded action set. There are no loops, no arbitrary
expressions — only typed action invocations, template references
between them, and export declarations.

```json
{
  "type": "script",
  "title": "Sign a message",
  "description": "Example sign-message flow",
  "exports": {
    "signature": {
      "source": "{get('cache.signResult')}"
    }
  },
  "run": {
    "signResult": {
      "type": "signData",
      "namespace": "cache",
      "detail": {
        "address": "addr_...",
        "message": "hello"
      }
    }
  }
}
```

### Anatomy

| Field | Purpose |
|---|---|
| `type` | Always `"script"` for the top-level form we target |
| `title`, `description` | Shown to the user in the wallet's confirmation UI |
| `run` | Ordered map of named actions the wallet executes |
| `exports` | Map of result channels — how outputs leave the wallet |

### Actions

Each entry in `run` is an **action invocation**. Actions have a
`type` (the action name, e.g. `buildTx`, `signTx`, `signData`,
`submitTx`, `getUTxOs`), a `namespace` (where its output is cached
for later reference), and a `detail` payload specific to the action.

Actions reference each other by template expressions like
`{get('cache.signResult')}`. Only previously-computed outputs in the
same script are reachable.

### Exports

The `exports` block declares the **result channels**. Each entry
maps a display name to a descriptor that specifies:

- `source` — a template expression resolving to the value to export;
- a **mode** — where the result goes (redirect, POST, download,
  QR, clipboard). See [Export modes](#export-modes).

Scripts may declare multiple exports; they are all performed.

## Encoding pipeline

The script never travels as plain JSON. Clients encode it like this:

```
JSON  ──lzma-alone──►  bytes  ──base64url──►  ascii  ──prepend──►  resolver URL
```

The final URL looks like:

```
https://beta-preprod-wallet.gamechanger.finance/api/2/run/<base64url-of-lzma-alone-encoded-json>
```

The base64 payload always starts with `XQ` — the base64 encoding of
the LZMA-alone properties byte (`0x5D`) followed by the top of the
little-endian dictionary-size field (`0x00`).

### The `.lzma` alone container (13-byte header)

The compressed body is not raw LZMA1 and not `.xz`. It is the legacy
`.lzma` "alone" container: a 13-byte header followed by an LZMA1
stream, with no end-of-stream marker beyond the uncompressed-size
field in the header.

| Offset | Size | Field              | Value                                |
| ------ | ---- | ------------------ | ------------------------------------ |
| 0      | 1    | properties         | `0x5D` (lc=3, lp=0, pb=2 — defaults) |
| 1      | 4    | dictionary size    | `0x02000000` LE = 32 MiB             |
| 5      | 8    | uncompressed size  | byte length of the JSON payload, LE  |

`liblzma`'s `lzma_alone_encoder` emits exactly this layout, with one
caveat: for streaming input it writes `0xFF…FF` in the
uncompressed-size field ("unknown"). The wallet's decoder rejects
that marker, so the encoder patches bytes 5–12 with the actual length
before handing the buffer off.

### Properties

- **lzma-alone** — legacy `.lzma` format, not `.xz`. Any `liblzma`
  build exposes it via `lzma_alone_encoder`; no custom magic. The
  GameChanger wallet detects this variant from its `XQ` header.
- **base64url** — URL-safe alphabet (`-`, `_` substitutions), padding
  (`=`) stripped.
- **Size threshold** — beyond a certain size the script does not fit
  in a URL and has to be hosted (the URL then references the hosted
  blob). This project targets the inline form; hosted scripts are a
  future concern.

### Haskell sketch

The implementation lives in
[`GameChanger.Encoding`](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/src/GameChanger/Encoding.hs).
The pipeline is:

```haskell
import qualified Data.Aeson as Aeson
import qualified Data.Base64.Types as B64T
import qualified Data.ByteString.Base64.URL as B64
import qualified Data.ByteString.Lazy as BSL
import GameChanger.Encoding (Environment (..), encodeScript)
import qualified GameChanger.Encoding.LzmaAlone as LzmaAlone

-- Pure; never fails.
-- encodeScript :: Environment -> Script -> ResolverUrl

-- Under the hood:
--   JSON bytes = Aeson.encode script
--   compressed = LzmaAlone.encode jsonBytes
--   payload    = B64.encodeBase64Unpadded compressed
--   url        = "https://" <> host env <> "/api/2/run/" <> payload
```

`LzmaAlone.encode` wraps `liblzma` via a small C shim (`cbits/gc_lzma_alone.c`)
because the Hackage `lzma` package only exposes the `.xz` format. The
inverse `decodeResolverUrl` rebuilds the `Script` and is used by both
the public API and the round-trip property test.

## Export modes

| Mode | Destination | Typical receiver | Notes |
|---|---|---|---|
| `return` | Appended to a redirect URL | The browser page that opened the wallet | Good for client-only flows |
| `post` | HTTP POST from the browser | A backend endpoint | The *only* path by which a non-browser process observes the signature |
| `download` | Browser file download | The human operator | Manual; fine for airgapped or forensic flows |
| `qr` | Displayed as a QR code | A second device (phone camera) | Out-of-band |
| `copy` | Placed on the clipboard | The human operator | Manual paste; vulnerable to clipboard hijack |

### Implication

A backend integration **must** use a `post` export (or a `return`
export to a page that itself POSTs to the backend). There is no
"pull" API — the wallet does not expose the result to a polled
endpoint. The result is *pushed* through whatever export the script
declared.

## What the protocol does not provide

- **No authentication** of the script issuer to the wallet. Any URL
  can be opened; the user's consent in the wallet UI is the gate.
- **No authentication** of the callback to the backend. The script
  issuer must bind session tokens to resolver URLs if it wants to
  distinguish legitimate callbacks from replays or forgeries.
- **No automatic retry.** If the callback fails, the signed result
  is lost unless the export mode also included a download or copy.

These gaps shape the [security model](./security.md).
