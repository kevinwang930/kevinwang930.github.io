---
title: "RocketMQ Network implementation"
date: 2025-06-18T21:07:39+07:00
categories:
- data
- event
tags:
- data
- event
- rocketmq
keywords:
- rocketmq
#thumbnailImage: //example.com/image.jpg
---
This Article introduces RocketMQ network implementation

<!--more-->


## RocketMQ remoting
RocketMQ remoting provides a single API for most network related service that uses pluggable transports and codecs. The remoting API provides the ability for making synchronous, asynchronous, oneway remote calls,  push and pull callbacks.

```plantuml
@startuml





interface RemotingService  {
  + start(): void
  + setRequestPipeline(RequestPipeline): void
  + registerRPCHook(RPCHook): void
  + clearRPCHook(): void
  + shutdown(): void
}
interface RemotingClient extends RemotingService {
  + invokeAsync(String, RemotingCommand, long, InvokeCallback): void
  + getAvailableNameSrvList(): List<String>
  + registerProcessor(int, NettyRequestProcessor, ExecutorService): void
  + closeChannels(List<String>): void
  + isChannelWritable(String): boolean
  + invoke(String, RemotingCommand, long): CompletableFuture<RemotingCommand>
  + getNameServerAddressList(): List<String>
  + setCallbackExecutor(ExecutorService): void
  + isAddressReachable(String): boolean
  + updateNameServerAddressList(List<String>): void
  + invokeOneway(String, RemotingCommand, long): void
  + invokeSync(String, RemotingCommand, long): RemotingCommand
}


   
@enduml




```


## Netty Implementation

The default RocketMQ network implementation is based on Netty. It defines its own protocol and codec.


### Client


```plantuml
class NettyRemotingAbstract {
  # defaultRequestProcessorPair: Pair<NettyRequestProcessor, ExecutorService>
  # semaphoreAsync: Semaphore
  # responseTable: ConcurrentMap<Integer, ResponseFuture>
  # processorTable: HashMap<Integer, Pair<NettyRequestProcessor, ExecutorService>>
  # sslContext: SslContext
  # requestPipeline: RequestPipeline
  # semaphoreOneway: Semaphore
  # isShuttingDown: AtomicBoolean
  # nettyEventExecutor: NettyEventExecutor
  # rpcHooks: List<RPCHook>
}

class NettyRemotingClient extends NettyRemotingAbstract implements RemotingClient {
  - eventLoopGroupWorker: EventLoopGroup
  - bootstrapMap: ConcurrentHashMap<String, Bootstrap>
  - publicExecutor: ExecutorService
  - channelEventListener: ChannelEventListener
  - defaultEventExecutorGroup: EventExecutorGroup
  - proxyMap: Map<String, SocksProxyConfig>
  - channelWrapperTables: ConcurrentMap<Channel, ChannelWrapper>
  - scanExecutor: ExecutorService
  - bootstrap: Bootstrap
  - callbackExecutor: ExecutorService
  - channelTables: ConcurrentMap<String, ChannelWrapper>
} 


```
