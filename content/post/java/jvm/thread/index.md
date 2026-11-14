---
title: "JVM Thread internals"
date: 2024-08-07T12:59:29+08:00
categories:
- java
- jvm
tags:
- jvm
- thread
keywords:
- jvm
- thread
#thumbnailImage: //example.com/image.jpg
---
本文记录jvm线程内部实现
<!--more-->


```plantuml

package java {
    class JAVA_Thread {
        long tid
        String name
        boolean interrupted
        ClassLoader contextClassLoader
        FieldHolder holder
        ThreadLocalMap threadLocals
        ThreadLocalMap inheritableThreadLocals
        Object scopedValueBindings
        Continuation cont
    }

    class FieldHolder {
        ThreadGroup group;
         Runnable task;
         long stackSize;
         int priority;
         boolean daemon;
         int threadStatus;
    }
    JAVA_Thread *-- FieldHolder
}

package jdk {
class CHeapObj {}
class ThreadShadow extends CHeapObj {
    oop _pending_exception
    const char* _exception_file
    int         _exception_line
}

class Thread extends ThreadShadow {
    static Thread* _thr_current
    GCThreadLocalData _gc_data
    HandleMark* _last_handle_mark
    ThreadLocalAllocBuffer _tlab
    jlong _allocated_bytes
    OSThread* _osthread
    address          _stack_base
    size_t           _stack_size
    ParkEvent * volatile _ParkEvent
} 

class JavaThread extends Thread {
    OopHandle      _threadObj
    ThreadFunction _entry_point
    JavaThreadState _thread_state
    LockStack _lock_stack
}
}


JavaThread o-right- JAVA_Thread

```





#  Memory Model
Java Memory Model(JMM) defines the allowable behavior of multi threaded programs.

## Actions

An inter-thread action is an action performed by one thread that can be detected or directly influenced by another thread.
* Read 
* Write
* Synchronization actions
  * volatile read
  * volatile write
  * Lock. Locking a monitor
  * unlock. Unlocking a monitor
  * The first and last action of a thread.
  * Actions that start or detect that a thread has terminated.


## Synchronization order
* unlock action on monitor m synchronized-with all subsequent lock actions on m
* write to a volatile variable v synchronizes-with all subsequent read of v by any thread.
* An action that starts a thread synchronizes-with the first action in the thread it starts.
* The write of the default value to each variable synchronizes-with the first action in every thread.
* The final action in a thread T1 synchronizes-with any action in another thread T2 that detects that T1 has terminated.
* if Thread T1 interrupts T2, the interrupt by T1 synchronizes-with any point where any other thread determines that T2 has been interrupted.

The source of a synchronizes-with edge is called a release, and the destination is called an acquire.


## Happens-before Order

* If x and y are actions of the same thread, and x comes before y in programming order, then `hb(x,y)`
* There is a happens-before edge from the end of a constructor of an object to the start of a finalizer for that object.
* If action x synchronizes-with a following action y, then `hb(x,y)`
* If `hb(x,y)` and `hb(y,z)`, then `hb(x,z)`

## Memory Access Ordering Model

* `LoadLoad`    barriers between load
* `StoreStore`  barriers between store
* `LoadStore`   barriers between load and store
* `StoreLoad`   barriers between store and load
```
 LoadLoad Load1(s); LoadLoad; Load2 
 StoreStore: Store1(s); StoreStore; Store2
 LoadStore:  Load1(s); LoadStore; Store2
 StoreLoad:  Store1(s); StoreLoad; Load2
```


in X86 system using `lock` prefix assembly to achieve fence.

```
inline void OrderAccess::fence() {
   // always use locked addl since mfence is sometimes expensive
#ifdef AMD64
  __asm__ volatile ("lock; addl $0,0(%%rsp)" : : : "cc", "memory");
#else
  __asm__ volatile ("lock; addl $0,0(%%esp)" : : : "cc", "memory");
#endif
  compiler_barrier();
}
```