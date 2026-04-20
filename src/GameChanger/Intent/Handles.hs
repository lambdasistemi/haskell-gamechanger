{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

{- | Typed placeholder handles for the 'GameChanger.Intent' surface.

Every action in "GameChanger.Intent" consumes and produces one of
these abstract types. At this layer they are newtypes over 'Text'
so that tests and examples can construct fixture values; ticket
#9 (the @Intent a -> Script@ compiler) will refine the internal
representation to stable-name references without changing this
public API.

The types are re-exported from "GameChanger.Intent"; importing
them from here directly is useful only when writing combinators
that don't need the monad surface.
-}
module GameChanger.Intent.Handles (
    Address (..),
    UTxO (..),
    Tx (..),
    SignedTx (..),
    Signature (..),
    TxId (..),
    ProposalId (..),
    Vote (..),
    BuildArgs (..),
) where

import Data.Text (Text)
import GHC.Generics (Generic)

{- | A Cardano address the wallet can query UTxOs for or sign
with.
-}
newtype Address = Address Text
    deriving stock (Eq, Show, Generic)

{- | A single unspent transaction output belonging to an
'Address'.
-}
newtype UTxO = UTxO Text
    deriving stock (Eq, Show, Generic)

-- | An unsigned Cardano transaction, as produced by @buildTx@.
newtype Tx = Tx Text
    deriving stock (Eq, Show, Generic)

-- | A signed transaction, as produced by @signTx@.
newtype SignedTx = SignedTx Text
    deriving stock (Eq, Show, Generic)

{- | A signature over an arbitrary message, as produced by
@signData@.
-}
newtype Signature = Signature Text
    deriving stock (Eq, Show, Generic)

-- | An on-chain transaction id, as produced by @submitTx@.
newtype TxId = TxId Text
    deriving stock (Eq, Show, Generic)

{- | A governance proposal identifier. Used by example flows
only; the wallet itself doesn't distinguish proposals from
any other 'Text' at this layer.
-}
newtype ProposalId = ProposalId Text
    deriving stock (Eq, Show, Generic)

{- | A vote, rendered as its wallet-side textual form (e.g.
@"yes"@ / @"no"@ / @"abstain"@).
-}
newtype Vote = Vote Text
    deriving stock (Eq, Show, Generic)

{- | Placeholder record for the arguments of a @buildTx@ call.

Ticket #9 will replace 'buildArgsSource' with a structured
description of inputs, outputs, certificates, and metadata;
for the operational surface we only need /something/ typed
enough to type-check @buildTx (voteConstraints …)@ in the
flagship example.
-}
newtype BuildArgs = BuildArgs {buildArgsSource :: Text}
    deriving stock (Eq, Show, Generic)
