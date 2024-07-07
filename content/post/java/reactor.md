---
title: "Reactor Project in Java"
date: 2024-07-03T14:50:33+08:00
categories:
- java
- reactor
tags:
- reactor
- NIO
keywords:
- reactor
#thumbnailImage: //example.com/image.jpg
---
本文介绍Java生态中重量级非阻塞应用库 Project Reactor
<!--more-->

Reactor is a fourth-generation reactive library, based on Reactive Streams specification, for building non-blocking applications on JVM


# Reactive Streams

Reactive Streams is a standard and specification for Stream-oriented libraries for JVM that
* process a potentially unbounded number of elements
* in sequence
* asynchronously passing elements between components
* with mandatory non-blocking backpressure.


## API components
1. publisher
2. subscriber
3. subscription
4. processor

`Publisher` is a provider of a potentially unbounded number of sequences elements, publishing them according to the demand received from its Subscribers.

In response to a call to `Publisher.subscribe(Subscriber)` the possible invocation sequences for methods on the `Subscriber` are give by the following protocol:
```
onSubscribe onNext* (onError | onComplete)?
```
This means that `onSubscribe` is always signaled, followed by a possibly unbounded number of `onNext` signals(as requested by `Subscriber`) followed by an `onError` signal if there is a failure, or an `onComplete` signal when no more elements are available 



# Reactor API

## Mono
A Reactive Streams Publisher with basic rx operations that emits at most one item via `onNext` signal then terminates with `onComplete` signal, or only emits `onError` signal.

```plantuml
interface HttpHandler {
    Mono<Void> handle( request,  response)
}

interface Publisher<T> {
    void subscribe(subscriber)
}

interface CorePublisher<T> extends Publisher {
    void subscribe(coreSubscriber)
}

interface Subscriber<T> {
    void onSubscribe(Subscription var1)
    void onNext(T var)
    void onError(Throwable var)
    void onComplete()
}

interface CoreSubscriber<T> extends Subscriber {

    Context currentContext()
    void onSubscribe(Subscription s)
}

interface Subscription {
    void request(long var)
    void cancel()
}


abstract class Mono<T> implements CorePublisher {

}

HttpHandler -right-> Mono : return
```