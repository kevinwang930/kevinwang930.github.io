---
title: "JAVA Class File and Reflection"
date: 2025-03-30T00:41:18+07:00
categories:
- java
- jvm
tags:
- jvm
- class
keywords:
- class
#thumbnailImage: //example.com/image.jpg
---
This article introduces  Java Class and  Class File format.
<!--more-->

# `Class<T>` is a object
Instances of the class `Class` represents classes and interfaces in running java application.
An enum class is a kind of class.
An Annotation interface is a kind of interface.
The primitive Java types and the keyword `void` are also represented as `Class` object

## class loading
* `BootClassLoader` native bootstrap class loader loads the `java.base` module
* `platformClassLoader` java level class loader loads other java library modules
* `AppClassLoader` loads application level class 

```plantuml


abstract class ClassLoader {
    ClassLoader parent
    Class<?> loadClass(String name)
}
class SecureClassLoader extends ClassLoader
class BuiltinClassLoader extends SecureClassLoader {
    BuiltinClassLoader parent
    URLClassPath ucp
}

class PlatformClassLoader extends BuiltinClassLoader
class AppClassLoader extends BuiltinClassLoader
class BootClassLoader extends BuiltinClassLoader
AppClassLoader -right-> PlatformClassLoader: parent
PlatformClassLoader -right->BootClassLoader : parent




```


## Reflection

Reflection allows programmatic access to information about the fields, methods, and constructors of the loaded classes, and the use of reflected fields, methods and constructors to operate on their underlying counterpart 

`Class` has no public constructor. Instead a `Class` object is constructed automatically by JVM when a class is derived from the bytes of a class file.


`Type` is the common superinterface for all types in the Java programming language. These include raw types, parameterized types, array types, type variables and primitive types.


`Field` provides information about, and dynamic access to , a single field of class or interface.The reflected field may be a class(static) field or an instance field.

A `Method` provides information about, and access to, a single method on a class or interface. The reflected method may be a class method or an instance method (including an abstract method)
```plantuml
interface AnnotatedElement {
    Annotation[] getAnnotations()
}

interface GenericDeclaration extends AnnotatedElement {
    TypeVariable<?>[] getTypeParameters()
}
interface Type {
    String getTypeName()
}
class Class<T> implements GenericDeclaration,Type, AnnotatedElement, Constable {
    Field[] getFields()
    Method[] getMethods()
}
class AccessibleObject implements AnnotatedElement
class Field extends AccessibleObject implements Member {
    Type getGenericType()
}
abstract  class Executable extends AccessibleObject implements Member,GenericDeclaration
class Method extends Executable
Class o-- Field
Class o-- Method
```

# class File 


Compiled code to be executed by JVM is represented using a hardware and os independent binary format, know as Class file format. The class file format precisely defines the representation of a class or interface.

A Class file consists of a stream of 8-bit bytes.

```
u1 unsigned 1 bytes
u2 unsigned 2 bytes
u4 unsigned 4 bytes
```
Tables, consists of zero or more variable sized items, are used in several class file structures.
Array in class file refers to zero or more contiguous fixed-sized items that can be indexed like array.

```
ClassFile {
    u4             magic;
    u2             minor_version;
    u2             major_version;
    u2             constant_pool_count;
    cp_info        constant_pool[constant_pool_count-1];
    u2             access_flags;
    u2             this_class;
    u2             super_class;
    u2             interfaces_count;
    u2             interfaces[interfaces_count];
    u2             fields_count;
    field_info     fields[fields_count];
    u2             methods_count;
    method_info    methods[methods_count];
    u2             attributes_count;
    attribute_info attributes[attributes_count];
}
```
## Constant Pool
 JVM instructions do not rely on runtime layout of classes, interfaces , class instances or arrays. Instead, instructions refer to symbolic information in the constant_pool table.
 ```
 cp_info {
    u1 tag;
    u1 info[];
}
```

Each Entry in constant pool must begin with 1-byte tag indicating the kind of constant denoted by the entry.  The content of info array varies with the value of tag.

