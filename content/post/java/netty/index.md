---
title: "Netty Internals"
date: 2024-08-02T13:54:59+08:00
categories:
- java
- netty
tags:
- netty
keywords:
- netty
#thumbnailImage: //example.com/image.jpg
---
本文记录Netty架构与实现
<!--more-->



Netty is an asynchronous event-driven network application framework for rapid development of maintainable high performance protocol servers & clients.

![structure](images/structure.png)




# Event Model

![event](images/event.png)

## Transport 
The data that flows through a network always has the same type: bytes. How these bytes are moved around depends mostly on what we refer to as the network transport, a concept that helps us to abstract away the underlying mechanics of data transfer.



## EventLoop and Threading model

`EventLoop` is used to handle all the I/O operations for the channels registered, multiple `Channel`s can be assigned to one `EventLoop`. Each `EventLoop` is powered by exactly one `Thread` that never changes.

* `ScheduledExecutorService` an `ExecutorService` that can schedule commands to run after a given delay.
* `EventExecutorGroup` provides the `EventExecutor` to use via its method `next()`. It also provides method of life-cycle management and shutting them down in global fashion.
* `EventExecutor` is a special `EventExecutorGroup` whose `next()` is itself.
* `EventLoopGroup` special `EventExecutorGroup` which allows registering `Channel`s that get processed for later selection during the event loop 
* `EventLoop` will handle all the I/O operations for a `Channel` once registered.
* `IoHandler` handles I/O dispatching for an `ThreadAwareExecutor`

```plantuml
@startuml

top to bottom direction


interface AutoCloseable 
interface Executor {
  void execute(Runnable command)
}
interface ThreadAwareExecutor extends Executor {
  boolean isExecutorThread(Thread thread)
}
interface ExecutorService extends Executor,AutoCloseable {
  Future<T> submit(Callable<T> task)
  void shutdown()
}

interface ScheduledExecutorService extends ExecutorService  {
  ScheduledFuture<?> schedule(Runnable command,long delay, TimeUnit unit)
}
interface EventExecutorGroup  extends ScheduledExecutorService {
    EventExecutor next()
    Future<?> shutdownGracefully()
}
class AbstractEventExecutorGroup implements EventExecutorGroup

interface EventExecutor extends EventExecutorGroup,ThreadAwareExecutor {
  EventExecutorGroup parent()
  boolean inEventLoop(Thread thread)

  
}
interface EventLoopGroup extends EventExecutorGroup {
    EventLoop next()
    ChannelFuture register(Channel channel)
}

interface OrderedEventExecutor extends EventExecutor
interface EventLoop extends OrderedEventExecutor,EventLoopGroup {
  EventLoopGroup parent()
}


class MultithreadEventExecutorGroup extends AbstractEventExecutorGroup {
    EventExecutor[] children
    Set<EventExecutor> readonlyChildren
    AtomicInteger terminatedChildren
    Promise<?> terminationFuture
    EventExecutorChooser chooser
    EventExecutor next()
    {abstract} EventExecutor newChild(Executor executor, args)
}
class MultithreadEventLoopGroup extends MultithreadEventExecutorGroup implements EventLoopGroup
class NioEventLoopGroup extends MultithreadEventLoopGroup {
    EventLoop newChild(Executor executor, Object... args)
}

abstract class SingleThreadEventExecutor extends AbstractScheduledEventExecutor implements EventExecutor {
  Queue<Runnable> taskQueue
  Thread thread
  ThreadProperties threadProperties
  Executor executor
  CountDownLatch threadLock
  Set<Runnable> shutdownHooks
  RejectedExecutionHandler rejectedExecutionHandler
  Promise<?> terminationFuture
  void execute(Runnable task)
  -void startThread()
  void run()
}

class ThreadPerTaskExecutor implements Executor {
  ThreadFactory threadFactory
}

class NioEventLoop extends SingleThreadEventLoop {
  Selector selector
  Selector unwrappedSelector
  SelectedSelectionKeySet selectedKeys
  SelectorProvider provider
  SelectStrategy selectStrategy
}
abstract class SingleThreadEventLoop extends SingleThreadEventExecutor implements EventLoop {
  Queue<Runnable> tailTasks
}
interface IoEventLoopGroup extends EventLoopGroup {
  IoEventLoop next()
  Future<IoRegistration> register(IoHandle handle)
}
interface IoEventLoop extends EventLoop, IoEventLoopGroup
class SingleThreadIoEventLoop extends SingleThreadEventLoop implements IoEventLoop {
  IoHandler ioHandler
}

interface IoHandler {
  IoRegistration register(IoHandle handle)
  int run(IoHandlerContext context)
}

class NioIoHandler implements IoHandler {
  Selector selector
  SelectorProvider provider
}

SingleThreadIoEventLoop *-- IoHandler

SingleThreadEventExecutor *-left- ThreadPerTaskExecutor

@enduml

```



