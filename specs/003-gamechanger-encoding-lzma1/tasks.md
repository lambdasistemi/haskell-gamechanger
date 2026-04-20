# Tasks: GameChanger.Encoding — LZMA alone + base64url + resolver URL

**Feature**: 003-gamechanger-encoding-lzma1
**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Data model**: [data-model.md](./data-model.md)

Each task must leave the tree bisect-safe (`just ci` green).

## Phase 1 — cabal + module stubs

- **T001** Add `lzma`, `base64` to the library `build-depends` of
  `haskell-gamechanger.cabal`. Add `QuickCheck`, `tasty-quickcheck`
  to the test suite `build-depends`.
- **T002** Add `GameChanger.Encoding` and
  `GameChanger.Encoding.LzmaAlone` to the library's
  `exposed-modules`.
- **T003** Create stub files:
  - `src/GameChanger/Encoding.hs` exporting `Environment (..)`,
    `ResolverUrl`, `mkResolverUrl`, `unResolverUrl`, `encodeScript`,
    `decodeResolverUrl`, `DecodeError (..)`. Bodies are `undefined`
    (bisect-safe stubs — phases 2-5 fill them in, annotated as
    such).
  - `src/GameChanger/Encoding/LzmaAlone.hs` exporting `encode`,
    `decode` with `undefined` bodies.
- **T004** `just ci` green after T001-T003 (stubs compile; no tests
  yet exercise `undefined`).

## Phase 2 — `.lzma` alone encoder / decoder

- **T005** Define the 13-byte header builder in
  `GameChanger.Encoding.LzmaAlone`:
  `header :: Int -> ByteString` (input size → header).
- **T006** Implement `encode :: ByteString -> ByteString`. First try
  D1 (synthesise header + call `lzma` package's raw stream). If
  that is not reachable from the public API, fall back to D1a (C
  shim). Record the choice in a module haddock.
- **T007** Implement `decode :: ByteString -> Either Text
  ByteString` using `decompressWith defaultDecompressParams
  { decompressAutoDecoder = True }`. Error messages from liblzma
  pass through as `Text`.
- **T008** Unit test in `test/EncodingSpec.hs` (new file, wired into
  `Spec.hs`): decode then re-encode a known-good wallet URL payload
  and assert the re-encoded bytes match byte-for-byte (regression
  against format drift).
- **T009** `just ci` green after T005-T008.

## Phase 3 — `GameChanger.Encoding` public API

- **T010** Implement `Environment` + `environmentHost`. One-line
  function, no magic.
- **T011** Implement the `ResolverUrl` newtype + `mkResolverUrl` +
  `unResolverUrl`. Smart constructor validates prefix against
  `Mainnet`, `BetaMainnet`, and `BetaPreprod` hosts.
- **T012** Implement `encodeScript`:
  `Aeson.encode → LzmaAlone.encode → Base64.encodeBase64UrlUnpadded
  → prepend host+path → ResolverUrl`.
- **T013** Implement `decodeResolverUrl`:
  `unResolverUrl → strip known prefix → decodeBase64Url →
  LzmaAlone.decode → Aeson.eitherDecode` with stage-matched
  `DecodeError` constructors.
- **T014** Implement the `DecodeError` sum.
- **T015** `just ci` green after T010-T014.

## Phase 4 — QuickCheck round-trip

- **T016** Create `test/Arbitrary.hs` with `Arbitrary` instances for
  `Script`, `Action`, `ActionKind`, `Export`, `Channel`, and the
  Aeson `Value` used inside `detail` / `metadata` / `qrOptions`
  (bounded size, non-ASCII allowed, `Value`s kept shallow — deep
  random JSON blows up compression time).
- **T017** Add `prop_encodeDecodeRoundTrip` using
  `tasty-quickcheck`, at 1000 cases, for every `Environment` case.
- **T018** `just ci` green after T016-T017.

## Phase 5 — real-world fixtures

- **T019** Create `test/fixtures/resolver-urls/preprod-tx.txt` with
  the full URL from the GameChanger public docs used in issue #7's
  description.
- **T020** Decode that URL manually (REPL or one-off script) to
  recover the JSON, normalise via #6's `Value`-compare pattern,
  and save alongside as `preprod-tx.json`.
- **T021** Collect at least one more real URL + JSON pair.
- **T022** Add a harness to `EncodingSpec.hs`: for each `.txt`
  under `fixtures/resolver-urls/`, decode via `decodeResolverUrl`,
  assert equality with the sibling `.json`.
- **T023** `just ci` green after T019-T022.

## Phase 6 — `docs/protocol.md` correction

- **T024** Edit `docs/protocol.md`:
  - Replace the "Encoding pipeline" section with the real format
    (LZMA alone, 13-byte header layout from data-model.md, path
    `/api/2/run/`).
  - Update the Haskell sketch to import from
    `GameChanger.Encoding` (not `Codec.Compression.GZip`).
  - Remove / rephrase any remaining reference to gzip and
    `/api/2/tx/`.
- **T025** Grep-clean: `rg gzip docs/protocol.md` and
  `rg '/api/2/tx/' docs/protocol.md` return no current-format hits.
- **T026** Build docs locally (`nix develop
  github:paolino/dev-assets?dir=mkdocs --quiet -c mkdocs build
  --strict`). No broken links.
- **T027** `just ci` green after T024-T026.

## Phase 7 — SC-005 live wallet verification

- **T028** Encode `test/golden/sign-data.json` from #6 via
  `hgc encode` (new subcommand? or a REPL one-off is fine for this
  ticket — the CLI proper is #11).
- **T029** Drive the live wallet headlessly via Playwright MCP:
  navigate to the encoded URL, wait, snapshot. Confirm the "Action
  Request" section does not say "Unknown decoder header".
- **T030** Attach the Playwright result (screenshot / snapshot
  text) to the PR body as the SC-005 evidence.

## Phase 8 — polish + PR

- **T031** Run `just format` + verify `just ci`.
- **T032** Update PR #17 body with code tour, design-call summary,
  and SC-005 evidence. Mark ready-for-review.
- **T033** Wait for CI green on `nixos` runner.
- **T034** Merge via merge-guard rebase. Close issue #7. Remove the
  worktree.
