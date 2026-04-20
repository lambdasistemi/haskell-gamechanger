{-# LANGUAGE OverloadedStrings #-}

{- | The flagship example from "GameChanger.Intent"'s Haddock
and from @docs/intent-dsl.md@, lifted into a module so the
normal @cabal test@ build type-checks it.

The compile is the test: if 'voteOnProposal' stops type-checking
because the surface drifted, CI goes red.
-}
module IntentSpec.VoteOnProposal (
    voteOnProposal,
    voteOnProposalWithExport,
    voteConstraints,
) where

import GameChanger.Intent (
    Address,
    BuildArgs (..),
    Channel (..),
    Intent,
    ProposalId,
    TxId,
    UTxO,
    Vote,
    buildTx,
    declareExport,
    getUTxOs,
    signTx,
    submitTx,
 )

{- | The flagship typed flow: fetch UTxOs, build a vote
transaction, sign it, submit it.
-}
voteOnProposal :: Address -> ProposalId -> Vote -> Intent TxId
voteOnProposal addr pid vote = do
    utxos <- getUTxOs addr
    tx <- buildTx (voteConstraints utxos pid vote)
    signed <- signTx tx
    submitTx signed

{- | A variant that declares a @return@ export for the final
tx hash. Exercises the 'DeclareExport' constructor.
-}
voteOnProposalWithExport ::
    Address -> ProposalId -> Vote -> Intent ()
voteOnProposalWithExport addr pid vote = do
    _ <- voteOnProposal addr pid vote
    declareExport
        "txHash"
        "{get('cache.submit.txHash')}"
        (Return "https://example.org/cb")

{- | Stub @buildTx@ arguments. The real constraint-generator
lives in #9's compiler; this function only has to exist at the
right type so 'voteOnProposal' type-checks.
-}
voteConstraints ::
    [UTxO] -> ProposalId -> Vote -> BuildArgs
voteConstraints _utxos _pid _vote =
    BuildArgs{buildArgsSource = "placeholder"}
