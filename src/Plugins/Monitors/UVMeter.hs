{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Plugins.Monitors.UVMeter
-- Copyright   :  (c) Róman Joost
-- License     :  BSD-style (see LICENSE)
--
-- Maintainer  :  Róman Joost
-- Stability   :  unstable
-- Portability :  unportable
--
-- An australian uv monitor for Xmobar
--
-----------------------------------------------------------------------------

module Plugins.Monitors.UVMeter where

import Plugins.Monitors.Common

import qualified Control.Exception as CE
import Control.Applicative hiding ((<|>),many)
import Network.HTTP
import Text.Read (readMaybe)
import Text.Parsec
import Text.Parsec.String


uvConfig :: IO MConfig
uvConfig = mkMConfig
       "<station>" -- template
       ["station"                               -- available replacements
       ]

newtype UvInfo = UV { index :: String }
    deriving (Show)

uvURL :: String
uvURL = "http://www.arpansa.gov.au/uvindex/realtime/xml/uvvalues.xml"

getData :: IO String
getData = do
    let request = getRequest uvURL
    CE.catch (simpleHTTP request >>= getResponseBody) errHandler
    where errHandler :: CE.IOException -> IO String
          errHandler _ = return "<Could not retrieve data>"

textToXMLDocument :: String -> Either ParseError [XML]
textToXMLDocument = parse document ""

formatUVRating :: Maybe Float -> Monitor String
formatUVRating Nothing = getConfigValue naString
formatUVRating (Just x) = do
    uv <- showWithColors show x
    parseTemplate [uv]

getUVRating :: String -> [XML] ->  Maybe Float
getUVRating locID (Element "stations" _ y:_) = getUVRating locID y
getUVRating locID (Element "location" [Attribute attr] ys:xs)
    | locID == snd attr = getUVRating locID ys
    | otherwise = getUVRating locID xs
getUVRating _ (Element "index" [] [Body rate]:_) = readMaybe rate
getUVRating locID (_:xs) = getUVRating locID xs
getUVRating _ [] = Nothing


runUVMeter :: [String] -> Monitor String
runUVMeter [] = return "N.A."
runUVMeter (s:_) = do
    resp <- io getData
    case textToXMLDocument resp of
        Right doc -> formatUVRating (getUVRating s doc)
        Left _ -> getConfigValue naString

-- | XML Parsing code comes here.
-- This is a very simple XML parser to just deal with the uvvalues.xml
-- provided by ARPANSA. If you work on a new plugin which needs an XML
-- parser perhaps consider using a real XML parser and refactor this
-- plug-in to us it as well.
--
-- Note: This parser can not deal with short tags.
--
-- Kudos to: Charlie Harvey for his article about writing an XML Parser
-- with Parsec.
--

type AttrName  = String
type AttrValue = String

newtype Attribute = Attribute (AttrName, AttrValue)
    deriving (Show)

data XML = Element String [Attribute] [XML]
         | Decl String
         | Body String
    deriving (Show)

-- | parse the document
--
document :: Parser [XML]
document = do
    spaces
    y <- try xmlDecl <|> tag
    spaces
    x <- many tag
    spaces
    return (y : x)

-- | parse any tags
--
tag :: Parser XML
tag  = do
    char '<'
    spaces
    name <- many (letter <|> digit)
    spaces
    attr <- many attribute
    spaces
    string ">"
    eBody <- many elementBody
    endTag name
    spaces
    return (Element name attr eBody)

xmlDecl :: Parser XML
xmlDecl = do
    string "<?xml"
    decl <- many (noneOf "?>")
    string "?>"
    return (Decl decl)

elementBody :: Parser XML
elementBody = spaces *> try tag <|> text

endTag :: String -> Parser String
endTag str = string "</" *> string str <* char '>'

text :: Parser XML
text = Body <$> many1 (noneOf "><")

attribute :: Parser Attribute
attribute = do
    name <- many (noneOf "= />")
    spaces
    char '='
    spaces
    char '"'
    value <- many (noneOf "\"")
    char '"'
    spaces
    return (Attribute (name, value))
