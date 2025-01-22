---
title: "Spring Expression Language"
date: 2025-01-22T21:09:34+07:00
categories:
- java
- spring
tags:
- spring
- spel
keywords:
- spel
#thumbnailImage: //example.com/image.jpg
---
Spring Expression Language ("SpEL for short") is a powerful expression language that support querying and manipulating an object graph at runtime.
<!--more-->

# Language Reference
The expression language supports the following functionality:

* Literal expressions
* Accessing properties, arrays, lists, and maps
* Inline lists
* Inline maps
* Array construction
* Relational operators
* Regular expressions
* Logical operators
* String operators
* Mathematical operators
* Assignment
* Type expressions
* Method invocation
* Constructor invocation
* Variables
* User-defined functions
* Bean references
* Ternary, Elvis, and safe-navigation operators
* Collection projection
* Collection selection
* Templated expressions

## Literal

* String delimited by `'` or `"`
* Number 
  * Integer `int` or `long`
  * Hexadecimal `int` or `long`
  * Real `float` or `double`
* Boolean `true` or `false`
* Null `null`

## property
Using a period (`.`) to indicate a nested property value.
```
birthdate.year + 1990
```
## Array and collection Index
Using square bracket notation to index array or collection
String can also be regarded as a character array thus be indexed.
Map can also be indexed using key within square bracket.
Object can also be indexed by specifying the name of the property within square brackets. 
```
inventions[3].name[7]
```

## Inline List
List can be expressed using `{}` notation
```
"{1,2,3,4}"
"{{1,2},{3,4}}"
```

## Inline Map
```
"{key:value}"
"{name: {first:'Nicola',last:'Tesla'},dob: {day:10,month:11,year:1888}}"
```
## Array Construction

**Spring does not support Array construction by now**
```
"new type[size]"
"new int[] {1,2,3,4}"
```

## Methods
Method can be invoked using typical Java programming syntax
```
// string literal, evaluates to "bc"
String bc = parser.parseExpression("'abc'.substring(1, 3)").getValue(String.class);

// evaluates to true
boolean isMember = parser.parseExpression("isMember('Mihajlo Pupin')").getValue(
		societyContext, Boolean.class);
```

## Operators
operators have symbolic notation and textual notation


* Relational Operators 
```
lt <
eq ==
ge >=
```
* Logical Operators
```
and &&
or || 
not !
```
* String Operators
  * concatenation (`+`)
  * subtraction (`-`) 
  * repeat (`*`)
```
"'d'-3"
"'abc'*2"
```
* Mathematical Operators
  * addition (+)
  * increment (++)
  * exponential power (^)
  * with textual equivalent 
    * div /
    * mod %

## Types
`T` operator to specify an instance of `java.util.class` type
```
"T(java.util.Date)"
```

## Constructor
`new` operator can be used to invoke constructors
```
"new org.spring.samples.spel.inventor.Inventor('Albert Einstein', 'German')"
```

## variable
Variable can be referenced by using `#variableName` notation
`#this` refers to current evaluation object
`#root` always refers to the root

## Bean resolver
`@` symbol for prefix for a bean
`&` symbol as prefix for a factory bean

## Ternary Operator
Elvis Operator can be used to shorten ternary operator
```
"conditon ? true : false"
"name?:'Unknown'"
@Value("#{systemProperties['pop3.port'] ?: 25}")
```

## Safe navigation Operator
```
ExpressionParser parser = new SpelExpressionParser();
EvaluationContext context = SimpleEvaluationContext.forReadOnlyDataBinding().build();

Inventor tesla = new Inventor("Nikola Tesla", "Serbian");
tesla.setPlaceOfBirth(new PlaceOfBirth("Smiljan"));

// evaluates to "Smiljan"
String city = parser.parseExpression("placeOfBirth?.city")
		.getValue(context, tesla, String.class);

tesla.setPlaceOfBirth(null);

// evaluates to null - does not throw NullPointerException
city = parser.parseExpression("placeOfBirth?.city")
		.getValue(context, tesla, String.class);
```

## Collection Selection 
```
.?[selectionExpression]
List<Inventor> list = (List<Inventor>) parser.parseExpression(
		"members.?[nationality == 'Serbian']").getValue(societyContext);
```

## Collection Projection

```
// evaluates to ["Smiljan", "Idvor"]
List placesOfBirth = parser.parseExpression("members.![placeOfBirth.city]")
		.getValue(societyContext, List.class);
```

## Expression Templating
Expression templating allow mixing literal text with one or more evaluation blocks.
The common practice for delimit evaluation blocks is `#{ }`
```
@Value("#{systemProperties['pop3.port'] ?: 25}")
```