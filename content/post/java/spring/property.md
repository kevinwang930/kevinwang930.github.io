---
title: "Property"
date: 2024-05-30T18:17:31+08:00
categories:
- java
- spring
tags:
- spring
- property
keywords:
- spring
#thumbnailImage: //example.com/image.jpg
---

本文记录spring配置和属性的加载过程
<!--more-->


# SpringFactoriesLoader

General purpose factory loading mechanism for internal use within the framework.
`SpringFactoriesLoader` loads and instantiates factories of a given type from "META-INF/spring.factories" files which may be present in multiple JAR files in the class path.


```plantuml

class SpringFactoriesLoader {
    ClassLoader classLoader
    Map<String, List<String>> factories
    loadFactoriesResource(classLoader, location)
    <T> T instantiateFactory(name,type,argumentResolver,failureHandler)
}

```

# SpringBoot Factory

## ApplicationContextFactory
Strategy interface for creating applicationContext and ApplicationEnvironment.

```plantuml
interface ApplicationContextFactory {
    ConfigurableEnvironment createEnvironment(applicationType)
    ConfigurableApplicationContext create(applicationType)
}

class ServletWebServerApplicationContextFactory implements ApplicationContextFactory

ServletWebServerApplicationContextFactory --> ApplicationServletEnvironment: createEnv
ServletWebServerApplicationContextFactory --> ServletWebServerApplicationContext: create Context
```


```plantuml
title: ApplicationServletEnvironment
skinparam linetype ortho


' Declare interfaces
interface PropertyResolver <<interface>>
interface ConfigurablePropertyResolver <<interface>>
interface Environment <<interface>>
interface ConfigurableEnvironment <<interface>>
interface ConfigurableWebEnvironment <<interface>>

' Declare classes
class AbstractEnvironment {
    Set<String> activeProfiles
    Set<String> defaultProfiles
    MutablePropertySources propertySources
    ConfigurablePropertyResolver propertyResolver
    protected void customizePropertySources(propertySources)
}
class StandardEnvironment {
    protected void customizePropertySources(propertySources)
}
note "system properties system envs" as p1
StandardEnvironment .. p1
class StandardServletEnvironment {
    protected void customizePropertySources(propertySources)
}
class ApplicationServletEnvironment

' Define relationships with arrow pointing from class to interface (left to right)
PropertyResolver <|-- ConfigurablePropertyResolver
Environment <|-- ConfigurableEnvironment
PropertyResolver <|-- Environment
ConfigurablePropertyResolver<|-- ConfigurableEnvironment
ConfigurableEnvironment <|-- ConfigurableWebEnvironment
ConfigurableEnvironment <|-- AbstractEnvironment
AbstractEnvironment  <|-- StandardEnvironment
 StandardEnvironment  <-- StandardServletEnvironment
ConfigurableWebEnvironment  <|-- StandardServletEnvironment
StandardServletEnvironment <|-- ApplicationServletEnvironment        
```

### Environment creation and configuration

```plantuml

package SpringBoot {
    class SpringApplication  {
        ConfigurableEnvironment environment
        getOrCreateEnvironment()
        configureEnvironment(env, sourceArgs)
    }
    class ApplicationServletEnvironment
SpringApplication *-- ApplicationServletEnvironment
}
```

reference: [博客](https://cloud.tencent.com/developer/article/2342951)


## EnvironmentPostProcessorApplicationListener

```plantuml
@startuml

!theme plain
top to bottom direction
skinparam linetype ortho

class ApplicationEvent
interface ApplicationListener<E> << interface >> {
    void onApplicationEvent(E event)
}
class EnvironmentPostProcessorApplicationListener {
    Function<ClassLoader, EnvironmentPostProcessorsFactory> postProcessorsFactory
    getEnvironmentPostProcessors(resourceLoader,bootstrapContext)
}
interface EventListener << interface >>
annotation FunctionalInterface << annotation >>
interface Ordered << interface >>
interface SmartApplicationListener << interface >> {
    boolean supportsEventType(eventType)
    int getOrder()
}

ApplicationListener                          -[#595959,dashed]->  ApplicationEvent                            
ApplicationListener                          -[#008200,plain]-^  EventListener                               
ApplicationListener                          -[#999900,dotted]-  FunctionalInterface                         
EnvironmentPostProcessorApplicationListener  -[#008200,dashed]-^  Ordered                                     
EnvironmentPostProcessorApplicationListener  -[#008200,dashed]-^  SmartApplicationListener                    
SmartApplicationListener                     -[#008200,plain]-^  ApplicationListener                         
SmartApplicationListener                     -[#008200,plain]-^  Ordered                                     
@enduml

```



