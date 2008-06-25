{- TODO:
    Make the Trie (Int,Int,Int)
    Have from,to-exact,to-prefix
    Can then only check from..to-exact for exact matches
    And use the Chunk (Int,_) to decide which start at 0
    Therefore don't need to do much sorting

    Also make EntryId be the search key of an element,
    then can order elements from the same database
    without looking at the Entry (other than checking
    for exact-string property)
-}

module Hoogle.DataBase.NameSearch
    (NameSearch, createNameSearch
    ,TextScore, searchNameSearch
    ) where

import Data.Binary.Defer
import Data.Binary.Defer.Trie
import Data.Binary.Defer.Chunk
import Data.Binary.Defer.Index
import Data.Char
import Data.List
import Data.Range
import General.Code
import Hoogle.DataBase.Item
import Hoogle.TextBase.All


---------------------------------------------------------------------
-- DATA TYPES

data NameSearch = NameSearch (Trie NameItem) (Chunk (Int,Lookup Entry))
                  deriving Show

data NameItem = NameItem {nameStart :: Int
                         ,nameCountAll :: Int -- number that match exactly
                         ,nameCountAny :: Int -- number that match a prefix
                         }

instance Show NameItem where
    show (NameItem a b c) = unwords $ map show [a,b,c]


instance BinaryDefer NameSearch where
    put (NameSearch a b) = put a >> put b
    get = get2 NameSearch

instance BinaryDefer NameItem where
    put (NameItem a b c) = put a >> put b >> put c
    get = get3 NameItem

{-
TRIE data structure

Given the functions "map" and "pm" we would generate:

Trie:
"ap"   (0,1,1)
"m"    (1,1,2)
"ma"   (2,0,1)  
"map"  (2,1,1)
"p"    (3,1,2)
"pm"   (4,1,1)

Chunk:
0 "ap"   (1,[map])
1 "m"    (1,[pm])
2 "map"  (0,[map])
3 "p"    (2,[map])
4 "pm"   (0,[pm])

There will be one trie entry per unique substring.
There will be one chunk entry per suffix.
Both are sorted by the string they represent.

[item] is the id of the item.
-}

---------------------------------------------------------------------
-- CREATION

createNameSearch :: [(TextItem, Maybe Entry)] -> NameSearch
createNameSearch xs = NameSearch
        (newTrie $ f sub (zip [0..] pre))
        (newChunk $ map snd pre)
    where
        ys = extractText xs
        sub = map head $ group $ sort $ concatMap (substrs . fst) ys
        pre = sortBy (compare `on` fst)
                  [(p,(i,e)) | (s,e) <- ys, (i,p) <- zip [0..] $ prefixes s]

        f :: [String] -> [(Int,(String,a))] -> [(String,NameItem)]
        f [] _ = []
        f (x:xs) ys = (x,NameItem s neq (neq+npr)) : f xs ys2
            where
                s = fst $ head ys
                (neq,npr) = (length eq, length pr)
                (eq,ys2) = span ((==) x . fst . snd) ys
                pr = takeWhile (isPrefixOf x . fst . snd) ys2


extractText :: [(TextItem, Maybe Entry)] -> [(String, Lookup Entry)]
extractText xs = [(map toLower s, newLookup $ entryId e)
                 |(_, Just e) <- xs, Focus s <- entryText e]


substrs, prefixes :: [a] -> [[a]]
substrs = concatMap (tail . inits) . prefixes
prefixes = init . tails


---------------------------------------------------------------------
-- SEARCHING

-- lower is better
data TextScore = TSExact | TSStart | TSNone
                 deriving (Eq,Ord)

instance Show TextScore where
    show TSExact = "exact"
    show TSStart = "start"
    show TSNone = "_"


searchNameSearch :: NameSearch -> Index Entry -> String -> [(Entry,EntryView,TextScore)]
searchNameSearch (NameSearch trie chunk) ents str =
    case lookupTrie (map toLower str) trie of
        Nothing -> []
        Just i -> order exact0E ++ order (exact0S ++ start) ++ order none
            where
                (exact0,exactN) = partition ((==) 0 . fst) exact
                (partial0,partialN) = partition ((==) 0 . fst) partial
                (exact,partial) = splitAt (nameCountAll i) $
                    lookupChunk (rangeStartCount (nameStart i) (nameCountAny i)) chunk

                none = map (f $ const TSNone) $ exactN ++ partialN
                (exact0E,exact0S) = partition ((==) TSExact . thd3 . snd) $ map (f test) exact0
                start = map (f $ const TSStart) partial0
                test e = if entryName e == str then TSExact else TSStart
    where
        nstr = length str

        f :: (Entry -> TextScore) -> (Int, Lookup Entry) -> (Int, (Entry,EntryView,TextScore))
        f score (p,e) = (entryId ent, (ent, FocusOn (rangeStartCount p nstr), score ent))
            where ent = lookupIndex e ents

        order = map snd . sortBy (compare `on` fst)
