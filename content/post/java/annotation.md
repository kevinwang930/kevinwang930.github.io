---
title: "JAVA Annotation"
date: 2025-02-25T15:03:30+07:00
categories:
- java
tags:
- java
- annotation
keywords:
- annotation
#thumbnailImage: //example.com/image.jpg
---
Annotation in java  is a marker which associates information with a program element, but has no effect at runtime.
<!--more-->


# Annotation Interfaces
An annotation interface is a specialized kind of interface, precedes the keyword `interface` by sign `@`
* annotation interface is never generic
* the direct superinterface type of annotation interface is always `java.lang.annotation.Annotation`


## Annotation Interface Elements
Element declaration:
```
{AnnotationInterfaceElementModifier} UnannType Identifier ( ) [Dims] [DefaultValue] ;

@interface RequestForEnhancement {
    int    id();       // No default - must be specified in 
                       // each annotation
    String synopsis(); // No default - must be specified in 
                       // each annotation
    String engineer()  default "[unassigned]";
    String date()      default "[unimplemented]";
    String[] targets() default {};
}
```

# Annotation 
An annotation denotes a specific instance of an annotation interface and usually provides values for the element of that interface.


## Normal Annotation 
An normal annotation specifies the name of an annotation interface and optionally a list of comma separated element-value pairs.Each pair contains element value that is associated with the element of the annotation interface.
```
NormalAnnotation:
    @ TypeName ( [ElementValuePairList] )
ElementValuePairList:
    ElementValuePair {, ElementValuePair}
ElementValuePair:
    Identifier = ElementValue
ElementValue:
    ConditionalExpression
    ElementValueArrayInitializer
    Annotation
ElementValueArrayInitializer:
    { [ElementValueList] [,] }
ElementValueList:
    ElementValue {, ElementValue}
```

## Marker Annotation
An marker annotation is a shorthand designed for use with marker annotation interfaces.
```
MarkerAnnotation:
@ TypeName

shorthand for 

@TypeName()
```

## Single Element Annotation
Single element annotation is a shorthand designed for use with single-element annotation interfaces

```
SingleElementAnnotation:
@ TypeName ( ElementValue )

short hand for

@TypeName(value = ElementValue)
```


# Annotation Usage
Annotations have a number of usages, among them : 
* Information for compiler - used by compiler to detect errors and suppress warnings.
* Compile-time and deployment-time processing - Software tools can process annotation information to generate code, XML files and so forth.
* Runtime processing - Some annotations are available to be examined at runtime.



