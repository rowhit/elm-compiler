module AST.Variable where

import Control.Applicative ((<$>), (<*>))
import Data.Binary
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import Text.PrettyPrint as P

import qualified AST.Helpers as Help
import qualified Reporting.PrettyPrint as P


-- VARIABLES

newtype Raw = Raw String
    deriving (Eq, Ord, Show)


data Home
    = BuiltIn
    | Module [String]
    | Local
    deriving (Eq, Ord, Show)


data Canonical = Canonical
    { home :: !Home
    , name :: !String
    }
    deriving (Eq, Ord, Show)


local :: String -> Canonical
local x = Canonical Local x


builtin :: String -> Canonical
builtin x = Canonical BuiltIn x


fromModule :: [String] -> String -> Canonical
fromModule home name =
    Canonical (Module home) name


-- VARIABLE RECOGNIZERS

is :: [String] -> String -> Canonical -> Bool
is home name var =
    var == Canonical (Module home) name


isJson :: Canonical -> Bool
isJson =
    is ["Json", "Encode"] "Value"


isMaybe :: Canonical -> Bool
isMaybe =
    is ["Maybe"] "Maybe"

isArray :: Canonical -> Bool
isArray =
    is ["Array"] "Array"


isTask :: Canonical -> Bool
isTask =
    is ["Task"] "Task"


isSignal :: Canonical -> Bool
isSignal =
    is ["Signal"] "Signal"


isList :: Canonical -> Bool
isList v =
    v == Canonical BuiltIn "List"


isTuple :: Canonical -> Bool
isTuple v =
    case v of
      Canonical BuiltIn name -> Help.isTuple name
      _ -> False


isPrimitive :: Canonical -> Bool
isPrimitive v =
    case v of
      Canonical BuiltIn name ->
          name `elem` ["Int","Float","String","Bool"]
      _ ->
          False


isPrim :: String -> Canonical -> Bool
isPrim prim v =
    case v of
      Canonical BuiltIn name -> name == prim
      _ -> False


isText :: Canonical -> Bool
isText =
    is ["Text"] "Text"


-- VARIABLE TO STRING

class ToString a where
  toString :: a -> String


instance ToString Raw where
  toString (Raw name) =
      name


instance ToString Canonical where
  toString (Canonical home name) =
      case home of
        BuiltIn -> name
        Module path -> List.intercalate "." (path ++ [name])
        Local -> name


-- LISTINGS

-- | A listing of values. Something like (a,b,c) or (..) or (a,b,..)
data Listing a = Listing
    { _explicits :: [a]
    , _open :: Bool
    }
    deriving (Eq, Ord, Show)


openListing :: Listing a
openListing =
    Listing [] True


closedListing :: Listing a
closedListing =
    Listing [] False


listing :: [a] -> Listing a
listing xs =
    Listing xs False


-- | A value that can be imported or exported
data Value
    = Value !String
    | Alias !String
    | Union !String !(Listing String)
    deriving (Eq, Ord, Show)


-- CATEGORIZING VALUES

getValues :: [Value] -> [String]
getValues values =
  Maybe.mapMaybe getValue values


getValue :: Value -> Maybe String
getValue value =
  case value of
    Value name -> Just name
    Alias _ -> Nothing
    Union _ _ -> Nothing


getAliases :: [Value] -> [String]
getAliases values =
  Maybe.mapMaybe getAlias values


getAlias :: Value -> Maybe String
getAlias value =
  case value of
    Value _-> Nothing
    Alias name -> Just name
    Union _ _ -> Nothing


getUnions :: [Value] -> [(String, Listing String)]
getUnions values =
  Maybe.mapMaybe getUnion values


getUnion :: Value -> Maybe (String, Listing String)
getUnion value =
  case value of
    Value _ -> Nothing
    Alias _ -> Nothing
    Union name ctors -> Just (name, ctors)


-- PRETTY VARIABLES

instance P.Pretty Raw where
  pretty _ (Raw name) =
      if Help.isOp name
        then P.parens (P.text name)
        else P.text name


instance P.Pretty Canonical where
  pretty _ var =
      P.text (toString var)


instance P.Pretty a => P.Pretty (Listing a) where
  pretty _ (Listing explicits open) =
      let dots = [if open then P.text ".." else P.empty]
      in
          P.parens (P.commaCat (map (P.pretty False) explicits ++ dots))


instance P.Pretty Value where
  pretty _ portable =
    case portable of
      Value name ->
          P.text name

      Alias name ->
          P.text name

      Union name ctors ->
          P.text name <> P.pretty False ctors


-- BINARY SERIALIZATION

instance Binary Canonical where
    put (Canonical home name) =
        case home of
          BuiltIn ->
              putWord8 0 >> put name

          Module path ->
              putWord8 1 >> put path >> put name

          Local ->
              putWord8 2 >> put name

    get =
      do  tag <- getWord8
          case tag of
            0 -> Canonical BuiltIn <$> get
            1 -> Canonical . Module <$> get <*> get
            2 -> Canonical Local <$> get
            _ -> error "Unexpected tag when deserializing canonical variable"


instance Binary Value where
    put portable =
        case portable of
          Value name ->
              putWord8 0 >> put name

          Alias name ->
              putWord8 1 >> put name

          Union name ctors ->
              putWord8 2 >> put name >> put ctors

    get =
      do  tag <- getWord8
          case tag of
            0 -> Value <$> get
            1 -> Alias <$> get
            2 -> Union <$> get <*> get
            _ -> error "Error reading valid import/export information from serialized string"


instance (Binary a) => Binary (Listing a) where
    put (Listing explicits open) =
        put explicits >> put open

    get = Listing <$> get <*> get
