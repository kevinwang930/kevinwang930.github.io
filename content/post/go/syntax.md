---
title: "go Syntax"
date: 2024-03-31T20:48:33+08:00
categories:
- go
tags:
- go
- syntax
keywords:
- go
#thumbnailImage: //example.com/image.jpg
---
本文记录go 语法
<!--more-->


[go语法文档](https://go.dev/ref/spec#Assignment_statements)

The syntax is specified using writh syntax notation
# Notation
```
Syntax      = { Production } .
Production  = production_name "=" [ Expression ] "." .
Expression  = Term { "|" Term } .
Term        = Factor { Factor } .
Factor      = production_name | token [ "…" token ] | Group | Option | Repetition .
Group       = "(" Expression ")" .
Option      = "[" Expression "]" .
Repetition  = "{" Expression "}" .
```
1. the equal sign indicates a production. the element on the left is defined to be the combination of elements on the right. A production is terminated by a full stop(period).

2. repetition is denoted by curly brackets.
3. optionality is expressed by square brackets.
4. Parentheses serve for groupings
5. productions are expressions constructed from terms and the following operators
    ```   
    |   alternation
    ()  grouping
    []  option (0 or 1 times)
    {}  repetition (0 to n times)
    ```
# source code

## characters
```
newline        = /* the Unicode code point U+000A */ .
unicode_char   = /* an arbitrary Unicode code point except newline */ .
unicode_letter = /* a Unicode code point categorized as "Letter" */ .
unicode_digit  = /* a Unicode code point categorized as "Number, decimal digit" */ .
```

# variable  declration
varaible declaration create one or more variables.

    VarDecl     = "var" ( VarSpec | "(" { VarSpec ";" } ")" ) .
    VarSpec     = IdentifierList ( Type [ "=" ExpressionList ] | "=" ExpressionList ) .

# type

a type definition creates a new , distinct type and binds an identifier to it

    TypeDef = identifier [ TypeParameters ] Type .

## Array type
    ArrayType   = "[" ArrayLength "]" ElementType .
    ArrayLength = Expression .
    ElementType = Type .

## Pointer type
    PointerType = "*" BaseType .
    BaseType    = Type .

## Function type
    FunctionType   = "func" Signature .
    Signature      = Parameters [ Result ] .
    Result         = Parameters | Type .
    Parameters     = "(" [ ParameterList [ "," ] ] ")" .
    ParameterList  = ParameterDecl { "," ParameterDecl } .
    ParameterDecl  = [ IdentifierList ] [ "..." ] Type .

## interface Type
    InterfaceType  = "interface" "{" { InterfaceElem ";" } "}" .
    InterfaceElem  = MethodElem | TypeElem .
    MethodElem     = MethodName Signature .
    MethodName     = identifier .
    TypeElem       = TypeTerm { "|" TypeTerm } .
    TypeTerm       = Type | UnderlyingType .
    UnderlyingType = "~" Type .

## map type
unordered group of elements of one type

    MapType     = "map" "[" KeyType "]" ElementType .
    KeyType     = Type .

## Channel type
A Channel provides a mechanism for concurrently executing functions to communicate by sending and reciving values of s specified element type
    ChannelType = ( "chan" | "chan" "<-" | "<-" "chan" ) ElementType .


# declaraton and scope
    Declaration   = ConstDecl | TypeDecl | VarDecl .
    TopLevelDecl  = Declaration | FunctionDecl | MethodDecl .
## Const declaration
    ConstDecl      = "const" ( ConstSpec | "(" { ConstSpec ";" } ")" ) .
    ConstSpec      = IdentifierList [ [ Type ] "=" ExpressionList ] .
    IdentifierList = identifier { "," identifier } .
    ExpressionList = Expression { "," Expression } .
## type declaration
type declaration binds an identifier, the type name to a type

    TypeDecl = "type" ( TypeSpec | "(" { TypeSpec ";" } ")" ) .
    TypeSpec = AliasDecl | TypeDef .
    AliasDecl = identifier "=" Type .


# Assignment

```
Assignment = ExpressionList assign_op ExpressionList .

assign_op = [ add_op | mul_op ] "=" .
```
