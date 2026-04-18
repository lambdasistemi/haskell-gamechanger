# haskell-gamechanger Constitution

**Version:** 0.1.0 · **Ratified:** 2026-04-18 · **Status:** Understanding phase

This project's current purpose is **to understand the GameChanger
wallet protocol thoroughly before writing any Haskell code against it**.
This constitution is therefore not (yet) a set of implementation rules.
It is a reference model of GameChanger — its script DSL, its URL
encoding, its export modes, its integration topologies, and its
security boundaries — written down so that any later Haskell library,
CLI, or service in this repository rests on a shared, audited
understanding.

The constitution is the authoritative prose artifact. The
[`docs/`](../../docs/) MkDocs site and [`data/rdf/`](../../data/rdf/)
ontology restate the same content in browsable and machine-readable
forms; if they diverge, **this document is the source of truth** and
the others are regenerated or reconciled.

---

## 1. What GameChanger Is

**GameChanger** is a browser-based Cardano wallet that exposes an
open, URL-driven signing protocol. Unlike CIP-30 browser injection,
GameChanger is driven by **script descriptors** — JSON documents that
declaratively describe an intent (build a transaction, sign a message,
collect a witness, run a multi-step flow) and specify how the result
must be returned.

The protocol has four invariants:

1. **The wallet is the sole key-holder.** No external process — CLI,
   backend, or library — ever sees private keys. All signing happens
   inside the wallet's browser context.
2. **Scripts are data, not code.** They are JSON documents with a
   bounded schema. They cannot execute arbitrary code; the wallet
   interprets them against a fixed action set.
3. **Results are exported, not returned.** The wallet does not
   "respond" in a request/response sense. It executes the script and
   then performs one or more **exports** (redirect, POST, download,
   QR, clipboard). Any party observing the result must be on the
   receiving end of at least one export.
4. **The signing hop crosses a trust boundary.** The party building
   the script and the party observing the signed result are usually
   not the same process. The protocol's security rests on correctly
   authenticating that boundary.

## 2. Protocol Terms

- **Script**: JSON document describing the intent. Top-level fields
  include `type`, `title`, `description`, `exports`, `run`.
- **Run block**: Ordered map of named actions to execute inside the
  wallet (e.g. `buildTx`, `signTx`, `submitTx`, `getUTxOs`).
- **Action**: A single named operation with typed inputs/outputs.
  Actions reference each other through `{get}` template expressions.
- **Export**: A clause declaring how a result leaves the wallet.
  Exports name the source (a run-block output) and the destination.
- **Resolver URL**: The `https://gamechanger.finance/resolver/...`
  (or `https://beta-wallet.gamechanger.finance/api/2/tx/...`)
  endpoint the user opens to hand the script to the wallet.
- **Session**: An issuer-minted correlation identifier that ties a
  specific resolver URL to a specific expected export destination.
  Not part of the wallet protocol itself — a discipline the
  integrator must impose.

## 3. Script DSL (Shape)

