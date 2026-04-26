---
title: "Spring kafka implementation"
date: 2026-03-29T13:47:04+02:00
categories:
- event
- kafka
- spring
tags:
- kafka
- spring
keywords:
- kafka
- spring
#thumbnailImage: //example.com/image.jpg
---
This article introduces spring kafka Implementation
<!--more-->


```plantuml


interface KafkaListenerEndpoint {
  + getAckMode(): String?
  + setupListenerContainer(MessageListenerContainer, MessageConverter?): void
  + getGroup(): String?
  + getTopicPartitionsToAssign(): TopicPartitionOffset[]?
  + getTopics(): Collection<String>?
  + getConcurrency(): Integer?
  + getConsumerProperties(): Properties?
}



interface DisposableBean {
  + destroy(): void
}
interface Lifecycle {
  + start(): void
  + stop(): void
  + isRunning(): boolean
}
interface MessageListenerContainer extends SmartLifecycle, DisposableBean {
  + setupMessageListener(Object): void
}
interface Phased  {
  + getPhase(): int
}
interface SmartLifecycle extends Lifecycle, Phased  {
  + stop(Runnable): void
  + isPauseable(): boolean
  + getPhase(): int
  + isAutoStartup(): boolean
}

interface GenericMessageListenerContainer<K, V> extends MessageListenerContainer
abstract class AbstractMessageListenerContainer<K, V> implements GenericMessageListenerContainer {
    ContainerProperties containerProperties
    ConsumerFactory<K, V> consumerFactory
    KafkaAdmin kafkaAdmin
}



class KafkaMessageListenerContainer<K, V> extends AbstractMessageListenerContainer {
    ListenerConsumer listenerConsumer

}


class ConcurrentMessageListenerContainer<K, V> extends AbstractMessageListenerContainer {
    List<KafkaMessageListenerContainer<K, V>> containers 
    List<AsyncTaskExecutor> executors 
    int concurrency
}

ConcurrentMessageListenerContainer o- KafkaMessageListenerContainer

```
