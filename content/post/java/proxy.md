---
title: "Java Proxy - Dynamic Class Creation"
date: 2025-01-31T23:48:46+07:00
categories:
- java
- proxy
tags:
- java
- proxy
keywords:
- proxy
- reflection
#thumbnailImage: //example.com/image.jpg
---

`Proxy` in java allows dynamic creation of class at runtime. 



<!--more-->

A `proxy` class in java is a class created at runtime that implements a specified list of interfaces, known as `proxy interfaces`.
A `proxy instance` is an instance of a proxy class, Each proxy instance has a associated invocation handler object, which implements `InvocationHandler`. A method invocation on a proxy instance through one of its proxy interfaces will be dispatched to the invoke method of the instance's invocation handler.

`ProxyGenerator` is created along with proxy instance to generate target binary class file in memory, then the class is loaded by class loader.

```plantuml

class ProxyGenerator {
    ClassFile CF_CONTEXT
    byte[] generateClassFile()
}

class ProxyMethod {
    void generateMethod(ClassBuilder clb)
}

interface ClassFile {
    byte[] build(...)
}

interface ClassBuilder  {
    ClassBuilder withMethod(...)
}
interface MethodBuilder {
    MethodBuilder withCode(...)
}

interface  CodeBuilder {
    CodeBuilder invokeinterface(invocationHandlerInvoke)
}

ProxyGenerator *-right- ProxyMethod
ProxyGenerator *-down- ClassFile
ClassFile --> ClassBuilder: build
ClassBuilder --> MethodBuilder: build
MethodBuilder --> CodeBuilder: build


```