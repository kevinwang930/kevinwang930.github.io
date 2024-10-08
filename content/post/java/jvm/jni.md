---
title: "Java native interface"
date: 2024-08-11T15:58:33+08:00
categories:
- java
- jvm
tags:
- jvm
- jni
keywords:
- jni
#thumbnailImage: //example.com/image.jpg
---
This article describes Java native interface
<!--more-->

Java native Interface(JNI) is a native programming interface that allows java code that runs inside a Java Virtual Machine(VM) to interoperate with applications and libraries written in other programming languages. such as C, C++ , an assembly.

# JNI load

# bytecode



#  example

## JNI header

`javac` can be used to compile java class, use `-h` to generate JNI header.

```
"$JAVA_HOME"/bin/javac -h c -d target Simple.java
```


A example Simple.java

```
package kevin.project.jni;


public class Simple {

    static {
        System.loadLibrary("simple");
    }


    static native int plus(int a, int b);


    public static void main(String[] args) {
        System.out.println("start main");
        System.out.println(plus(1, 2));
    }
}
```

Generated Header

```
/* DO NOT EDIT THIS FILE - it is machine generated */
#include <jni.h>
/* Header for class kevin_project_jni_Simple */

#ifndef _Included_kevin_project_jni_Simple
#define _Included_kevin_project_jni_Simple
#ifdef __cplusplus
extern "C" {
#endif
/*
 * Class:     kevin_project_jni_Simple
 * Method:    plus
 * Signature: (II)I
 */
JNIEXPORT jint JNICALL Java_kevin_project_jni_Simple_plus
  (JNIEnv *, jclass, jint, jint);

#ifdef __cplusplus
}
#endif
#endif

```

Cpp implementation
```
/* DO NOT EDIT THIS FILE - it is machine generated */
#include <jni.h>
#include <stdio.h>
/* Header for class kevin_project_jni_Simple */
#include "kevin_project_jni_Simple.h"
/*
 * Class:     kevin_project_jni_Simple
 * Method:    plus
 * Signature: (II)I
 */
JNIEXPORT jint JNICALL Java_kevin_project_jni_Simple_plus
  (JNIEnv *env, jclass obj, jint a, jint b) {
  printf ("inside c code\n");
  return a + b;
}

```

## JNI Shared library
native C++ code can be compiled to shared library, and loaded into jvm dynamically.
When compile JNI shared library, JNI headers needs to be included.
```
cc -g -shared -fpic -I${JAVA_HOME}/include -I${JAVA_HOME}/include/darwin c/kevin_project_jni_Simple.c -o  lib/libSimple.dylib
```

## load JNI shared library

when start jvm, specify `library.path` to the generated shared library

```
"$JAVA_HOME"/bin/java -Djava.library.path="$LD_LIBRARY_PATH":./lib -cp target kevin.project.jni.Simple
```
# Reference

[JNICookbook](https://github.com/mkowsiak/jnicookbook)

<!--more-->
