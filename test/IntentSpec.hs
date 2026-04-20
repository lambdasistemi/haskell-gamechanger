{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

{- | Smoke tests for the 'GameChanger.Intent' surface.

These tests are the drift sentinel for constitution §11.1:
they walk a 'GameChanger.Intent.Intent' program using
'Control.Monad.Operational.view' and pattern-match every
'GameChanger.Intent.IntentI' constructor by name. A refactor
that removes the operational encoding (e.g. to final-tagless)
would break these tests at the import site.
-}
module IntentSpec (
    tests,
) where

import Control.Monad.Operational (ProgramViewT (..), view)
import GameChanger.Intent (
    IntentI (..),
 )
import qualified GameChanger.Intent as I
import qualified IntentSpec.VoteOnProposal as VOP
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

tests :: TestTree
tests =
    testGroup
        "Intent"
        [ testCase "voteOnProposal first step is GetUTxOs" $ do
            let prog =
                    VOP.voteOnProposal
                        (I.Address "addr")
                        (I.ProposalId "prop-1")
                        (I.Vote "yes")
            case view prog of
                GetUTxOs (I.Address a) :>>= _ -> a @?= "addr"
                _ -> assertFailure "first step is not GetUTxOs"
        , testCase "voteOnProposalWithExport surfaces DeclareExport" $ do
            let prog =
                    VOP.voteOnProposalWithExport
                        (I.Address "addr")
                        (I.ProposalId "prop-1")
                        (I.Vote "yes")
            -- Walk past the four action steps; each step of an
            -- 'Intent' program produced by the smart constructors
            -- yields exactly one GADT constructor followed by its
            -- continuation.
            case view prog of
                GetUTxOs _ :>>= k1 ->
                    case view (k1 []) of
                        BuildTx _ :>>= k2 ->
                            case view (k2 (I.Tx "t")) of
                                SignTx _ :>>= k3 ->
                                    case view (k3 (I.SignedTx "s")) of
                                        SubmitTx _ :>>= k4 ->
                                            case view (k4 (I.TxId "x")) of
                                                DeclareExport n _ _ :>>= _ ->
                                                    n @?= "txHash"
                                                _ ->
                                                    assertFailure
                                                        "no DeclareExport after submitTx"
                                        _ -> assertFailure "no SubmitTx"
                                _ -> assertFailure "no SignTx"
                        _ -> assertFailure "no BuildTx"
                _ -> assertFailure "no GetUTxOs"
        , testCase "IntentI constructors cover all six cases" $
            -- Exhaustiveness sentinel: the 'case' below MUST
            -- mention every 'IntentI' constructor by name so that
            -- -Wincomplete-patterns (with -Werror from the
            -- warnings stanza) fires if anyone adds or removes a
            -- constructor without updating the tests. Wildcards
            -- are deliberately NOT used.
            case constructors of
                [] -> assertFailure "empty constructors list"
                _ -> pure ()
        ]
  where
    -- A list of tag strings, one per 'IntentI' constructor,
    -- derived via an exhaustive pattern match on a sample value
    -- of each constructor. The match is for the side effect of
    -- exhaustiveness checking; the returned strings are
    -- incidental.
    constructors :: [String]
    constructors =
        [ tag (GetUTxOs (I.Address "a"))
        , tag (BuildTx (I.BuildArgs "b"))
        , tag (SignTx (I.Tx "t"))
        , tag (SignData (I.Address "a") "m")
        , tag (SubmitTx (I.SignedTx "s"))
        , tag (DeclareExport "n" "s" I.Copy)
        ]

    tag :: IntentI a -> String
    tag i = case i of
        GetUTxOs _ -> "GetUTxOs"
        BuildTx _ -> "BuildTx"
        SignTx _ -> "SignTx"
        SignData _ _ -> "SignData"
        SubmitTx _ -> "SubmitTx"
        DeclareExport{} -> "DeclareExport"
