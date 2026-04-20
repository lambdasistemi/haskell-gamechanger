# Quickstart — GameChanger.Intent

## Goal

Walk an author from "I have a Haskell project that needs to drive
the GameChanger wallet" to "I have a typed `Intent TxId` program
that compiles, passes the smoke test, and is ready for #9's
compiler to turn into JSON".

## Prereqs

- This repo's `nix develop` shell (supplies GHC, cabal, fourmolu,
  hlint).
- `GameChanger.Script` from #6 + `GameChanger.Encoding` from #7
  installed (default on `main`).

## 1. Import the surface

```haskell
module MyFlows where

import Data.Text (Text)
import GameChanger.Intent
  ( Intent
  , Address
  , ProposalId
  , Vote
  , UTxO
  , TxId
  , BuildArgs (..)
  , buildTx
  , declareExport
  , getUTxOs
  , signTx
  , submitTx
  )
import GameChanger.Intent qualified as I
  ( Channel (..)
  )
```

## 2. Write a flow in `do`-notation

```haskell
voteOnProposal
  :: Address
  -> ProposalId
  -> Vote
  -> Intent TxId
voteOnProposal addr pid vote = do
  utxos  <- getUTxOs addr
  tx     <- buildTx (voteConstraints utxos pid vote)
  signed <- signTx tx
  submitTx signed

voteConstraints
  :: [UTxO] -> ProposalId -> Vote -> BuildArgs
voteConstraints _utxos _pid _vote =
  BuildArgs { buildArgsSource = "…placeholder source…" }
```

The flow type-checks. Each `<-` binding is typed: `utxos :: [UTxO]`,
`tx :: Tx`, `signed :: SignedTx`, and the whole program ends in
`Intent TxId`. A typo like `signTx utxos` is a compile error.

## 3. Declare an export

```haskell
voteOnProposalWithExport
  :: Address -> ProposalId -> Vote -> Intent ()
voteOnProposalWithExport addr pid vote = do
  _ <- voteOnProposal addr pid vote
  declareExport
    "txHash"
    "{get('cache.submit.txHash')}"
    (I.Return "https://example.org/cb")
```

The second argument of `declareExport` is still a raw `Text`
template expression; #9's compiler will type-check these against
actual bindings. For now, the author is expected to write them
by hand, matching what they'd write in a hand-authored JSON
script.

## 4. Pattern match with `view` (debugging / inspection)

Any consumer — the future compiler in #9, a test, a CLI — can
inspect an `Intent a` via `view`:

```haskell
import Control.Monad.Operational (view, ProgramView (..))

firstStep :: Intent a -> String
firstStep prog = case view prog of
  Return _ -> "program returned immediately"
  GetUTxOs _addr :>>= _k -> "first step is getUTxOs"
  BuildTx _args  :>>= _k -> "first step is buildTx"
  _ -> "other"
```

This is the operational-encoding guarantee the spec's US3 pins
down via the smoke test.

## 5. Run `just ci`

```bash
nix develop -c just ci
```

`build + test + format-check + hlint` all pass.

## Next steps

- Ticket #9 will introduce the pure interpreter that folds
  `Intent a` into `GameChanger.Script.Script`, plus the
  `{get('cache.<name>')}` stable-name generator.
- Ticket #11 will wire Intent programs into the CLI (`hgc`).
