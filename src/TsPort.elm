module TsPort exposing (..)

import Json.Encode as Encode


type Encoder encodesFrom
    = Encoder (encodesFrom -> Encode.Value) TsType


encoder : Encoder encodesFrom -> (encodesFrom -> Encode.Value)
encoder (Encoder encodeFn tsType_) encodesFrom =
    encodeFn encodesFrom


typeDef : Encoder encodesFrom -> String
typeDef (Encoder encodeFn tsType_) =
    tsTypeToString tsType_


rawType : ObjectBuilder a -> VariantTypeDef
rawType (ObjectBuilder entries) =
    entries
        |> List.map (\( key, encodeFn, tsType_ ) -> ( key, tsType_ ))
        |> KeyValue


type ObjectBuilder encodesFrom
    = ObjectBuilder (List ( String, encodesFrom -> Encode.Value, TsType ))


type TsType
    = String
    | List TsType
    | TypeObject (List ( String, TsType ))
    | Custom (List ( String, VariantTypeDef ))


build : ObjectBuilder encodesFrom
build =
    ObjectBuilder []


property : String -> Encoder encodesFrom -> ObjectBuilder encodesFrom -> ObjectBuilder encodesFrom
property keyName (Encoder encodeFn tsType_) (ObjectBuilder entries) =
    ObjectBuilder
        (( keyName
         , encodeFn
         , tsType_
         )
            :: entries
        )


string : Encoder String
string =
    Encoder Encode.string String


map : (encodesFrom -> value) -> Encoder value -> Encoder encodesFrom
map getter (Encoder encodeFn tsType_) =
    Encoder (\value -> value |> getter |> encodeFn) tsType_


list : Encoder a -> Encoder (List a)
list (Encoder encodeFn tsType_) =
    Encoder
        (\encodesFrom -> Encode.list encodeFn encodesFrom)
        (List tsType_)


custom :
    custom
    -> CustomBuilder custom
custom match =
    CustomBuilder match []


type CustomBuilder match
    = CustomBuilder match (List ( String, VariantTypeDef ))


type VariantTypeDef
    = Positional (List TsType)
    | KeyValue (List ( String, TsType ))


variant0 :
    String
    -> CustomBuilder (Encode.Value -> match)
    -> CustomBuilder match
variant0 variantName (CustomBuilder builder tsTypes_) =
    CustomBuilder
        (builder
            (Encode.object
                [ ( "tag", Encode.string variantName ) ]
            )
        )
        (( variantName, Positional [] ) :: tsTypes_)


variant1 :
    String
    -> Encoder arg1
    -> CustomBuilder ((arg1 -> Encode.Value) -> match)
    -> CustomBuilder match
variant1 variantName (Encoder encoder_ tsType_) (CustomBuilder builder tsTypes) =
    let
        mappedEncoder : arg1 -> Encode.Value
        mappedEncoder arg1 =
            Encode.object
                [ ( "tag", Encode.string variantName )
                , ( "args"
                  , Encode.list identity
                        [ arg1 |> encoder_ ]
                  )
                ]
    in
    CustomBuilder
        (builder mappedEncoder)
        (( variantName, Positional [ tsType_ ] ) :: tsTypes)


objectVariant :
    String
    -> ObjectBuilder arg1
    -> CustomBuilder ((arg1 -> Encode.Value) -> match)
    -> CustomBuilder match
objectVariant variantName (ObjectBuilder entries) (CustomBuilder builder tsTypes) =
    let
        objectTypeDef =
            entries
                |> List.map (\( key, encodeFn, tsType_ ) -> ( key, tsType_ ))

        mappedEncoder : arg1 -> Encode.Value
        mappedEncoder arg1 =
            Encode.object
                (( "tag", Encode.string variantName )
                    :: (entries
                            |> List.map
                                (\( key, encodeFn, tsType_ ) ->
                                    ( key, encodeFn arg1 )
                                )
                       )
                )
    in
    CustomBuilder
        (builder mappedEncoder)
        (( variantName, KeyValue objectTypeDef ) :: tsTypes)


encodeProVariant :
    String
    -> ObjectBuilder arg1
    -> arg1
    -> Encode.Value
encodeProVariant variantName (ObjectBuilder entries) arg1 =
    Encode.object
        (( "tag", Encode.string variantName )
            :: (entries
                    |> List.map
                        (\( key, encodeFn, tsType_ ) ->
                            ( key, encodeFn arg1 )
                        )
               )
        )


type VariantBuilder
    = VariantBuilder


buildCustom : CustomBuilder (match -> Encode.Value) -> Encoder match
buildCustom (CustomBuilder toValue tsTypes_) =
    Encoder toValue (Custom tsTypes_)


toEncoder : ObjectBuilder value -> Encoder value
toEncoder (ObjectBuilder entries) =
    Encoder
        (\encodesFrom ->
            entries
                |> List.map
                    (\( key, encodeFn, tsType_ ) ->
                        ( key
                        , encodeFn encodesFrom
                        )
                    )
                |> Encode.object
        )
        (entries
            |> List.map (\( key, encodeFn, tsType_ ) -> ( key, tsType_ ))
            |> TypeObject
        )


proTypeAnnotation : List ( String, VariantTypeDef ) -> String
proTypeAnnotation entries =
    customTypeDefToString entries


tsTypeToString : TsType -> String
tsTypeToString tsType =
    case tsType of
        String ->
            "string"

        List listType ->
            tsTypeToString listType ++ "[]"

        TypeObject keyTypes ->
            "{ "
                ++ (keyTypes
                        |> List.map
                            (\( key, tsType_ ) ->
                                key ++ " : " ++ tsTypeToString tsType_
                            )
                        |> String.join "; "
                   )
                ++ " }"

        Custom tsTypes_ ->
            customTypeDefToString tsTypes_


customTypeDefToString : List ( String, VariantTypeDef ) -> String
customTypeDefToString tsTypes_ =
    tsTypes_
        |> List.map
            (\( variantName, variantTypes ) ->
                case variantTypes of
                    Positional positionalArgs ->
                        "{ tag : \""
                            ++ variantName
                            ++ "\"; "
                            ++ argsToString positionalArgs
                            ++ " }"

                    KeyValue keyValueArgs ->
                        "{ tag : \""
                            ++ variantName
                            ++ "\"; "
                            ++ keyValueArgsToString keyValueArgs
                            ++ " }"
            )
        |> String.join " | "


keyValueArgsToString : List ( String, TsType ) -> String
keyValueArgsToString keyValueArgs =
    List.map
        (\( key, tsType_ ) ->
            key ++ " : " ++ tsTypeToString tsType_
        )
        keyValueArgs
        |> String.join "; "


argsToString : List TsType -> String
argsToString variantTypes =
    if List.isEmpty variantTypes then
        ""

    else
        "args: [ "
            ++ (List.map
                    (\tsType_ ->
                        tsTypeToString tsType_
                    )
                    variantTypes
                    |> String.join ""
               )
            ++ " ];"
