# Feature Specification: GameChanger.Script types + Aeson codec + golden tests

**Feature Branch**: `002-script-types`
**Created**: 2026-04-20
**Status**: Draft
**Ticket**: [#6](https://github.com/lambdasistemi/haskell-gamechanger/issues/6)
**Input**: Typed Haskell records for the GameChanger JSON script protocol with Aeson codec and golden round-trip tests.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A downstream ticket can build a script value in Haskell and round-trip it through JSON (Priority: P1) 🎯 MVP

A future contributor lands ticket #9 (Intent → Script compiler) and needs a typed value of the Script protocol to produce from their compiler. They import `GameChanger.Script`, construct a `Script` record, encode it to JSON via `Aeson.encode`, and feed that JSON straight into the encoding pipeline (gzip + base64url, ticket #7). Decoding the same JSON back yields a structurally equal `Script` value.

**Why this priority**: Every downstream ticket (#7, #9, #10, #11, #12) consumes `GameChanger.Script`. Nothing else can proceed until this type exists and round-trips cleanly. This ticket is on the critical path to a runnable `hgc`.

**Independent Test**: Clone the branch, enter `nix develop`, open `ghci`, build a `Script` value with smart constructors, `Aeson.encode` it, `Aeson.eitherDecode` it back, assert equal.

**Acceptance Scenarios**:

1. **Given** a Haskell value built via the smart constructor `signDataAction "cache" "addr_..." "hello"`, **When** the enclosing `Script` is Aeson-encoded and Aeson-decoded, **Then** the decoded value equals the original.
2. **Given** any `Script` value in the library, **When** it is Aeson-encoded, **Then** the JSON object contains `{"type":"script", ...}` and only the documented field names (`title`, `description`, `run`, `exports`, `metadata` when present).
3. **Given** a `Script` with at least one export in each of the five channel modes (`return`, `post`, `download`, `qr`, `copy`), **When** encoded and decoded, **Then** round-trip equality holds.

---

### User Story 2 - Published example scripts decode and re-encode byte-equal (Priority: P1) 🎯 MVP

The GameChanger documentation publishes a handful of canonical example scripts. A future protocol reader needs confidence that `GameChanger.Script` parses every one of them without loss. We check in a small set of these as golden fixtures under `test/golden/`, and the test suite asserts: decode to `Script`, re-encode to JSON, compare byte-for-byte (modulo whitespace normalisation) against the fixture.

**Why this priority**: The `Script` type is the published JSON boundary (constitution §8). If the decoder silently drops a field, or the encoder emits a shape the wallet rejects, every downstream ticket ships a broken integration. The golden set is the authoritative cross-check.

**Independent Test**: `just test` is green. Each fixture lives at `test/golden/<name>.json` and has a matching test case. Adding a fixture + a one-line entry in `Spec.hs` is enough to extend coverage.

**Acceptance Scenarios**:

1. **Given** the fixture `test/golden/sign-data.json` from the published docs, **When** the test runs `Aeson.eitherDecode` then `Aeson.encode`, **Then** the canonicalised output equals the canonicalised input.
2. **Given** a fixture that exercises every action kind (`buildTx`, `signTx`, `signData`, `submitTx`, `getUTxOs`) and every export channel mode, **When** decoded, **Then** no fields are dropped and every constructor round-trips.

---

### User Story 3 - Smart constructors give a type-safe action surface (Priority: P2)

The downstream Intent compiler (#9) does not build `Run` entries by hand-crafting JSON keys; it calls smart constructors exported from `GameChanger.Script` — one per action kind. Each constructor takes the action's required inputs as typed parameters and produces a `Run` fragment or `Script.Action` value.

**Why this priority**: This is what distinguishes a typed library from a `Value` alias. Without smart constructors the downstream compiler re-invents the JSON shape and the type system does not help. P2 because the record type alone is enough for MVP round-trip; smart constructors are the ergonomic layer that makes the library pleasant to use.

**Independent Test**: `hgc` REPL can `Script.signDataAction "cache" "addr_..." "msg" :: Script.Action` and it type-checks.

**Acceptance Scenarios**:

1. **Given** the five action kinds (`buildTx`, `signTx`, `signData`, `submitTx`, `getUTxOs`), **When** a contributor looks at `GameChanger.Script`'s exports, **Then** there is one smart constructor per kind.
2. **Given** a smart constructor, **When** it is called with valid arguments, **Then** the resulting `Action` encodes to the JSON shape the wallet expects for that action kind.

---

### User Story 4 - Breaking the protocol shape breaks the build (Priority: P2)

Any change to the protocol model must be load-bearing: the constitution, the docs, and the code must all agree. This story requires that the golden fixtures double as a regression harness. If a developer accidentally changes a field name, drops a channel mode, or reorders a sum type, the golden test suite fails loudly before the change lands.

**Why this priority**: Constitution §8 makes the JSON shape the published boundary. Silent drift here leaks into every downstream integration.

**Independent Test**: Temporarily rename one field in `GameChanger.Script` (e.g. `description` → `desc`); `just test` fails with a clear fixture mismatch naming the offending path. Revert the change.

**Acceptance Scenarios**:

1. **Given** a field rename in `GameChanger.Script`, **When** `just test` runs, **Then** the failing fixture's name and the diverging JSON path are in the output.
2. **Given** an action-kind constructor rename, **When** the golden for that action decodes, **Then** the failing action name is surfaced in the decode error.

---

### Edge Cases

- A fixture contains a `metadata` field we do not yet model — decoder must either preserve it (as raw `Value`) or explicitly drop it and the choice must be documented.
- A fixture omits the `description` field — decoder must accept omission; encoder must not emit `null` for missing optional fields.
- An export descriptor uses a mode string we have not seen (`clipboard` vs `copy` confusion). Decoder must fail with a message naming the unknown mode, not silently succeed.
- An action-kind string the library does not model (extensibility) — decoder must fail explicitly; no `UnknownAction` constructor.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose a module `GameChanger.Script` with a `Script` data type covering the top-level fields: `type` (constant `"script"`), `title`, `description` (optional), `run`, `exports`, and `metadata` (optional).
- **FR-002**: The `Script` type MUST have `ToJSON` and `FromJSON` instances that produce exactly the JSON shape the GameChanger wallet accepts today (shape documented in `docs/protocol.md`).
- **FR-003**: The library MUST model the five action kinds as a closed sum type: `BuildTx`, `SignTx`, `SignData`, `SubmitTx`, `GetUTxOs`. The `type` JSON string MUST match the documented lowercase form (`buildTx`, `signTx`, `signData`, `submitTx`, `getUTxOs`).
- **FR-004**: The library MUST model the five export channel modes as a closed sum type: `Return`, `Post`, `Download`, `QR`, `Copy`. The JSON tag MUST match the documented lowercase form.
- **FR-005**: The library MUST expose one smart constructor per action kind that takes the action's required inputs and produces an `Action` value.
- **FR-006**: The test suite MUST include a golden-fixture harness that, for every `test/golden/<name>.json`, performs decode → re-encode → compare against a canonical form and fails with the fixture's path on mismatch.
- **FR-007**: The library MUST round-trip at least one fixture per action kind and one fixture per export channel mode (so every constructor is exercised).
- **FR-008**: The encoder MUST omit optional fields when absent (do not emit `"description": null`).
- **FR-009**: The decoder MUST reject unknown action-kind strings and unknown export-channel mode strings with an error message naming the offending value.
- **FR-010**: All exports from `GameChanger.Script` MUST carry Haddock headers describing their role. The module MUST have a module-level Haddock.
- **FR-011**: The library MUST NOT depend on `cardano-api`, `cardano-ledger`, or `plutus-core` for this ticket — the `Script` type is the *published JSON boundary*, not a Cardano-typed surface.
- **FR-012**: The `detail` payloads for the richer actions (`buildTx`, `signTx`) MAY be typed as `Aeson.Value` in this ticket — refining them to typed records is deferred to later tickets (#9 onwards).

### Key Entities

- **Script**: top-level protocol value. Fields: `type`, `title`, optional `description`, `run`, `exports`, optional `metadata`. This is the boundary type — everything the library emits and every URL the wallet accepts decodes to this.
- **Action**: one entry in the `run` map. Fields: `type` (one of the five action-kind strings), `namespace`, `detail` (action-specific payload). Encoded inline as a JSON object.
- **Export**: one entry in the `exports` map. Fields: `source` (template expression `String`), `mode` (one of `return`, `post`, `download`, `qr`, `copy`), plus per-mode descriptor fields.
- **Channel**: the sum type of the five export modes. Load-bearing for exhaustiveness of downstream pattern matches.
- **Metadata**: an optional map-or-record placeholder; kept minimal at this ticket (`Aeson.Value` is acceptable).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every fixture in `test/golden/` round-trips decode → re-encode → canonicalise → byte-equal against its on-disk form. No exceptions, no skips.
- **SC-002**: All five action kinds and all five export channel modes are exercised by at least one fixture each.
- **SC-003**: `just ci` is green on the branch (build + test + format-check + hlint).
- **SC-004**: A reviewer can add coverage for a newly-documented action by adding one `test/golden/<name>.json` and one test-case line — no changes to the harness required.
- **SC-005**: `GameChanger.Script` is manually verified against the beta wallet (documented in the PR body by pasting a resolver URL produced from one of the fixtures and confirming the wallet renders the expected confirmation screen).

## Assumptions

- The published protocol, as captured in `docs/protocol.md` and the linked docs, is the authoritative shape. If divergence is discovered during implementation, the docs are updated in the same vertical commit (governance rule).
- `detail` payloads for `buildTx` / `signTx` remain `Aeson.Value` for now. Typed refinement lands with the Intent compiler (#9).
- `metadata` is `Maybe Aeson.Value` for now — no downstream ticket on the critical path consumes it.
- `aeson`, `bytestring`, `text`, `containers` are acceptable dependencies (core boot-ish). No new CHaP pins introduced.
- Golden fixtures are small JSON files committed at `test/golden/` — cabal `data-files` is sufficient, no `Paths_` magic required (read from a path relative to the package's source directory, which is how the existing test-suite resolves fixtures in sister projects).
- The constitution's encoding choice (no final-tagless) does not apply to `Script` — this ticket ships plain records. The operational-monad rule is for the Intent surface (#8).
- Tasty is used for the test harness (as set up in #5); `tasty-golden` is the intended mechanism for the golden-file comparisons.
