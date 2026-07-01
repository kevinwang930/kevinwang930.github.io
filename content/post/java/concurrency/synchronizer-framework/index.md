---
title: "java concurrency - Synchronizer Framework"
date: 2024-04-06T17:00:29+08:00
categories:
- java
- concurrency
tags:
- java
- concurrency
- synchronizer
keywords:
- synchronizer
#thumbnailImage: //example.com/image.jpg
---

`ReentrantLock`, `Semaphore`, and `CountDownLatch` look unrelated at the API level, but each holds a private **`Sync extends AbstractQueuedSynchronizer`**. The **`Sync`** subclass overrides **`tryAcquire`** / **`tryRelease`** and decides what **`state`** represents. **`AbstractQueuedSynchronizer`** (AQS) is the base class: it owns `state`, the CLH sync queue, `acquire` / `release`, and the nested **`ConditionObject`**.

<!--more-->

---

## 1. Architecture

### 1.1 Design overview

A blocking synchronizer has two operations: **acquire** waits until `state` permits progress; **release** updates `state` and may wake waiters. In the JDK this splits across two classes:

| Class | Responsibility |
|-------|----------------|
| **`Sync extends AQS`** | Override `tryAcquire*` / `tryRelease*`; define what `state` means |
| **`AbstractQueuedSynchronizer`** | Hold `state`, run the `acquire` / `release` loop, manage the CLH queue, park threads via `LockSupport` |

![AbstractQueuedSynchronizer: synchronizers, Sync subclass, and AQS internals](images/synchronizer-architecture.svg)

The diagram shows the call chain:

1. **`ReentrantLock`**, **`Semaphore`**, etc. — public API (`lock`, `acquire`, `await`).
2. **`Sync`** — inner class that extends AQS and implements the `try*` hooks. `ReentrantLock.Sync` treats `state` as hold count; `Semaphore.Sync` treats it as permit count.
3. **`AbstractQueuedSynchronizer`** — when `tryAcquire` fails, AQS enqueues the thread on a CLH FIFO queue and blocks it with `LockSupport.park`. On `release`, AQS calls `tryRelease` then `signalNext` to unpark a successor. Also contains **`ConditionObject`** for `await` / `signal`, and extends **`AbstractOwnableSynchronizer`** to track the exclusive owner thread.

`AbstractQueuedLongSynchronizer` is the same design with a `long state` field — used by `ReentrantReadWriteLock`.

Both modes share one sync queue; the node type records the mode:

| Mode | AQS API | Node class | Examples |
|------|---------|------------|----------|
| Exclusive | `acquire` / `release` | `ExclusiveNode` | `ReentrantLock`, write lock |
| Shared | `acquireShared` / `releaseShared` | `SharedNode` | `Semaphore`, `CountDownLatch.await`, read lock |

CAS, memory fences, and the OS primitives behind `park` are covered in [Synchronization](/2024/04/concurrency/synchronization/).

### 1.2 AbstractQueuedSynchronizer

Every AQS-backed type holds a `Sync extends AbstractQueuedSynchronizer` (or `AbstractQueuedLongSynchronizer`) and overrides the hook methods:

```plantuml
@startuml
abstract class AbstractOwnableSynchronizer {
    transient Thread exclusiveOwnerThread
}

abstract class AbstractQueuedSynchronizer extends AbstractOwnableSynchronizer {
    transient volatile Node head
    transient volatile Node tail
    volatile int state
    + acquire(int arg)
    + release(int arg)
    + acquireShared(int arg)
    + releaseShared(int arg)
    # tryAcquire(int arg)
    # tryRelease(int releases)
    # tryAcquireShared(int arg)
    # tryReleaseShared(int releases)
}

abstract class Node {
    volatile Node prev
    volatile Node next
    Thread waiter
    volatile int status
}

class ExclusiveNode extends Node
class SharedNode extends Node
class ConditionNode extends Node {
    ConditionNode nextWaiter
}

AbstractQueuedSynchronizer "1" o-- "*" Node : sync queue
@enduml
```

