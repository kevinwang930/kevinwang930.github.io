---
title: "Spring Webflux"
date: 2024-05-29T19:43:22+08:00
categories:
- java
- spring
tags:
- spring
- webflux
keywords:
- webflux
#thumbnailImage: //example.com/image.jpg
---
本文介绍 spring-webflux

<!--more-->


WebFlux is non-blocking, asynchronous web framework based on project Reactor.

Servlet API is synchronous (Filter, Servlet) or blocking(getParameter, getPart) which can not used directly in webFlux.


# API

## Mono
A Reactive Streams Publisher with basic rx operations that emits at most one item via `onNext` signal then terminates with `onComplete` signal, or only emits `onError` signal.

```plantuml


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
    cache()
    Mono<T> doOnCancel(onCancel)
    Mono<T> doOnNext(onNext)
    Mono<T> filter(tester)
    Flux<T> expand(expander)
    Mono<R> flatMap(transformer)
    Mono<Boolean> hasElement()
    Mono<T> onErrorComplete()
    Mono<T> retry()
    Disposable subscribe()
    Mono<V> then(Mono<V> other)
}

class Flux<T> implements CorePublisher {

}


Subscriber -left-> Publisher
Subscriber -right-> Subscription
```