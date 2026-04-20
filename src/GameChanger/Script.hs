{- | Public surface for the GameChanger script protocol.

Re-exports the record types from "GameChanger.Script.Types" and
the smart constructors from "GameChanger.Script.Smart". Downstream
tickets import this module rather than the internals.
-}
module GameChanger.Script (
    -- * Types
    Script (..),
    Action (..),
    ActionKind (..),
    Export (..),
    Channel (..),

    -- * Smart constructors
    buildTxAction,
    signTxAction,
    signDataAction,
    submitTxAction,
    getUTxOsAction,
) where

import GameChanger.Script.Smart (
    buildTxAction,
    getUTxOsAction,
    signDataAction,
    signTxAction,
    submitTxAction,
 )
import GameChanger.Script.Types (
    Action (..),
    ActionKind (..),
    Channel (..),
    Export (..),
    Script (..),
 )
