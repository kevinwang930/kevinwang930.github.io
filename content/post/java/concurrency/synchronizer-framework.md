---
title: "java concurrency - Synchronizer Framework"
date: 2024-04-06T17:00:29+08:00
categories:
- java
- synchronizer
tags:
- java
- synchronizer
- concurrency
keywords:
- synchronizer
#thumbnailImage: //example.com/image.jpg
---
本文记录 java AbstractQueuedSynchronizer (AQS) 的设计、实现以及具体应用。
<!--more-->

# Requirement
Synchronizers possess two kinds of methods: 
1. acquire operation blocks the calling thread until the synchronization state allows it to proceed.
2. release operation changes synchronization state in a way that may allow one or more blocked threads to unblock.

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
AQS maintains synchronization state using only a single (32-bit) int, and exports operations to access and update state

   1. getState()
   2. setState()
   3. compareAndSetState()


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

The heart of the framework is maintenance of queues of blocked threads, which are restricted to FIFO queues.
The appropriate choices for synchronization queues are non-blocking data structures that do not themselves need to be constructed using lower-level locks.
CLH(lock queue) have been used only in spinlocks.
AQS made modification to the CLH locks to support blocking,cancellation and timeouts.
1. CLH node with `prev` node link can deal with timeouts and cancellation
2. CLH node with `next` node link to support blocking and waking up (park/unpark)
3. `status` field kept in each node for purposes of controlling blocking.
4. garbage collection of nodes relies on GC


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



## Condition queues

The synchronizer framework provides a `ConditionObject` class for use by synchronizers that maintain exclusive synchronization and conform to the `LOCK` interface.
Any number of condition objects may be attached to a lock object, providing classis monitor-style await, signal and signalAll operations.

A `ConditionObject` uses the same internal queue nodes as synchronizers, but maintains them on a separate condition queue. The signal operation is implemented as a queue transfer from the condition queue to the lock queue, without necessarily waking up the signalled thread before it has re-acquired its lock.

```
await:
    create and add new node to condition queue;
    release lock;
    block until node is on lock queue;
    re-acquire lock;

signal:
    transfer the first node from condition queue to lock queue.
```


```plantuml

interface Condition {
    void await()
    void awaitUninterruptibly()
    long awaitNanos(long nanosTimeout)
    boolean await(long time, TimeUnit unit)
    boolean awaitUntil(Date deadline)
    void signal()
    void signalAll()
}

class Node {
    volatile Node prev
    volatile Node next
    Thread waiter
    volatile int status
}

class ConditionObject implements Condition {
    transient ConditionNode firstWaiter
    transient ConditionNode lastWaiter
}

interface ManagedBlocker {
    boolean block() throws InterruptedException
    boolean isReleasable()
}

class ConditionNode extends Node implements ManagedBlocker {
    ConditionNode nextWaiter
}

ConditionObject *-right- ConditionNode

```


# Synchronizers

## ReentrantLock


ReentrantLock will check the current owner of the lock,if it is the current thread, it set state and return directly.

```plantuml
interface Lock {
    void lock()
    void lockInterruptibly() throws InterruptedException
    boolean tryLock()
    boolean tryLock(long time, TimeUnit unit) throws InterruptedException
    void unlock()
    Condition newCondition()
}

class ReentrantLock implements Lock {
    final Sync sync
}

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
abstract  class Sync extends AbstractQueuedSynchronizer {

}
ReentrantLock *-- Sync
AbstractQueuedSynchronizer o-- Node
```

## ReentrantReadWriteLock

State of lock is 32 bit, upper 16 bits store shared count, lower 16 bits store exclusive count.

The ReadLock uses the `acquireShared` methods to enable multiple readers.




```plantuml

interface Lock {
    void lock()
    void lockInterruptibly() throws InterruptedException
    boolean tryLock()
    boolean tryLock(long time, TimeUnit unit) throws InterruptedException
    void unlock()
    Condition newCondition()
}

interface ReadWriteLock {
    Lock readLock()
    Lock writeLock()
}

class ReentrantReadWriteLock  {
    ReadLock readerLock
    WriteLock writerLock
    Sync sync
}

class ReadLock {
    Sync sync
}

class WriteLock  {
    Sync sync
}
abstract class Sync extends AbstractQueuedSynchronizer {
    ThreadLocalHoldCounter readHolds
    HoldCounter cachedHoldCounter
    Thread firstReader
    int firstReaderHoldCount
}

class NonfairSync extends Sync
Lock <|--- ReadLock
Lock <|--- WriteLock
ReadWriteLock <|-- ReentrantReadWriteLock
ReentrantReadWriteLock *-left- ReadLock
ReentrantReadWriteLock *-right- WriteLock


ReentrantReadWriteLock *-down- Sync

```

## Semaphore
Semaphore uses the synchronization state to hold the current count. It  defines `acquireShared` to decrement the count or block if nonpositive, and `tryRelease` to increment the count, possibly unblocking threads if it is now positive.


## CountDownlatch 
`CountDownLatch` uses the synchronization state to represent the count.All acquires pass when it reaches zero.


## CyclicBarrier
A synchronization aid that allows a set of threads to all wait for each other to reach a common barrier point. It 



## FutureTask
`FutureTask` uses synchronization state to represent the run-state of a future(initial, running, cancelled, done). Setting or cancelling a future invokes release, unblocking threads waiting for its computed value via `acquire`.

```plantuml
interface Future<V> {
    boolean cancel(boolean mayInterruptIfRunning)
    boolean isCancelled()
    boolean isDone()
    V get() 
    V get(long timeout, TimeUnit unit)
    default V resultNow() 
    default Throwable exceptionNow()
    default State state()
}
interface RunnableFuture<V> extends Runnable, Future {
    void run()
}

class FutureTask<V> implements RunnableFuture {
    volatile int state
    Callable<V> callable
    Object outcome
    volatile Thread runner
    volatile WaitNode waiters
}
class WaitNode {
    Thread thread
    WaitNode next
}
FutureTask *-right- WaitNode
```