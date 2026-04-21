# Feature Specification: Haskell Client CLI UX — returnURLPattern + localhost callback

**Feature Branch**: `007-haskell-client-cli`
**Created**: 2026-04-21
**Status**: Draft
**Input**: Issue #25 — A Haskell developer wants to sit at their
keyboard, run `cabal run gc-sign-message -- --address <addr> --message
<msg>`, approve a signature in their browser, and have the signed
payload arrive back in their terminal. The library must provide the
canonical building blocks for this flow and the E2E test must prove
it works against the real upstream wallet on preprod.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Haskell dev signs a message from the terminal (Priority: P1)

A Haskell developer on their laptop runs an executable shipped with
this library. The tool prints a resolver URL (and optionally a
terminal QR), the developer opens the URL in their browser, the
GameChanger wallet loads, the developer approves the `signData`
action, the wallet redirects to `http://localhost:<port>/callback`,
a one-shot HTTP server running inside the executable captures the
`{result}` substitution, and the signed payload is printed to
stdout. The whole flow is same-laptop, no tunnel, no public endpoint.

**Why this priority**: This is the canonical first-touch experience
for a Haskell developer. It is also the only flow that keeps the
library honest: `returnURLPattern` is the *actual* upstream delivery
mechanism, so building around it forces the library to expose the
real primitive instead of the fabricated `Post`/`Download`/`QR`/`Copy`
`Channel` constructors currently in `GameChanger.Script`.

**Independent Test**: A developer with the library installed and
the GameChanger beta wallet in their browser can run
`cabal run gc-sign-message -- --address addr_test1... --message "hello"`
and get a CIP-8 signature printed to stdout, with no other setup.

**Acceptance Scenarios**:

1. **Given** a Haskell developer with GameChanger beta wallet
   available in their browser and the dev shell entered, **When**
   they run `cabal run gc-sign-message -- --address <addr> --message <msg>`,
   **Then** the tool prints a resolver URL, waits, the developer
   approves the action in their browser, and the tool prints a
   CIP-8 signature to stdout and exits 0.
2. **Given** the tool is waiting for a callback, **When** the
   developer cancels the browser flow or closes the tab, **Then**
   the tool times out with a clear error message and exits non-zero.
3. **Given** the tool fails to bind to a local port, **When** the
   developer runs the tool, **Then** the tool reports the bind
   failure and exits non-zero without emitting a resolver URL.

---

### User Story 2 — Library consumer wires the same flow into their own app (Priority: P1)

An application developer depending on `haskell-gamechanger` wants
to request a signature from their own code. They call a single
blocking library function `signMessage :: Environment -> Address -> Text -> IO Signature`,
display the returned resolver URL to the user in whatever way their
application prefers, and receive the signature when the call
returns. The library owns the localhost callback server, the
URL encoding, and the parsing of the wallet's redirect.

**Why this priority**: The executable in US1 is a thin shell over
library primitives. Those primitives must be independently usable
so any backend integration (not just our CLI) can drive the same
flow.

**Independent Test**: A second executable in the repo — the E2E
driver — imports `signMessage` from the library, calls it, and
asserts the returned signature is a valid CIP-8 COSE Sign1
structure. No shell parsing, no stdout scraping.

**Acceptance Scenarios**:

1. **Given** a running server app, **When** `signMessage` is
   called, **Then** it emits the resolver URL via the
   user-provided display callback, blocks until the wallet
   redirects, and returns the decoded signature.
2. **Given** `signMessage` is called twice concurrently, **When**
   both calls race, **Then** each gets its own callback server on
   its own port and neither sees the other's result.

---

### User Story 3 — E2E test proves the flow works against the real wallet (Priority: P1)

A CI pipeline checks out the repo, enters the nix dev shell, starts
a headless browser with Playwright, loads the resolver URL produced
by the library, uses a preprod seed (delivered via secret) to unlock
a fresh GameChanger wallet in the browser, approves the `signData`
prompt, and asserts the signature returned to the library is
well-formed. The whole run must complete on every PR.

**Why this priority**: Without an E2E test that actually runs the
upstream wallet, everything written in docs is speculation. The
user explicitly rejected exempting this as "out of scope" during
design — preprod + `signData` + a headless browser is feasible and
the E2E is the arbiter of whether the library's model of the
protocol matches the upstream reality.

**Independent Test**: Run the Playwright-driven test locally with
the seed secret provided; it should produce a signature that
round-trips through CIP-8 COSE Sign1 decoders.

**Acceptance Scenarios**:

1. **Given** the preprod seed secret is available, **When** the
   E2E test runs, **Then** it exits 0 with a valid signature
   captured.
