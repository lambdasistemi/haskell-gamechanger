{-# LANGUAGE GADTs #-}

{- | Typed surface for authoring GameChanger scripts in Haskell.

This module is the public entry point of the Intent eDSL. A
user-level flow is ordinary @do@-notation against 'Intent', and
each @<-@ binding is typed by the corresponding 'IntentI'
constructor:

> voteOnProposal :: Address -> ProposalId -> Vote -> Intent TxId
> voteOnProposal addr pid vote = do
>   utxos  <- getUTxOs addr
>   tx     <- buildTx (voteConstraints utxos pid vote)
>   signed <- signTx tx
>   submitTx signed

A typo in wiring — for example, @signTx utxos@ — is a GHC type
error, not a wallet runtime error.

The encoding is 'Control.Monad.Operational.Program': the
primitives are the GADT 'IntentI', and consumers (notably the
compiler in ticket #9) walk programs via
'Control.Monad.Operational.view'. Typeclass-indexed surfaces
(final-tagless) are deliberately not used; constitution §11.1.

The compiler from @Intent a@ to 'GameChanger.Script.Script' is
out of scope for this module; ticket #9 owns it.
-}
module GameChanger.Intent (
    -- * The intent monad
    Intent,
    IntentI (..),

    -- * Smart constructors
    getUTxOs,
    buildTx,
    signTx,
    signData,
    submitTx,
    declareExport,

    -- * Typed handles
    module GameChanger.Intent.Handles,

    -- * Channels (re-exported from "GameChanger.Script.Types")
    Channel (..),
) where

import Control.Monad.Operational (Program, singleton)
import Data.Text (Text)
import GameChanger.Intent.Handles
import GameChanger.Script.Types (Channel (..))

{- | The primitives of the Intent eDSL, indexed by the result
type of each wallet action.

Constructors correspond one-to-one with
'GameChanger.Script.Types.ActionKind', plus a sixth
'DeclareExport' constructor that drives the @exports@ clause
of the compiled script.
-}
data IntentI a where
    -- | Fetch the UTxOs of an address.
    GetUTxOs :: Address -> IntentI [UTxO]
    -- | Build a transaction from a set of build arguments.
    BuildTx :: BuildArgs -> IntentI Tx
    -- | Ask the wallet to sign a transaction.
    SignTx :: Tx -> IntentI SignedTx
    {- | Ask the wallet to sign an arbitrary message with the
    key backing a given address.
    -}
    SignData :: Address -> Text -> IntentI Signature
    -- | Submit a signed transaction to the network.
    SubmitTx :: SignedTx -> IntentI TxId
    {- | Declare a named export. The first argument is the
    export name (a label used by the wallet UI), the second
    is the raw @{get('…')}@ template expression selecting
    the value to export, and the third is the 'Channel' the
    export is delivered over.
    -}
    DeclareExport :: Text -> Text -> Channel -> IntentI ()

{- | The Intent monad — a 'Program' over 'IntentI'.

No newtype wrapper: consumers are expected to import
"Control.Monad.Operational" and walk programs directly via
'Control.Monad.Operational.view'.
-}
type Intent = Program IntentI

-- | Smart constructor for 'GetUTxOs'.
getUTxOs :: Address -> Intent [UTxO]
getUTxOs = singleton . GetUTxOs

-- | Smart constructor for 'BuildTx'.
buildTx :: BuildArgs -> Intent Tx
buildTx = singleton . BuildTx

-- | Smart constructor for 'SignTx'.
signTx :: Tx -> Intent SignedTx
signTx = singleton . SignTx

-- | Smart constructor for 'SignData'.
signData :: Address -> Text -> Intent Signature
signData addr msg = singleton (SignData addr msg)

-- | Smart constructor for 'SubmitTx'.
submitTx :: SignedTx -> Intent TxId
submitTx = singleton . SubmitTx

{- | Declare a named export on the compiled script.

The @source@ argument is a raw @{get('cache.<bind>')}@ template
expression; ticket #9 will type-check these against actual
bindings. For now, authors write them by hand to match what
they'd write in a hand-authored JSON script.

Example:

> declareExport
>   "txHash"
>   "{get('cache.submit.txHash')}"
>   (Return "https://example.org/cb")
-}
declareExport :: Text -> Text -> Channel -> Intent ()
declareExport name src ch = singleton (DeclareExport name src ch)
