# Implementation Plan: GameChanger.Script types + Aeson codec + golden tests

**Branch**: `002-script-types` | **Date**: 2026-04-20 | **Spec**: [spec.md](./spec.md)
**Ticket**: [#6](https://github.com/lambdasistemi/haskell-gamechanger/issues/6)

## Summary

Ship `GameChanger.Script` as the published JSON boundary: typed records for the five-kind action set and five-mode export set, Aeson codecs that match the wallet's accepted shape exactly, smart constructors per action kind, a golden-file harness at `test/golden/` driving round-trip equality. Land it as a pure Haskell library addition with no new CHaP pins and no Cardano deps — `cardano-api` / `cardano-ledger` stay out of this ticket by construction.

## Technical Context

- **Language/Version**: Haskell (GHC 9.12.3) via `haskell.nix`, per #5.
- **Primary Dependencies**: `aeson`, `text`, `bytestring`, `containers`, `tasty`, `tasty-hunit`, `tasty-golden`. All from Hackage at the pinned `index-state` (2026-04-19).
- **Storage**: JSON files in `test/golden/` (checked into the repo).
- **Testing**: `tasty` + `tasty-hunit` (unit round-trips) + `tasty-golden` (fixture harness).
- **Target Platform**: Linux / `x86_64-linux` (and whatever `haskell.nix` unlocks for free). No WASM.
- **Project Type**: library addition to an existing single-package cabal.
- **Performance Goals**: N/A — test suite expected to run in seconds.
- **Constraints**: No `cardano-api` / `cardano-ledger` / `plutus-core` deps. No final-tagless encoding for `Script` (plain records). Bisect-safe commits.
- **Scale/Scope**: ~5 golden fixtures, ~300 LOC in `src/`, ~150 LOC in `test/`.

## Constitution Check

| Gate | Status | Note |
|---|---|---|
| §8 Published JSON boundary is load-bearing | ✅ | This ticket *is* that boundary. Golden tests enforce shape. |
| §11 Operational-monad encoding for Intent eDSL | ✅ N/A | `Script` is a plain record — the operational-monad rule is for `Intent`, not `Script`. Spec FR-011 calls this out. |
| Scope A — backend only, no browser/WASM | ✅ | Library-only addition; no WASM surface. |
| Vertical commits, bisect-safe | ✅ | Phases end in green states; no half-baked intermediates. |
| No `cardano-api` | ✅ | Explicit FR-011. |
| Docs travel with code | ✅ | Haddock on every export (FR-010); no separate docs commit. |

No violations; Complexity Tracking section omitted.

## Design decisions

- **D1 — Plain records, not final-tagless.** `Script` is the JSON boundary; typeclass-indexed encodings add zero value here and the constitution forbids them for the Intent surface anyway. Records give a single, obvious JSON shape.
- **D2 — Closed sum types for `ActionKind` and `Channel`.** The published protocol enumerates five of each. Modelling them as closed sums gives us exhaustiveness checks in every downstream pattern match and an explicit decoder failure on unknown values (FR-009).
- **D3 — `detail` typed as `Aeson.Value` for now.** `buildTx` / `signTx` detail payloads are rich (addresses, UTxO sets, redeemers). Typing them properly requires Cardano types that are banned from this ticket. Ship as `Value`; refine in #9 when the Intent compiler has the typed surface on hand.
- **D4 — `metadata :: Maybe Value`.** Same reasoning. If a downstream ticket needs structured metadata, it types it there.
- **D5 — Golden fixtures under `test/golden/`, read by relative path.** No `Paths_` / `data-files` hand-wiring: `tasty-golden`'s `findByExtension` scans the directory at test time. Adding a fixture is literally dropping a JSON file in the directory.
- **D6 — Canonicalise via `aeson`'s sort-by-key encoding for comparison, not raw bytes.** Aeson's default `encode` produces non-canonical key ordering. The harness decodes the on-disk JSON *and* the library's re-encoded output, then compares the resulting `Value`s — not bytes. This decouples fixture stability from encoder-output whitespace.
- **D7 — Smart constructors take positional required inputs; optional fields get explicit setters.** Keeps call sites terse for the common case (e.g. `signDataAction ns addr msg`) without forcing record-update syntax for every call.
- **D8 — Module split inside `GameChanger.Script`:**
  - `GameChanger.Script` — re-exports the public surface.
  - `GameChanger.Script.Types` — records + sum types + Aeson instances.
  - `GameChanger.Script.Smart` — smart constructors.
  This keeps the public module small and lets downstream tickets import the surface without re-exporting codec internals.

## Pinned deps / tool versions

| Dep | Version | Source |
|---|---|---|
| `aeson` | `^>= 2.2` | Hackage @ 2026-04-19 |
| `bytestring` | boot | inherited |
| `containers` | boot | inherited |
| `text` | `>= 2.0` | already pinned in #5 |
| `tasty` | `>= 1.5` | already pinned in #5 |
| `tasty-hunit` | `>= 0.10` | already pinned in #5 |
| `tasty-golden` | `>= 2.3` | Hackage @ 2026-04-19 (new in #6) |

No CHaP additions. GHC 9.12.3 unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/002-script-types/
├── spec.md
├── plan.md                  # this file
├── quickstart.md            # Phase 1 output
├── tasks.md                 # Phase 2 output (/speckit.tasks)
├── data-model.md            # Phase 1 output — the Script / Action / Export / Channel / Metadata record shapes
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
haskell-gamechanger.cabal    # add tasty-golden to test-suite, add new modules
src/
├── GameChanger.hs           # re-export Script surface
├── GameChanger/
│   └── Script.hs            # public module (re-exports Types + Smart)
│   ├── Script/
│   │   ├── Types.hs         # records + sum types + Aeson instances
│   │   └── Smart.hs         # smart constructors
test/
├── Spec.hs                  # hooks the golden harness into tasty
├── Golden.hs                # the harness (decode → re-encode → compare)
└── golden/
    ├── sign-data.json
    ├── build-tx.json
    ├── sign-tx.json
    ├── submit-tx.json
    ├── get-utxos.json
    ├── export-return.json
    ├── export-post.json
    ├── export-download.json
    ├── export-qr.json
    └── export-copy.json
```

**Structure Decision**: Stay on the single-package cabal layout from #5. The only cabal change is adding `tasty-golden` to the test-suite build-depends and exposing the new modules from the library.

## Quality gates (matches CI and `just ci`)

Every commit must pass:

```bash
just build         # cabal build all -O0
just test          # nix run .#tests (includes golden harness)
just format-check  # fourmolu + cabal-fmt -c
just hlint         # hlint src app test
```

Golden fixtures stabilise on first run; subsequent runs compare against the committed canonical form.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `aeson` instance emits a shape the beta wallet rejects | SC-005: manually feed one fixture through the wallet, paste confirmation screen evidence into the PR body. |
| A fixture we copy from the docs contains a field not in our record type | Parse with `genericParseJSON` using `rejectUnknownFields = True` — decoder will fail loudly with the field name, surfacing the gap. |
| Smart-constructor API drifts from JSON shape | Golden harness is the regression trap: if a constructor change produces different JSON, the corresponding fixture fails. |
| `tasty-golden` not in the cache yet | Trivial dep, no FFI; should build quickly on the nixos runner and populate the shared store on first CI. |

## Open questions

None at this stage. All [NEEDS CLARIFICATION] were resolved in the spec via Assumptions section.
