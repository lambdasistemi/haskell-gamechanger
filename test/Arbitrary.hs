{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{- | 'Arbitrary' instances for the 'Script' protocol types.

Test-only: keeps the library free of a 'QuickCheck' dependency while
still powering the round-trip property in 'EncodingSpec'.

Generators are bounded. Deep random JSON inside @detail@,
@metadata@, and @qrOptions@ blows up compression time, so 'Value'
generators are capped at a shallow depth.
-}
module Arbitrary () where

import Data.Aeson (Value)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as V
import GameChanger.Script (
    Action (..),
    ActionKind (..),
    Channel (..),
    Export (..),
    Script (..),
 )
import Test.QuickCheck (
    Arbitrary (..),
    Gen,
    arbitraryBoundedEnum,
    choose,
    elements,
    frequency,
    listOf,
    oneof,
    resize,
    sized,
    suchThat,
    vectorOf,
 )

-- | Short, possibly-non-ASCII 'Text'.
genText :: Gen Text
genText = do
    n <- choose (0, 12)
    T.pack <$> vectorOf n genChar
  where
    genChar =
        frequency
            [ (5, choose ('a', 'z'))
            , (2, choose ('A', 'Z'))
            , (2, choose ('0', '9'))
            , (1, elements "-_. /:")
            , (1, elements "中世界αβγøñé")
            ]

{- | Shallow JSON 'Value' for payload slots.

Depth is capped at two levels; arrays and objects hold at most four
elements each. Stay shallow — deep random JSON inflates the LZMA
compression time past the QuickCheck budget.
-}
genValue :: Gen Value
genValue = sized (go . min 2)
  where
    go 0 =
        oneof
            [ pure Aeson.Null
            , Aeson.Bool <$> arbitrary
            , Aeson.Number . fromInteger <$> choose (-1000, 1000)
            , Aeson.String <$> genText
            ]
    go d =
        frequency
            [ (3, go 0)
            , (1, Aeson.Array . V.fromList <$> resize 4 (listOf (go (d - 1))))
            , (1, Aeson.Object . KeyMap.fromList <$> resize 4 (listOf (kv (d - 1))))
            ]
    kv d = (,) . Key.fromText <$> genText <*> go d

{- | A 'Value' that is never 'Aeson.Null'.

Aeson's @.:?@ collapses missing fields and explicit @null@ into
'Nothing', so @Just Null@ does not round-trip through the codec.
Optional 'Value'-typed fields in the 'Script' tree use this
generator to stay on the canonical @Nothing@ branch.
-}
genNonNullValue :: Gen Value
genNonNullValue = genValue `suchThat` (/= Aeson.Null)

instance Arbitrary ActionKind where
    arbitrary = arbitraryBoundedEnum

instance Arbitrary Action where
    arbitrary = Action <$> arbitrary <*> genText <*> genValue

instance Arbitrary Channel where
    arbitrary =
        oneof
            [ Return <$> genText
            , Post <$> genText
            , Download <$> genText
            , QR <$> oneof [pure Nothing, Just <$> genNonNullValue]
            , pure Copy
            ]

instance Arbitrary Export where
    arbitrary = Export <$> genText <*> arbitrary

-- | Bounded map generator: 0–4 entries keyed by short 'Text'.
genMap :: Gen a -> Gen (Map.Map Text a)
genMap gv = do
    n <- choose (0, 4)
    Map.fromList <$> vectorOf n ((,) <$> genText <*> gv)

instance Arbitrary Script where
    arbitrary =
        Script
            <$> genText
            <*> oneof [pure Nothing, Just <$> genText]
            <*> genMap arbitrary
            <*> genMap arbitrary
            <*> oneof [pure Nothing, Just <$> genNonNullValue]