2. **Given** the upstream beta wallet DOM changes in a
   non-breaking way, **When** the test runs, **Then** the test
   authors investigate whether the change affects the flow
   before marking the test as flaky. Flakiness must be proven,
   not presumed.

---

### User Story 4 — Tutorial reflects the real flow (Priority: P2)

A developer reading `docs/tutorial.md` gets walked through the
executable first, then shown the library API that underlies it,
then shown the decode/round-trip primitives. The tutorial uses
`returnURLPattern` exclusively; the fabricated `Post`/`Download`/
`QR`/`Copy` channels are not shown.

**Why this priority**: The current tutorial was written against
the legacy `Channel` type before research established that those
constructors are not upstream-supported. Leaving it in place
teaches the wrong mental model and guarantees integration
failures.

**Independent Test**: `mkdocs build --strict` is green and the
tutorial's code blocks compile as part of the library's doctest
or example harness.

**Acceptance Scenarios**:

1. **Given** the tutorial, **When** a developer copies the
   `signMessage` example and pastes it into a fresh project,
   **Then** it compiles and behaves identically to the executable.

---

### User Story 5 — Optional terminal QR for convenience (Priority: P3)

A Haskell developer can pass `--qr` to the executable to have
the resolver URL also rendered as a block-Unicode QR code in the
terminal. This is a convenience feature for developers who prefer
to scan rather than paste, *within the same-laptop flow* (the QR
encodes the same URL the terminal prints; it is not a phone-scan
channel — that is #26 and blocked on this work).

**Why this priority**: Nice-to-have. The core flow (paste URL in
browser) already works without it. Worth shipping in the same PR
only if it stays minimal (<100 LoC, pure Haskell, no external
binary).

**Independent Test**: `gc-sign-message --qr --print-url-only` (or
similar dry-run flag) emits a QR code for a known URL; snapshot
test against a golden file.

**Acceptance Scenarios**:

1. **Given** `--qr`, **When** the executable prints the URL,
   **Then** a block-Unicode QR of the same URL is printed above
   or below it.

---

### Edge Cases

- **Port already in use**: the callback server fails to bind.
  Report clearly, exit non-zero, do not emit a URL pointing at a
  port the library does not own.
- **Wallet never redirects**: the user closes the tab or denies
  the prompt. The CLI must enforce a timeout (default: 5 min)
  and exit with a clear message.
- **Wallet redirects with an error payload**: `{result}` may be
  an error object rather than a signature. Decode attempts must
  distinguish "malformed" from "wallet reported error" and surface
  both as non-zero exits with distinct error messages.
- **Multiple concurrent invocations**: each call gets its own
  ephemeral port; port 0 + OS assignment.
- **User runs on a headless server**: `http://localhost` is
  meaningless over SSH unless the user has set up port forwarding.
  The CLI must document this; the flow remains correct because the
  resolver URL and the callback URL both reference localhost — if
  the user forwards the port and opens the printed URL from their
  laptop's browser, it works.
- **Wallet does not accept `http://` in `returnURLPattern`**:
  research assumed it does; this is an open question that blocks
  US1. If the wallet rejects plain http localhost URLs we need a
  different mechanism (e.g. copy/paste the result from the wallet
  back into the terminal).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST provide a `GameChanger.Callback`
  module exposing `withCallbackServer :: (Url -> IO a) -> IO (a, Result)`
  (or equivalent shape) that binds an ephemeral localhost port,
  runs a one-shot handler, and returns both the user action
  result and the captured `{result}` payload.
- **FR-002**: The library MUST provide a blocking
  `signMessage :: Environment -> Address -> Text -> IO Signature`
  that wires a `signData` script, encodes it as a resolver URL
  targeted at the callback, runs the callback server, and
  decodes the returned payload.
- **FR-003**: The library MUST deprecate (with a `{-# DEPRECATED #-}`
  pragma) the `Post`, `Download`, `QR`, and `Copy` constructors of
  `GameChanger.Script.Channel` on grounds that upstream has no such
  export modes. `Return` remains and is the one true channel.
- **FR-004**: The repo MUST ship an executable `gc-sign-message`
  whose CLI is `--address <addr> --message <msg> [--env mainnet|beta-mainnet|beta-preprod] [--qr] [--timeout <sec>]`.
- **FR-005**: `gc-sign-message` MUST print a resolver URL to
  stdout, wait for the callback, then print the signature as the
  last line of stdout and exit 0. Errors MUST go to stderr and
  exit non-zero.
- **FR-006**: The E2E test MUST drive a real GameChanger beta
  wallet via Playwright on the `nixos` self-hosted runner, load
  a preprod seed from a CI-injected secret, approve the `signData`
  prompt, and assert the returned signature is a well-formed
  CIP-8 COSE Sign1. [NEEDS CLARIFICATION Q1: how is the seed
  delivered to CI — GitHub Actions secret containing the
  mnemonic? Something else?]
- **FR-007**: The E2E test MUST run on every PR. It MAY be
  demoted to nightly-only *after* it has been shown to be flaky
  with evidence (at least N consecutive false-positive failures
  with no code change), never pre-emptively.
- **FR-008**: `docs/tutorial.md` MUST be rewritten to drive the
  `signMessage` / `gc-sign-message` flow as the first example
  and MUST NOT reference the deprecated `Channel` constructors.

### Non-Functional Requirements

- **NFR-001**: The callback server uses port 0 (OS-assigned
  ephemeral port). No static port.
- **NFR-002**: The library has no new runtime dependencies on
  anything outside the existing `haskell-gamechanger` + `warp` +
  `wai` + `qrcode-core` set. QR rendering must be pure Haskell.
- **NFR-003**: `just ci` on the `nixos` runner builds, tests,
  lints, and runs the E2E in under 10 min for a warm cache.
- **NFR-004**: The executable's first output (the resolver URL)
  appears within 500ms of invocation.

### Out of Scope

- **Phone-scan flow** (scanning a QR with a phone and receiving
  the callback on a public endpoint). Tracked as issue #26,
  blocked on this work.
- **`buildTx` / `signTx` / `submitTx` CLI**. This PR ships only
  `signData`. Transaction flows come later and will reuse the
  same callback primitives.
- **Browser / WASM target**. Out of scope per the library's
  standing scope doc.
- **Full retirement of `GameChanger.Script.Channel`**. This PR
  deprecates the fabricated constructors but does not remove
  them; removal is a follow-up ticket. [NEEDS CLARIFICATION Q4:
  do we keep `Channel` as a newtype over `Return` only, or do
  we hoist `returnURLPattern` to a top-level `Script` field?]

### Key Entities

- **Environment** — existing: `Mainnet | BetaMainnet | BetaPreprod`.
- **Address** — bech32-encoded Cardano address (payment or stake).
- **Signature** — CIP-8 COSE Sign1 bytes + associated public key;
  exact Haskell type to be chosen in the plan phase.
- **CallbackResult** — the raw `{result}` payload captured from
  the wallet's redirect; either a signature blob or an error
  object.

## Success Criteria *(mandatory)*

- **SC-001**: A developer new to the library can go from
  `git clone` to a successful signature on their laptop in under
  5 minutes, following the tutorial.
- **SC-002**: The E2E test passes on `nixos` self-hosted CI for
  20 consecutive PR runs without a flake retry.
- **SC-003**: `mkdocs build --strict` is green after the tutorial
  rewrite, with all code blocks compiling in a doctest harness.
- **SC-004**: Zero references to the deprecated `Post`/`Download`/
  `QR`/`Copy` channel constructors remain in `src/`, `docs/`, and
  `test/` after this PR lands.

## Assumptions

- **A1**: The GameChanger beta wallet accepts `http://localhost:<port>`
  URLs in `returnURLPattern`. [NEEDS CLARIFICATION Q2: confirm by
  experiment before implementation starts.]
- **A2**: Playwright runs on the `nixos` self-hosted runner with
  chromium in the nix store and no network-gated driver download.
  [NEEDS CLARIFICATION Q3: verify via minimal smoke workflow on
  the runner.]
- **A3**: The preprod seed lives at `/code/moog/tmp/requester.json`
  and can be adapted into whatever CI secret form Q1 decides on.
- **A4**: `signData` requires no funds; the preprod address
  derived from the seed does not need to be funded for this
  feature. Address derivation for `buildTx` flows is deferred to
  later tickets.

## Open Questions

- **Q1 (blocks FR-006)**: seed delivery mechanism from local dev
  to GitHub Actions. Default assumption: a `PREPROD_SEED_MNEMONIC`
  repo secret containing the 12-word mnemonic.
- **Q2 (blocks US1, FR-002, A1)**: does the wallet accept plain
  `http://localhost` in `returnURLPattern`? Must be confirmed by
  manual experiment before the plan phase finalises the callback
  module shape.
- **Q3 (blocks FR-007, A2)**: Playwright+chromium on `nixos`
  self-hosted runners — does it work without manual driver
  installation? If not, the plan must include a cached driver
  derivation.
- **Q4 (blocks FR-003, FR-008)**: scope of `Channel` cleanup.
  Deprecate fabricated constructors only (this PR) vs full
  redesign of the `Script`/`Export`/`Channel` records (follow-up
  ticket). Default: deprecation + `-Werror=deprecations` off for
  this PR only.
