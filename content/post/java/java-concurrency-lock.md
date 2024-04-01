---
title: "Concurrency in Java"
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

# Concurrency Utilities in Java
The concurrency utilities packages provide a powerful, extensible framework of high-performance threading utilities such as thread pools and blocking queues. This package frees the programmer from the need to craft these utilities by hand, in much the same manner the collections framework did for data structures. Additionally, these packages provide low-level primitives for advanced concurrent programming.

<!--more-->

## Task Scheduling

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
    <T> Future<T> submit(Runnable task, T result)
    Future<?> submit(Runnable task)
    <T> List<Future<T>> invokeAll(Collection<? extends Callable<T>> tasks)
    <T> List<Future<T>> invokeAll(Collection<? extends Callable<T>> tasks,long timeout, TimeUnit unit)
    <T> T invokeAny(Collection<? extends Callable<T>> tasks)
        throws InterruptedException, ExecutionException
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
```


## Lock

### CountdownLatch

used in tomcat endpoint to control connection size.