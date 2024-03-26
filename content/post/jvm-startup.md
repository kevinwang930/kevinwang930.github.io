---
title: "JVM 启动流程"
date: 2024-03-20T00:46:56+08:00
categories:
- jvm
tags:
- jvm
keywords:
- tech
#thumbnailImage: //example.com/image.jpg
---

本文记录jvm启动流程
<!--more-->


# 启动概述


```plantuml
main.c-->main.c:main(int argc, char **argv)
main.c-->java.c:JLI_Launch(...)
java.c-->java_md.c:CreateExecutionEnvironment
java.c-->java_md.c:LoadJavaVM
java.c-->java_md.c:JVMInit
java_md.c-->java.c:ContinueInNewThread
java.c-->java_md.c:CallJavaMainInNewThread
java_md.c-->pthread:pthread_create
pthread-->java.c:JavaMain
java.c-->java.c:InitializeJVM
java.c-->java.c:LoadMainClass
java.c-->java_md_common.c:CreateApplicationArgs
java.c-->java.c:invokeStaticMainWithArgs
java.c-->JNIEnv:GetStaticMethodID
JNIEnv-->jni.cpp:jni_GetStaticMethodID
java.c-->JNIEnv:CallStaticVoidMethod
JNIEnv-->jni.cpp:jni_CallStaticVoidMethod
jni.cpp-->jni.cpp:jni_invoke_static
jni.cpp-->javaCalls.cpp:call
javaCalls.cpp-->javaCalls.cpp:call_helper

```

# jvm调用java方法

jvm 由 c++ 编写， 调用java方法时借用函数指针的方式，调用interpreter对应函数入口