#### State and hooks

`state` is read and written only through `getState`, `setState`, and `compareAndSetState`. Subclasses override **hooks**; callers never touch `state` directly:

| Mode | Acquire hook | Release hook | Result |
|------|--------------|--------------|--------|
| Exclusive | `tryAcquire(int arg)` | `tryRelease(int releases)` | `boolean`; `true` when fully released |
| Shared | `tryAcquireShared(int arg)` | `tryReleaseShared(int releases)` | `int`: negative = fail; `0` = success; positive = success and others may proceed |

`AbstractOwnableSynchronizer` tracks `exclusiveOwnerThread` for exclusive syncs. When 32 bits are insufficient, **`AbstractQueuedLongSynchronizer`** provides the same API with a `long state` — used by `ReentrantReadWriteLock`.

#### Sync queue

On first contention AQS installs a dummy header; waiters link at `tail` via CAS:

```java
private transient volatile Node head;
private transient volatile Node tail;
```

| Field | Role |
|-------|------|
| `prev`, `next` | CLH-variant links; enqueue uses `prev`; `next` may lag after cancellation |
| `waiter` | `Thread` passed to `LockSupport.unpark` |
| `status` | `WAITING` (1), `CANCELLED`, `COND` (2) — bit flags |

#### ExclusiveNode and SharedNode

`ExclusiveNode` and `SharedNode` are empty subclasses of `Node` — no extra fields. AQS uses the type tag to decide which hook to call and which waiters to wake:

| | `ExclusiveNode` | `SharedNode` |
|---|-----------------|--------------|
| **Created when** | `acquire(..., shared=false, ...)` | `acquire(..., shared=true, ...)` |
| **Fast-path hook** | `tryAcquire(arg)` → `boolean` | `tryAcquireShared(arg) >= 0` |
| **Release path** | `release` → `signalNext(head)` | `releaseShared` → `signalNext(head)` |
| **After becoming head** | stop | `signalNextIfShared(node)` — wake next shared waiter if still eligible |
| **Queue inspection** | `getExclusiveQueuedThreads()` | `getSharedQueuedThreads()` |

Enqueue picks the node type in the main acquire loop:

```java
node = (shared) ? new SharedNode() : new ExclusiveNode();
```

Inside the loop, the same `acquire(...)` method branches on `shared`:

```java
if (shared)
    acquired = (tryAcquireShared(arg) >= 0);
else
    acquired = tryAcquire(arg);
```

When a shared waiter succeeds and installs itself as the new head, AQS may propagate the wake to the next shared node — multiple readers can pass through without each needing a separate `release`:

```java
if (acquired) {
    if (first) {
        node.prev = null;
        head = node;
        pred.next = null;
        node.waiter = null;
        if (shared)
            signalNextIfShared(node);   // only unparks if successor is SharedNode
        // ...
    }
    return 1;
}
```

`signalNext` wakes any successor; `signalNextIfShared` wakes only a `SharedNode`:

```java
private static void signalNext(Node h) {
    Node s;
    if (h != null && (s = h.next) != null && s.status != 0) {
        s.getAndUnsetStatus(WAITING);
        LockSupport.unpark(s.waiter);
    }
}

private static void signalNextIfShared(Node h) {
    Node s;
    if (h != null && (s = h.next) != null &&
        (s instanceof SharedNode) && s.status != 0) {
        s.getAndUnsetStatus(WAITING);
        LockSupport.unpark(s.waiter);
    }
}
```

`ConditionNode` is a third node type, used on condition queues rather than the CLH sync queue (§1.3).

#### Acquire and release

Public entry points try the hook once, then delegate to the internal loop:

```java
// exclusive — ReentrantLock.lock()
public final void acquire(int arg) {
    if (!tryAcquire(arg))
        acquire(null, arg, false, false, false, 0L);
}

// shared — Semaphore.acquire(), CountDownLatch.await()
public final void acquireShared(int arg) {
    if (tryAcquireShared(arg) < 0)
        acquire(null, arg, true, false, false, 0L);
}
```

