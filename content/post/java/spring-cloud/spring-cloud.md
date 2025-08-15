---
title: "Spring Cloud 微服务框架"
date: 2024-04-30T18:03:51+08:00
draft: true
draft: true
categories:
- java
- springCloud
tags:
- springCloud
keywords:
- spring cloud
#thumbnailImage: //example.com/image.jpg
---
<!--more-->


# Context

## BootstrapApplicationListener

A listener that prepares a SpringApplication by delegating to `ApplicationContextInitializer` beans in a separate bootstrap context.

```plantuml

interface  ApplicationListener
class BootstrapApplicationListener implements ApplicationListener {
    onApplicationEvent(event)
}



Class BootStrapApplicationContext


class BootstrapImportSelectorConfiguration {}

BootstrapApplicationListener --> BootStrapApplicationContext: create

BootStrapApplicationContext --> BootstrapImportSelectorConfiguration: source

BootstrapImportSelectorConfiguration --> BootstrapImportSelector: import

BootstrapImportSelector-->BootstrapConfiguration:loadFactory


class PropertySourceBootstrapConfiguration {
    List<PropertySourceLocator> propertySourceLocators
}

BootstrapConfiguration <|-- PropertySourceBootstrapConfiguration


```


# gateway

Spring gateway provides a simple , yet effective way to route to APIs and provide cross cutting concerns such as security, resiliency.
route code example:


# service registration and discovery


# loadBalancer
spring cloud provides client-side load balancer.
LoadBalancerClient configured in client spring boot application.

# sentinel
Alibaba sentinel often used as flow control, traffic shaping, concurrency limiting, circuit breaking and overload protection.

# actuator

`spring-boot-actuator`  helps monitor and manage your application.

actuator provides endpoints to monitor and interact with application.
common endpoints include:
```
health
```


# General microServices and Structures

## Auth

```plantuml
title: microservice architecture
left to right direction
actor user
rectangle gateway
rectangle auth 
rectangle system
rectangle BizModule
user --> gateway

gateway --> auth: login

gateway --> system: api
auth -right-> system : feign
gateway --> BizModule: bizApi
BizModule -left-> system: feign
```









