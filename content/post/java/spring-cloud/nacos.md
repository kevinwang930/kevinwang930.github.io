---
title: "NACOS - service and configuration management"
date: 2024-06-10T17:45:28+08:00
categories:
- java
- spring-cloud
tags:
- spring-cloud
- nacos
keywords:
- nacos
#thumbnailImage: //example.com/image.jpg
---
This Article introduces NACOS 

<!--more-->

# Starter


## Config

NACOS allows user to manage the configuration of all applications and services in a centralized , externalized and dynamic manner across all environments

`NacosPropertySource` represents nacos config with unique dataId in group

`NacosContextRefresher` add nacos listeners to all application level dataIds, when there is a change in the data, listeners will refresh configurations.


```plantuml



class  NacosContextRefresher implements ApplicationListener, ApplicationContextAware {
    NacosConfigProperties nacosConfigProperties
    ConfigService configService
    NacosConfigManager configManager
    ApplicationContext applicationContext
    Map<String, Listener> listenerMap
}

abstract class AbstractSharedListener implements Listener {
    String dataId
    String group
    abstract void innerReceive(String dataId, String group, String configInfo)
}


class NacosConfigService implements ConfigService {
    ClientWorker worker
    String namespace
    ConfigFilterChainManager configFilterChainManager
}

class ClientWorker implements Closeable {
    AtomicReference<Map<String, CacheData>> cacheMap
    ConfigRpcTransportClient agent
}

class CacheData {
    String envName
    String dataId
    String group
    String tenant
    String content
    List<ManagerListenerWrap> listeners
}
abstract class ConfigTransportClient {
    ScheduledExecutorService executor
    ServerListManager serverListManager
    abstract void startInternal()
}


class ConfigRpcTransportClient extends ConfigTransportClient {
    Map<String, ExecutorService> multiTaskExecutor
    BlockingQueue<Object> listenExecutebell
    RpcClient ensureRpcClient(String taskId)
}

class RpcClientFactory {
    static void destroyClient(String clientName)
    static RpcClient getClient(String clientName)
    static RpcClient createClient(clientName,connectionType,labels)
}

NacosContextRefresher o-- AbstractSharedListener
NacosConfigService *-- ClientWorker
ClientWorker o---- CacheData
CacheData *-- AbstractSharedListener
ClientWorker o-- ConfigRpcTransportClient 
ConfigRpcTransportClient -->  RpcClientFactory: get


```









# Bootstrap
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




