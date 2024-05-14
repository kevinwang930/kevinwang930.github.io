---
title: "Spring Cloud 微服务框架"
date: 2024-04-30T18:03:51+08:00
categories:
- java
- spring
- cloud
tags:
- springCloud
keywords:
- spring cloud
#thumbnailImage: //example.com/image.jpg
---
<!--more-->

# gateway

Spring gateway provides a simple , yet effective way to route to APIs and provide cross cutting concerns such as security, resiliency.
route code example:
```
@Bean
    public RouteLocator routes(RouteLocatorBuilder builder,UriConfiguration uriConfiguration) {
        String httpUri = uriConfiguration.getHttpbin();
        return builder.routes().route(p -> p.path("/get")
                        .filters(f -> f.addRequestHeader("Hello", "world"))
                        .uri(httpUri))
                .route(p->p.host("*.circuitbreaker.com")
                        .filters(f->f.circuitBreaker(config -> config.setName("mycmd").setFallbackUri("forward" +
                                ":/fallback")))
                        .uri(httpUri))
                .build();
    }
```

# service registration and discovery

## nacos
Naming and Configuration Service

Service registration
```
curl -X POST 'http://127.0.0.1:8848/nacos/v1/ns/instance?serviceName=nacos.naming.serviceName&ip=20.18.7.10&port=8080'
```
Service discovery
```
curl -X GET 'http://127.0.0.1:8848/nacos/v1/ns/instance/list?serviceName=nacos.naming.serviceName'
```
Publish Config
```
curl -X POST "http://127.0.0.1:8848/nacos/v1/cs/configs?dataId=nacos.cfg.dataId&group=test&content=helloWorld"
```
Get config
```
curl -X GET "http://127.0.0.1:8848/nacos/v1/cs/configs?dataId=nacos.cfg.dataId&group=test"
```


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









