{-# LANGUAGE OverloadedStrings #-}

{- | Placeholder top-level module for the haskell-gamechanger library.

The library is empty by design at ticket #5 — the skeleton provides
a buildable home for the Scope A modules that follow (@GameChanger.Script@,
@GameChanger.Encoding@, @GameChanger.Intent@, @GameChanger.QR@,
@GameChanger.Callback@). Each lands in its own ticket (#6–#12).
-}
module GameChanger (
    version,
) where

import Data.Text (Text)

{- | Current library version, hard-coded to match the cabal file.

Downstream tickets will replace this with a Paths_-derived value
once there is non-trivial content to version.
-}
version :: Text
version = "0.1.0.0"
