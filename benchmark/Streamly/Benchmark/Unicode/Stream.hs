-- |
-- Module      : Streamly.Unicode.Stream
-- Copyright   : (c) 2019 Composewell Technologies
-- License     : BSD-3-Clause
-- Maintainer  : streamly@composewell.com
-- Stability   : experimental
-- Portability : GHC

{-# LANGUAGE CPP #-}
{-# LANGUAGE ScopedTypeVariables #-}

#ifdef __HADDOCK_VERSION__
#undef INSPECTION
#endif

#ifdef INSPECTION
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fplugin Test.Inspection.Plugin #-}
#endif

import Prelude hiding (last, length)
import System.IO (Handle)

import qualified Streamly.Data.Fold as FL
import qualified Streamly.Unicode.Stream as SS
import qualified Streamly.FileSystem.Handle as FH
import qualified Streamly.Internal.Data.Unfold as IUF
import qualified Streamly.Internal.Unicode.Stream as IUS
import qualified Streamly.Internal.FileSystem.Handle as IFH
import qualified Streamly.Internal.Unicode.Array.Char as IUA
import qualified Streamly.Internal.Data.Stream.IsStream as IP
import qualified Streamly.Data.Array.Foreign as A
import qualified Streamly.Prelude as S

import Gauge hiding (env)
import Streamly.Benchmark.Common
import Streamly.Benchmark.Common.Handle

#ifdef INSPECTION
import Foreign.Storable (Storable)
import Streamly.Internal.Data.Stream.StreamD.Type (Step(..))
import qualified Streamly.Internal.Data.Fold.Type as Fold
import qualified Streamly.Internal.Data.Tuple.Strict as Strict
import qualified Streamly.Internal.Data.Array.Foreign.Type as AT
import qualified Streamly.Internal.Data.Array.Foreign.Mut.Type as MA

import Test.Inspection
#endif

moduleName :: String
moduleName = "Unicode.Stream"

-- | Copy file
{-# NOINLINE copyCodecUtf8ArraysLenient #-}
copyCodecUtf8ArraysLenient :: Handle -> Handle -> IO ()
copyCodecUtf8ArraysLenient inh outh =
   S.fold (FH.write outh)
     $ SS.encodeUtf8'
     $ IUS.decodeUtf8Arrays
     $ IFH.toChunks inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'copyCodecUtf8ArraysLenient
-- inspect $ 'copyCodecUtf8ArraysLenient `hasNoType` ''Step
#endif

o_1_space_decode_encode_chunked :: BenchEnv -> [Benchmark]
o_1_space_decode_encode_chunked env =
    [ bgroup "decode-encode/toChunks"
        [
        mkBenchSmall "decodeEncodeUtf8Lenient" env $ \inH outH ->
            copyCodecUtf8ArraysLenient inH outH
        ]
    ]

-------------------------------------------------------------------------------
-- copy with group/ungroup transformations
-------------------------------------------------------------------------------

{-# NOINLINE linesUnlinesCopy #-}
linesUnlinesCopy :: Handle -> Handle -> IO ()
linesUnlinesCopy inh outh =
    S.fold (FH.write outh)
      $ SS.encodeLatin1'
      $ IUS.unlines IUF.fromList
      $ S.splitOnSuffix (== '\n') FL.toList
      $ SS.decodeLatin1
      $ S.unfold FH.read inh

{-# NOINLINE linesUnlinesArrayWord8Copy #-}
linesUnlinesArrayWord8Copy :: Handle -> Handle -> IO ()
linesUnlinesArrayWord8Copy inh outh =
    S.fold (FH.write outh)
      $ IP.interposeSuffix 10 A.read
      $ S.splitOnSuffix (== 10) A.write
      $ S.unfold FH.read inh

-- XXX splitSuffixOn requires -funfolding-use-threshold=150 for better fusion
-- | Lines and unlines
{-# NOINLINE linesUnlinesArrayCharCopy #-}
linesUnlinesArrayCharCopy :: Handle -> Handle -> IO ()
linesUnlinesArrayCharCopy inh outh =
    S.fold (FH.write outh)
      $ SS.encodeLatin1'
      $ IUA.unlines
      $ IUA.lines
      $ SS.decodeLatin1
      $ S.unfold FH.read inh

#ifdef INSPECTION
inspect $ hasNoTypeClassesExcept 'linesUnlinesArrayCharCopy [''Storable]
-- inspect $ 'linesUnlinesArrayCharCopy `hasNoType` ''Step
#endif

-- XXX to write this we need to be able to map decodeUtf8 on the A.read fold.
-- For that we have to write decodeUtf8 as a Pipe.
{-
{-# INLINE linesUnlinesArrayUtf8Copy #-}
linesUnlinesArrayUtf8Copy :: Handle -> Handle -> IO ()
linesUnlinesArrayUtf8Copy inh outh =
    S.fold (FH.write outh)
      $ SS.encodeLatin1'
      $ IP.intercalate (A.fromList [10]) (pipe SS.decodeUtf8P A.read)
      $ S.splitOnSuffix (== '\n') (IFL.map SS.encodeUtf8' A.write)
      $ SS.decodeLatin1
      $ S.unfold FH.read inh
-}

-- | Word, unwords and copy
{-# NOINLINE wordsUnwordsCopyWord8 #-}
wordsUnwordsCopyWord8 :: Handle -> Handle -> IO ()
wordsUnwordsCopyWord8 inh outh =
    S.fold (FH.write outh)
        $ IP.interposeSuffix 32 IUF.fromList
        $ S.wordsBy isSp FL.toList
        $ S.unfold FH.read inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'wordsUnwordsCopyWord8
-- inspect $ 'wordsUnwordsCopyWord8 `hasNoType` ''Step
#endif

-- | Word, unwords and copy
{-# NOINLINE wordsUnwordsCopy #-}
wordsUnwordsCopy :: Handle -> Handle -> IO ()
wordsUnwordsCopy inh outh =
    S.fold (FH.write outh)
      $ SS.encodeLatin1'
      $ IUS.unwords IUF.fromList
      -- XXX This pipeline does not fuse with wordsBy but fuses with splitOn
      -- with -funfolding-use-threshold=300.  With wordsBy it does not fuse
      -- even with high limits for inlining and spec-constr ghc options. With
      -- -funfolding-use-threshold=400 it performs pretty well and there
      -- is no evidence in the core that a join point involving Step
      -- constructors is not getting inlined. Not being able to fuse at all in
      -- this case could be an unknown issue, need more investigation.
      $ S.wordsBy isSpace FL.toList
      -- -- $ S.splitOn isSpace FL.toList
      $ SS.decodeLatin1
      $ S.unfold FH.read inh

#ifdef INSPECTION
-- inspect $ hasNoTypeClasses 'wordsUnwordsCopy
-- inspect $ 'wordsUnwordsCopy `hasNoType` ''Step
#endif

{-# NOINLINE wordsUnwordsCharArrayCopy #-}
wordsUnwordsCharArrayCopy :: Handle -> Handle -> IO ()
wordsUnwordsCharArrayCopy inh outh =
    S.fold (FH.write outh)
      $ SS.encodeLatin1'
      $ IUA.unwords
      $ IUA.words
      $ SS.decodeLatin1
      $ S.unfold FH.read inh

o_1_space_copy_read_group_ungroup :: BenchEnv -> [Benchmark]
o_1_space_copy_read_group_ungroup env =
    [ bgroup "ungroup-group"
        [ mkBenchSmall "US.unlines . S.splitOnSuffix ([Word8])" env
            $ \inh outh -> linesUnlinesCopy inh outh
        , mkBenchSmall "S.interposeSuffix . S.splitOnSuffix(Array Word8)" env
            $ \inh outh -> linesUnlinesArrayWord8Copy inh outh
        , mkBenchSmall "UA.unlines . UA.lines (Array Char)" env
            $ \inh outh -> linesUnlinesArrayCharCopy inh outh

        , mkBenchSmall "S.interposeSuffix . S.wordsBy ([Word8])" env
            $ \inh outh -> wordsUnwordsCopyWord8 inh outh
        , mkBenchSmall "US.unwords . S.wordsBy ([Char])" env
            $ \inh outh -> wordsUnwordsCopy inh outh
        , mkBenchSmall "UA.unwords . UA.words (Array Char)" env
            $ \inh outh -> wordsUnwordsCharArrayCopy inh outh
        ]
    ]

-------------------------------------------------------------------------------
-- copy unfold
-------------------------------------------------------------------------------

-- | Copy file (encodeLatin1')
{-# NOINLINE copyStreamLatin1' #-}
copyStreamLatin1' :: Handle -> Handle -> IO ()
copyStreamLatin1' inh outh =
   S.fold (FH.write outh)
     $ SS.encodeLatin1'
     $ SS.decodeLatin1
     $ S.unfold FH.read inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'copyStreamLatin1'
inspect $ 'copyStreamLatin1' `hasNoType` ''Step
inspect $ 'copyStreamLatin1' `hasNoType` ''IUF.ConcatState -- FH.read/UF.many
inspect $ 'copyStreamLatin1' `hasNoType` ''MA.ReadUState  -- FH.read/A.read

inspect $ 'copyStreamLatin1' `hasNoType` ''Fold.Step
inspect $ 'copyStreamLatin1' `hasNoType` ''AT.ArrayUnsafe -- FH.write/writeNUnsafe
inspect $ 'copyStreamLatin1' `hasNoType` ''Strict.Tuple3' -- FH.write/chunksOf
#endif

-- | Copy file (encodeLatin1)
{-# NOINLINE copyStreamLatin1 #-}
copyStreamLatin1 :: Handle -> Handle -> IO ()
copyStreamLatin1 inh outh =
   S.fold (FH.write outh)
     $ SS.encodeLatin1
     $ SS.decodeLatin1
     $ S.unfold FH.read inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'copyStreamLatin1
inspect $ 'copyStreamLatin1 `hasNoType` ''Step
inspect $ 'copyStreamLatin1 `hasNoType` ''IUF.ConcatState -- FH.read/UF.many
inspect $ 'copyStreamLatin1 `hasNoType` ''MA.ReadUState  -- FH.read/A.read

inspect $ 'copyStreamLatin1 `hasNoType` ''Fold.ManyState
inspect $ 'copyStreamLatin1 `hasNoType` ''Fold.Step
inspect $ 'copyStreamLatin1 `hasNoType` ''AT.ArrayUnsafe -- FH.write/writeNUnsafe
inspect $ 'copyStreamLatin1 `hasNoType` ''Strict.Tuple3' -- FH.write/chunksOf
#endif

-- | Copy file
_copyStreamUtf8' :: Handle -> Handle -> IO ()
_copyStreamUtf8' inh outh =
   S.fold (FH.write outh)
     $ SS.encodeUtf8'
     $ SS.decodeUtf8'
     $ S.unfold FH.read inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses '_copyStreamUtf8'
-- inspect $ '_copyStreamUtf8 `hasNoType` ''Step
-- inspect $ '_copyStreamUtf8 `hasNoType` ''AT.FlattenState
-- inspect $ '_copyStreamUtf8 `hasNoType` ''D.ConcatMapUState
#endif

-- | Copy file
{-# NOINLINE copyStreamUtf8 #-}
copyStreamUtf8 :: Handle -> Handle -> IO ()
copyStreamUtf8 inh outh =
   S.fold (FH.write outh)
     $ SS.encodeUtf8
     $ SS.decodeUtf8
     $ S.unfold FH.read inh

#ifdef INSPECTION
inspect $ hasNoTypeClasses 'copyStreamUtf8
-- inspect $ 'copyStreamUtf8Lax `hasNoType` ''Step
-- inspect $ 'copyStreamUtf8Lax `hasNoType` ''AT.FlattenState
-- inspect $ 'copyStreamUtf8Lax `hasNoType` ''D.ConcatMapUState
#endif

o_1_space_decode_encode_read :: BenchEnv -> [Benchmark]
o_1_space_decode_encode_read env =
    [ bgroup "decode-encode"
        [
        -- This needs an ascii file, as decode just errors out.
          mkBench "SS.encodeLatin1' . SS.decodeLatin1" env $ \inh outh ->
            copyStreamLatin1' inh outh
        , mkBench "SS.encodeLatin1 . SS.decodeLatin1" env $ \inh outh ->
            copyStreamLatin1 inh outh
#ifdef DEVBUILD
        , mkBench "copyUtf8" env $ \inh outh ->
            _copyStreamUtf8' inh outh
#endif
        , mkBenchSmall "SS.encodeUtf8 . SS.decodeUtf8Lax" env $ \inh outh ->
            copyStreamUtf8 inh outh
        ]
    ]

main :: IO ()
main = do
    (_, cfg, benches) <- parseCLIOpts defaultStreamSize
    env <- mkHandleBenchEnv
    runMode (mode cfg) cfg benches (allBenchmarks env)

    where

    allBenchmarks env =
        [ bgroup (o_1_space_prefix moduleName) $ Prelude.concat $
            [ o_1_space_copy_read_group_ungroup env
            , o_1_space_decode_encode_chunked env
            , o_1_space_decode_encode_read env
            ]
        ]
