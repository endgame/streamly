-- |
-- Module      : Main
-- Copyright   : (c) 2020 Composewell Technologies
--
-- License     : BSD-3-Clause
-- Maintainer  : streamly@composewell.com
-- Stability   : experimental
-- Portability : GHC
--
module Main (main) where

import Streamly.Internal.Data.Unfold (Unfold)

import qualified Data.List as List
import qualified Prelude
import qualified Streamly.Internal.Data.Unfold as UF
import qualified Streamly.Internal.Data.Stream.IsStream as S
import qualified Streamly.Internal.Data.Stream.StreamD as D
import qualified Streamly.Internal.Data.Stream.StreamK as K

import Control.Monad.Trans.State.Strict
import Data.Functor.Identity
import Prelude hiding (const, take, drop, concat, mapM)
import Streamly.Prelude (SerialT)
import Test.Hspec as H
import Test.Hspec.QuickCheck
import Test.QuickCheck
import Test.QuickCheck.Function

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------

-- | @testUnfoldM unf seed initial final xs@, runs an unfold under state monad
-- using @initial@ as the initial state. @final@ is the expected state after
-- running it and @xs@ is the list of elements the stream must produce.
testUnfoldM ::
       (Eq s, Eq b) => Unfold (State s) a b -> a -> s -> s -> [b] -> Bool
testUnfoldM unf seed si sf lst = evalState action si

    where

    action = do
        x <- S.toList $ S.unfold unf seed
        y <- get
        return $ x == lst && y == sf

testUnfoldMD :: Unfold (State Int) a Int -> a -> Int -> Int -> [Int] -> Bool
testUnfoldMD = testUnfoldM

-- | This is similar to 'testUnfoldM' but without the state monad.
testUnfold :: Eq b => Unfold Identity a b -> a -> [b] -> Bool
testUnfold unf seed lst = runIdentity action

    where

    action = do
        x <- S.toList $ S.unfold unf seed
        return $ x == lst

testUnfoldD :: Unfold Identity a Int -> a -> [Int] -> Bool
testUnfoldD = testUnfold

-------------------------------------------------------------------------------
-- Operations on input
-------------------------------------------------------------------------------

lmapM :: Bool
lmapM =
    let unf = UF.lmapM (\x -> modify (+ 1) >> return x) (UF.function id)
     in testUnfoldMD unf 1 0 1 [1]

supply :: Bool
supply =
    let unf = UF.supply 1 (UF.function id)
     in testUnfold unf undefined ([1] :: [Int])

supplyFirst :: Bool
supplyFirst =
    let unf = UF.supplyFirst 1 (UF.function id)
     in testUnfold unf 2 ([(1, 2)] :: [(Int, Int)])

supplySecond :: Bool
supplySecond =
    let unf = UF.supplySecond 1 (UF.function id)
     in testUnfold unf 2 ([(2, 1)] :: [(Int, Int)])

discardFirst :: Bool
discardFirst =
    let unf = UF.discardFirst (UF.function id)
     in testUnfold unf ((1, 2) :: (Int, Int)) [2]

discardSecond :: Bool
discardSecond =
    let unf = UF.discardSecond (UF.function id)
     in testUnfold unf ((1, 2) :: (Int, Int)) [1]

swap :: Bool
swap =
    let unf = UF.swap (UF.function id)
     in testUnfold unf ((1, 2) :: (Int, Int)) [(2, 1)]

-------------------------------------------------------------------------------
-- Stream generation
-------------------------------------------------------------------------------

fromStream :: Property
fromStream =
    property
        $ \list ->
              testUnfoldD
                  UF.fromStream
                  (S.fromList list :: SerialT Identity Int)
                  list

fromStreamD :: Property
fromStreamD =
    property
        $ \list -> testUnfoldD UF.fromStreamD (D.fromList list) (list :: [Int])

fromStreamK :: Property
fromStreamK =
    property
        $ \list -> testUnfoldD UF.fromStreamK (K.fromList list) (list :: [Int])

nilM :: Bool
nilM =
    let unf = UF.nilM put
     in testUnfoldMD unf 1 0 1 []

consM :: Bool
consM =
    let cns = UF.consM (\a -> modify (+ a) >> get)
        unf = cns $ cns $ UF.nilM $ \a -> modify (+ a)
     in testUnfoldMD unf 1 0 3 [1, 2]

functionM :: Bool
functionM =
    let unf = UF.functionM (\a -> modify (+ a) >> get)
     in testUnfoldMD unf 1 0 1 [1]

const :: Bool
const =
    let unf = UF.yieldM (modify (+ 1) >> get)
     in testUnfoldMD unf (0 :: Int) 0 1 [1]

