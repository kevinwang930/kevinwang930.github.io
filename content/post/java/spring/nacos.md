---
title: "NACOS - service and configuration management"
date: 2024-06-10T17:45:28+08:00
categories:
- java
- spring
tags:
- spring
- nacos
keywords:
- nacos
#thumbnailImage: //example.com/image.jpg
---
This Article introduces NACOS 

<!--more-->

# Dynamic Configuration Management

NACOS allows user to manage the configuration of all applications and services in a centralized , externalized and dynamic manner across all environments





```plantuml

interface BootstrapConfiguration 

class NacosConfigBootstrapConfiguration {
    Bean NacosConfigManager
    Bean NacosPropertySourceLocator
}

interface  PropertySourceLocator {
    PropertySource<?> locate(Environment environment)
}

class NacosPropertySourceLocator implements PropertySourceLocator



BootstrapConfiguration <|-- NacosConfigBootstrapConfiguration 
NacosConfigBootstrapConfiguration --> NacosPropertySourceLocator: create

```

## API
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




