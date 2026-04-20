# Scope

This page records what `haskell-gamechanger` is and is not, and why.
The short form is a sentence:

> A backend Haskell library for integrating with the GameChanger
> wallet protocol. Not a browser library, not a WASM artifact, not
> an alternative to CIP-30.

## What this library serves

Two of the three integration topologies described in
[Integration](./integration.md):

- **§6.2 — Client + backend callback.** A Haskell backend mints a
  session token, compiles a typed `Intent` to a GameChanger script,
  encodes a resolver URL, redirects the user's browser to it, and
  receives the signed result on its own callback endpoint.
- **§6.3 — Backend-only issuer.** The same backend prints resolver
  URLs (or renders QR codes) for humans, out-of-band. The human
  signs on whatever device holds their wallet. The result comes
  back via `post`.

Both topologies share the same Haskell value proposition: the
library sits next to the code that already talks to
`cardano-node`, and drops in a way to get user signatures without
the backend ever touching keys.

## What this library does not serve

**Topology §6.1 — client-only.** A browser page that builds the
script, opens the wallet, and consumes the signed result entirely
in-browser. This is explicitly out of scope.

## Why topology 6.1 is out of scope

Three reasons, in order of weight.

### 1. The ledger does not compile to WASM

Anything that parses or validates Cardano CBOR (signed
transactions, redeemers, protocol parameters) transitively depends
on `cardano-ledger`, `cardano-api`, `plutus-core`, or
`secp256k1`. None of these compile to `wasm32-wasi` today without
deep vendoring, and even then they carry a multi-megabyte footprint
that is wrong for a browser library. This is not a solvable
toolchain problem on a near horizon.

### 2. The Haskell value concentrates on the native side

The things Haskell is genuinely the right tool for in this project
are submission via `cardano-api`, integration with existing
Haskell services (MPFS, MOOG, `cardano-node-clients`,
`cardano-wallet`), and typed transaction handling in the callback
path. None of those live in the browser.

The things a browser library actually needs — JSON building,
gzip + base64url, URL opening, optional QR generation — are
trivial in any language. A typed Haskell surface for them would be
nice but is not load-bearing.

### 3. A schema beats a shim

`GameChanger.Script`'s JSON is a stable, documented format. Any
language can produce scripts and any language can build its own
typed surface on top. Publishing a schema is more durable than
publishing a WASM artifact, and it does not pretend the ledger fits
in the browser.

## What an integrator does for topology 6.1

Writes the browser side in whatever tool fits:

- **TypeScript** — straightforward JSON building, tiny footprint.
- **PureScript** with `purescript-run` or similar — equivalent
  expressivity to the Haskell eDSL via final-tagless or
  freer-monad encodings. GADTs are not load-bearing for this
  domain.
- **Plain HTML + `window.location` assignment** — sufficient for
  many flows where the backend has already produced the URL.

## Three alternatives considered

For posterity, the three scopes weighed before settling on this
one:

### A. Backend-only (this repository)

Ship only what runs natively. Publish the JSON schema. Don't
pretend to be in the browser. Smallest scope, cleanest story,
biggest overlap with the project's actual Haskell workloads.

### B. Backend + WASM emit path only

Ship a WASM build of `Script + Intent + Encoding + QR` — no
cardano-api, no CBOR parsing in the browser. Possible, but the
toolchain cost and multi-megabyte artifact buy only a small
convenience over a JS/TS client reading the same JSON schema.

### C. Two codebases sharing a JSON schema

Haskell for 6.2 / 6.3. A separate PureScript or TypeScript library
for 6.1. Two implementations, one schema. Right answer if the
browser use case grows its own weight independently; unneeded
overhead today.

**Chosen: A.** Documented here so a future reader understands why
B and C were not picked, and can re-open the decision if the
browser case grows enough to justify (C).
