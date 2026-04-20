# Data model: GameChanger.Script

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

The records below are the public JSON boundary of the library. Every field maps 1:1 to a documented wallet-accepted field. The types are deliberately plain (no final-tagless, no phantom parameters); this is the boundary, not the DSL.

## `Script`

```haskell
data Script = Script
  { title       :: Text
  , description :: Maybe Text
  , run         :: Map Text Action
  , exports     :: Map Text Export
  , metadata    :: Maybe Aeson.Value
  }
```

JSON shape:

```json
{
  "type": "script",
  "title": "...",
  "description": "...",
  "run":     { "<name>": <Action>, ... },
  "exports": { "<name>": <Export>, ... },
  "metadata": { ... }
}
```

- `type` is always the literal `"script"` — emitted by the encoder, expected by the decoder. Not a Haskell field.
- `description` and `metadata` are omitted from the encoded JSON when `Nothing`.

## `Action`

```haskell
data Action = Action
  { kind      :: ActionKind
  , namespace :: Text
  , detail    :: Aeson.Value
  }

data ActionKind
  = BuildTx
  | SignTx
  | SignData
  | SubmitTx
  | GetUTxOs
```

JSON shape:

```json
{
  "type": "<kind>",
  "namespace": "cache",
  "detail": { ... action-specific payload ... }
}
```

- `kind`'s JSON tag is the documented lowercase form: `buildTx`, `signTx`, `signData`, `submitTx`, `getUTxOs`.
- `detail` is `Aeson.Value` in this ticket. Downstream tickets (#9) refine it to typed sub-records per kind. Decoder does not inspect `detail`.

## `Export`

```haskell
data Export = Export
  { source :: Text
  , channel :: Channel
  }

data Channel
  = Return   { returnUrl    :: Text }
  | Post     { postUrl      :: Text }
  | Download { downloadName :: Text }
  | QR       { qrOptions    :: Maybe Aeson.Value }
  | Copy
```

JSON shape (top-level export):

```json
{
  "source": "{get('cache.signResult')}",
  "mode":   "post",
  ... per-mode descriptor fields ...
}
```

- `mode` tag is the documented lowercase form: `return`, `post`, `download`, `qr`, `copy`.
- Per-mode descriptor fields are flattened into the same object as `source` and `mode`. The `Channel` sum type's record fields encode directly; the decoder uses `mode` as the discriminator.
- `Copy` has no extra fields.
- `QR`'s options are deliberately `Maybe Value` — the documented options shape is in flux and not load-bearing for backend topologies (6.2, 6.3).

## Invariants

- Action-kind strings: five allowed, decoder rejects any other. No `UnknownAction` escape hatch.
- Export-mode strings: five allowed, decoder rejects any other. No `UnknownChannel`.
- `type` at script root is always `"script"`; decoder rejects other values with an error naming the offending string.
- Optional fields (`description`, `metadata`, `Channel.qrOptions`) omitted when absent — the encoder never emits `null`.
