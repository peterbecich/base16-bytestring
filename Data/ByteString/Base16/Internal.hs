{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
module Data.ByteString.Base16.Internal
( -- * worker loops
  encodeLoop
, decodeLoop
, lenientLoop
  -- * utils
, c2w
, aix
, reChunk
, unsafeShiftR
) where


import Data.Bits ((.&.), (.|.))
import qualified Data.ByteString as B
import Data.ByteString.Internal (ByteString(..))
import Data.Char (ord)

import Foreign.ForeignPtr
import Foreign.Ptr
import Foreign.Storable

import GHC.Word
import GHC.Exts
  (Int(I#), Addr#, indexWord8OffAddr#, word2Int#, uncheckedShiftRL#)


-- ------------------------------------------------------------------ --
-- Loops

encodeLoop
    :: Ptr Word8
    -> Ptr Word8
    -> Ptr Word8
    -> IO ()
encodeLoop !dptr !sptr !end = go dptr sptr
  where
    !hex = "0123456789abcdef"#

    go !dst !src
      | src == end = return ()
      | otherwise = do
        !t <- peek src

        poke dst (aix (unsafeShiftR t 4) hex)
        poke (plusPtr dst 1) (aix (t .&. 0x0f) hex)

        go (plusPtr dst 2) (plusPtr src 1)
{-# INLINE encodeLoop #-}

decodeLoop
  :: ForeignPtr Word8
  -> Ptr Word8
  -> Ptr Word8
  -> Ptr Word8
  -> IO (Either String ByteString)
decodeLoop !dfp !dptr !sptr !end = go dptr sptr
  where
    err !src = return . Left
      $ "invalid character at offset: "
      ++ show (src `minusPtr` sptr)

    !lo = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\xff\xff\xff\xff\xff\xff\xff\x0a\x0b\x0c\x0d\x0e\x0f\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x0a\x0b\x0c\x0d\x0e\x0f\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

    !hi = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00\x10\x20\x30\x40\x50\x60\x70\x80\x90\xff\xff\xff\xff\xff\xff\xff\xa0\xb0\xc0\xd0\xe0\xf0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xa0\xb0\xc0\xd0\xe0\xf0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

    go !dst !src
      | src == end = return (Right (PS dfp 0 (dst `minusPtr` dptr)))
      | otherwise = do
        !x <- peek src
        !y <- peek (plusPtr src 1)

        let !a = aix x hi
            !b = aix y lo

        if a == 0xff
        then err src
        else
          if b == 0xff
          then err (plusPtr src 1)
          else do
            poke dst (a .|. b)
            go (plusPtr dst 1) (plusPtr src 2)
{-# INLINE decodeLoop #-}

lenientLoop
  :: ForeignPtr Word8
  -> Ptr Word8
  -> Ptr Word8
  -> Ptr Word8
  -> IO ByteString
lenientLoop !dfp !dptr !sptr !end = goHi dptr sptr 0
  where
    !lo = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\xff\xff\xff\xff\xff\xff\xff\x0a\x0b\x0c\x0d\x0e\x0f\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x0a\x0b\x0c\x0d\x0e\x0f\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

    !hi = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00\x10\x20\x30\x40\x50\x60\x70\x80\x90\xff\xff\xff\xff\xff\xff\xff\xa0\xb0\xc0\xd0\xe0\xf0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xa0\xb0\xc0\xd0\xe0\xf0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

    goHi !dst !src !n
      | src == end = return (PS dfp 0 n)
      | otherwise = do
        !x <- peek src

        let !a = aix x hi

        if a == 0xff
        then goHi dst (plusPtr src 1) n
        else goLo dst (plusPtr src 1) a n

    goLo !dst !src !a !n
      | src == end = return (PS dfp 0 n)
      | otherwise = do
        !y <- peek src

        let !b = aix y lo

        if b == 0xff
        then goLo dst (plusPtr src 1) a n
        else do
          poke dst (a .|. b)
          goHi (plusPtr dst 1) (plusPtr src 1) (n + 1)
{-# INLINE lenientLoop #-}


-- ------------------------------------------------------------------ --
-- Utils

aix :: Word8 -> Addr# -> Word8
aix (W8# w) table = W8# (indexWord8OffAddr# table (word2Int# w))
{-# INLINE aix #-}

-- | Form a list of chunks, and rechunk the list of bytestrings
-- into length multiples of 2
--
reChunk :: [ByteString] -> [ByteString]
reChunk [] = []
reChunk (c:cs) = case B.length c `divMod` 2 of
    (_, 0) -> c : reChunk cs
    (n, _) -> case B.splitAt (n * 2) c of
      ~(m, q) -> m : cont_ q cs
  where
    cont_ q [] = [q]
    cont_ q (a:as) = case B.splitAt 1 a of
      ~(x, y) -> let q' = B.append q x
        in if B.length q' == 2
          then
            let as' = if B.null y then as else y:as
            in q' : reChunk as'
          else cont_ q' as

unsafeShiftR :: Word8 -> Int -> Word8
unsafeShiftR (W8# x#) (I# i#) = W8# (x# `uncheckedShiftRL#` i#)
{-# INLINE unsafeShiftR #-}

c2w :: Char -> Word8
c2w = fromIntegral . ord
{-# INLINE c2w #-}