### Channel
`Channel`  A nexus to a network socket or a component which is capable of I/O operations such as read,write,connect and bind.
  A channel provides a user:
  * the current state of the channel (open or connected)
  * the `configuration properties` of the channel(receive buffer size)
  * the `ChannelPipeline` which handles all I/O events and requests associated with the channel

`ChannelFuture` The result of an asynchronous `Channel` I/O operation.

`ServerChannel` A `Channel` that accepts an incoming connection attempt and creates its child `Channel`s by accepting them. 
All I/O operations in Netty are asynchronous. A `ChannelFuture` instance will be returned which gives you the information of about the result or status of I/O operation.

`ChannelPromise` special `ChannelFuture` which is writable.
`ChannelFutureListener` callback function which can be added to the `ChannelFuture`.

`ChannelOutboundInvoker` are methods be called from Application layer to the Transport Layer

`ChannelInboundInvoker` are methods be called from Transport layer to the Application Layer



```plantuml
interface ChannelOutboundInvoker {
  bind()
  connect()
  close()
  register()
  deregister()
  read()
  write()
}

interface Channel extends AttributeMap, ChannelOutboundInvoker {
  EventLoop eventLoop()
  Channel parent()
  boolean isRegistered()
  boolean isActive()
  ChannelPipeline pipeline()
}
interface DuplexChannel extends Channel
interface SocketChannel extends DuplexChannel
interface DatagramChannel extends Channel
abstract class AbstractChannel implements Channel
abstract class AbstractNioChannel extends AbstractChannel
abstract class AbstractNioByteChannel extends AbstractNioChannel
class NioSocketChannel extends AbstractNioByteChannel implements SocketChannel
```

### Channel Handler

* `ChannelHandler` handles an I/O event or intercepts an I/O operation, and forwards it to its next handlers in its `ChannelPipeline`
* `ChannelPipeline` a list of `ChannelHandler`s which handles or intercepts inbound events and outbound operations of a `Channel`



```plantuml
@startuml

top to bottom direction

interface ChannelInboundInvoker << interface >>
interface ChannelOutboundInvoker << interface >>
interface ChannelPipeline  extends ChannelInboundInvoker, ChannelOutboundInvoker {
  ChannelHandler first()
  ChannelPipeline addFirst(String name, ChannelHandler handler)
  ChannelHandler removeFirst()
}

interface ChannelHandlerContext extends AttributeMap, ChannelInboundInvoker, ChannelOutboundInvoker
class DefaultChannelPipeline implements ChannelPipeline{
  ~ head: HeadContext
  ~ tail: TailContext
  - channel: Channel
  - childExecutors: Map<EventExecutorGroup, EventExecutor>
  - estimatorHandle: Handle
  - registered: boolean
  - pendingHandlerCallbackHead: PendingHandlerCallback
  - succeededFuture: ChannelFuture
  - voidPromise: VoidChannelPromise
}
abstract class AbstractChannelHandlerContext implements ChannelHandlerContext {
  AbstractChannelHandlerContext next
  AbstractChannelHandlerContext prev
  DefaultChannelPipeline pipeline
  EventExecutor executor
}
class DefaultChannelHandlerContext extends AbstractChannelHandlerContext {
  ChannelHandler handler
}



DefaultChannelPipeline o-right- DefaultChannelHandlerContext
@enduml
```


```plantuml
title Channel Handler
interface ChannelHandler
interface ChannelInboundHandler extends ChannelHandler
interface ChannelOutboundHandler extends ChannelHandler
class ChannelInboundHandlerAdapter extends ChannelHandlerAdapter implements ChannelInboundHandler
class ChannelOutboundHandlerAdapter extends ChannelHandlerAdapter implements ChannelOutboundHandler
```



# BootStrap

`ServerBootstrap` make it easy to bootstrap a `ServerChannel` 


```plantuml
abstract class AbstractBootstrap<B extends AbstractBootstrap<B, C>, C extends Channel> implements Cloneable {
  EventLoopGroup group
  ChannelFactory<? extends C> channelFactory
  SocketAddress localAddress
  Map<ChannelOption<?>, Object> options
  Map<AttributeKey<?>, Object> attrs
  ChannelHandler handler
  ClassLoader extensionsClassLoader
  ChannelFuture bind(int inetPort)
  abstract void init(Channel channel)
}
class ServerBootstrap extends AbstractBootstrap<ServerBootstrap, ServerChannel> {
  Map<ChannelOption<?>, Object> childOptions
  Map<AttributeKey<?>, Object> childAttrs
  ServerBootstrapConfig config
  EventLoopGroup childGroup
  ChannelHandler childHandler
  void init(Channel channel)
}
```