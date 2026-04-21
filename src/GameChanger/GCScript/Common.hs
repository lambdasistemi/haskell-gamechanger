{- | Shared attributes, polymorphic @run@ field, and return modes.

Re-exports from "GameChanger.GCScript". Import this module when
working with the cross-cutting pieces that appear on every
function call ('CommonAttrs', 'RunBlock', 'ReturnSpec'),
without needing the full 'FunctionCall' zoo.
-}
module GameChanger.GCScript.Common (
    CommonAttrs (..),
    emptyCommonAttrs,
    RunBlock (..),
    ReturnMode (..),
    ReturnSpec (..),
) where

import GameChanger.GCScript (
    CommonAttrs (..),
    ReturnMode (..),
    ReturnSpec (..),
    RunBlock (..),
    emptyCommonAttrs,
 )