The internal **`acquire(...)`** loop handles enqueue, park, and retry. Simplified flow:

```java
for (;;) {
    // 1. If at queue head (or not yet enqueued), try the hook
    if (first || pred == null) {
        boolean acquired = shared
            ? (tryAcquireShared(arg) >= 0)
            : tryAcquire(arg);
        if (acquired) { /* set head, maybe signalNextIfShared */ return 1; }
    }
    // 2. Initialize queue on first contention
    if (tail == null)
        tryInitializeHead();
    // 3. Allocate ExclusiveNode or SharedNode
    else if (node == null)
        node = shared ? new SharedNode() : new ExclusiveNode();
    // 4. CAS onto tail, link prev
    else if (pred == null) { /* enqueue */ }
    // 5. Spin after unpark (postSpins)
    else if (first && spins != 0) { --spins; Thread.onSpinWait(); }
    // 6. Set WAITING on predecessor, then park
    else if (node.status == 0)
        node.status = WAITING;
    else {
        LockSupport.park(this);   // or parkNanos for timed acquire
        node.clearStatus();
    }
}
```

Release is symmetric and short — hook first, then unpark one successor:

```java
public final boolean release(int arg) {
    if (tryRelease(arg)) {
        signalNext(head);
        return true;
    }
    return false;
}

public final boolean releaseShared(int arg) {
    if (tryReleaseShared(arg)) {
        signalNext(head);
        return true;
    }
    return false;
}
```

Timed or interrupted acquires set `CANCELLED`; `cleanQueue()` unlinks dead nodes so successors remain reachable.

### 1.3 ConditionObject

`ConditionObject` is nested inside AQS and backs `Lock.newCondition()`. It reuses `ConditionNode` but maintains a **separate condition queue** (`firstWaiter` / `lastWaiter`), distinct from the CLH sync queue:

```plantuml
@startuml
interface Condition {
    + await()
    + awaitUninterruptibly()
    + awaitNanos(long nanosTimeout)
    + await(long time, TimeUnit unit)
    + awaitUntil(Date deadline)
    + signal()
    + signalAll()
}

abstract class Node {
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
    + block() : boolean
    + isReleasable() : boolean
}

class ConditionNode extends Node implements ManagedBlocker {
    ConditionNode nextWaiter
}

ConditionObject *-right- ConditionNode : condition queue
@enduml
```

**`await()`** (caller must hold the exclusive lock):

1. `enableWait(node)` — enqueue on the condition list, then **`release(savedState)`**.
2. Park (`ForkJoinPool.managedBlock` or `LockSupport.park`) until signalled.
3. `reacquire(node, savedState)` — competitive `acquire`; may re-enter the sync queue.
4. Restore interrupt status if interrupted after a real signal.

**`signal()`** transfers nodes from the condition queue to the sync queue. The signalled thread does not run until it re-acquires the lock:

```java
private void doSignal(ConditionNode first, boolean all) {
    while (first != null) {
        ConditionNode next = first.nextWaiter;
        if ((first.getAndUnsetStatus(COND) & COND) != 0) {
            enqueue(first);
            if (!all) break;
        }
        first = next;
    }
}
```

Unlike `synchronized`, each `Condition` instance has its own wait set rather than sharing one per monitor.

---

## 2. Implementation

### 2.1 LockSupport

AQS stores the waiting thread in `Node.waiter` and calls **`LockSupport.unpark`** from `signalNext`. Each thread holds at most **one permit**; `park()` consumes it or blocks. Parking is per-thread, not bound to a lock object. Short spins (`postSpins`, `Thread.onSpinWait`) before parking cut context switches when the releaser is still on-CPU.

### 2.2 Built-in synchronizers