unfoldrM :: Property
unfoldrM =
    property
        $ \gen ->
              let genA = apply gen :: Int -> Maybe (Int, Int)
                  genM x = modify (+ 1) >> return (genA x)
                  list = Prelude.take 100 $ List.unfoldr genA 1
                  unf = UF.take 100 $ UF.unfoldrM genM
                  ll = length list
                  fs = if ll < 100 then ll + 1 else 100
               in testUnfoldMD unf 1 0 fs list

fromListM :: Property
fromListM =
    property
        $ \list ->
              let listM = Prelude.map (\x -> modify (+ 1) >> return x) list
               in testUnfoldMD UF.fromListM listM 0 (length list) list

replicateM :: Property
replicateM =
    property
        $ \i ->
              let ns = max 0 i
                  seed = modify (+ 1) >> get
               in testUnfoldMD (UF.replicateM i) seed 0 ns [1 .. i]

repeatM :: Bool
repeatM =
    testUnfoldMD (UF.take 10 UF.repeatM) (modify (+ 1) >> get) 0 10 [1 .. 10]

iterateM :: Property
iterateM =
    property
        $ \next ->
              let nextA = apply next :: Int -> Int
                  nextM x = modify (+ 1) >> return (nextA x)
                  list = Prelude.take 100 $ List.iterate nextA 1
                  unf = UF.take 100 $ UF.iterateM nextM
               in testUnfoldMD unf (modify (+ 10) >> return 1) 0 110 list

fromIndicesM :: Property
fromIndicesM =
    property
        $ \indF ->
              let indFA = apply indF :: Int -> Int
                  indFM x = modify (+ 1) >> return (indFA x)
                  list = Prelude.take 100 $ Prelude.map indFA [1 ..]
                  unf = UF.take 100 $ UF.fromIndicesM indFM
               in testUnfoldMD unf 1 0 (length list) list

enumerateFromStepNum :: Property
enumerateFromStepNum =
    property
        $ \f s ->
              let unf = UF.take 10 $ UF.enumerateFromStepNum s
                  lst = Prelude.take 10 $ List.unfoldr (\x -> Just (x, x + s)) f
               in testUnfoldD unf f lst

#if MIN_VERSION_base(4,12,0)
enumerateFromToFractional :: Property
enumerateFromToFractional =
    property
        $ \f t ->
              let unf = UF.enumerateFromToFractional (t :: Double)
               in testUnfold unf (f :: Double) [f..(t :: Double)]
#endif

enumerateFromStepIntegral :: Property
enumerateFromStepIntegral =
    property
        $ \f s ->
              let unf = UF.take 10 UF.enumerateFromStepIntegral
                  lst = Prelude.take 10 $ List.unfoldr (\x -> Just (x, x + s)) f
               in testUnfoldD unf (f, s) lst

enumerateFromToIntegral :: Property
enumerateFromToIntegral =
    property
        $ \f t ->
              let unf = UF.enumerateFromToIntegral t
               in testUnfoldD unf f [f .. t]

-------------------------------------------------------------------------------
-- Stream transformation
-------------------------------------------------------------------------------

mapM :: Property
mapM =
    property
        $ \f list ->
              let fA = apply f :: Int -> Int
                  fM x = modify (+ 1) >> return (fA x)
                  unf = UF.mapM fM UF.fromList
                  mList = Prelude.map fA list
               in testUnfoldMD unf list 0 (length list) mList

mapMWithInput :: Property
mapMWithInput =
    property
        $ \f list ->
              let fA = applyFun2 f :: [Int] -> Int -> Int
                  fM x y = modify (+ 1) >> return (fA x y)
                  unf = UF.mapMWithInput fM UF.fromList
                  mList = Prelude.map (fA list) list
               in testUnfoldMD unf list 0 (length list) mList

take :: Property
take =
    property
        $ \i ->
              testUnfoldD
                  (UF.take i UF.repeatM)
                  (return 1)
                  (Prelude.take i (Prelude.repeat 1))

takeWhileM :: Property
takeWhileM =
    property
        $ \f list ->
              let fM x =
                      if apply f x
                      then modify (+ 1) >> return True
                      else return False
                  unf = UF.takeWhileM fM UF.fromList
                  fL = Prelude.takeWhile (apply f) list
                  fS = Prelude.length fL
               in testUnfoldMD unf list 0 fS fL

filterM :: Property
filterM =
    property
        $ \f list ->
              let fM x =
                      if apply f x
                      then modify (+ 1) >> return True
                      else return False
                  unf = UF.filterM fM UF.fromList
                  fL = Prelude.filter (apply f) list
                  fS = Prelude.length fL
               in testUnfoldMD unf list 0 fS fL

drop :: Property
drop =
    property
        $ \i list ->
              let unf = UF.drop i UF.fromList
                  fL = Prelude.drop i list
               in testUnfoldD unf list fL

dropWhileM :: Property
dropWhileM =
    property
        $ \f list ->
              let fM x =
                      if apply f x
                      then modify (+ 1) >> return True
                      else return False
                  unf = UF.dropWhileM fM UF.fromList
                  fL = Prelude.dropWhile (apply f) list
                  fS = Prelude.length list - Prelude.length fL
               in testUnfoldMD unf list 0 fS fL

