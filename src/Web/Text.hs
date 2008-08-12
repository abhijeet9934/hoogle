
module Web.Text where

import Data.Char
import Data.Maybe
import Data.TagStr
import Numeric


-- | Only append strings if neither one is empty
(+?) :: String -> String -> String
a +? b = if null a || null b then [] else a ++ b

-- | Escape the second argument as HTML before appending
(+&) :: String -> String -> String
a +& b = a ++ escapeHTML b

-- | Escape the second argument as a CGI query string before appending
(+%) :: String -> String -> String
a +% b = a ++ escapeCGI b


escapeHTML = concatMap f
    where
        f '\"' = "&quot;"
        f '<' = "&lt;"
        f '>' = "&gt;"
        f x = [x]

escapeCGI = concatMap f
    where
        f x | isAlphaNum x || x `elem` "-" = [x]
            | x == ' ' = "+"
            | otherwise = '%' : ['0'|length s == 1] ++ s
            where s = showHex (ord x) ""


showTagHTML = showTagHTMLWith (const Nothing)


showTagHTMLWith :: (TagStr -> Maybe String) -> TagStr -> String
showTagHTMLWith f x = g x
    where
        g x | isJust (f x) = fromJust $ f x
        g (Str x) = escapeHTML x
        g (Tags xs) = concatMap g xs
        g (TagBold x) = "<b>" ++ showTagHTML x ++ "</b>"
        g (TagUnderline x) = "<i>" ++ showTagHTML x ++ "</i>"
        g (TagHyperlink url x) = "<a href=\"" +& url ++ "\">" ++ showTagHTML x ++ "</a>"
        g (TagColor i x) = "<span class='c" ++ show i ++ "'>" ++ showTagHTML x ++ "</span>"