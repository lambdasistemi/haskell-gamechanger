# Quickstart: GameChanger.Script types + Aeson codec + golden tests

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Clone and build

```bash
git clone git@github.com:lambdasistemi/haskell-gamechanger.git
cd haskell-gamechanger
git checkout 002-script-types

nix develop                 # enters the GHC 9.12.3 dev shell
just ci                     # build + test (incl. golden harness) + fourmolu + hlint
```

## Build a Script by hand in ghci

```bash
nix develop -c cabal repl lib:haskell-gamechanger
```

```haskell
λ> :set -XOverloadedStrings
λ> import qualified Data.Aeson as Aeson
λ> import qualified Data.Map.Strict as Map
λ> import GameChanger.Script
λ>
λ> let script = Script
        { title = "Sign a message"
        , description = Just "Hello-world example"
        , run = Map.fromList
            [ ("signResult", signDataAction "cache" "addr_test..." "hello") ]
        , exports = Map.fromList
            [ ("signature", Export "{get('cache.signResult')}" Copy) ]
        , metadata = Nothing
        }
λ> Aeson.encode script
-- {"type":"script","title":"Sign a message","description":"Hello-world example", ... }
```

## Round-trip a golden fixture

```bash
nix develop -c cabal test --test-options "-p Golden"
```

Expected output:

```
haskell-gamechanger
  Golden
    sign-data.json:      OK
    build-tx.json:       OK
    sign-tx.json:        OK
    submit-tx.json:      OK
    get-utxos.json:      OK
    export-return.json:  OK
    export-post.json:    OK
    export-download.json: OK
    export-qr.json:      OK
    export-copy.json:    OK
```

## Add a new golden fixture

1. Drop a JSON file at `test/golden/<name>.json`.
2. Run `just test`. `tasty-golden`'s `findByExtension` auto-picks it up.
3. If the test fails because the committed fixture is not yet in canonical form, copy the "actual" output back into the fixture and re-run to confirm stability.

No harness edits required (FR-004, SC-004).

## Manually verify against the beta wallet (SC-005)

```bash
# Take the sign-data fixture, pipe it through the eventual encoder (ticket #7
# handles gzip+base64url). For this ticket, use the docs-endorsed resolver
# helper manually: paste the fixture JSON at
# https://beta-wallet.gamechanger.finance/doc/api/v2/script-builder
# and open the generated URL.
```

Paste a screenshot or the generated resolver URL into the PR body as evidence.
