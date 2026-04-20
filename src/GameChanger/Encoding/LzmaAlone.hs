{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- | LZMA \"alone\" (legacy @.lzma@) encode / decode.

The format predates @.xz@ and is what the GameChanger wallet accepts
on its @\/api\/2\/run\/@ endpoint. A stream is a 13-byte header
followed by the raw LZMA1 bytes:

@
offset  size  field               observed value
0       1     properties          0x5D (lc=3, lp=0, pb=2)
1       4     dictionary size     0x02000000 LE = 32 MiB
5       8     uncompressed size   byte length of the input, LE
@

The Hackage @lzma@ package exposes only @.xz@, so 'encode' calls a
small C shim in @cbits\/gc_lzma_alone.c@ that invokes liblzma's
@lzma_alone_encoder@ directly (design decision D1a in the plan).

'decode' reuses the Hackage package's auto-detecting decoder, which
already accepts legacy @.lzma@ inputs.
-}
module GameChanger.Encoding.LzmaAlone (
    encode,
    decode,
) where

import qualified Codec.Compression.Lzma as Lzma
import Control.Exception (SomeException, evaluate, try)
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Internal as BSI
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Unsafe as BSU
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64, Word8)
import Foreign.C.Types (CInt (..), CSize (..))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr, castPtr)
import Foreign.Storable (peek, poke)
import System.IO.Unsafe (unsafePerformIO)

foreign import ccall unsafe "gc_lzma_alone_compress"
    gc_lzma_alone_compress ::
        Ptr Word8 ->
        CSize ->
        Ptr Word8 ->
        Ptr CSize ->
        IO CInt

foreign import ccall unsafe "gc_lzma_alone_compress_bound"
    gc_lzma_alone_compress_bound :: CSize -> CSize

{- | Compress a payload into an LZMA-alone stream: 13-byte header +
raw LZMA1 bytes. Uses liblzma's default preset with the dictionary
size pinned to 32 MiB to match the wallet's observed output.

Pure by construction: 'unsafePerformIO' wraps a deterministic FFI
call over the input buffer.
-}
encode :: ByteString -> ByteString
encode input = patchHeaderSize (BS.length input) (rawEncode input)

rawEncode :: ByteString -> ByteString
rawEncode input = unsafePerformIO $
    BSU.unsafeUseAsCStringLen input $
        \(srcPtr, srcLen) -> do
            let srcSz = fromIntegral srcLen :: CSize
                cap = gc_lzma_alone_compress_bound srcSz
                capI = fromIntegral cap :: Int
            alloca $ \dstSzPtr -> do
                poke dstSzPtr cap
                BSI.createAndTrim capI $ \dstPtr -> do
                    ret <-
                        gc_lzma_alone_compress
                            (castPtr srcPtr)
                            srcSz
                            dstPtr
                            dstSzPtr
                    case ret of
                        0 -> do
                            written <- peek dstSzPtr
                            pure (fromIntegral written)
                        _ ->
                            error $
                                "GameChanger.Encoding.LzmaAlone.encode:"
                                    <> " gc_lzma_alone_compress failed with "
                                    <> show ret

{- | Overwrite the 8-byte uncompressed-size field of the @.lzma@
header (bytes 5..12, little-endian) with the actual payload length.

liblzma's @lzma_alone_encoder@ leaves the size field as
@0xFFFFFFFFFFFFFFFF@ (the \"unknown\" marker). The GameChanger
wallet emits the real length, and matching it keeps our output
byte-compatible with the wallet for the header region.
-}
patchHeaderSize :: Int -> ByteString -> ByteString
patchHeaderSize srcLen bs =
    BS.take 5 bs <> sizeBytes <> BS.drop 13 bs
  where
    n :: Word64
    n = fromIntegral srcLen
    sizeBytes =
        BS.pack
            [ fromIntegral ((n `shiftR` (8 * i)) `mod` 256)
            | i <- [0 .. 7]
            ]

{- | Decode an LZMA-alone stream. Uses liblzma's auto-detecting
decoder, which accepts both legacy @.lzma@ and modern @.xz@ inputs.
Errors from liblzma (bad header, corrupt stream, etc.) pass through
as a 'Text' diagnostic.
-}
decode :: ByteString -> Either Text ByteString
decode bs = unsafePerformIO $ do
    r <-
        try
            . evaluate
            . BSL.toStrict
            . Lzma.decompressWith params
            $ BSL.fromStrict bs
    pure $ case r of
        Right out -> Right out
        Left (e :: SomeException) -> Left (T.pack (show e))
  where
    params =
        Lzma.defaultDecompressParams
            { Lzma.decompressAutoDecoder = True
            }
