---
title: "java concurrency - Synchronizer Framework"
date: 2024-04-06T17:00:29+08:00
categories:
- java
- synchronizer
tags:
- synchronizer
- concurrency
keywords:
- synchronizer
#thumbnailImage: //example.com/image.jpg
---
本文记录 java AbstractQueuedSynchronizer (AQS) 的设计与实现
<!--more-->

# Requirement
Synchronizers possess two kinds of methods: 
1. acquire operation blocks the calling thread until the synchronization state allows it to proceed.
2. release operation changes synchronization state ina way that may allow one or more blocked threads to unblock.

Each synchronizer supports:
1. nonblocking synchronization attempts as well as blocking versions. 
2. Optional timeouts, so applications can give up waiting.
3. Cancellability via interruption, usually separated into one version of acquire that is cancellable, and one that is not.


Synchronizers may vary according to whether they manage only exclusive states:
1. only one thread at a time may continue past a possible blocking point
2. shared states in which multiple threads can at least sometimes proceed.

`java.util.concurrent` package also defines interface `Condition`, supporting monitor-style await/signal operations that may be associated with exclusive Lock Classes

## Performance

Primary performance goal is scalability: the overhead required to pass a synchronization point should be constant no matter how may threads are trying to do so. However this must be balanced against resource considerations, including:
1. total cpu time requirements
2. memory traffic
3. thread scheduling overhead

# Design and Implementation
The ideas between synchronizer are straightforward.

```
acquire:
while (synchronization state does not allow acquire) {
    enqueue current thread if not already queued
    possibly block current thread
}   dequeue current thread if it was queued

release:
if (state permit a blocked thread to acquire)
    unblock one or more queued threads 
```


Support for these operations requires the coordination of three basic components:
1. Atomically managing synchronization state.
2. blocking and unblocking threads
3. maintaining queues

The central decision in the synchronizer framework was to choose a concrete implementation of each of these three components, while still permitting a wide range of options in how they are used.

## Synchronization state
1. getState()
2. compareAndSetState()

Concrete classes based on AbstractQueuedSynchronizer must define methods:
1. tryAcquire
2. tryRelease

## Blocking

`java.util.concurrent.locks` package includes a LockSupport class with methods that :
1. LockSupport.park blocks the current thread. 
2. Thread.interrupt  interrupting a thread unparks it.
3. LockSupport.unpark unblocks the current thread.
HotspotJVM uses a pthread condvar 


## Queues



```plantuml

abstract class AbstractOwnableSynchronizer {
    transient Thread exclusiveOwnerThread
}
class AbstractQueuedSynchronizer extends AbstractOwnableSynchronizer {
    transient volatile Node head
    transient volatile Node tail
    volatile int state
}

class Node {
    volatile Node prev
    volatile Node next
    Thread waiter
    volatile int status
}

AbstractQueuedSynchronizer o-- Node
```