---
title: "java对象的内存实现"
date: 2024-04-22T18:11:29+08:00
categories:
- java
- jvm
tags:
- jvm
- object
keywords:
- jvm object
#thumbnailImage: //example.com/image.jpg
---
本文记录jvm 对象内部实现
<!--more-->

# oopDesc
oopDesc is the class representation of java object in jvm, it has 2 fields :
    1. markword  
    2. class pointer 

```plantuml
class oopDesc {
    volatile markWord _mark
    Klass*      _klass
}
class markword {
    uintptr_t _value
}

class Handle {
    oop* _handle
}


Handle --> oopDesc
oopDesc -right-> markword: header 
```
Markword describes the header of the object.


Bit-format of an object header in  in 64 bit:
```
unused:25 hash:31 -->| unused_gap:1  age:4  unused_gap:1  lock:2 (normal object)


```
1. hash  contains the identity hash value. 
2. 2 lock bits:
  - the two lock bits are used to describe three states: locked/unlocked and monitor.
```
    [ptr             | 00]  locked             ptr points to real header on stack (stack-locking in use)
    [header          | 00]  locked             locked regular object header (fast-locking in use)
    [header          | 01]  unlocked           regular object header
    [ptr             | 10]  monitor            inflated lock (header is swapped out)
    [ptr             | 11]  marked             used to mark an object
    [0 ............ 0| 00]  inflating          inflation in progress (stack-locking in use)


We assume that stack/thread pointers have the lowest 2 bits cleared.

inflating is a distinguished markword value of all zeros that is used when inflating an existing stack-lock into an ObjectMonitor
```