| Class | AQS base | `state` meaning | Mode |
|-------|----------|-----------------|------|
| `ReentrantLock` | `AbstractQueuedSynchronizer` | hold count (0 = unlocked) | exclusive |
| `ReentrantReadWriteLock` | `AbstractQueuedLongSynchronizer` | high 32 = reads, low 32 = writes | both |
| `Semaphore` | `AbstractQueuedSynchronizer` | available permits | shared |
| `CountDownLatch` | `AbstractQueuedSynchronizer` | countdown (0 = open) | shared |
| `CyclicBarrier` | — (`ReentrantLock` + `Condition`) | `count` under lock | — |
| `FutureTask` | — (own CAS `state` + `WaitNode` stack) | task lifecycle | — |

#### ReentrantLock

A reentrant mutual-exclusion lock: one thread holds it at a time, but the owner may acquire it again. It supports optional FIFO fairness, timed and interruptible acquire, and multiple condition variables on the same lock. Use it wherever `synchronized` is too limited — `tryLock`, fairness, or separate *notFull* / *notEmpty* waits on one buffer.

```plantuml
@startuml
interface Lock {
    + lock()
    + lockInterruptibly()
    + tryLock()
    + tryLock(long time, TimeUnit unit)
    + unlock()
    + newCondition() : Condition
}

interface Condition {
    + await()
    + signal()
    + signalAll()
}

class ConditionObject implements Condition

class ReentrantLock implements Lock {
    final Sync sync
}

abstract class Sync extends AbstractQueuedSynchronizer {
    + newCondition() : ConditionObject
}

class NonfairSync extends Sync
class FairSync extends Sync

ReentrantLock *-- Sync
Sync ..> ConditionObject : newCondition()
@enduml
```

`lock.newCondition()` returns a **`ConditionObject`** on the same `Sync`. A thread **`await`**s only while holding the lock; `await` releases the lock and waits on the condition queue; **`signal`** moves waiters back to the sync queue. One lock can have many conditions (e.g. *notFull* and *notEmpty*).

Fairness is not in AQS — it is chosen in the **`Sync` subclass**. The default constructor uses **`NonfairSync`**; `new ReentrantLock(true)` uses **`FairSync`**:

```java
public ReentrantLock() {
    sync = new NonfairSync();
}

public ReentrantLock(boolean fair) {
    sync = fair ? new FairSync() : new NonfairSync();
}
```

**NonfairSync** skips the queue check, so a new thread can **barge** ahead of waiters:

```java
final boolean initialTryLock() {
    Thread current = Thread.currentThread();
    if (compareAndSetState(0, 1)) {
        setExclusiveOwnerThread(current);
        return true;
    } else if (getExclusiveOwnerThread() == current) {
        setState(getState() + 1);
        return true;
    }
    return false;
}

protected final boolean tryAcquire(int acquires) {
    if (getState() == 0 && compareAndSetState(0, acquires)) {
        setExclusiveOwnerThread(Thread.currentThread());
        return true;
    }
    return false;
}
```

**FairSync** calls `hasQueuedThreads()` / `hasQueuedPredecessors()` before CAS:

```java
final boolean initialTryLock() {
    Thread current = Thread.currentThread();
    int c = getState();
    if (c == 0) {
        if (!hasQueuedThreads() && compareAndSetState(0, 1)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    } else if (getExclusiveOwnerThread() == current) {
        setState(++c);
        return true;
    }
    return false;
}

protected final boolean tryAcquire(int acquires) {
    if (getState() == 0 && !hasQueuedPredecessors() &&
        compareAndSetState(0, acquires)) {
        setExclusiveOwnerThread(Thread.currentThread());
        return true;
    }
    return false;
}
```

`lock()` always tries `initialTryLock()` before `acquire(1)`, so a fair lock still takes the fast path when the queue is empty.

`state` is the reentrant hold count; `exclusiveOwnerThread` is the owner. `tryRelease` decrements and returns `true` at zero, which triggers `signalNext`:

