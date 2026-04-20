{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-partial-fields #-}

{- | Record types for the GameChanger JSON script protocol.

This module is the published JSON boundary: the shape emitted by
'ToJSON' and accepted by 'FromJSON' is exactly the shape the
GameChanger wallet accepts. Any drift here breaks downstream
integrations, so the golden-test suite pins each action kind and
channel mode to a fixture.

Constitution §8: the JSON shape is load-bearing. Changes to this
module's encoded form require a matching update to the
constitution, the docs, and the ontology in one vertical commit.
-}
module GameChanger.Script.Types (
    Script (..),
    Action (..),
    ActionKind (..),
    Export (..),
    Channel (..),
) where

import Data.Aeson (
    FromJSON (..),
    ToJSON (..),
    Value,
    object,
    withObject,
    withText,
    (.!=),
    (.:),
    (.:?),
    (.=),
 )
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

{- | Top-level protocol value.

The 'type' discriminator is always the literal @"script"@ — emitted
by the encoder and required by the decoder.
-}
data Script = Script
    { title :: Text
    , description :: Maybe Text
    , run :: Map Text Action
    , exports :: Map Text Export
    , metadata :: Maybe Value
    }
    deriving stock (Show, Eq, Generic)

instance ToJSON Script where
    toJSON s =
        object $
            [ "type" .= ("script" :: Text)
            , "title" .= title s
            , "run" .= run s
            , "exports" .= exports s
            ]
                <> maybe [] (\d -> ["description" .= d]) (description s)
                <> maybe [] (\m -> ["metadata" .= m]) (metadata s)

instance FromJSON Script where
    parseJSON = withObject "Script" $ \o -> do
        t <- o .: "type"
        if (t :: Text) /= "script"
            then fail $ "expected type \"script\", got " <> show t
            else
                Script
                    <$> o .: "title"
                    <*> o .:? "description"
                    <*> o .:? "run" .!= mempty
                    <*> o .:? "exports" .!= mempty
                    <*> o .:? "metadata"

{- | One entry in the 'Script' @run@ map.

The @type@ field discriminates the action kind; @detail@ carries
the action-specific payload. 'detail' is 'Value' here — typed
per-kind refinement lands with the Intent compiler (#9).
-}
data Action = Action
    { kind :: ActionKind
    , namespace :: Text
    , detail :: Value
    }
    deriving stock (Show, Eq, Generic)

instance ToJSON Action where
    toJSON a =
        object
            [ "type" .= kind a
            , "namespace" .= namespace a
            , "detail" .= detail a
            ]

instance FromJSON Action where
    parseJSON = withObject "Action" $ \o ->
        Action
            <$> o .: "type"
            <*> o .: "namespace"
            <*> o .:? "detail" .!= Aeson.Null

{- | The five action kinds the GameChanger wallet accepts.

Decoder rejects unknown strings (FR-009). No @UnknownAction@
escape hatch — the closed set is load-bearing for downstream
pattern matches.
-}
data ActionKind
    = BuildTx
    | SignTx
    | SignData
    | SubmitTx
    | GetUTxOs
    deriving stock (Show, Eq, Generic, Enum, Bounded)

actionKindTag :: ActionKind -> Text
actionKindTag = \case
    BuildTx -> "buildTx"
    SignTx -> "signTx"
    SignData -> "signData"
    SubmitTx -> "submitTx"
    GetUTxOs -> "getUTxOs"

instance ToJSON ActionKind where
    toJSON = Aeson.String . actionKindTag

instance FromJSON ActionKind where
    parseJSON = withText "ActionKind" $ \case
        "buildTx" -> pure BuildTx
        "signTx" -> pure SignTx
        "signData" -> pure SignData
        "submitTx" -> pure SubmitTx
        "getUTxOs" -> pure GetUTxOs
        other ->
            fail $
                "unknown action kind \""
                    <> T.unpack other
                    <> "\" (expected buildTx, signTx, signData, submitTx, getUTxOs)"

{- | One entry in the 'Script' @exports@ map.

An export declares the @source@ template expression and the
'Channel' it is delivered over.
-}
data Export = Export
    { source :: Text
    , channel :: Channel
    }
    deriving stock (Show, Eq, Generic)

instance ToJSON Export where
    toJSON e =
        case toJSON (channel e) of
            Aeson.Object km ->
                Aeson.Object $ KeyMap.insert "source" (toJSON (source e)) km
            _ ->
                object ["source" .= source e]

instance FromJSON Export where
    parseJSON v = do
        o <- parseJSON v
        s <- (o :: Aeson.Object) .: "source"
        ch <- parseJSON (Aeson.Object o)
        pure (Export s ch)

{- | The five export channel modes the GameChanger wallet supports.

Decoder rejects unknown mode strings (FR-009). Each constructor
carries its per-mode descriptor fields flattened into the shared
JSON object with @source@ and @mode@.
-}
data Channel
    = Return {returnUrl :: Text}
    | Post {postUrl :: Text}
    | Download {downloadName :: Text}
    | QR {qrOptions :: Maybe Value}
    | Copy
    deriving stock (Show, Eq, Generic)

instance ToJSON Channel where
    toJSON =
        Aeson.Object . \case
            Return u -> KeyMap.fromList [("mode", "return"), ("returnUrl", toJSON u)]
            Post u -> KeyMap.fromList [("mode", "post"), ("postUrl", toJSON u)]
            Download n -> KeyMap.fromList [("mode", "download"), ("downloadName", toJSON n)]
            QR opts ->
                KeyMap.fromList $
                    ("mode", "qr")
                        : maybe [] (\o -> [("qrOptions", o)]) opts
            Copy -> KeyMap.fromList [("mode", "copy")]

instance FromJSON Channel where
    parseJSON = withObject "Channel" $ \o -> do
        m <- o .: "mode"
        case (m :: Text) of
            "return" -> Return <$> o .: "returnUrl"
            "post" -> Post <$> o .: "postUrl"
            "download" -> Download <$> o .: "downloadName"
            "qr" -> QR <$> o .:? "qrOptions"
            "copy" -> pure Copy
            other ->
                fail $
                    "unknown export mode \""
                        <> T.unpack other
                        <> "\" (expected return, post, download, qr, copy)"
