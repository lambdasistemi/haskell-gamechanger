{-# LANGUAGE OverloadedStrings #-}

{- | Smart constructors for the five GameChanger action kinds.

Each constructor takes the action's minimal required inputs as
positional arguments and returns an 'Action' with an
appropriately-shaped @detail@ payload. The payload is kept as
'Aeson.Value' at this ticket (#6); typed refinement lands with the
Intent compiler (#9).
-}
module GameChanger.Script.Smart (
    buildTxAction,
    signTxAction,
    signDataAction,
    submitTxAction,
    getUTxOsAction,
) where

import Data.Aeson (Value, object, (.=))
import Data.Text (Text)
import GameChanger.Script.Types (Action (..), ActionKind (..))

{- | Build a @buildTx@ action.

@buildTxAction ns spec@ — @ns@ is the namespace the wallet caches
the result under; @spec@ is the @detail@ payload describing
inputs, outputs, and auxiliary data. The payload shape is opaque
here; the Intent compiler (#9) will construct it from a typed
surface.
-}
buildTxAction :: Text -> Value -> Action
buildTxAction = Action BuildTx

{- | Build a @signTx@ action.

@signTxAction ns txRef@ — signs the transaction referenced by
@txRef@ (typically a template expression referring to an earlier
@buildTx@ result) and caches the witness under @ns@.
-}
signTxAction :: Text -> Text -> Action
signTxAction ns txRef =
    Action SignTx ns $ object ["tx" .= txRef]

{- | Build a @signData@ (CIP-8 COSE Sign1) action.

@signDataAction ns addr message@ — signs @message@ as the signer
at @addr@, caching the COSE Sign1 blob under @ns@.
-}
signDataAction :: Text -> Text -> Text -> Action
signDataAction ns addr message =
    Action SignData ns $
        object
            [ "address" .= addr
            , "message" .= message
            ]

{- | Build a @submitTx@ action.

@submitTxAction ns txRef@ — submits the transaction referenced by
@txRef@ to the node the wallet is connected to.
-}
submitTxAction :: Text -> Text -> Action
submitTxAction ns txRef =
    Action SubmitTx ns $ object ["tx" .= txRef]

{- | Build a @getUTxOs@ action.

@getUTxOsAction ns@ — caches the wallet's UTxO set under @ns@ for
downstream actions (e.g. @buildTx@) to reference. No extra input
is required.
-}
getUTxOsAction :: Text -> Action
getUTxOsAction ns = Action GetUTxOs ns $ object []