```java
protected final boolean tryRelease(int releases) {
    int c = getState() - releases;
    if (getExclusiveOwnerThread() != Thread.currentThread())
        throw new IllegalMonitorStateException();
    boolean free = (c == 0);
    if (free) setExclusiveOwnerThread(null);
    setState(c);
    return free;
}
```

#### ReentrantReadWriteLock

A read/write lock: many threads may hold the read lock together; the write lock excludes all readers and other writers. Both modes are reentrant. It fits read-heavy data — caches, config snapshots — where writes are infrequent but must see a consistent view.

```plantuml
@startuml
interface Lock {
    + lock()
    + unlock()
    + newCondition() : Condition
}

interface Condition {
    + await()
    + signal()
}

class ConditionObject implements Condition

interface ReadWriteLock {
    + readLock() : Lock
    + writeLock() : Lock
}

class ReentrantReadWriteLock implements ReadWriteLock {
    readerLock : ReadLock
    writerLock : WriteLock
    sync : Sync
}

class ReadLock implements Lock {
    sync : Sync
}

class WriteLock implements Lock {
    sync : Sync
}

abstract class "AbstractQueuedLongSynchronizer" as AQLS {
    volatile long state
}

abstract class Sync extends AQLS {
    + newCondition() : ConditionObject
    readHolds : ThreadLocalHoldCounter
    cachedHoldCounter : HoldCounter
}

class HoldCounter {
    count : int
}

class ThreadLocalHoldCounter

class NonfairSync extends Sync
class FairSync extends Sync

ReentrantReadWriteLock *-- ReadLock
ReentrantReadWriteLock *-- WriteLock
ReentrantReadWriteLock *-- Sync
WriteLock ..> ConditionObject : newCondition()
Sync ..> ConditionObject
note right of ReadLock : newCondition() throws\nUnsupportedOperationException
@enduml
```

Only **`writeLock().newCondition()`** is supported — `await` must release exclusive ownership. **`readLock().newCondition()`** throws `UnsupportedOperationException`.

`SHARED_SHIFT = 32`: low 32 bits hold write count, high 32 bits hold read count. `ReadLock` calls `acquireShared`; `WriteLock` calls `acquire`. Per-thread read recursion is tracked in `ThreadLocalHoldCounter`.

#### Semaphore

A counting semaphore tracks a pool of permits. `acquire` takes one and blocks when the pool is empty; `release` returns one. There is no owner — any thread may release. Typical uses are connection pools, rate limiters, and any cap of *N* concurrent workers.

```plantuml
@startuml
class Semaphore {
    final Sync sync
    + acquire()
    + release()
    + tryAcquire()
}

abstract class Sync extends AbstractQueuedSynchronizer {
    + nonfairTryAcquireShared(int) : int
}

class NonfairSync extends Sync
class FairSync extends Sync

Semaphore *-- Sync
@enduml
```

`state` holds available permits. **NonfairSync** subtracts via CAS with no queue check. **FairSync** returns `-1` when `hasQueuedPredecessors()` is true, forcing the thread to enqueue:

```java
// NonfairSync — barging allowed
protected int tryAcquireShared(int acquires) {
    for (;;) {
        int available = getState();
        int remaining = available - acquires;
        if (remaining < 0 || compareAndSetState(available, remaining))
            return remaining;
    }
}

// FairSync
protected int tryAcquireShared(int acquires) {
    for (;;) {
        if (hasQueuedPredecessors())
            return -1;
        int available = getState();
        int remaining = available - acquires;
        if (remaining < 0 || compareAndSetState(available, remaining))
            return remaining;
    }
}
```

#### CountDownLatch

A one-shot countdown latch starts at *N*. Threads `await` until `countDown` has been called *N* times; then every waiter is released at once. The count cannot be reset — use a new latch or a `CyclicBarrier` when the gate must fire again. Common pattern: wait for all workers to finish startup before processing begins.

```plantuml
@startuml
class CountDownLatch {
    final Sync sync
    + await()
    + countDown()
    + getCount() : int
}

class Sync extends AbstractQueuedSynchronizer {
    + getCount() : int
}

CountDownLatch *-- Sync
@enduml
```