A script is a JSON object. The minimum viable shape is:

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
      "detail": { "address": "...", "message": "hello" }
    }
  }
}
```

Notes:

- **`run`** values have a `type` (the action name) and a `detail`
  payload specific to the action. A `namespace` determines where the
  action result is stored for later reference.
- **`{get('cache.signResult')}`** is a template expression: the export
  pulls the cached output of the `signResult` action by name.
- **`exports`** is a map from an export-name to a descriptor.
  Export-names are display-only; the descriptor's `source` (value) and
  mode (where it is sent) drive behavior.

This project intentionally does not attempt to reproduce the entire
DSL here. It captures the **shape and invariants**; the authoritative
DSL lives at [docs.gamechanger.finance](https://docs.gamechanger.finance)
(external — see §10 links).

## 4. Encoding Pipeline

The script does not travel on the wire as plain JSON. It is compressed
and encoded into a resolver URL:

```
JSON → gzip → base64url → https://.../resolver/<encoded>
```

Key properties:

- **gzip** (not zlib raw) — with standard headers. Decodes in any
  language that has gzip.
- **base64url** — `+` → `-`, `/` → `_`, `=` padding typically
  stripped. URL-safe.
- **Length matters.** Beyond a size threshold, scripts must be hosted
  (the URL references a hash or ID, not the full script). For this
  phase we only model the inline form.

## 5. Export Modes

Every script ships with at least one export. Exports define the
*result channel* — how and where the wallet delivers its output.

| Mode | Where the result goes | Who receives it | Trust model |
|---|---|---|---|
| **return** | Appended to a redirect URL as a query/fragment param | Whoever owns that URL (usually the browser page that opened the wallet) | Integrity depends on the URL and the receiving page |
| **post** | Browser-side `fetch` POST to a URL | A backend HTTP endpoint | Integrity must be enforced by the backend (auth, session binding) |
| **download** | Browser download of a file | The human operator | Manual; integrity depends on what humans do with the file |
| **qr** | Displayed as a QR code | A second device (phone camera) | Out-of-band; good for airgapped flows |
| **copy** | Placed on the clipboard | The human operator | Manual; subject to clipboard hijack |

Implication: **for any backend integration, the script must declare a
`post` export** (or a `return` export to a page that forwards). There
is no other path by which a non-browser process observes the signature.

## 6. Integration Topologies

Three canonical topologies for this project:

### 6.1 Client-only

A single browser page builds the script, opens the resolver URL,
receives the result via `return` export in its own URL, uses it
locally. No backend involvement.

### 6.2 Client + backend callback

A backend issues the resolver URL (with a `post` export pointing at a
backend endpoint) and waits for the wallet to POST the signed result.
Sessions are tracked server-side. This is the topology the Haskell
library primarily targets.

### 6.3 Backend-only issuer

A backend builds scripts and prints resolver URLs (or renders QRs) for
humans. Results come back via `post` or via humans pasting returned
values. The Haskell library supports this by separating script
construction, URL encoding, and callback parsing into distinct,
composable layers.

## 7. Security Model (Discovery)

This section is the result of threat-modeling the protocol itself. It
is **not** a security audit of GameChanger, nor of any code in this
repository (there is none yet).

### 7.1 In-scope trust boundary

- Between the **script issuer** (backend) and the **wallet** —
  crosses the browser + user's machine. The script travels openly in
  a URL.
- Between the **wallet** and the **export destination** — the result
  channel.

### 7.2 Attack surface

| Attack | Surface | Mitigation direction |
|---|---|---|
| Callback spoofing | An attacker POSTs a forged "signed" result to the backend's callback endpoint | Bind each resolver URL to a server-issued session token; require that token in the callback; validate CBOR signatures cryptographically before accepting |
| Resolver URL tampering | An attacker modifies the encoded script in the URL before the user opens it | The user sees the wallet's human-readable confirmation; plus, the backend should only ever submit a CBOR that corresponds to *its own intent*, not whatever CBOR comes back |
| Replay of a signed tx | A signed CBOR is captured and resubmitted | TTLs on session tokens; check on-chain presence before resubmitting |
| Malicious script injected by a page | A compromised front-end crafts a script that drains the user instead of the intended operation | User always confirms in the wallet UI; design issuance so the backend is the sole script author for sensitive flows |
| Phishing via crafted resolver URLs | A lookalike URL tricks the user into signing something unintended | Out-of-band verification; users should verify the wallet's transaction preview |
| Session hijack | An attacker who obtains a session token can race the legitimate user to the callback | Single-use session tokens; bind to additional request context (IP, User-Agent) where possible; short TTLs |
| CBOR injection | A callback receives malformed CBOR that crashes or misleads the backend | Strict CBOR validation and typed parsing before any use |

### 7.3 Publicly known audits of GameChanger itself

**Searching is a task for the docs phase.** We do not assert the
presence or absence of a published audit here; the `docs/security.md`
page is the authoritative record of what we found (including negative
results — "no public audit found as of 2026-04-18" is valid content).

## 8. What This Repository Will Ship (Eventually)

The eventual scope of a Haskell implementation rests on this
constitution:

- A **pure Haskell model** of the script DSL (Aeson records), the
  encoding pipeline, the export descriptors, and the callback
  payload shape.
- A **URL builder** that takes a typed script and returns a resolver
  URL, plus a **QR renderer** for out-of-band delivery.
- A **callback receiver** (servant or warp) for the `post` export
  that validates sessions, parses CBOR, and hands signed transactions
  to an existing cardano-api / node-clients submission path.
- A **small CLI** that wraps both — useful for manual preprod
  testing and as an integration smoke-test.

Explicitly out of scope:

- Signing in Haskell. (Cannot be done; the wallet holds keys.)
- WASM compilation of this library. (Not needed for a backend-driven
  integration; revisit only if an in-browser use case emerges.)
- Reimplementing any part of the wallet.

## 9. How To Use This Repository (Today)

1. Read the docs site at `https://lambdasistemi.github.io/haskell-gamechanger/`.
2. Open the graph view:
   `https://lambdasistemi.github.io/graph-browser/?repo=lambdasistemi/haskell-gamechanger`
   — a visual representation of the same concepts described here.
3. Read [`docs/security.md`](../../docs/security.md) before integrating.
4. File issues for anything that is unclear, wrong, or under-specified.

Once the constitution and docs stabilize, speckit specs for individual
features (script DSL codec, URL encoder, callback handler, CLI) will
follow the standard workflow:
`/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement`.

## 10. References

- GameChanger site: <https://gamechanger.finance/>
- Beta wallet (web): <https://beta-wallet.gamechanger.finance/>
- Official docs (external): <https://docs.gamechanger.finance/>
- Graph-browser (for the ontology view): <https://github.com/lambdasistemi/graph-browser>
- This repository: <https://github.com/lambdasistemi/haskell-gamechanger>

---

**Governance:** Amendments to this constitution require a PR that
updates (a) this document, (b) the `docs/` site, and (c) the
`data/rdf/` ontology together in one vertical commit. All three are
derivative of the same understanding and must move in lockstep.

**Version:** 0.1.0 | **Ratified:** 2026-04-18 | **Last Amended:** 2026-04-18
