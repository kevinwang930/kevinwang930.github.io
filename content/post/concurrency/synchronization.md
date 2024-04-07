---
title: "Synchronization"
date: 2024-04-06T21:48:25+08:00
categories:
- concurrency
- synchronization
tags:
- concurrency
- synchronization
keywords:
- synchronization
- concurrency
#thumbnailImage: //example.com/image.jpg
---
本文记录并发共享内存编程所需的基础模块 Synchronization - 同步器的功能与实现
<!--more-->

On Shared-memory machines, processors communicate by sharing data structures. To ensure the consistency of shared data structures, processors perform simple operations by using hardware-supported atomic primitives and coordinate complex operations by using synchronization constructs and conventions to protect against overlap of conflicting operations.

Synchronization constructs can be divided into two classes:
1. blocking construct that deschedule waiting processes
2. busy-wait constructs in which processes repeatedly test shared variables to determine when they may proceed.

Two of the most widely used busy-wait synchronization constructs are spinlocks and barriers.

Spin locks provide a means for achieving mutual exclusion and ar a basic building block for synchronization constructs with richer semantics, such as semaphores and monitors.

Barriers provide a means of ensuring that no processes advance beyond a particular point in a computation until all have arrived at that point.


# spin lock
spin lock is a lock that causes a thread trying to acquire it to simply wait in a loop(spin) while repeatedly checking whether the lock is available. since the thread remains active but is not performing a useful task, the use of such lock is kind of busy waiting.

## test and set
simplest form of spin lock with backoff

## ticket lock
```
fetch_and_increment req_count
wait until req_count equals rel_count
```
ticket lock probes with read operation only(thus avoids the overhead of unnecessary invalidations in coherent cache machines)


## Array-Based Queuing Locks
Each processor has its own address to spin 

## MCS Queue Lock
```
type qnode = record
    next: qnode
    locked: Boolean

type lock = qnode

// parameter I points to a qnode record allocated in shared memory locally-accessible to the invoking processor
procedure acquire_lock(L: lock, I: qnode)
    I-> next := nil
    predecessor: qnode := fetch_and_store(L,I)
    if predecessor != nil // queue is not empty
        I -> locked := true
        predecessor->next := I
        repeat will I->locked  // spin

procedure release_lock(L:lock,I:qnote)
    if I-> next = nil
        if compare_and_swap(L,I,nil)
            return
        repeat while I->next= nil
    I->next->locked := false
```

# barriers

In concurrency, a barrier is a type of synchronization method. A barrier for a group of threads or processes means any thread/process must stop at this point and can not proceed until all other threads/processes reach this barrier.

## Centralized Barrier
In a centralized implementation of barrier synchronization, each processor updates a small amount of shared state to indicate its arrival and then polls that state to determine when all of the processors have arrived.

```
shared count : integer := p
shared sense : Boolean := true
processor private local_sense: Boolean := true

procedure central_barrier
    local_sense := not local_sense
    if fetch_and_decrement (&count) = 1
        count := p
        sense := local_sense
    else:
        repeat until sense = local_sense.  // spin
```

## Software Combining Tree Barrier

```
type node = record
    k: integer
    count: integer
    locksense: Boolean
    parent: node

shared nodes: array[0..p-1]
processor private sense: Boolean := true
processor private mynode: node
```


# Assemby on synchronization

## X86
1. CMPXCHG compare and exchange
2. lock XADD exchange and add
