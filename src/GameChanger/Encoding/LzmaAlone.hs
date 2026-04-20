{- | LZMA \"alone\" (legacy @.lzma@) encode / decode.

The format predates @.xz@ and is what the GameChanger wallet accepts
on its @\/api\/2\/run\/@ endpoint. Each stream starts with a 13-byte
header:

@
offset  size  field
0       1     properties byte (0x5D — lc=3, lp=0, pb=2)
1       4     dictionary size (LE, 0x02000000 = 32 MiB)
5       8     uncompressed size (LE)
@

followed by the raw LZMA1 stream.

Bodies are stubbed with 'undefined' in the initial commit and filled
in by phase 2 of the task list (T005–T008).
-}
module GameChanger.Encoding.LzmaAlone (
    encode,
    decode,
) where

import Data.ByteString (ByteString)
import Data.Text (Text)

{- | Compress a payload into an LZMA-alone stream: 13-byte header +
raw LZMA1 bytes. Uses preset 6 (default), matching the 32 MiB
dictionary size the wallet emits.
-}
encode :: ByteString -> ByteString
encode = undefined -- NOTE: stub, filled in by T006

{- | Decode an LZMA-alone stream. Also accepts @.xz@ inputs, since
liblzma's auto-detecting decoder handles both.
-}
decode :: ByteString -> Either Text ByteString
decode = undefined -- NOTE: stub, filled in by T007
