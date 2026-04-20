# Implementation Plan: GameChanger.Encoding — LZMA alone + base64url + resolver URL

**Feature**: 003-gamechanger-encoding-lzma1
**Spec**: [spec.md](./spec.md)
**Tracks**: [#7](https://github.com/lambdasistemi/haskell-gamechanger/issues/7)

## Design decisions

### D1 — LZMA backend: `lzma` Hackage package + custom "alone" encoder on top

Hackage's [`lzma`](https://hackage.haskell.org/package/lzma) package
wraps liblzma and exposes `.xz`-format compress / decompress, plus an
auto-detecting decoder that accepts legacy `.lzma`. It does **not**
expose `lzma_alone_encoder` (the legacy encoder). We deal with that as
follows:

- **Decode**: use the existing `decompressWith
  defaultDecompressParams { decompressAutoDecoder = True }` — accepts
  both `.xz` and `.lzma` inputs.
- **Encode**: synthesise the 13-byte legacy header ourselves and
  concatenate it with the raw LZMA1 stream we can obtain from liblzma
  via `lzma` package internals *or* from a thin FFI to
  `lzma_raw_encoder`.

This avoids adding a second liblzma binding. If `lzma` package
internals do not expose a raw-LZMA1 stream, we fall back to **D1a**.

### D1a (fallback) — 30-line C shim calling `lzma_alone_encoder`

If D1's "synthesise the header yourself" turns out to require low-level
liblzma state exposure that the Hackage `lzma` package does not grant,
we vendor a tiny C shim:

```c
int gc_lzma_alone_compress(
  const uint8_t* src, size_t src_sz,
  uint8_t*       dst, size_t* dst_sz);
```

Linked against the same liblzma the `lzma` package already pulls in.
Haskell side: one FFI `foreign import ccall` plus a `ByteString`
wrapper. Still no second system dependency.

The plan phase does not lock this choice — implementation T-tasks will
try D1 first, escalate to D1a if needed, and document which path we
took in the commit that lands the encoder.

### D2 — `base64` package

Pin to [`base64`](https://hackage.haskell.org/package/base64) `>= 0.4`
which exposes `encodeBase64UrlUnpadded` and `decodeBase64Url` (both
accept padded / unpadded input on decode). Avoid the older
`base64-bytestring` which has a less ergonomic URL-safe API.

### D3 — `ResolverUrl` smart constructor owns host + path

```haskell
newtype ResolverUrl = ResolverUrl { unResolverUrl :: Text }

mkResolverUrl :: Environment -> Text -> Maybe ResolverUrl
-- checks prefix matches environment host + "/api/2/run/"
```

The smart constructor is exported for callers that received a URL
from outside and want a typed handle. `encodeScript` uses it
internally after assembling the URL so the invariant is enforced at
one point.

### D4 — `Environment` closed sum, host-only

```haskell
data Environment = Mainnet | BetaMainnet | BetaPreprod
  deriving (Show, Eq, Enum, Bounded)

environmentHost :: Environment -> Text
```

No other per-environment state. Mainnet vs preprod at the Cardano
ledger level lives inside the `Script`, not in the URL.

### D5 — `DecodeError` typed by stage

```haskell
data DecodeError
  = BadResolverPrefix { errActualPrefix :: Text }
  | BadBase64         { errB64Message   :: Text }
  | BadCompression    { errLzmaMessage  :: Text }
  | BadJson           { errJsonMessage  :: Text }
  deriving (Show, Eq)
```

Stage-named constructors let callers pattern-match without string
parsing. Each carries a short diagnostic message. No
`InternalError Text` escape hatch — if a stage fails, it fails as one
of the four constructors.

### D6 — QuickCheck `Arbitrary Script` lives in `test/`, not in the library

Generating arbitrary `Script`, `Action`, `Export`, `Channel` values
is a test-only concern. Instances go in `test/Arbitrary.hs` so the
library has no QuickCheck dep. The generator produces:

- all five `ActionKind`s with plausible `detail` payloads
- all five `Channel` modes, including `QR` with both `Nothing` and
  `Just` descriptor
- `title` / `description` strings that can include non-ASCII
  codepoints and short lengths (large payloads are expensive to
  compress; bound generator size)

### D7 — Real-world fixtures: `test/fixtures/resolver-urls/*.txt`

Each file holds one wallet URL, one line. The test harness reads the
file, decodes via `decodeResolverUrl`, and asserts the resulting
`Script` matches a sibling `*.json` fixture (normalised via the
canonicalisation pattern from #6's `Golden` harness).

Starter set (at least two):

- `preprod-tx.txt` — the full URL from the public docs example cited
  in issue #7.
- A second, shorter URL (to be collected during implementation).

Over time this corpus grows — any future wallet-format change shows
up as a golden diff here.

### D8 — `docs/protocol.md` correction is part of the same vertical commit

Per constitution §8 and the ticket #6 precedent, the commit that
lands the encoder also rewrites the "Encoding pipeline" section of
`docs/protocol.md`:

- replaces "gzip" with "LZMA alone (`.lzma`, 13-byte header)"
- replaces `/api/2/tx/` with `/api/2/run/`
- replaces the Haskell sketch's `compress` import

No docs-only PR, no "style" followup.

## Pinned dependencies

| Package       | Range           | Why                                      |
| ------------- | --------------- | ---------------------------------------- |
| `lzma`        | `>= 0.0.1 && < 0.1` | Hackage's liblzma binding            |
| `base64`      | `^>= 1.0`       | URL-safe unpadded encode / decode         |
| `bytestring`  | `>= 0.11 && < 0.13` | already a direct dep via #6        |
| `text`        | `>= 2.0 && < 2.2` | already a direct dep via #6          |
| `QuickCheck`  | `^>= 2.14` (test) | round-trip property                 |
| `tasty-quickcheck` | `^>= 0.10` (test) | wire QuickCheck into tasty      |

No new system dependencies beyond `liblzma` (already transitively
available on the dev shell and CI nixos runners via `lzma`).

## Project structure

```
src/GameChanger/
  Script.hs                (unchanged — from #6)
  Script/Types.hs          (unchanged — from #6)
  Script/Smart.hs          (unchanged — from #6)
  Encoding.hs              NEW — public surface:
                             Environment (..),
                             ResolverUrl,
                             mkResolverUrl,
                             unResolverUrl,
                             encodeScript,
                             decodeResolverUrl,
                             DecodeError (..)
  Encoding/LzmaAlone.hs    NEW — the `.lzma` header + raw-LZMA1
                             byte assembly / teardown

test/
  Arbitrary.hs             NEW — Arbitrary instances for Script etc.
  EncodingSpec.hs          NEW — round-trip + stage-by-stage
                             error-path unit tests
  fixtures/resolver-urls/  NEW — .txt + .json pairs, at least 2

docs/
  protocol.md              EDIT — replace the Encoding pipeline
                             section with the real format

haskell-gamechanger.cabal  EDIT — new module, new deps
```

## Verification plan

1. `just ci` green on every commit in the series (build + 17
   existing tests + the new round-trip + the new unit tests +
   format-check + hlint).
2. QuickCheck `prop_encodeDecodeRoundTrip` runs ≥ 1000 cases.
3. Real-world fixtures decode and match their sibling JSON.
4. SC-005: encode one of #6's golden fixtures, paste the resulting
   URL into the live wallet via Playwright MCP, confirm the wallet
   accepts it (no "Unknown decoder header"). Attach the Playwright
   trace / screenshot to the PR body.
5. `docs/protocol.md` grep-clean for `gzip` and `/api/2/tx/`.

## Risk register

- **R1** — `lzma` package may not expose the raw-LZMA1 stream state
  needed for D1. Mitigation: D1a (C shim). Budgeted: 1 extra hour.
- **R2** — The wallet may also accept `.xz`. If so, D1 simplifies to
  "call `compress` and prepend nothing." We do not rely on this; the
  spec pins the legacy format because that's what the wallet's
  public docs URL uses. Verifying the wallet's tolerance is a bonus
  diagnostic, not a substitute for matching the observed format.
- **R3** — liblzma's `lzma_alone_encoder` parameters may differ from
  what the wallet expects beyond the 13-byte header (e.g. preset
  level). The 32 MiB dictionary in the observed bytes corresponds to
  preset level 6 (default). Mitigation: start with level 6; if the
  wallet rejects, bisect the preset space.
- **R4** — Non-ASCII JSON may produce bytes that confuse the wallet's
  decoder. Mitigation: one of the fixtures will include a non-ASCII
  character to catch this early.

## Open questions

None. The plan depends on one unknown (D1 vs D1a) that can only be
resolved by touching the `lzma` package internals; the fallback is
concrete and budgeted.
