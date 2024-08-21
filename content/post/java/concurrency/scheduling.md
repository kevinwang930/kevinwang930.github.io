---
title: "Java Concurrency - Task Scheduling"
date: 2024-02-25T01:57:48+08:00
categories:
- java
- concurrency
tags:
- java
- concurrency
- lock

#thumbnailImage: //example.com/image.jpg
---
本文记录jdk提供的并发编程基础模块 - 线程池与异步执行框架
<!--more-->


The concurrency utilities packages provide a powerful, extensible framework of high-performance threading utilities such as thread pools and blocking queues. This package frees the programmer from the need to craft these utilities by hand, in much the same manner the collections framework did for data structures. Additionally, these packages provide low-level primitives for advanced concurrent programming.

The concurrency utilities include:
* high-performance, flexible thread pool
* a framework for asynchronous execution of tasks.
* Collection classes optimized for concurrent access.
* Synchronization utilities such as counting semaphores, atomic variables, locks and condition variables. 


Developer guides on concurrency utilities can be found [here](https://docs.oracle.com/en/java/javase/21/core/concurrency.html#GUID-59C16A2D-57CE-4C83-9D6F-91A48E01E3C6)

<!--more-->

# Task Scheduling

`Runnable` An operation that does not return a result.

`Callable` A task that returns a result and may throw an exception.

`Executor` An object that executes submitted Runnable Tasks. This interface provides a way of decoupling task submission from the mechanics of how each task will be run.

`ExecutorService` An Executor that provides methods to manage termination and methods that can produce a Future for tracking progress of asynchronous tasks.

`Future` represents the result of asynchronous computation. Methods are provided to check if the computation is complete, to wait for its completion. and to retrieve the result of computation.

`CompletableFuture` A Future that may be explicitly completed, supports dependent functions and actions that trigger upon its completion.




## Thread pool Implementation

`FutureTask` A cancellable asynchronous computation.
It maintain a `waiters` thread list.
The `get` method will block if computation has not yet completed.  

```plantuml

interface Executor {
    void execute(Runnable command)
}
interface ExecutorService extends Executor, AutoCloseable {
    void shutdown()
    List<Runnable> shutdownNow()
    boolean isShutdown()
    boolean isTerminated()
    boolean awaitTermination(long timeout, TimeUnit unit)
    <T> Future<T> submit(Callable<T> task)
    <T> List<Future<T>> invokeAll(tasks, timeout, unit)
    <T> T invokeAny(tasks)
    default void close()
}
abstract class AbstractExecutorService implements ExecutorService

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





class ThreadPoolExecutor extends AbstractExecutorService {
    AtomicInteger ctl
    BlockingQueue<Runnable> workQueue
    ReentrantLock mainLock
    HashSet<Worker> workers
    SharedThreadContainer container
    int largestPoolSize
    long completedTaskCount
    volatile ThreadFactory threadFactory
    volatile RejectedExecutionHandler handler
    volatile long keepAliveTime
    volatile boolean allowCoreThreadTimeOut
    volatile int corePoolSize
    volatile int maximumPoolSize
    Condition termination = mainLock.newCondition

}

Callable -right-> ThreadPoolExecutor: submit
ThreadPoolExecutor -right-> FutureTask

```

## Asynchronous Execution Implementation

`CompletionStage` A stage of a possibly asynchronous computation, that performs an action or computes a value when another CompletionStage completes.
A stage's execution may be trigger by completion of other stages, it inturn can trigger computation of other stages. Thus form a asynchronous task chain.


`CompletableFuture` A `Future` that may be explicitly completed , and may be used as a `CompletionStage` supporting dependent functions and actions that trigger upon its completion.



```plantuml
interface CompletionStage<T>  {
     CompletionStage<U> thenApply(fn)
     CompletionStage<U> thenApplyAsync(fn)
     CompletionStage<U> thenApplyAsync(fn,executor)
     CompletionStage<Void> thenAccept(consumer)
     CompletionStage<Void> thenRun(runnable)
     CompletionStage<V> thenCombine(otherStage,biFn)
     CompletionStage<U> applyToEither(otherStage, fn)
     CompletionStage<U> thenCompose(stageFn)
     CompletionStage<U> handle(biFn)
}

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

class CompletableFuture<T> implements Future, CompletionStage {
    Object result
    Completion stack
}

abstract class Completion extends ForkJoinTask<Void> implements Runnable,AsynchronousCompletionTask {
    Completion next
        }

abstract class ForkJoinTask<V> implements Future {
    int status
    Aux aux
}

CompletableFuture *-down- Completion
```
