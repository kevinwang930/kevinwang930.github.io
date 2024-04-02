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





# type
A type determines a set of values together with operations and methods specific to those values.
    Type      = TypeName [ TypeArgs ] | TypeLit | "(" Type ")" .
    TypeName  = identifier | QualifiedIdent .
    TypeArgs  = "[" TypeList [ "," ] "]" .
    TypeList  = Type { "," Type } .
    TypeLit   = ArrayType | StructType | PointerType | FunctionType | InterfaceType |
                SliceType | MapType | ChannelType .

a type definition creates a new , distinct type and binds an identifier to it

    TypeDef = identifier [ TypeParameters ] Type .

## Array type
    ArrayType   = "[" ArrayLength "]" ElementType .
    ArrayLength = Expression .
    ElementType = Type .

## struct types
A struct is a sequence of named elements, called fields, each of which has a name and a type.
    StructType    = "struct" "{" { FieldDecl ";" } "}" .
    FieldDecl     = (IdentifierList Type | EmbeddedField) [ Tag ] .
    EmbeddedField = [ "*" ] TypeName [ TypeArgs ] .
    Tag           = string_lit .

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



# blocks
A block is possibly empty sequence of declrations and statements within matching brace brackets.
    Block = "{" StatementList "}" .
    StatementList = { Statement ";" } .


# declaraton and scope
    Declaration   = ConstDecl | TypeDecl | VarDecl .
    TopLevelDecl  = Declaration | FunctionDecl | MethodDecl .

## variable  declration
varaible declaration create one or more variables.

    VarDecl     = "var" ( VarSpec | "(" { VarSpec ";" } ")" ) .
    VarSpec     = IdentifierList ( Type [ "=" ExpressionList ] | "=" ExpressionList ) .

### short variable declaration

    ShortVarDecl = IdentifierList ":=" ExpressionList .
### Const declaration
    ConstDecl      = "const" ( ConstSpec | "(" { ConstSpec ";" } ")" ) .
    ConstSpec      = IdentifierList [ [ Type ] "=" ExpressionList ] .
    IdentifierList = identifier { "," identifier } .
    ExpressionList = Expression { "," Expression } .
### zero value
Variables declared without an explicit initial value are given their zero value.
1. 0 for numeric types
2. false for boolean
3. "" for string



## type declaration
type declaration binds an identifier, the type name to a type

    TypeDecl = "type" ( TypeSpec | "(" { TypeSpec ";" } ")" ) .
    TypeSpec = AliasDecl | TypeDef .
    AliasDecl = identifier "=" Type .


# Expressions
An expression specifies the computation of a value by applying operators and functions to operands.



# statements
Statement control execution.

    Statement =
        Declaration | LabeledStmt | SimpleStmt |
        GoStmt | ReturnStmt | BreakStmt | ContinueStmt | GotoStmt |
        FallthroughStmt | Block | IfStmt | SwitchStmt | SelectStmt | ForStmt |
        DeferStmt .

    SimpleStmt = EmptyStmt | ExpressionStmt | SendStmt | IncDecStmt | Assignment | ShortVarDecl .
## for statement

    ForStmt = "for" [ Condition | ForClause | RangeClause ] Block .
    Condition = Expression .
    ForClause = [ InitStmt ] ";" [ Condition ] ";" [ PostStmt ] .
    InitStmt = SimpleStmt .
    PostStmt = SimpleStmt .
    RangeClause = [ ExpressionList "=" | IdentifierList ":=" ] "range" Expression .

## if statement
    IfStmt = "if" [ SimpleStmt ";" ] Expression Block [ "else" ( IfStmt | Block ) ] .

## Switch statement
    SwitchStmt = ExprSwitchStmt | TypeSwitchStmt .
    ExprSwitchStmt = "switch" [ SimpleStmt ";" ] [ Expression ] "{" { ExprCaseClause } "}" .
    ExprCaseClause = ExprSwitchCase ":" StatementList .
    ExprSwitchCase = "case" ExpressionList | "default" .

    TypeSwitchStmt  = "switch" [ SimpleStmt ";" ] TypeSwitchGuard "{" { TypeCaseClause } "}" .
    TypeSwitchGuard = [ identifier ":=" ] PrimaryExpr "." "(" "type" ")" .
    TypeCaseClause  = TypeSwitchCase ":" StatementList .
    TypeSwitchCase  = "case" TypeList | "default" .


# Assignment

```
Assignment = ExpressionList assign_op ExpressionList .

assign_op = [ add_op | mul_op ] "=" .
```
