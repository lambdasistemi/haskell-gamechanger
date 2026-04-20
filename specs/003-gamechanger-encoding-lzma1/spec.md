# Feature Specification: GameChanger.Encoding — LZMA1 + base64url + resolver URL

**Feature Branch**: `003-gamechanger-encoding-lzma1`
**Created**: 2026-04-20
**Status**: Draft
**Tracks**: [#7](https://github.com/lambdasistemi/haskell-gamechanger/issues/7)
**Input**: The on-wire encoding pipeline that turns a `Script` into a
URL the live GameChanger wallet accepts. Per SC-005 on [#6 / PR #16](https://github.com/lambdasistemi/haskell-gamechanger/pull/16),
the wallet speaks **raw LZMA1 + base64url at `/api/2/run/`**, not gzip +
`/api/2/tx/` as the old `docs/protocol.md` sketch said. This ticket
replaces the sketch with the real format.

## User Scenarios & Testing

### User Story 1 — Encode a Script into a wallet URL (Priority: P1)

A caller holds a `Script` (from ticket #6) and needs the exact URL
string to hand to a browser. `encodeScript env s` returns a
`ResolverUrl` whose string form is accepted by the live wallet.

**Why this priority**: This is the single value proposition of the
module — without it, every downstream integration (CLI, QR, callback
server) is a no-op. The types from #6 are unusable against a real
wallet until this ships.

**Independent Test**: Feed a representative fixture (from #6's
`test/golden/`), encode it, paste the URL into the live wallet, and
confirm the wallet opens the script runner without a "decoder header"
or schema error. Also: decode-encode round-trip on arbitrary Scripts.

**Acceptance Scenarios**:

1. **Given** any `Script` value, **when** `encodeScript env s` is
   called, **then** it returns a `ResolverUrl` whose string form starts
   with the environment's host and path prefix (e.g.
   `https://wallet.gamechanger.finance/api/2/run/`) followed by a
   base64url-encoded raw-LZMA1-compressed serialisation.
2. **Given** a known-good URL copied from the GameChanger public docs,
   **when** `decodeResolverUrl url` is called, **then** it returns
   `Right s` where `s` decodes to the published JSON shape.
3. **Given** a URL whose compression header is not raw LZMA1, **when**
   `decodeResolverUrl url` is called, **then** it returns `Left
   BadCompressionHeader`.

---

### User Story 2 — Decode a wallet URL back to a Script (Priority: P1)

A caller holds a URL (e.g. from a callback, a pasted link, or a URL
parameter) and needs to inspect the underlying `Script`.
`decodeResolverUrl url` returns either a parsed `Script` or a typed
`DecodeError` that names the stage of failure (host/path, base64,
LZMA, JSON).

**Why this priority**: Servers receiving a wallet callback (#12) and
any diagnostic tooling (#11 CLI) need this to work. P1 because the
encoder and decoder are co-authored — you cannot confidently ship one
without the other.

**Independent Test**: Round-trip QuickCheck (≥1000 cases) —
`decode . encode = Right` for any generated `Script`. Plus unit tests
against a small set of real-world wallet URLs extracted from the
public docs.

**Acceptance Scenarios**:

1. **Given** `s :: Script`, **when** `decodeResolverUrl (encodeScript
   env s)` is called, **then** it returns `Right s`.
2. **Given** a URL with the wrong host or a path that isn't
   `/api/2/run/`, **when** `decodeResolverUrl` is called, **then** it
   returns `Left (BadResolverPrefix host path)`.
3. **Given** a URL with a valid host + path but invalid base64url,
   **when** `decodeResolverUrl` is called, **then** it returns `Left
   (BadBase64 …)`.

---

### User Story 3 — Multiple environments (mainnet / beta / preprod) (Priority: P2)

A caller needs to target different wallet deployments:
`wallet.gamechanger.finance`, `beta-wallet.gamechanger.finance`,
`beta-preprod-wallet.gamechanger.finance`. The encoder must emit the
right host and the decoder must accept URLs from any of them.

**Why this priority**: Real integrations span environments. Not P1
because the default (mainnet) is enough for the wallet smoke test;
multi-environment support is a small additional surface once the core
pipeline is right.

**Independent Test**: Table-driven unit tests — for each `Environment`
case, `encodeScript env s` produces the right host and `decodeResolverUrl`
round-trips.

**Acceptance Scenarios**:

1. **Given** `Mainnet`, **when** `encodeScript Mainnet s`, **then** the
   URL host is `wallet.gamechanger.finance`.
2. **Given** `BetaPreprod`, **when** `encodeScript BetaPreprod s`,
   **then** the URL host is `beta-preprod-wallet.gamechanger.finance`.
3. **Given** any environment's URL, **when** `decodeResolverUrl url`
   is called, **then** it returns `Right s`.

---

### User Story 4 — `docs/protocol.md` matches the wire (Priority: P2)

A contributor reading `docs/protocol.md` sees the real encoding
(LZMA1, `/api/2/run/`), not the outdated gzip / `/api/2/tx/` sketch.

**Why this priority**: Constitution §8 makes the JSON boundary
load-bearing and docs part of the vertical commit. A docs-only PR
would violate that principle; the docs update travels with the code
that implements the format.

**Independent Test**: Grep the committed `docs/protocol.md` for
`gzip` and `/api/2/tx/` — should find none as current-format
descriptions. The Haskell sketch block should use LZMA.

**Acceptance Scenarios**:

1. **Given** the merged PR, **when** `docs/protocol.md` is read,
   **then** the "Encoding pipeline" section describes raw LZMA1 and
   the path is `/api/2/run/`.
2. **Given** the merged PR, **when** the Haskell sketch is read,
   **then** it calls an LZMA1 encoder (not `Codec.Compression.GZip`).

---

### Edge Cases

- **Empty Script** — a `Script` with empty `run` and `exports` maps
  must still round-trip.
- **Large Script** — a Script above the URL length threshold; per
  `docs/protocol.md` the inline form is the only target (hosted
  scripts are a future concern). For this ticket, over-threshold URLs
  encode normally but emit no warning; the caller's responsibility to
  keep scripts small.
- **Non-ASCII strings** — a `title` or `description` containing UTF-8
  codepoints must round-trip. Aeson emits UTF-8 JSON bytes; LZMA is
  byte-level; base64url is ASCII-only.
- **Padding on input** — incoming base64url MAY be padded with `=`;
  decoder must accept both padded and unpadded forms.
- **URL-safe alphabet variants** — decoder MUST use the URL-safe
  alphabet (`-`, `_`). Inputs using standard base64 (`+`, `/`) are
  rejected with `BadBase64`.
- **Corrupt compressed payload** — garbage bytes after a valid LZMA1
  header are rejected with `BadCompression` (stage name carries the
  LZMA decoder's error).
- **JSON shape mismatch** — a well-formed LZMA1 payload that decodes
  to bytes that aren't a valid `Script` returns `Left BadJson` with
  the Aeson parse error.

## Requirements

### Functional Requirements

- **FR-001**: `encodeScript :: Environment -> Script -> ResolverUrl`
  MUST produce a URL whose prefix is the environment's host +
  `/api/2/run/`, followed by a base64url-encoded (URL-safe, unpadded)
  raw-LZMA1-compressed Aeson-encoded JSON payload.
- **FR-002**: `decodeResolverUrl :: ResolverUrl -> Either DecodeError
  Script` MUST reject URLs that don't match the expected prefix with
  `BadResolverPrefix`.
- **FR-003**: The raw LZMA1 parameters MUST match what the wallet
  emits byte-for-byte for small payloads: properties byte `0x5D`
  (default `lc=3, lp=0, pb=2`), dictionary size `0x02000000` (32 KB,
  little-endian), no uncompressed-size field (i.e. the LZMA1 "stream
  end" marker is used).
- **FR-004**: The `Environment` type MUST cover at minimum `Mainnet`
  (`wallet.gamechanger.finance`), `BetaMainnet`
  (`beta-wallet.gamechanger.finance`), and `BetaPreprod`
  (`beta-preprod-wallet.gamechanger.finance`). Additional environments
  MAY be added later without breaking API.
- **FR-005**: `DecodeError` MUST be a typed sum with one constructor
  per failure stage: `BadResolverPrefix`, `BadBase64`,
  `BadCompression`, `BadJson`. Each constructor MUST carry enough
  information for a useful error message.
- **FR-006**: `ResolverUrl` MUST be a newtype around `Text` with a
  smart constructor that enforces the prefix invariant; the raw
  constructor MUST NOT be exported.
- **FR-007**: Encoder and decoder MUST be inverse on any `Script`
  value: `decodeResolverUrl . encodeScript env ≡ Right`. Verified by
  a QuickCheck property running at least 1000 cases.
- **FR-008**: The decoder MUST accept base64url with or without
  padding. The encoder MUST emit unpadded base64url.
- **FR-009**: The decoder MUST NOT fall back to gzip. Inputs whose
  decompression header is not raw LZMA1 MUST be rejected with
  `BadCompression`.
- **FR-010**: `docs/protocol.md` MUST describe the real format (LZMA1,
  `/api/2/run/`) in the same commit that introduces the encoder —
  docs and protocol travel together (constitution §8).
- **FR-011**: Module MUST NOT introduce a `cardano-api` /
  `cardano-ledger` / `plutus-core` dependency (constitution §1,
  inherited from #6).
- **FR-012**: The `Script` type surfaced through `encode` / `decode`
  MUST be `GameChanger.Script.Script` (no new record); this ticket
  owns only the byte-level pipeline on top of #6.

### Key Entities

- **`Environment`** — closed sum naming a wallet deployment; used to
  pick the host.
- **`ResolverUrl`** — newtype around `Text`, constructed only through
  `encodeScript` or a smart constructor that validates the prefix;
  exposes `unResolverUrl :: ResolverUrl -> Text`.
- **`DecodeError`** — typed sum naming the failing stage of the
  decoding pipeline.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Round-trip QuickCheck property passes with ≥ 1000 cases,
  covering all five `ActionKind`s and all five `Channel` modes (via
  #6's `Arbitrary Script` instance introduced in this ticket if not
  already present).
- **SC-002**: At least two real-world wallet URLs copied verbatim
  from the GameChanger public docs decode to the expected `Script`.
- **SC-003**: A representative `Script` (one of #6's golden fixtures)
  is encoded into a URL, pasted into the live wallet, and the wallet
  accepts the URL without a "decoder header" error — captured as a
  note / screenshot / Playwright run in the PR body.
- **SC-004**: `docs/protocol.md` contains no remaining references to
  gzip or `/api/2/tx/` as current-format descriptions (grep-clean).
- **SC-005**: `just ci` green (build + tests + format-check + hlint)
  on every commit in the series.

## Assumptions

- **A1** — The raw LZMA1 format is the format the wallet's
  `lzma-native.js` or `lzma-js` frontend library accepts. If the
  wallet migrates to xz or a newer variant, this ticket's encoder
  will need to follow; that's a future concern.
- **A2** — A pure Haskell LZMA1 implementation exists on Hackage
  (e.g. `lzma` package with appropriate parameter knobs) or can be
  built via a C binding. Investigation in the plan phase.
- **A3** — The two known-good URLs used as fixtures are the current
  format. If the wallet's preprod example in the docs is updated,
  the fixtures must be refreshed.
- **A4** — Environments are identified by host only; no other
  per-environment parameter is required at this layer. Network
  selection (mainnet vs preprod at the Cardano level) is carried
  inside the Script, not in the URL.

## Dependencies

- **D1** — `GameChanger.Script` (from #6) is the domain type.
- **D2** — An LZMA1 Haskell package (TBD in plan phase).
- **D3** — `base64` (or `base64-bytestring`) with URL-safe alphabet
  support.
