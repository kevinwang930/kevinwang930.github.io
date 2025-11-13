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
- [Notation](#notation)
- [characters](#characters)
- [String Literals](#string-literals)
- [Identifiers](#identifiers)
- [keyword](#keyword)
- [Variable](#variable)
  - [variable  declaration](#variable-declaration)
    - [short variable declaration](#short-variable-declaration)
- [type](#type)
  - [Array type](#array-type)
  - [struct types](#struct-types)
  - [Pointer type](#pointer-type)
  - [Function type](#function-type)
  - [interface Type](#interface-type)
  - [map type](#map-type)
  - [Channel type](#channel-type)
- [blocks](#blocks)
- [declaraton and scope](#declaraton-and-scope)
    - [Const declaration](#const-declaration)
    - [zero value](#zero-value)
  - [type declaration](#type-declaration)
    - [type definition](#type-definition)
    - [type conversion](#type-conversion)
- [Expressions](#expressions)
  - [Operands](#operands)
    - [Composite Literals](#composite-literals)
  - [Type Assertion](#type-assertion)
  - [Type conversion](#type-conversion-1)
- [statements](#statements)
  - [for statement](#for-statement)
    - [range clause](#range-clause)
  - [if statement](#if-statement)
  - [Switch statement](#switch-statement)
  - [Type Switch](#type-switch)
  - [Select Statement](#select-statement)
- [Assignment](#assignment)


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

# characters
```
newline        = /* the Unicode code point U+000A */ .
unicode_char   = /* an arbitrary Unicode code point except newline */ .
unicode_letter = /* a Unicode code point categorized as "Letter" */ .
unicode_digit  = /* a Unicode code point categorized as "Number, decimal digit" */ .
```
example 
```
"日本語"                                 // UTF-8 input text
`日本語`                                 // UTF-8 input text as a raw literal
"\u65e5\u672c\u8a9e"                    // the explicit Unicode code points
"\U000065e5\U0000672c\U00008a9e"        // the explicit Unicode code points
"\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e"  // the explicit UTF-8 bytes
```

# String Literals

String literals represents a string constant obtained from concatenating a sequence of characters. 
```
string_lit             = raw_string_lit | interpreted_string_lit .
raw_string_lit         = "`" { unicode_char | newline } "`" .
interpreted_string_lit = `"` { unicode_value | byte_value } `"` .
```

# Identifiers

Identifiers name program entities such as variables and types.
```
identifier = letter { letter | unicode_digit } .
```
# keyword
Keywords are reserved and may not be used as identifier.
```
break        default      func         interface    select
case         defer        go           map          struct
chan         else         goto         package      switch
const        fallthrough  if           range        type
continue     for          import       return       var
```

# Variable
Variable is a storage location for a value, the set of permissible values is determined by the variable's type.

## variable  declaration
varaible declaration create one or more variables.

    VarDecl     = "var" ( VarSpec | "(" { VarSpec ";" } ")" ) .
    VarSpec     = IdentifierList ( Type [ "=" ExpressionList ] | "=" ExpressionList ) .

### short variable declaration
a shorthand for regular variable declaration with initializer expression but no types
    ShortVarDecl = IdentifierList ":=" ExpressionList .
    
# type
A type determines a set of values together with operations and methods specific to those values.

    Type      = TypeName [ TypeArgs ] | TypeLit | "(" Type ")" .
    TypeName  = identifier | QualifiedIdent .
    TypeArgs  = "[" TypeList [ "," ] "]" .
    TypeList  = Type { "," Type } .
    TypeLit   = ArrayType | StructType | PointerType | FunctionType | InterfaceType |
                SliceType | MapType | ChannelType .



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
```
ChannelType = ( "chan" | "chan" "<-" | "<-" "chan" ) ElementType .
```


# blocks
A block is possibly empty sequence of declrations and statements within matching brace brackets.

    Block = "{" StatementList "}" .
    StatementList = { Statement ";" } .


# declaraton and scope
    Declaration   = ConstDecl | TypeDecl | VarDecl .
    TopLevelDecl  = Declaration | FunctionDecl | MethodDecl .


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

### type definition

a type definition creates a new , distinct type and binds an identifier to it

    TypeDef = identifier [ TypeParameters ] Type .



### type conversion

```
Conversion = Type "(" Expression [ "," ] ")" .
```

# Expressions
An expression specifies the computation of a value by applying operators and functions to operands.

## Operands
Operands denote the elementary values in an expression. 
```
Operand     = Literal | OperandName [ TypeArgs ] | "(" Expression ")" .
Literal     = BasicLit | CompositeLit | FunctionLit .
BasicLit    = int_lit | float_lit | imaginary_lit | rune_lit | string_lit .
OperandName = identifier | QualifiedIdent .
```

### Composite Literals
Composite literals construct new values for structs, arrays, slices, and maps each time they are evaluated. They consist of the type of the literal followed by a brace-bound list of elements. Each element may optionally be preceded by a corresponding key.
```
CompositeLit = LiteralType LiteralValue .
LiteralType  = StructType | ArrayType | "[" "..." "]" ElementType |
               SliceType | MapType | TypeName [ TypeArgs ] .
LiteralValue = "{" [ ElementList [ "," ] ] "}" .
ElementList  = KeyedElement { "," KeyedElement } .
KeyedElement = [ Key ":" ] Element .
Key          = FieldName | Expression | LiteralValue .
FieldName    = identifier .
Element      = Expression | LiteralValue .
```
## Type Assertion

For an expression x of interface type, but not a type parameter, and a type T, the primary expression
```
x.(T)
v, ok = x.(T)
```
asserts that x is not nil and the value stored in x is of type T
Type assertion can be used in assignment statement

## Type conversion

```
Conversion = Type "(" Expression [ "," ] ")" .
```

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

### range clause
for statement with range clause iterates through all entries of an array, slice, map, string ,  value received from channel, integer values from zero to upper limit, or values passed to an iterators yield function. For each entry it assigns iteration values to corresponding iteration variables if present and then executes the block. 



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


## Type Switch 
Type switch is a special syntax, where type can be used as a value in switch case

## Select Statement
Select statement chooses which of a set of possible send or receive operations will proceed
```
SelectStmt = "select" "{" { CommClause } "}" .
CommClause = CommCase ":" StatementList .
CommCase   = "case" ( SendStmt | RecvStmt ) | "default" .
RecvStmt   = [ ExpressionList "=" | IdentifierList ":=" ] RecvExpr .
RecvExpr   = Expression .
SendStmt = Channel "<-" Expression .
Channel  = Expression .
```

# Assignment

```
Assignment = ExpressionList assign_op ExpressionList .

assign_op = [ add_op | mul_op ] "=" .
```