`state` is the remaining count. `await` succeeds only when `state == 0`; the last `countDown` returns `true` from `tryReleaseShared` and wakes all waiters.

```java
protected int tryAcquireShared(int acquires) {
    return (getState() == 0) ? 1 : -1;
}

protected boolean tryReleaseShared(int releases) {
    for (;;) {
        int c = getState();
        if (c == 0) return false;
        int nextc = c - 1;
        if (compareAndSetState(c, nextc))
            return nextc == 0;
    }
}
```

#### CyclicBarrier

A cyclic barrier synchronizes a fixed number of parties. Each calls `await`; when the last arrives, an optional action runs and everyone proceeds. The barrier then resets for the next round — suited to parallel algorithms that advance in lockstep phases. `reset()` or a broken barrier starts a fresh cycle.

```plantuml
@startuml
interface Condition {
    + await()
    + signalAll()
}

class ConditionObject implements Condition

class ReentrantLock {
    + newCondition() : Condition
}

class CyclicBarrier {
    ReentrantLock lock
    Condition trip
    int parties
    int count
    Generation generation
}

class Generation {
    boolean broken
}

CyclicBarrier *-- ReentrantLock
CyclicBarrier o-- Condition : trip
ReentrantLock ..> ConditionObject : newCondition()
note right of Condition
  trip: parties await here
  until count hits 0;
  last party signalAll()
  in nextGeneration()
end note
@enduml
```

Field **`trip`** is the condition all parties share. Under `lock`, each party decrements `count`; non-last threads **`trip.await()`**; the last thread runs the barrier action and **`trip.signalAll()`** in **`nextGeneration()`** to release everyone for the next cycle.

Fields and setup:

```java
private final ReentrantLock lock = new ReentrantLock();
private final Condition trip = lock.newCondition();
```

Each party decrements `count` under `lock`. Non-last parties **`trip.await()`**; the last party runs `barrierCommand`, then **`nextGeneration()`** resets `count` and **`trip.signalAll()`** wakes everyone:

```java
private void nextGeneration() {
    trip.signalAll();
    count = parties;
    generation = new Generation();
}

// inside dowait(), after lock.lock()
int index = --count;
if (index == 0) {          // last party — trip the barrier
    if (barrierCommand != null)
        barrierCommand.run();
    nextGeneration();
    return 0;
}
for (;;) {
    if (!timed)
        trip.await();      // wait for last party to signal
    else if (nanos > 0L)
        nanos = trip.awaitNanos(nanos);
    if (g != generation)     // woken by nextGeneration()
        return index;
}
```

#### FutureTask

A `FutureTask` wraps a `Callable` or `Runnable`, runs it on an executor, and exposes the result through `Future`. Callers block on `get()` until the task completes, fails, or is cancelled — the usual task type behind `ExecutorService.submit`.

```plantuml
@startuml
interface Future<V> {
    + get() : V
    + cancel(boolean) : boolean
}

interface Runnable
interface RunnableFuture<V> extends Runnable, Future

class FutureTask<V> implements RunnableFuture {
    volatile int state
    volatile WaitNode waiters
}

class WaitNode {
    Thread thread
    WaitNode next
}

FutureTask *-right- WaitNode
@enduml
```

---

## Summary

| Piece | Role |
|-------|------|
| **`state` + hooks** | Subclass decides when acquire / release succeeds |
| **`acquire` / `release`** | Template loop: try → enqueue → park → retry |
| **CLH queue** | FIFO waiters; fair mode checks `hasQueuedPredecessors` |
| **`LockSupport`** | Per-thread park / unpark |
| **`ConditionObject`** | Separate condition queue; `signal` enqueues onto sync queue |
| **Concrete syncs** | Thin wrappers mapping domain semantics onto `state` |

Every AQS-backed class wraps a **`Sync`** inner class: read how **`state`** is encoded, then read **`tryAcquire*`** / **`tryRelease*`**.