| Constant Kind               | Tag |
|-----------------------------|-----|
| CONSTANT_Class              | 7   |
| CONSTANT_Fieldref           | 9   |
| CONSTANT_Methodref          | 10  |
| CONSTANT_InterfaceMethodref | 11  |
| CONSTANT_String             | 8   |
| CONSTANT_Integer            | 3   |
| CONSTANT_Float              | 4   |
| CONSTANT_Long               | 5   |
| CONSTANT_Double             | 6   |
| CONSTANT_NameAndType        | 12  |
| CONSTANT_Utf8               | 1   |
| CONSTANT_MethodHandle       | 15  |
| CONSTANT_MethodType         | 16  |
| CONSTANT_Dynamic            | 17  |
| CONSTANT_InvokeDynamic      | 18  |
| CONSTANT_Module             | 19  |
| CONSTANT_Package            | 20  |


Fields, methods, and interfaces methods represented by similar structures.


`name_and_type_index` must be a valid index into the constant_pool. the entry at that index of constant pool must be a `CONSTANT_NameAndType_info` structure.

```
CONSTANT_Fieldref_info {
    u1 tag;
    u2 class_index;
    u2 name_and_type_index;
}

CONSTANT_Methodref_info {
    u1 tag;
    u2 class_index;
    u2 name_and_type_index;
}

CONSTANT_InterfaceMethodref_info {
    u1 tag;
    u2 class_index;
    u2 name_and_type_index;
}
```

The `CONSTANT_NameAndType_info` structure is used to represent a field or method, without indicating which class or interface type it belongs to .


```
CONSTANT_NameAndType_info {
    u1 tag;
    u2 name_index;
    u2 descriptor_index;
}
```
The `descriptor_index` must be a valid index into the constant_pool, the constant_pool entry at the index must be a `CONSTANT_Utf8_info` structure representing a valid field or method descriptor.

The `CONSTANT_Utf8_info` structure is used to represent constant string values

```
CONSTANT_Utf8_info {
    u1 tag;
    u2 length;
    u1 bytes[length];
}
```

## Fields

Each Field is described by a `field_info` structure.
```
field_info {
    u2             access_flags;
    u2             name_index;
    u2             descriptor_index;
    u2             attributes_count;
    attribute_info attributes[attributes_count];
}
```

## methods
Each method including instance initialization method and the class or interface initialization method is described by `method_info` structure.
```
method_info {
    u2             access_flags;
    u2             name_index;
    u2             descriptor_index;
    u2             attributes_count;
    attribute_info attributes[attributes_count];
}
```

## attributes

Attributes are used in the Class File ,field_info,method_info,Code_attribute structures and so on.
```
attribute_info {
    u2 attribute_name_index;
    u4 attribute_length;
    u1 info[attribute_length];
}
```

Critical attributes 
- ConstantValue
- Code
- StackMapTable
- BootstrapMethods
- NestHost
- NestMembers
- PermittedSubclasses

other attributes
- Exceptions
- InnerClasses
- EnclosingMethod
- Synthetic
- Signature
- Record
- SourceFile
- LineNumberTable
- LocalVariableTable
- LocalVariableTypeTable
- SourceDebugExtension
- Deprecated
- RuntimeVisibleAnnotations
- RuntimeInvisibleAnnotations
- RuntimeVisibleParameterAnnotations
- RuntimeInvisibleParameterAnnotations
- RuntimeVisibleTypeAnnotations
- RuntimeInvisibleTypeAnnotations
- AnnotationDefault
- MethodParameters
- Module
- ModulePackages
- ModuleMainClass

### Signature attributes

Signatures encode declarations written in Java that uses types outside the type system of JVM . They support reflection and debugging.

The field signature preserves the actual type parameter which  used in Spring framework facilitating autowire type matching. 
```
class Test {
    private List<String> stringList;
}
```


## reference


[JVM Specification 23 Class File format](https://docs.oracle.com/javase/specs/jvms/se23/html/jvms-4.html#jvms-4.4.1)