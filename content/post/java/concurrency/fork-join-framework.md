---
title: "java Concurrency - Fork Join Framework"
date: 2024-04-06T13:02:58+08:00
categories:
- java
- concurrency
tags:
- concurrency
- forkJoin
keywords:
- forkJoin
#thumbnailImage: //example.com/image.jpg
---
本文记录java并发编程- fork join framework 的设计与实现
<!--more-->

Fork join Framework supports a style of parallel programming in which Problems are solved by (recursively) splitting them into subtasks that are solved in parallel, waiting for them to complete, and then composing results.

# Design


Fork/Join programs can be run using any framework that supports construction of subtasks that are executed in parallel, along with a mechanism for waiting out their completion.

Fork/Join task has its own characteristics:
1. Fork/Join tasks have simple and regular synchronization and management requirements.
   1. do not need to block except to wait out subtasks
2. Given reasonable base task granularity, the cost of constructing and managing a thread can be greater than the computation time of the task itself.

Design details:

1. A pool of worker thread is established.  Normally thread number equals to CPU number.
2. All Fork/Join tasks are instances of a lightweight executable class,not instances of threads.
3. A special purpose queuing and scheduling discipline is used to manage tasks and execute them via the worker threads. These mechanics are triggered by those few methods provided in the task class: 
   1. fork
   2. join
   3. isDone

## work-stealing
The heart of Fork/Join framework lies in its lightweight scheduling mechanics.

1. Each worker thread maintains runnable tasks in its own scheduling queue.
2. Queues are maintained as double-ended queues(deques),supporting both LIFO(stack operation push and pop), as well as FIFO (queue operation offer and poll)
3. Subtasks generated in tasks run by a given worker thread are pushed onto that workers own deque.
4. Worker threads process their own deques in LIFO order by popping tasks.
5. Worker threads take(steal) a task from another workers using FIFO rule.
6. When a worker thread encounters a join operation, it processes other tasks, if available, until the target task is noticed to have completed. All tasks otherwise run to completion without blocking.
7. When a worker thread has no work and fails to steal any from others, it backs off and tries again later unless all workers are known to be similarly idle.


## Implementation


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

abstract class ForkJoinTask<V> implements Future {
    volatile int status
    volatile Aux aux
}

 class Aux {
    Thread thread
    final Throwable ex
    Aux next
 }
interface Executor {
    void execute(Runnable command)
}
interface ExecutorService extends Executor, AutoCloseable {
    <T> Future<T> submit(Callable<T> task)
    void shutdown()
    List<Runnable> shutdownNow()
    boolean isShutdown()
    boolean awaitTermination(long timeout, TimeUnit unit)
    boolean isTerminated()
    <T> List<Future<T>> invokeAll(tasks, timeout, unit)
    <T> T invokeAny(tasks)
    default void close()
}
abstract class AbstractExecutorService implements ExecutorService
class ForkJoinPool extends AbstractExecutorService {
    {static} final ForkJoinPool common
    {static} volatile int poolIds
    volatile CountDownLatch termination
    final Predicate<? super ForkJoinPool> saturate
    final ForkJoinWorkerThreadFactory factory
    final UncaughtExceptionHandler ueh
    final SharedThreadContainer container
    final String workerNamePrefix
    WorkQueue[] queues                
    final long keepAlive                
    final long config        
    volatile long stealCount       
    volatile long threadIds
    volatile int runState
    volatile long ctl
    int parallelism
 }

class ForkJoinWorkerThread extends Thread


ForkJoinTask *-- Aux
ForkJoinTask -right-> ForkJoinPool: poolSubmit

```