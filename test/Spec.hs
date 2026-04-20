{- | Test entry point. Skeleton stub: one trivial assertion to keep
the test-suite derivation honest. Real tests arrive with the
modules they cover (tickets #6–#14).
-}
module Main (
    main,
) where

import qualified Data.Text as T
import GameChanger (version)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

main :: IO ()
main =
    defaultMain $
        testGroup
            "haskell-gamechanger"
            [ testCase "version is non-empty" $
                assertBool "version should not be empty" (not (T.null version))
            ]
