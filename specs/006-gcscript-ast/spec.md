# Feature Specification: GameChanger.GCScript — upstream AST + JSON round-trip

**Feature Branch**: `006-gcscript-ast`
**Created**: 2026-04-20
**Status**: Draft
**Input**: Issue [#19](https://github.com/lambdasistemi/haskell-gamechanger/issues/19) — model the full upstream GCScript language as a Haskell AST with deterministic JSON round-trip.

## Context

Upstream research (2026-04-20) against
[GameChangerFinance/gamechanger.wallet](https://github.com/GameChangerFinance/gamechanger.wallet)
— the GameChanger browser wallet — shows the canonical GCScript
language is significantly wider than the flat five-action `Script`
surface shipped in #4–#7. A GCScript is a recursive tree of typed
function calls with ~43 built-in functions; any function call is
itself a JSON object with a `type :: String` discriminator and
type-specific fields. Nested `script` blocks are legal as
function-call values. The `run` field is polymorphic — either a
key-value object or an ordered array — and this difference is
semantically meaningful (array indices become cache keys
`"cache.0"`, `"cache.1"`, …).

This feature ships a Haskell AST that faithfully models that
language and round-trips a curated subset of the published example
corpus byte-for-byte. It unblocks [#9](https://github.com/lambdasistemi/haskell-gamechanger/issues/9)
(Intent compiler) by providing a proper compilation target, and
unblocks #20 (ISL AST), #21 (retire deprecated names), #22 (drop
fictitious `metadata`), and #23 (align channel taxonomy).

## User Scenarios & Testing

### User Story 1 — Parse a real upstream script from JSON (Priority: P1)

A backend developer has a `.gcscript` file from the upstream example
corpus and wants to load it as a typed Haskell value. They call
`Aeson.eitherDecode` on the bytes. The result is a `GCScript` that
preserves every field — function kinds, nested sub-scripts, ISL
template strings, array-vs-object `run` blocks, and any function
the library doesn't structurally model (round-tripped via an
opaque fallback constructor).

**Why this priority**: without a parser that accepts real upstream
scripts, the AST is decorative. The whole point is to consume and
produce wallet-loadable JSON.

**Independent Test**: decode each file in the curated corpus;
confirm `Right _` without a `Left`.

**Acceptance Scenarios**:

1. **Given** `examples/🚀 Pay me 1 ADA.gcscript`, **when** parsed,
   **then** the result is a `GCScript` with `run` as an object map
   containing four named entries (`build`, `sign`, `submit`,
   `finally`) and a `return.mode = Last`.
2. **Given** `examples/Minimal Coin Sending Demo.gcscript`,
   **when** parsed, **then** the result is a `GCScript` with `run`
   as a three-element array whose entries are `buildTx`,
   `signTxs`, `submitTxs`.
3. **Given** an example using a function not in our structured
   universe (e.g. `getCurrentAddress`), **when** parsed, **then**
   the function appears as an `Unsupported` constructor preserving
   the full JSON body.

---

### User Story 2 — Emit JSON that the wallet accepts (Priority: P1)

The same developer has constructed or transformed a `GCScript`
value and needs to hand the wallet its JSON serialization. The
emitted bytes match the canonical upstream shape — correct field
order where ordering matters, no stray nulls, array vs object
preserved.

**Why this priority**: output is half of the round-trip. This is
what compilation pipelines downstream (#9's `Intent` compiler, any
hand-written `GCScript` authored in Haskell) will feed to the
wallet.

**Independent Test**: encode each parsed example and compare
byte-for-byte against the original file after a normalizing
pretty-print pass (keys sorted, whitespace canonical). A sample
handful pass byte-for-byte without normalization.

**Acceptance Scenarios**:

1. **Given** a `GCScript` decoded from an example, **when**
   re-encoded via `Aeson.encode`, **then** the bytes decode to an
   equal `GCScript`.
2. **Given** any `GCScript` value `s`, **when** encoded twice
   with the same library version, **then** the byte sequences are
   identical.

---

### User Story 3 — Round-trip the curated corpus (Priority: P1)

The acceptance gate for this ticket: every file in the curated
corpus (~15 examples chosen to span the language) passes
`decode >>> encode >>> decode` returning the same `GCScript`
value.

**Why this priority**: this is the empirical proof that the AST is
faithful. A model that parses one example but fails on another is
a bug.

**Independent Test**: tasty golden suite iterates over
`test/golden/gcscript/*.gcscript`, runs the round-trip, and
compares the decoded-encoded-decoded value to the first decode.

**Acceptance Scenarios**:

1. **Given** any file in the curated corpus, **when** the test
   suite runs `decode >>> encode >>> decode`, **then** the
   resulting `GCScript` equals the first decode.

---

### User Story 4 — Emit type-level guidance for the structured function kinds (Priority: P2)

For the ten function kinds we model structurally (`buildTx`,
`signTxs`, `submitTxs`, `buildFsTxs`, `signDataWithAddress`,
`verifySignatureWithAddress`, `query`, `plutusScript`,
`plutusData`, `nativeScript`, plus the recursive `script` block —
eleven total), the AST exposes typed constructors with
type-specific fields.

**Why this priority**: typed access is the value-add for
downstream code. Without it, `Unsupported { functionName ::
Text, body :: Value }` is the only shape and we gain nothing over
`Aeson.Value`.

**Independent Test**: unit tests that read fields like `buildTx.tx`,
`signTxs.txs`, `script.run`, `script.exportAs`, and
`return.mode` directly from the decoded value without touching
`Aeson.Value`.

**Acceptance Scenarios**:

1. **Given** a parsed `buildTx` call, **when** the test inspects
   its `tx` field, **then** the field is typed (object, not opaque).
2. **Given** a parsed `signTxs` call, **when** the test inspects
   its `txs` field, **then** the field is a list of ISL-carrying
   `Text` values (not yet parsed as ISL — that's #20).

---

### Edge Cases

- **`run` as object vs array.** Some examples use objects
  (`"run": { "build": {...}, "sign": {...} }`); others use arrays
  (`"run": [ {...}, {...} ]`). Array indices become cache keys
  (`"cache.0"`, `"cache.1"`). Both shapes must round-trip; we do
  not normalize one into the other.
- **`run` as a single ISL string (for `macro`).** Some `macro`
  function calls have `run` as a plain string rather than an
  object/array (e.g. `"run": "{get('cache.foo')}"`). This is a
  third shape for `run` specific to `macro`; model it without
  collapsing it into the other two.
- **Nested sub-scripts.** A `run` entry may itself be
  `{"type": "script", "run": {...}, "exportAs": "X"}`. The AST is
  recursive.
- **Function kinds we don't structurally model.** Per upstream the
  universe is ~43 built-ins; we structure ten (eleven with
  `script`). The rest round-trip via an `Unsupported` constructor
  that preserves the exact JSON body, so that later tickets can
  promote specific functions to structured without re-parsing the
  corpus.
- **Common attribute fields.** Every function call may carry
  optional `title`, `description`, `exportAs`, `args`, `argsByKey`,
  `returnURLPattern`, `require`, and `return` alongside its
  type-specific fields. Our AST captures these as a shared
  record attached to each function call.
- **Unknown fields.** If a function call carries a field we do not
  name, the `Unsupported` constructor captures it. Decoding into a
  structured constructor requires that every non-optional field is
  recognized; unknown fields cause fall-back to `Unsupported`.
- **Ordering of JSON object keys on emit.** JSON objects are
  unordered per spec, but byte-for-byte round-trip requires a
  deterministic emit. We sort keys alphabetically on output. The
  upstream example files are not sorted; our round-trip is
  `decode >>> encode >>> decode`, not strict byte equality against
  the original file.
- **`args` shape is polymorphic.** It can be a JSON object, a
  string (ISL), or absent. Kept as `Maybe Value` at the top-level
  `script` layer to avoid overfitting.

## Requirements

### Functional Requirements

- **FR-001**: The library MUST expose a module
  `GameChanger.GCScript` with a top-level type `GCScript`.
- **FR-002**: `GCScript` MUST model the upstream root `script`
  shape with fields `type` (fixed to `"script"`), `title`,
  `description`, `run`, `exportAs`, `args`, `argsByKey`, `return`,
  `returnURLPattern`, `require`. All fields except `type` and
  `run` are optional.
- **FR-003**: The `run` field MUST round-trip all three upstream
  shapes: (a) JSON object of named children, (b) JSON array of
  anonymous children, (c) a single ISL-carrying string (only valid
  inside `macro` calls — see FR-007).
- **FR-004**: The library MUST expose a type `FunctionCall` that is
  a sum of one structured constructor per modeled function kind
  plus an `Unsupported` fallback.
- **FR-005**: The structured constructors MUST cover the
  following eleven function kinds (ten domain + one recursive):
  `buildTx`, `signTxs`, `submitTxs`, `buildFsTxs`,
  `signDataWithAddress`, `verifySignatureWithAddress`, `query`,
  `plutusScript`, `plutusData`, `nativeScript`, and the recursive
  `script` nested sub-block.
- **FR-006**: Each `FunctionCall` constructor MUST expose the
  common attributes `title`, `description`, `exportAs`, `args`,
  `argsByKey`, `returnURLPattern`, `require`, `return` as a shared
  record alongside its type-specific fields.
- **FR-007**: The `macro` function kind MUST be modeled (treated
  as structured enough to cover the `run`-as-string shape from
  FR-003-(c)). Counts as the twelfth structured kind.
- **FR-008**: `Unsupported` MUST preserve the exact JSON body of
  the function call (including type-specific fields we do not
  know about) as an `Aeson.Value`, and MUST round-trip unchanged.
- **FR-009**: `ToJSON` / `FromJSON` instances MUST round-trip any
  `GCScript` value: `decode (encode v) == Right v`.
- **FR-010**: JSON emission MUST be deterministic. `encode v`
  MUST produce the same bytes across runs for the same value.
- **FR-011**: The library MUST NOT introduce a dependency on
  `cardano-api` (constitution §1).
- **FR-012**: ISL template strings (field values like
  `"{get('cache.build.txHash')}"`) MUST be preserved verbatim as
  `Text`. Parsing them is out of scope (ticket #20).
- **FR-013**: The module MUST NOT remove or re-use names from
  the existing `GameChanger.Script` layer. Both live side by
  side until the follow-up tickets (#21, #22, #23, and #9)
  complete.

### Key Entities

- **`GCScript`**: the top-level script object. Has a distinguished
  root-only field `returnURLPattern` (which may also appear on
  individual function calls per the corpus). Carries the recursive
  `run` field.
- **`FunctionCall`**: a sum type. Twelve structured constructors
  (eleven domain + `Macro`) plus `Unsupported`.
- **`CommonAttrs`**: optional shared fields attached to every
  `FunctionCall`.
- **`RunBlock`**: the three-shape polymorphic `run` field — either
  `RunObject :: Map Text FunctionCall`, `RunArray :: [FunctionCall]`,
  or `RunISL :: Text` (for `macro`-style runs).
- **`ReturnMode`**: sum type with constructors `All`, `None`,
  `First`, `Last`, `One`, `Some`, `Macro` matching the upstream
  values.
- **`Require`**: kept as `Aeson.Value` for this ticket — the
  predicate language is out of scope.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A curated corpus of ~15 example files, drawn from
  `GameChangerFinance/gamechanger.wallet/examples`, round-trips
  `decode >>> encode >>> decode` to the first decode. Curated set
  (pinned; adjustable during planning):
  - `Simple Script No Export No Return URL.gcscript` — array `run`
    with only `data`-like entries.
  - `Simple Export.gcscript` — root-level `exportAs` with
    getter functions.
  - `Minimal Coin Sending Demo.gcscript` — `buildTx` +
    `signTxs` + `submitTxs` in array form.
  - `🚀 Pay me 1 ADA.gcscript` — object `run`, ISL everywhere,
    `return.mode = last`, `macro` block.
  - `CIP-8 Data Signing and Encrypting Demo.gcscript` — nested
    `script` sub-blocks, `signDataWithAddress`,
    `verifySignatureWithAddress`, `require` field.
  - `Subroutines Demo.gcscript` — `importAsScript` (Unsupported),
    `argsByKey`.
  - `Arguments and ISL.gcscript` — `args` as ISL-carrying object.
  - `Plutus Script Parametrization.gcscript` — `plutusScript`
    fields.
  - `Run Plutus V3 Script.gcscript` — `plutusData`, `plutusScript`
    together.
  - `Complex Native Scripts.gcscript` — `nativeScript`.
  - `Query Beacon Tokens.gcscript` — `query`.
  - `Script Return Modes Demo.gcscript` — exercises every
    `return.mode` value.
  - `Stake Delegation.gcscript` — functions we don't model
    (`Unsupported` fallback).
  - `Transaction Pipeline.gcscript` — a longer realistic pipeline.
  - `Using console.gcscript` — `macro` with `console(...)` ISL.
- **SC-002**: A property test over at least 100 generated
  `GCScript` values confirms `decode (encode v) == Right v` and
  `encode v == encode v` byte-for-byte.
- **SC-003**: The `Unsupported` fallback is exercised by at least
  three distinct function kinds across the corpus.
- **SC-004**: The library has zero `IO` imports and zero
  `unsafePerformIO` references.
- **SC-005**: `just ci` on the PR branch is green: build + tests +
  `fourmolu -m check` + `cabal-fmt -c` + `hlint` with no hints.

## Assumptions

- The curated corpus of ~15 examples is stable during this
  ticket. If an upstream push to `gamechanger.wallet` changes any
  file, we pin by commit sha in `test/golden/gcscript/`.
- Byte-for-byte parity with the original example files is NOT a
  goal. Round-trip parity (decode/encode/decode stability) is. The
  upstream files are hand-formatted; our emitter sorts keys.
- The upstream function universe is ~43; we do not commit to a
  fixed count because the docs don't publish one. The
  `Unsupported` constructor keeps us safe against new additions.
- The ISL template language (#20) is represented as `Text` in
  this ticket. Field-level promotion to `ISL.Expr` happens in a
  later ticket that crosses both #19 and #20.
- The legacy `GameChanger.Script` module remains shipped and
  unchanged by this ticket. Migration and retirement are tracked
  in #21, #22, #23.
- The name `GCScript` (not `Script`) is used deliberately to avoid
  clashing with the legacy type during the migration window.
