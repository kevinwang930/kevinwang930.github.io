---
title: "RocketMQ原理与架构"
date: 2024-11-10T11:03:55+08:00
draft: true
categories:
- data
- event
tags:
- data
- event
keywords:
- rocketmq
#thumbnailImage: //example.com/image.jpg
---
本文介绍RocketMQ原理与架构
<!--more-->


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



# Domain Model

* `Message` 最小数据传输单元  消息包含如下属性
  * `Topic` 主题
  * `MessageType` 消息类型 


# Reference

* [RocketMQ原理与架构](https://rocketmq.io/course/baseLearn/rocketmq_learning-framework/)