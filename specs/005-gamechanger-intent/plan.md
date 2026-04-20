# Implementation Plan: GameChanger.Intent — operational-monad surface

**Branch**: `005-gamechanger-intent` | **Date**: 2026-04-20 | **Spec**: [spec.md](./spec.md)
**Input**: [spec.md](./spec.md)

## Summary

Ship the public `GameChanger.Intent` module — the typed Haskell
surface authors use to write GameChanger flows in `do`-notation.
The surface is backed by `Control.Monad.Operational`: primitives
are a GADT (`IntentI`), the monad is `type Intent = Program IntentI`,
smart constructors delegate to `singleton`, and `declareExport`
reuses the `Channel` ADT from `GameChanger.Script.Types`. The
compiler from `Intent a` to `Script` is **out of scope**; ticket #9
owns it. The smoke test in this ticket asserts the operational
encoding is reachable via `view`, cementing constitution §11.3
against future final-tagless drift.

## Technical Context

**Language/Version**: Haskell 2010 on GHC 9.6+ (inherits the
library's common-warnings stanza).
**Primary Dependencies**: `operational ^>= 0.2.4` (new),
`GameChanger.Script.Types` (#6), `text`, `base`. No `aeson`, no
`bytestring` — this is a pure surface, no serialisation.
**Storage**: N/A — the module is a pure AST.
**Testing**: `tasty` + `tasty-hunit` (already wired; extend
`test/Spec.hs` with a new `IntentSpec` module).
**Target Platform**: Native GHC (constitution §11.3.4). No WASM.
**Project Type**: Single Haskell library (`haskell-gamechanger`).
**Performance Goals**: None — compilation-time cost, not runtime.
**Constraints**: `-Wall -Werror` clean; Haddock on all exports;
module MUST compile on a fresh `just ci` in < 30 s additional
build time.
**Scale/Scope**: ~150 LOC in `src/GameChanger/Intent.hs` + ~50
LOC of typed-handle stubs + ~80 LOC of test harness.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Rule | Gate | Status |
|---|---|---|
| §1 — No `cardano-api`/`cardano-ledger`/`plutus-core` dep | Only `operational` + existing deps | ✅ |
| §8 — JSON boundary via `GameChanger.Script` | Intent has no direct JSON surface; #9 owns the compiler | ✅ |
| §11.1 — Operational encoding, not final-tagless | `data IntentI a where …`, `type Intent = Program IntentI`, smoke test pattern-matches on `ProgramView` | ✅ |
| §11.3.1 — Surface-only | `voteOnProposal` equivalent compiles; no new wallet actions | ✅ |
| §11.3.2 — Deterministic compilation | N/A this ticket (compiler is #9) | N/A |
| §11.3.3 — No runtime effects | Module is pure; no `IO` in signatures | ✅ |
| §11.3.4 — Native-only | No conditional WASM code; package stays native | ✅ |
| CLAUDE.md — 70-char line limit, leading commas/arrows | Fourmolu enforced by CI | ✅ |
| CLAUDE.md — Haddock on all exports | Plan includes Haddock for every exported name | ✅ |

All gates pass. No complexity tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/005-gamechanger-intent/
├── spec.md           # Feature spec (already committed)
├── plan.md           # This file
├── research.md       # Phase 0 — operational package choice
├── data-model.md     # Phase 1 — IntentI + handles
├── quickstart.md     # Phase 1 — voteOnProposal walkthrough
└── tasks.md          # Phase 2 — /speckit.tasks output
```

### Source Code (repository root)

```text
src/GameChanger/
├── Encoding.hs              # (#7) unchanged
├── Encoding/LzmaAlone.hs    # (#7) unchanged
├── Intent.hs                # NEW — public surface
├── Intent/
│   └── Handles.hs           # NEW — Address / UTxO / Tx / … stubs
├── Script.hs                # (#6) unchanged
├── Script/Smart.hs          # (#6) unchanged
└── Script/Types.hs          # (#6) — re-exports Channel here

test/
├── IntentSpec.hs            # NEW — view-pattern-match smoke test
├── IntentSpec/
│   └── VoteOnProposal.hs    # NEW — compile harness + asserts
├── EncodingSpec.hs          # (#7) unchanged
├── Golden.hs                # (#6/#7) unchanged
├── Arbitrary.hs             # (#7) unchanged
└── Spec.hs                  # wire in IntentSpec

haskell-gamechanger.cabal    # add operational dep; new modules
docs/intent-dsl.md           # flip "Design-phase" block → link to code
```

**Structure Decision**: Split the surface in two — the public
`GameChanger.Intent` module exports the monad, constructors, and
combinators; a sibling `GameChanger.Intent.Handles` carries the
abstract typed placeholders (`Address`, `UTxO`, `Tx`, …). Keeping
them separate means ticket #9 can rewrite the handles without
touching the surface, and anyone reading `GameChanger.Intent`
sees only operational-flavoured definitions.

The test harness is split the same way: the compile-only module
lives in `test/IntentSpec/VoteOnProposal.hs` so the harness
double-duties as the example from `docs/intent-dsl.md` — any
change to the example means this file moves in the same commit.

## Complexity Tracking

No constitution violations; table intentionally left empty.
