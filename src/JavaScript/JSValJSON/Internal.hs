{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE JavaScriptFFI #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module JavaScript.JSValJSON.Internal where

import GHCJS.Types (JSVal, JSString, JSException)
import Control.Monad.Trans.Either
import Control.Monad.Error.Class
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Foldable (toList, asum)
import qualified Data.JSString as JSS
import Control.Exception (try)
import Data.Int (Int32)
import Control.Applicative (Alternative)
import qualified Data.Vector as V

type Value = JSVal
newtype Object = Object {unObject :: Value}
newtype Array = Array {unArray :: Value}

newtype Parser a = Parser {unParser :: EitherT String IO a}
  deriving (Functor, Applicative, MonadIO, Alternative)

instance Monad Parser where
  {-# INLINE return #-}
  return = Parser . return
  {-# INLINE (>>=) #-}
  Parser ma >>= mf = Parser (ma >>= unParser . mf)
  {-# INLINE fail #-}
  fail = Parser . throwError

class FromJSON a where
  parseJSON :: Value -> Parser a

class ToJSON a where
  toJSON :: a -> IO Value

class FromJSONKey a where
  fromJSONKey :: a -> Parser a

class ToJSONKey a where
  toJSONKey :: a -> IO JSString

{-# INLINE checkType #-}
checkType :: String -> String -> Bool -> Parser ()
checkType what ty b = if b
  then return ()
  else fail ("Expected " ++ what ++ " of type " ++ ty ++ " but got something else")

{-# INLINE withNull #-}
withNull :: String -> Parser a -> Value -> Parser a
withNull what m val = do
  checkType what "null" (js_isNull val)
  m
foreign import javascript unsafe "$r = $1 === null" js_isNull :: Value -> Bool

{-# INLINE _Null #-}
_Null :: Value
_Null = js_null
foreign import javascript unsafe "null" js_null :: Value

{-# INLINE withInteger #-}
withInteger :: Integral a => String -> (a -> Parser b) -> Value -> Parser b
withInteger what cont val = do
  checkType what "integer" (js_isInteger val)
  cont (round (js_toFloat val))
foreign import javascript unsafe "$r = (typeof $1 === \"number\" && $1 === +$1 && $1 == ($1|0))" js_isInteger :: Value -> Bool

-- TODO make the serialization skip the conversion to integer, if possible
{-# INLINE _Integer #-}
_Integer :: (Show a, Integral a) => a -> Value
_Integer x = if integralIsRepresentable x
  then js_fromFloat (fromIntegral x)
  else error ("Integral is not representable in js: " ++ show x)
foreign import javascript unsafe "$r = $1" js_fromFloat :: Double -> Value

integralIsRepresentable :: Integral a => a -> Bool
integralIsRepresentable (toInteger -> x) =
  x <= 9007199254740991 && x >= -9007199254740991

{-# INLINE withNumber #-}
withNumber :: String -> (Double -> Parser a) -> Value -> Parser a
withNumber what cont val = do
  checkType what "number" (js_isNumber val)
  cont (js_toFloat val)
foreign import javascript unsafe "$r = typeof $1 === \"number\"" js_isNumber :: Value -> Bool
foreign import javascript unsafe "$r = $1" js_toFloat :: Value -> Double

{-# INLINE _Number #-}
_Number :: Double -> Value
_Number = js_fromFloat

{-# INLINE withBool #-}
withBool :: String -> (Bool -> Parser a) -> Value -> Parser a
withBool what cont val = do
  checkType what "boolean" (js_isBoolean val)
  cont (js_toBool val)
foreign import javascript unsafe "$r = $1" js_toBool :: Value -> Bool
foreign import javascript unsafe "$r = typeof $1 === \"boolean\"" js_isBoolean :: Value -> Bool

{-# INLINE _Bool #-}
_Bool :: Bool -> Value
_Bool = js_fromBool
foreign import javascript unsafe "$r = $1" js_fromBool :: Bool -> Value

{-# INLINE withString #-}
withString :: String -> (JSString -> Parser a) -> Value -> Parser a
withString what cont val = do
  checkType what "string" (js_isString val)
  cont (js_toString val)
foreign import javascript unsafe "$r = $1" js_toString :: Value -> JSString
foreign import javascript unsafe "$r = typeof $1 === \"string\"" js_isString :: Value -> Bool

{-# INLINE _String #-}
_String :: JSString -> Value
_String = js_fromString
foreign import javascript unsafe "$r = $1" js_fromString :: JSString -> Value

{-# INLINE withArray #-}
withArray :: String -> (Array -> Parser a) -> Value -> Parser a
withArray what cont val = do
  checkType what "array" (js_isArray val)
  cont (Array val)
foreign import javascript unsafe "$r = $1.constructor === Array" js_isArray :: Value -> Bool

{-# INLINE arrayGenerate #-}
arrayGenerate ::
     (Value -> Parser a)
  -> (Int -> (Int -> Parser a) -> Parser b)
  -> Array
  -> Parser b
arrayGenerate parseElem generate (Array val) = do
  len <- round <$> liftIO (js_arrayLength val)
  generate len $ \ix -> do
    ixVal <- liftIO (js_arrayIndex val (fromIntegral ix))
    parseElem ixVal

foreign import javascript unsafe "$r = $1.length" js_arrayLength :: Value -> IO Double
foreign import javascript unsafe "$r = $1[$2]" js_arrayIndex :: Value -> Double -> IO Value

{-# INLINE arrayToList #-}
arrayToList :: Array -> Parser [Value]
arrayToList (Array val) = liftIO $ do
  len :: Int <- round <$> js_arrayLength val
  let
    loop !ix = if ix >= len
      then return []
      else (:) <$> js_arrayIndex val (fromIntegral ix) <*> loop (ix+1)
  loop 0

{-# INLINE arrayLength #-}
arrayLength :: Array -> Parser Int
arrayLength (Array val) = round <$> liftIO (js_arrayLength val)

{-# INLINE mkArray #-}
mkArray :: Foldable t => t Value -> IO Array
mkArray xs0 = do
  val <- js_arrayEmpty
  let
    loop !ix = \case
      [] -> return ()
      x : xs -> do
        js_arraySetIndex val (fromIntegral ix) x
        loop (ix+1) xs
  loop (0 :: Int) (toList xs0)
  return (Array val)

foreign import javascript unsafe "$1[$2] = $3" js_arraySetIndex :: Value -> Double -> Value -> IO ()
foreign import javascript unsafe "$r = []" js_arrayEmpty :: IO Value

{-# INLINE _Array #-}
_Array :: Array -> Value
_Array (Array v) = v

{-# INLINE array #-}
array :: Foldable t => t Value -> IO Value
array = fmap _Array . mkArray

{-# INLINE withObject #-}
withObject :: String -> (Object -> Parser a) -> Value -> Parser a
withObject what cont val = do
  checkType what "object" (js_isObject val)
  cont (Object val)
foreign import javascript unsafe "$r = $1.constructor === Object" js_isObject :: Value -> Bool

{-# INLINE objectLookup #-}
objectLookup :: Object -> JSString -> Parser (Maybe Value)
objectLookup (Object o) x = liftIO $ do
  val <- js_objectLookup o x
  if js_isUndefined val
    then return Nothing
    else return (Just val)
foreign import javascript unsafe "$r = $1 === undefined" js_isUndefined :: Value -> Bool
foreign import javascript unsafe "$r = $1[$2]" js_objectLookup :: Value -> JSString -> IO Value

{-# INLINE (.:) #-}
(.:) :: FromJSON a => Object -> JSString -> Parser a
obj .: label = do
  mbX <- objectLookup obj label
  case mbX of
    Nothing -> fail ("Could not find key " ++ JSS.unpack label)
    Just x -> parseJSON x

{-# INLINE (.:?) #-}
(.:?) :: FromJSON a => Object -> JSString -> Parser (Maybe a)
obj .:? label = do
  mbX <- objectLookup obj label
  case mbX of
    Nothing -> return Nothing
    Just x -> if js_isNull x
      then return Nothing
      else Just <$> parseJSON x

{-# INLINE (.:!) #-}
(.:!) :: FromJSON a => Object -> JSString -> Parser (Maybe a)
obj .:! label = do
  mbX <- objectLookup obj label
  case mbX of
    Nothing -> return Nothing
    Just x -> Just <$> parseJSON x

{-# INLINE _Object #-}
_Object :: Object -> Value
_Object (Object x) = x

type Pair = (JSString, Value)

{-# INLINE mkObject #-}
mkObject :: Foldable t => t (IO Pair) -> IO Object
mkObject xs0 = do
  val <- js_objectEmpty
  let
    loop = \case
      [] -> return ()
      mpair : xs -> do
        (label, x) <- mpair
        js_objectSet val label x
        loop xs
  loop (toList xs0)
  return (Object val)

foreign import javascript unsafe "$1[$2] = $3" js_objectSet :: Value -> JSString -> Value -> IO ()
foreign import javascript unsafe "$r = {}" js_objectEmpty :: IO Value

{-# INLINE object #-}
object :: Foldable t => t (IO Pair) -> IO Value
object = fmap _Object . mkObject

{-# INLINE (.=) #-}
(.=) :: (ToJSONKey k, ToJSON v) => k -> v -> IO Pair
k .= v = do
  kj <- toJSONKey k
  vj <- toJSON v
  return (kj, vj)

-- running
-- --------------------------------------------------------------------

runParser :: (Value -> Parser a) -> Value -> IO (Either String a)
runParser f v = runEitherT (unParser (f v))

-- From string
-- --------------------------------------------------------------------

parseJSONFromString :: JSString -> (Value -> Parser a) -> IO (Either String a)
parseJSONFromString s f = do
  mbVal :: Either JSException Value <- try (js_jsonParse s)
  runEitherT $ case mbVal of
    Left err -> fail ("couldn't parse json string: " ++ show err)
    Right val -> unParser (f val)

foreign import javascript safe "$r = JSON.parse($1)" js_jsonParse :: JSString -> IO Value

toJSONString :: Value -> IO JSString
toJSONString v = js_jsonStringify(v)

foreign import javascript safe "$r = JSON.stringify($1)" js_jsonStringify :: Value -> IO JSString

-- FromJSON
-- --------------------------------------------------------------------

instance FromJSON Bool where
  {-# INLINE parseJSON #-}
  parseJSON = withBool "Bool" return

instance FromJSON Ordering where
  parseJSON = withString "Ordering" $ \s ->
    case s of
      "LT" -> return LT
      "EQ" -> return EQ
      "GT" -> return GT
      _ -> fail "Parsing Ordering value failed: expected \"LT\", \"EQ\", or \"GT\""

instance FromJSON () where
    parseJSON = withArray "()" $ \arr -> do
      len <- arrayLength arr
      if len > 0
        then fail "Expected an empty array"
        else return ()
    {-# INLINE parseJSON #-}

instance FromJSON Char where
    parseJSON = withString "Char" $ \t ->
                  if JSS.length t == 1
                    then pure $ JSS.head t
                    else fail "Expected a string of length 1"
    {-# INLINE parseJSON #-}

instance FromJSON Int32 where
  parseJSON = withInteger "Int32" return
  {-# INLINE parseJSON #-}

instance FromJSON Int where
  parseJSON = withInteger "Int" return
  {-# INLINE parseJSON #-}

instance FromJSON Double where
  parseJSON = withNumber "Double" return
  {-# INLINE parseJSON #-}

instance FromJSON a => FromJSON (Maybe a) where
  parseJSON v = asum
    [ withNull "Maybe" (return Nothing) v
    , Just <$> parseJSON v
    ]
  {-# INLINE parseJSON #-}

instance FromJSON a => FromJSON (V.Vector a) where
  parseJSON = withArray "Vector" (arrayGenerate parseJSON V.generateM)

-- ToJSON
-- --------------------------------------------------------------------

instance ToJSON Bool where
  {-# INLINE toJSON #-}
  toJSON = return . _Bool

instance ToJSON Ordering where
  toJSON x = return $ _String $ case x of
    EQ -> "EQ"
    LT -> "LT"
    GT -> "GT"

instance ToJSON Double where
  toJSON = return . _Number
  {-# INLINE toJSON #-}

instance ToJSON () where
    toJSON _ = array []
    {-# INLINE toJSON #-}

instance ToJSON Char where
    toJSON ch = return (_String (JSS.pack [ch]))
    {-# INLINE toJSON #-}

instance ToJSON Int32 where
  toJSON = return . _Integer
  {-# INLINE toJSON #-}

instance ToJSON Int where
  toJSON = return . _Integer
  {-# INLINE toJSON #-}

instance ToJSON a => ToJSON (Maybe a) where
  toJSON = \case
    Nothing -> return _Null
    Just x -> toJSON x
  {-# INLINE toJSON #-}

instance ToJSON a => ToJSON (V.Vector a) where
  toJSON x = array =<< traverse toJSON x
  {-# INLINE toJSON #-}