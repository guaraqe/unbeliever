{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_HADDOCK prune #-}

-- |
-- Useful tools for working with 'Rope's. Support for pretty printing,
-- multi-line strings, and...
--
-- ![ANSI colours](AnsiColours.png)
module Core.Text.Utilities
  ( -- * Pretty printing
    Render (..),
    AnsiColour,
    bold,
    render,
    renderNoAnsi,
    dullRed,
    brightRed,
    pureRed,
    dullGreen,
    brightGreen,
    pureGreen,
    dullBlue,
    brightBlue,
    pureBlue,
    dullCyan,
    brightCyan,
    pureCyan,
    dullMagenta,
    brightMagenta,
    pureMagenta,
    dullYellow,
    brightYellow,
    pureYellow,
    pureBlack,
    dullGrey,
    brightGrey,
    pureGrey,
    pureWhite,
    dullWhite,
    brightWhite,

    -- * Helpers
    indefinite,
    breakWords,
    breakLines,
    breakPieces,
    isNewline,
    wrap,
    calculatePositionEnd,
    underline,
    leftPadWith,
    rightPadWith,

    -- * Multi-line strings
    quote,
    -- for testing
    intoPieces,
    intoChunks,
    byteChunk,
    intoDocA,
  )
where

import Core.Text.Breaking
import Core.Text.Bytes
import Core.Text.Parsing
import Core.Text.Rope
import Data.Bits (Bits (..))
import qualified Data.ByteString as B (ByteString, length, splitAt, unpack)
import Data.Char (intToDigit)
import Data.Colour.SRGB (sRGB, sRGB24read)
import qualified Data.FingerTree as F (ViewL (..), viewl, (<|))
import qualified Data.List as List (dropWhileEnd, foldl', splitAt)
import qualified Data.Text as T
import Data.Text.Prettyprint.Doc
  ( Doc,
    LayoutOptions (LayoutOptions),
    PageWidth (AvailablePerLine),
    Pretty (..),
    SimpleDocStream (..),
    annotate,
    emptyDoc,
    flatAlt,
    group,
    hsep,
    layoutPretty,
    pretty,
    reAnnotateS,
    softline',
    unAnnotateS,
    vcat,
  )
import Data.Text.Prettyprint.Doc.Render.Text (renderLazy)
import qualified Data.Text.Short as S
  ( ShortText,
    replicate,
    singleton,
    toText,
    uncons,
  )
import Data.Word (Word8)
import Language.Haskell.TH (litE, stringL)
import Language.Haskell.TH.Quote (QuasiQuoter (QuasiQuoter))
import System.Console.ANSI.Codes (setSGRCode)
import System.Console.ANSI.Types (ConsoleIntensity (..), ConsoleLayer (..), SGR (..))

-- |
-- An accumulation of ANSI escape codes used to add colour when pretty
-- printing to console.
newtype AnsiColour = Escapes [SGR]

-- change AnsiStyle to a custom token type, perhaps Ansi, which
-- has the escape codes already converted to Rope.

-- |
-- Types which can be rendered "prettily", that is, formatted by a pretty
-- printer and embossed with beautiful ANSI colours when printed to the
-- terminal.
--
-- Use 'render' to build text object for later use or
-- <https://hackage.haskell.org/package/core-program/docs/Core-Program-Logging.html Control.Program.Logging>'s
-- <https://hackage.haskell.org/package/core-program/docs/Core-Program-Logging.html#v:writeR writeR>
-- if you're writing directly to console now.
class Render α where
  -- |
  -- Which type are the annotations of your Doc going to be expressed in?
  type Token α :: *

  -- |
  -- Convert semantic tokens to specific ANSI escape tokens
  colourize :: Token α -> AnsiColour

  -- |
  -- Arrange your type as a 'Doc' @ann@, annotated with your semantic
  -- tokens.
  highlight :: α -> Doc (Token α)

-- | Nothing should be invoking 'intoDocA'.
intoDocA :: α -> Doc (Token α)
intoDocA = error "Nothing should be invoking this method directly."

{-# DEPRECATED intoDocA "method'intoDocA' has been renamed 'highlight'; implement that instead." #-}

-- | Medium \"Scarlet Red\" (@#cc0000@ from the Tango color palette).
dullRed :: AnsiColour
dullRed =
  Escapes [SetRGBColor Foreground (sRGB24read "#CC0000")]

-- | Highlighted \"Scarlet Red\" (@#ef2929@ from the Tango color palette).
brightRed :: AnsiColour
brightRed =
  Escapes [SetRGBColor Foreground (sRGB24read "#EF2929")]

-- | Pure \"Red\" (full RGB red channel only).
pureRed :: AnsiColour
pureRed =
  Escapes [SetRGBColor Foreground (sRGB 1 0 0)]

-- | Shadowed \"Chameleon\" (@#4e9a06@ from the Tango color palette).
dullGreen :: AnsiColour
dullGreen =
  Escapes [SetRGBColor Foreground (sRGB24read "#4E9A06")]

-- | Highlighted \"Chameleon\" (@#8ae234@ from the Tango color palette).
brightGreen :: AnsiColour
brightGreen =
  Escapes [SetRGBColor Foreground (sRGB24read "#8AE234")]

-- | Pure \"Green\" (full RGB green channel only).
pureGreen :: AnsiColour
pureGreen =
  Escapes [SetRGBColor Foreground (sRGB 0 1 0)]

-- | Medium \"Sky Blue\" (@#3465a4@ from the Tango color palette).
dullBlue :: AnsiColour
dullBlue =
  Escapes [SetRGBColor Foreground (sRGB24read "#3465A4")]

-- | Highlighted \"Sky Blue\" (@#729fcf@ from the Tango color palette).
brightBlue :: AnsiColour
brightBlue =
  Escapes [SetRGBColor Foreground (sRGB24read "#729FCF")]

-- | Pure \"Blue\" (full RGB blue channel only).
pureBlue :: AnsiColour
pureBlue =
  Escapes [SetRGBColor Foreground (sRGB 0 0 1)]

-- | Dull \"Cyan\" (from the __gnome-terminal__ console theme).
dullCyan :: AnsiColour
dullCyan =
  Escapes [SetRGBColor Foreground (sRGB24read "#06989A")]

-- | Bright \"Cyan\" (from the __gnome-terminal__ console theme).
brightCyan :: AnsiColour
brightCyan =
  Escapes [SetRGBColor Foreground (sRGB24read "#34E2E2")]

-- | Pure \"Cyan\" (full RGB blue + green channels).
pureCyan :: AnsiColour
pureCyan =
  Escapes [SetRGBColor Foreground (sRGB 0 1 1)]

-- | Medium \"Plum\" (@#75507b@ from the Tango color palette).
dullMagenta :: AnsiColour
dullMagenta =
  Escapes [SetRGBColor Foreground (sRGB24read "#75507B")]

-- | Highlighted \"Plum\" (@#ad7fa8@ from the Tango color palette).
brightMagenta :: AnsiColour
brightMagenta =
  Escapes [SetRGBColor Foreground (sRGB24read "#AD7FA8")]

-- | Pure \"Magenta\" (full RGB red + blue channels).
pureMagenta :: AnsiColour
pureMagenta =
  Escapes [SetRGBColor Foreground (sRGB 1 0 1)]

-- | Shadowed \"Butter\" (@#c4a000@ from the Tango color palette).
dullYellow :: AnsiColour
dullYellow =
  Escapes [SetRGBColor Foreground (sRGB24read "#C4A000")]

-- | Highlighted \"Butter\" (@#fce94f@ from the Tango color palette).
brightYellow :: AnsiColour
brightYellow =
  Escapes [SetRGBColor Foreground (sRGB24read "#FCE94F")]

-- | Pure \"Yellow\" (full RGB red + green channels).
pureYellow :: AnsiColour
pureYellow =
  Escapes [SetRGBColor Foreground (sRGB 1 1 0)]

-- | Pure \"Black\" (zero in all RGB channels).
pureBlack :: AnsiColour
pureBlack =
  Escapes [SetRGBColor Foreground (sRGB 0 0 0)]

-- | Shadowed \"Deep Aluminium\" (@#2e3436@ from the Tango color palette).
dullGrey :: AnsiColour
dullGrey =
  Escapes [SetRGBColor Foreground (sRGB24read "#2E3436")]

-- | Medium \"Dark Aluminium\" (from the Tango color palette).
brightGrey :: AnsiColour
brightGrey =
  Escapes [SetRGBColor Foreground (sRGB24read "#555753")]

-- | Pure \"Grey\" (set at @#999999@, being just over half in all RGB channels).
pureGrey :: AnsiColour
pureGrey =
  Escapes [SetRGBColor Foreground (sRGB24read "#999999")]

-- | Pure \"White\" (fully on in all RGB channels).
pureWhite :: AnsiColour
pureWhite =
  Escapes [SetRGBColor Foreground (sRGB 1 1 1)]

-- | Medium \"Light Aluminium\" (@#d3d7cf@ from the Tango color palette).
dullWhite :: AnsiColour
dullWhite =
  Escapes [SetRGBColor Foreground (sRGB24read "#D3D7CF")]

-- | Highlighted \"Light Aluminium\" (@#eeeeec@ from the Tango color palette).
brightWhite :: AnsiColour
brightWhite =
  Escapes [SetRGBColor Foreground (sRGB24read "#EEEEEC")]

-- |
-- Given an 'AnsiColour', lift it to bold intensity.
--
-- Note that many console fonts do /not/ have a bold face variant, and
-- terminal emulators that "support bold" do so by doubling the thickness of
-- the lines in the glyphs. This may or may not be desirable from a
-- readibility standpoint but really there's only so much you can do to keep
-- users who make poor font choices from making poor font choices.
bold :: AnsiColour -> AnsiColour
bold (Escapes list) =
  Escapes (SetConsoleIntensity BoldIntensity : list)

instance Semigroup AnsiColour where
  (<>) (Escapes list1) (Escapes list2) = Escapes (list1 <> list2)

instance Monoid AnsiColour where
  mempty = Escapes []

instance Render Rope where
  type Token Rope = ()
  colourize = const mempty
  highlight = foldr f emptyDoc . unRope
    where
      f :: S.ShortText -> Doc () -> Doc ()
      f piece built = (<>) (pretty (S.toText piece)) built

instance Render Char where
  type Token Char = ()
  colourize = const mempty
  highlight c = pretty c

instance (Render a) => Render [a] where
  type Token [a] = Token a
  colourize = colourize @a
  highlight = mconcat . fmap highlight

instance Render T.Text where
  type Token T.Text = ()
  colourize = const mempty
  highlight t = pretty t

-- (), aka Unit, aka **1**, aka something with only one inhabitant

instance Render Bytes where
  type Token Bytes = ()
  colourize = const brightGreen
  highlight = prettyBytes

prettyBytes :: Bytes -> Doc ()
prettyBytes =
  annotate () . vcat . twoWords
    . fmap wordToHex
    . byteChunk
    . unBytes

twoWords :: [Doc ann] -> [Doc ann]
twoWords ds = go ds
  where
    go [] = []
    go [x] = [softline' <> x]
    go xs =
      let (one : two : [], remainder) = List.splitAt 2 xs
       in group (one <> spacer <> two) : go remainder

    spacer = flatAlt softline' "  "

byteChunk :: B.ByteString -> [B.ByteString]
byteChunk = reverse . go []
  where
    go acc blob =
      let (eight, remainder) = B.splitAt 8 blob
       in if B.length remainder == 0
            then eight : acc
            else go (eight : acc) remainder

-- Take an [up to] 8 byte (64 bit) word
wordToHex :: B.ByteString -> Doc ann
wordToHex eight =
  let ws = B.unpack eight
      ds = fmap byteToHex ws
   in hsep ds

byteToHex :: Word8 -> Doc ann
byteToHex c = pretty hi <> pretty low
  where
    !low = byteToDigit $ c .&. 0xf
    !hi = byteToDigit $ (c .&. 0xf0) `shiftR` 4

    byteToDigit :: Word8 -> Char
    byteToDigit = intToDigit . fromIntegral

-- |
-- Given an object of a type with a 'Render' instance, transform it into a
-- Rope saturated with ANSI escape codes representing syntax highlighting or
-- similar colouring, wrapping at the specified @width@.
--
-- The obvious expectation is that the next thing you're going to do is send
-- the Rope to console with:
--
-- @
--     'Core.Program.Execute.write' ('render' 80 thing)
-- @
--
-- However, the /better/ thing to do is to instead use:
--
-- @
--     'Core.Program.Execute.writeR' thing
-- @
--
-- which is able to pretty print the document text respecting the available
-- width of the terminal.

-- the annotation (_ :: α) of the parameter is to bring type a into scope
-- at term level so that it can be used by TypedApplications. Which then
-- needed AllowAmbiguousTypes, but with all that finally it works:
-- colourize no longer needs a in its type signature.
render :: Render α => Int -> α -> Rope
render columns (thing :: α) =
  let options = LayoutOptions (AvailablePerLine (columns - 1) 1.0)
   in intoRope . go [] . reAnnotateS (colourize @α)
        . layoutPretty options
        . highlight
        $ thing
  where
    go :: [AnsiColour] -> SimpleDocStream AnsiColour -> Rope
    go as x = case x of
      SFail -> error "Unhandled SFail"
      SEmpty -> emptyRope
      SChar c xs ->
        singletonRope c <> go as xs
      SText _ t xs ->
        intoRope t <> go as xs
      SLine len xs ->
        singletonRope '\n'
          <> intoRope (S.replicate len (S.singleton ' '))
          <> go as xs
      SAnnPush a xs ->
        intoRope (convert a) <> go (a : as) xs
      SAnnPop xs ->
        case as of
          [] -> error "Popped an empty stack"
          -- First discard the current one that's just been popped. Then look
          -- at the next one: if it's the last one, we reset the console back
          -- to normal mode. But if they're piled up, then return to the
          -- previous formatting.
          (_ : as') -> case as' of
            [] -> reset <> go [] xs
            (a : _) -> convert a <> go as' xs

    convert :: AnsiColour -> Rope
    convert (Escapes codes) = intoRope (setSGRCode codes)

    reset :: Rope
    reset = intoRope (setSGRCode [Reset])

-- |
-- Having gone to all the trouble to colourize your rendered types...
-- sometimes you don't want that. This function is like 'render', but removes
-- all the ANSI escape codes so it comes outformatted but as plain black &
-- white text.
renderNoAnsi :: Render α => Int -> α -> Rope
renderNoAnsi columns (thing :: α) =
  let options = LayoutOptions (AvailablePerLine (columns - 1) 1.0)
   in intoRope . renderLazy . unAnnotateS
        . layoutPretty options
        . highlight
        $ thing

--

-- | Render "a" or "an" in front of a word depending on English's idea of
-- whether it's a vowel or not.
indefinite :: Rope -> Rope
indefinite text =
  let x = unRope text
   in case F.viewl x of
        F.EmptyL -> text
        piece F.:< _ -> case S.uncons piece of
          Nothing -> text
          Just (c, _) ->
            if c `elem` ['A', 'E', 'I', 'O', 'U', 'a', 'e', 'i', 'o', 'u']
              then intoRope ("an " F.<| x)
              else intoRope ("a " F.<| x)

-- |
-- Often the input text represents a paragraph, but does not have any internal
-- newlines (representing word wrapping). This function takes a line of text
-- and inserts newlines to simulate such folding, keeping the line under
-- the supplied maximum width.
--
-- A single word that is excessively long will be included as-is on its own
-- line (that line will exceed the desired maxium width).
--
-- Any trailing newlines will be removed.
wrap :: Int -> Rope -> Rope
wrap margin text =
  let built = wrapHelper margin (breakWords text)
   in built

wrapHelper :: Int -> [Rope] -> Rope
wrapHelper _ [] = ""
wrapHelper _ [x] = x
wrapHelper margin (x : xs) =
  snd $ List.foldl' (wrapLine margin) (widthRope x, x) xs

wrapLine :: Int -> (Int, Rope) -> Rope -> (Int, Rope)
wrapLine margin (pos, builder) word =
  let wide = widthRope word
      wide' = pos + wide + 1
   in if wide' > margin
        then (wide, builder <> "\n" <> word)
        else (wide', builder <> " " <> word)

underline :: Char -> Rope -> Rope
underline level text =
  let title = fromRope text
      line = T.map (\_ -> level) title
   in intoRope line

-- |
-- Pad a pieve of text on the left with a specified character to the desired
-- width. This function is named in homage to the famous result from Computer
-- Science known as @leftPad@ which has a glorious place in the history of the
-- world-wide web.
leftPadWith :: Char -> Int -> Rope -> Rope
leftPadWith c digits text =
  intoRope pad <> text
  where
    pad = S.replicate len (S.singleton c)
    len = digits - widthRope text

-- |
-- Right pad a text with the specified character.
rightPadWith :: Char -> Int -> Rope -> Rope
rightPadWith c digits text =
  text <> intoRope pad
  where
    pad = S.replicate len (S.singleton c)
    len = digits - widthRope text

-- |
-- Multi-line string literals.
--
-- To use these you need to enable the @QuasiQuotes@ language extension
-- in your source file:
--
-- @
-- \{\-\# LANGUAGE OverloadedStrings \#\-\}
-- \{\-\# LANGUAGE QuasiQuotes \#\-\}
-- @
--
-- you are then able to easily write a string stretching over several lines.
--
-- How best to formatting multi-line string literal within your source code is
-- an aesthetic judgement. Sometimes you don't care about the whitespace
-- leading a passage (8 spaces in this example):
--
-- @
--     let message = ['quote'|
--         This is a test of the Emergency Broadcast System. Do not be
--         alarmed. If this were a real emergency, someone would have tweeted
--         about it by now.
--     |]
-- @
--
-- because you are feeding it into a 'Data.Text.Prettyprint.Doc.Doc' for
-- pretty printing and know the renderer will convert the whole text into a
-- single line and then re-flow it. Other times you will want to have the
-- string as is, literally:
--
-- @
--     let poem = ['quote'|
-- If the sun
--     rises
--         in the
--     west
-- you     drank
--     too much
--                 last week.
--     |]
-- @
--
-- Leading whitespace from the first line and trailing whitespace from the
-- last line will be trimmed, so this:
--
-- @
--     let value = ['quote'|
-- Hello
--     |]
-- @
--
-- is translated to:
--
-- @
--     let value = 'Data.String.fromString' \"Hello\\n\"
-- @
--
-- without the leading newline or trailing four spaces. Note that as string
-- literals they are presented to your code with 'Data.String.fromString' @::
-- String -> α@ so any type with an 'Data.String.IsString' instance (as 'Rope'
-- has) can be constructed from a multi-line @['quote'| ... |]@ literal.

-- I thought this was going to be more complicated.
quote :: QuasiQuoter
quote =
  QuasiQuoter
    (litE . stringL . trim) -- in an expression
    (error "Cannot use [quote| ... |] in a pattern")
    (error "Cannot use [quote| ... |] as a type")
    (error "Cannot use [quote| ... |] for a declaration")
  where
    trim :: String -> String
    trim = bot . top

    top [] = []
    top ('\n' : cs) = cs
    top str = str

    bot = List.dropWhileEnd (== ' ')
