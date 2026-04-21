# haskell-gamechanger

A Haskell client for the [GameChanger](https://gamechanger.finance/)
Cardano wallet.

!!! info "Status: Understanding phase"
    The repository currently carries no Haskell implementation. Its
    first output is a clear, machine-readable model of the GameChanger
    protocol: this documentation site, a companion
    [RDF ontology](./ontology.md), and a
    [security analysis](./security.md). Implementation follows once the
    model is stable.

## What is GameChanger?

GameChanger is a **browser-based Cardano wallet** driven by an open,
URL-encoded signing protocol. Instead of a CIP-30 JavaScript injection
into a dapp page, GameChanger consumes a JSON **script descriptor**
that declares what to do (build a transaction, sign a message, run a
multi-step flow) and how to return the result. The protocol is
deliberately asynchronous: the wallet does not "respond" in a
request/response sense; it executes the script and then *exports* the
result via one of several named channels.

This makes GameChanger an unusually clean fit for backend
integrations: any party able to build JSON and receive HTTP POSTs can
drive signing flows without running a browser.

## Why a Haskell client?

Because the Haskell side of this repository's ecosystem
(cardano-wallet, cardano-api, node-clients, MPFS, MOOG) routinely
needs to produce transactions that are signed by real end-users
holding real keys, and GameChanger is a pragmatic way to request
signatures from those users without forcing them through a desktop
wallet install or a bespoke UI.

What Haskell can do:

- Build GameChanger scripts as typed records, serialize to JSON.
- Encode scripts into resolver URLs (gzip + base64url).
- Render URLs as QR codes for out-of-band delivery.
- Receive `post` export callbacks, validate CBOR, submit
  transactions through existing node-clients paths.

What Haskell cannot do:

- **Sign.** Keys live in the wallet. Signing requires the user's
  browser. This is a protocol invariant, not a Haskell limitation —
  the same constraint applies to every external-wallet integration.

## Where to start

- **Wondering what this library is?** Read [Scope](./scope.md) — a
  short page on what this library does, what it does not, and why
  topology 6.1 (client-only) is out of scope.
- **Ready to use the library?** Read [Tutorial](./tutorial.md) — an
  end-to-end walk from building a script to delivering a resolver URL
  and receiving the wallet's response.
- **New to GameChanger?** Read [Protocol](./protocol.md) — it covers
  the script DSL, the encoding pipeline, and export modes.
- **Planning to integrate?** Read [Integration](./integration.md) —
  three canonical topologies with trade-offs.
- **Responsible for a deployment?** Read
  [Security](./security.md) — threat model, attack surface, and known
  published audits.
- **Designing the Haskell API?** Read
  [Intent eDSL](./intent-dsl.md) — the monadic surface that compiles
  to GameChanger scripts, native backend only.
- **Working with the low-level AST?** Read
  [GCScript AST](./gcscript.md) — the JSON-faithful Haskell mirror
  of the wallet DSL, with a five-minute decode/encode tutorial.
- **Browsing visually?** Open the
  [graph view](https://lambdasistemi.github.io/graph-browser/?repo=lambdasistemi/haskell-gamechanger)
  — the same concepts as a node-link diagram, backed by a
  [Turtle ontology](./ontology.md).

## Links

- [Constitution](https://github.com/lambdasistemi/haskell-gamechanger/blob/main/.specify/memory/constitution.md) — authoritative source for this documentation
- [Repository](https://github.com/lambdasistemi/haskell-gamechanger)
- [GameChanger official docs](https://docs.gamechanger.finance/)
- [GameChanger beta wallet](https://beta-wallet.gamechanger.finance/)