-------------------------------------------------------------------------------
-- Stream combination
-------------------------------------------------------------------------------

zipWithM :: Property
zipWithM =
    property
        $ \f ->
              let unf1 = UF.enumerateFromToIntegral 10
                  unf2 = UF.enumerateFromToIntegral 20
                  fA = applyFun2 f :: Int -> Int -> Int
                  fM a b = modify (+ 1) >> return (fA a b)
                  unf = UF.zipWithM fM (UF.lmap fst unf1) (UF.lmap snd unf2)
                  lst = Prelude.zipWith fA [1 .. 10] [1 .. 20]
               in testUnfoldMD unf (1, 1) 0 10 lst

concat :: Bool
concat =
    let unfIn = UF.replicateM 10
        unfOut = UF.map return $ UF.enumerateFromToIntegral 10
        unf = UF.many unfOut unfIn
        lst = Prelude.concat $ Prelude.map (Prelude.replicate 10) [1 .. 10]
     in testUnfoldD unf 1 lst

outerProduct :: Bool
outerProduct =
    let unf1 = UF.enumerateFromToIntegral 10
        unf2 = UF.enumerateFromToIntegral 20
        unf = crossProduct unf1 unf2
        lst = [(a, b) :: (Int, Int) | a <- [0 .. 10], b <- [0 .. 20]]
     in testUnfold unf ((0, 0) :: (Int, Int)) lst

    where

    crossProduct u1 u2 = UF.cross (UF.lmap fst u1) (UF.lmap snd u2)

concatMapM :: Bool
concatMapM =
    let inner b =
          let u = UF.lmap (\_ -> modify (+ 1) >> return b) (UF.replicateM 10)
           in modify (+ 1) >> return u
        unf = UF.concatMapM inner (UF.enumerateFromToIntegral 10)
        list = List.concatMap (replicate 10) [1 .. 10]
     in testUnfoldMD unf 1 0 110 list

-------------------------------------------------------------------------------
-- Test groups
-------------------------------------------------------------------------------

testInputOps :: Spec
testInputOps =
    describe "Input"
        $ do
            -- prop "lmap" lmap
            prop "lmapM" lmapM
            prop "supply" supply
            prop "supplyFirst" supplyFirst
            prop "supplySecond" supplySecond
            prop "discardFirst" discardFirst
            prop "discardSecond" discardSecond
            prop "swap" swap

testGeneration :: Spec
testGeneration =
    describe "Generation"
        $ do
            prop "fromStream" fromStream
            prop "fromStreamK" fromStreamK
            prop "fromStreamD" fromStreamD
            prop "nilM" nilM
            prop "consM" consM
            prop "functionM" functionM
            -- prop "function" function
            -- prop "identity" identity
            prop "const" const
            prop "unfoldrM" unfoldrM
            -- prop "fromList" fromList
            prop "fromListM" fromListM
            -- prop "fromSVar" fromSVar
            -- prop "fromProducer" fromProducer
            prop "replicateM" replicateM
            prop "repeatM" repeatM
            prop "iterateM" iterateM
            prop "fromIndicesM" fromIndicesM
            prop "enumerateFromStepIntegral" enumerateFromStepIntegral
            prop "enumerateFromToIntegral" enumerateFromToIntegral
            -- prop "enumerateFromIntegral" enumerateFromIntegral
            prop "enumerateFromStepNum" enumerateFromStepNum
            -- prop "numFrom" numFrom
#if MIN_VERSION_base(4,12,0)
            prop "enumerateFromToFractional" enumerateFromToFractional
#endif

testTransformation :: Spec
testTransformation =
    describe "Transformation"
        $ do
            -- prop "map" map
            prop "mapM" mapM
            prop "mapMWithInput" mapMWithInput
            prop "takeWhileM" takeWhileM
            -- prop "takeWhile" takeWhile
            prop "take" take
            -- prop "filter" filter
            prop "filterM" filterM
            prop "drop" drop
            -- prop "dropWhile" dropWhile
            prop "dropWhileM" dropWhileM

testCombination :: Spec
testCombination =
    describe "Transformation"
        $ do
            prop "zipWithM" zipWithM
            -- prop "zipWith" zipWith
            -- prop "teeZipWith" teeZipWith
            prop "concat" concat
            prop "concatMapM" concatMapM
            prop "outerProduct" outerProduct
            -- prop "ap" ap
            -- prop "apDiscardFst" apDiscardFst
            -- prop "apDiscardSnd" apDiscardSnd

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

moduleName :: String
moduleName = "Data.Unfold"

main :: IO ()
main =
    hspec
        $ describe moduleName
        $ do
            testInputOps
            testGeneration
            testTransformation
            testCombination
