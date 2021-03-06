{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE JavaScriptFFI #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module JavaScript.JSValJSON
  ( Value
  , Object
  , Array

  , Parser
  , runParser
  , parseJSONFromString
  , toJSONString

  , FromJSON(..)
  , ToJSON(..)
  , FromJSONKey(..)
  , ToJSONKey(..)

  , withNull
  , _Null
  , withInteger
  , _Integer
  , integralIsRepresentable
  , withNumber
  , _Number
  , withBool
  , _Bool
  , withString
  , _String
  , withArray
  , withEmptyArray
  , arrayGenerate
  , arrayToList
  , arrayLength
  , arrayUnsafeIndex
  , mkArray
  , _Array
  , array
  , withObject
  , ObjectCursor
  , objectCursorNew
  , objectCursorNext
  , objectLookup
  , objectLookup_
  , objectToList
  , (.:)
  , (.:?)
  , (.:!)
  , _Object
  , mkObject
  , object
  , (.=)
  ) where

import JavaScript.JSValJSON.Internal
