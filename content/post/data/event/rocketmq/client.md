---
title: "RocketMQ Client Architecture "
date: 2024-11-10T11:03:55+08:00
draft: false
categories:
- data
- event
- rocketmq
tags:
- data
- event
- rocketmq
keywords:
- rocketmq
#thumbnailImage: //example.com/image.jpg
---
This Article Introduces RocketMQ Architecture.
<!--more-->

# rocketmq-client




## Producer Implementation

```plantuml
interface MQAdmin   {
  + createTopic(...)
}
interface MQProducer extends MQAdmin {
  + SendResult send(final Message msg)
}


class DefaultMQProducer extends ClientConfig implements MQProducer {
  DefaultMQProducerImpl defaultMQProducerImpl
}

class DefaultMQProducerImpl implements MQProducerInner {
  RPCHook rpcHook
  ConcurrentMap<String, TopicPublishInfo> topicPublishInfoTable
  MQClientInstance mQClientFactory
  + SendResult send(...)
}

class TopicPublishInfo {
  - orderTopic: boolean
  - messageQueueList: List<MessageQueue>
  - topicRouteData: TopicRouteData
  - haveTopicRouterInfo: boolean
  - sendWhichQueue: ThreadLocalIndex

  + MessageQueue selectOneMessageQueue(QueueFilter ...filter)
}


class MessageQueue {
  - serialVersionUID: long
  - brokerName: String
  - queueId: int
  - topic: String
}

class MQClientInstance {
  - ConcurrentMap<String, MQProducerInner> producerTable
  - ConcurrentMap<String, MQConsumerInner> consumerTable
  - ConcurrentMap<String, MQAdminExtInner> adminExtTable
  - NettyClientConfig nettyClientConfig
  - MQClientAPIImpl mQClientAPIImpl
  - MQAdminImpl mQAdminImpl
  - ConcurrentMap<String, TopicRouteData> topicRouteTable
  - ConcurrentMap<String, ConcurrentMap<MessageQueue, String>> topicEndPointsTable
  - ConcurrentMap<String, HashMap<Long, String>> brokerAddrTable
  - ScheduledExecutorService scheduledExecutorService
  - ScheduledExecutorService fetchRemoteConfigExecutorService
  - PullMessageService pullMessageService
  - RebalanceService rebalanceService
}


interface NameServerUpdateCallback {

}

class MQClientAPIImpl  {
  - log: Logger
  - sendSmartMsg: boolean
  - clientConfig: ClientConfig
  - remotingClient: RemotingClient
  - topAddressing: TopAddressing
  - clientRemotingProcessor: ClientRemotingProcessor
  - nameSrvAddr: String

  + SendResult sendMessage(...)
}











DefaultMQProducer *-- DefaultMQProducerImpl
DefaultMQProducerImpl o-right- TopicPublishInfo
TopicPublishInfo o-- MessageQueue
DefaultMQProducerImpl *-- MQClientInstance
MQClientInstance *-- MQClientAPIImpl
NameServerUpdateCallback <|... MQClientAPIImpl
StartAndShutdown <|.. MQClientAPIImpl


```



# rocketmq-spring
rocketmq-spring integrate RocketMQ with Spring Boot

`RocketMQAutoConfiguration` creates `DefaultMQProducer` and `DefaultLitePullConsumer` based on `RocketMQProperties`
`RocketMQTemplate` is created with producer and consumer as bean dependencies.

`RocketMQMessageListenerBeanPostProcessor` registers `Consumer`s based on the `RocketMQMessageListener` annotation and `RocketMQProperties`

```plantuml

class RocketMQAutoConfiguration implements ApplicationContextAware


class RocketMQProperties
interface MQAdmin  
interface MQProducer extends MQAdmin
class DefaultMQProducer  implements MQProducer

class DefaultLitePullConsumer  implements LitePullConsumer


class MessageConverterConfiguration 

class RocketMQMessageConverter

class RocketMQTemplate 

RocketMQAutoConfiguration-> RocketMQProperties: createBean
RocketMQAutoConfiguration-> DefaultLitePullConsumer: createBean
RocketMQAutoConfiguration--> DefaultMQProducer: createBean
RocketMQAutoConfiguration---> RocketMQTemplate: createBean
DefaultMQProducer  <- RocketMQProperties: properties
RocketMQProperties -right> DefaultLitePullConsumer: properties

MessageConverterConfiguration ---> RocketMQMessageConverter: createBean
RocketMQMessageConverter --> DefaultMQProducer: injection
RocketMQMessageConverter --> DefaultLitePullConsumer: injection

DefaultMQProducer --> RocketMQTemplate:injection
DefaultLitePullConsumer --> RocketMQTemplate:injection


```
```plantuml
title RocketMQConsumer

class RocketMQMessageListenerBeanPostProcessor implements ApplicationContextAware, BeanPostProcessor, InitializingBean, SmartLifecycle {
  RocketMQMessageListenerContainerRegistrar registrar
  Object postProcessAfterInitialization(bean,beanName)
}

class RocketMQMessageListenerContainerRegistrar {
  registerContainer(beanName,bean, annotation)
}

class RocketMqListener

RocketMQMessageListenerBeanPostProcessor --> RocketMQMessageListenerContainerRegistrar: register bean
RocketMQMessageListenerContainerRegistrar --> RocketMqListener: register





```



# Reference

* [RocketMQ原理与架构](https://rocketmq.io/course/baseLearn/rocketmq_learning-framework/)