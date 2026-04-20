{-# LANGUAGE OverloadedStrings #-}

{- | @hgc@ executable entry point.

Skeleton stub: prints the library version and exits. Real
subcommands (@build@, @encode@, @qr@, @serve-callback@,
@preprod-smoke@) land in tickets #11 and #13.
-}
module Main (
    main,
) where

import qualified Data.Text.IO as T
import GameChanger (version)

main :: IO ()
main = T.putStrLn $ "hgc " <> version
