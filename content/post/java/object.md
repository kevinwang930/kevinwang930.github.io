---
title: "java对象的内存实现"
date: 2024-04-22T18:11:29+08:00
categories:
- java
- object
tags:
- java
- object
keywords:
- java object
#thumbnailImage: //example.com/image.jpg
---
本文记录java object 内存实现
<!--more-->


oopDesc is the class representation of java object in jvm, it has 2 fields :
    1. markword  
    2. class pointer 


Markword describes the header of the object.
It contains 3 useful infos of the object.
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
```


 in 64 bit markword:
```
unused:25 hash:31 -->| unused_gap:1  age:4  unused_gap:1  lock:2 (normal object)


```
```plantuml
class oopDesc {
    volatile markWord _mark
    Klass*      _klass
}
class markword {
    hash
    age
    lock
}


oopDesc --> markword: header 
```

