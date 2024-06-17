---
title: "Spring"
date: 2024-06-08T18:30:11+08:00
categories:
- java
- spring
tags:
- java
- spring
keywords:
- spring
#thumbnailImage: //example.com/image.jpg
---
本文介绍spring架构
<!--more-->

![alt text]( images/image.png)

# 1. Core



## 1.1 Environment 

Environment Interface is an abstraction in container that models 2 key aspects of application environment.

### profile
A profile is a named, logical group of bean definitions to be registered with the container only if the given profile is active

### properties
Properties play an important role in almost all applications and may originate from a variety of sources: properties files, JVM system properties, system environment variables, JNDI, servlet context parameters, ad-hoc Properties objects, Map objects, and so on


```plantuml
title: Environment
skinparam linetype ortho


' Declare interfaces
interface PropertyResolver <<interface>> {
    boolean containsProperty(String key)
    String getProperty(String key)
}
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
    protected ConfigurablePropertyResolver createPropertyResolver( propertySources)
}
class StandardEnvironment {
    protected void customizePropertySources(propertySources)
}
note "system properties system envs" as p1
StandardEnvironment .. p1
class StandardServletEnvironment {
    protected void customizePropertySources(propertySources)
}
package SpringBoot {
    class ApplicationServletEnvironment {

    }
}


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

# 2. Context

```plantuml
@startuml
scale 1536 width
!theme plain
top to bottom direction
skinparam linetype ortho
package SpringBoot {
class AnnotationConfigServletWebServerApplicationContext
}
class AbstractApplicationContext
interface AliasRegistry << interface >>
interface AnnotationConfigRegistry << interface >>

interface ApplicationContext << interface >>
interface ApplicationEventPublisher << interface >>
interface AutoCloseable << interface >>
interface BeanDefinitionRegistry << interface >>
interface BeanFactory << interface >>
interface Closeable << interface >>
interface ConfigurableApplicationContext << interface >>
interface ConfigurableWebApplicationContext << interface >>
interface ConfigurableWebServerApplicationContext << interface >>
class DefaultResourceLoader
annotation Deprecated << annotation >>
interface EnvironmentCapable << interface >>
annotation FunctionalInterface << annotation >>
class GenericApplicationContext
class GenericWebApplicationContext
interface HierarchicalBeanFactory << interface >>
interface Lifecycle << interface >>
interface ListableBeanFactory << interface >>
interface MessageSource << interface >>
interface ResourceLoader << interface >>
interface ResourcePatternResolver << interface >>
class ServletWebServerApplicationContext
interface ThemeSource << interface >>
interface WebApplicationContext << interface >>
interface WebServerApplicationContext << interface >>

AbstractApplicationContext                          -[#008200,dashed]-^  ConfigurableApplicationContext                     
AbstractApplicationContext                          -[#000082,plain]-^  DefaultResourceLoader                              
AnnotationConfigServletWebServerApplicationContext  -[#008200,dashed]-^  AnnotationConfigRegistry                           
AnnotationConfigServletWebServerApplicationContext  -[#000082,plain]-^  ServletWebServerApplicationContext                 
ApplicationContext                                  -[#008200,plain]-^  ApplicationEventPublisher                          
ApplicationContext                                  -[#008200,plain]-^  EnvironmentCapable                                 
ApplicationContext                                  -[#008200,plain]-^  HierarchicalBeanFactory                            
ApplicationContext                                  -[#008200,plain]-^  ListableBeanFactory                                
ApplicationContext                                  -[#008200,plain]-^  MessageSource                                      
ApplicationContext                                  -[#008200,plain]-^  ResourcePatternResolver                            
ApplicationEventPublisher                           -[#999900,dotted]-  FunctionalInterface                                
BeanDefinitionRegistry                              -[#008200,plain]-^  AliasRegistry                                      
Closeable                                           -[#008200,plain]-^  AutoCloseable                                      
ConfigurableApplicationContext                      -[#008200,plain]-^  ApplicationContext                                 
ConfigurableApplicationContext                      -[#008200,plain]-^  Closeable                                          
ConfigurableApplicationContext                      -[#008200,plain]-^  Lifecycle                                          
ConfigurableWebApplicationContext                   -[#008200,plain]-^  ConfigurableApplicationContext                     
ConfigurableWebApplicationContext                   -[#008200,plain]-^  WebApplicationContext                              
ConfigurableWebServerApplicationContext             -[#008200,plain]-^  ConfigurableApplicationContext                     
ConfigurableWebServerApplicationContext             -[#008200,plain]-^  WebServerApplicationContext                        
DefaultResourceLoader                               -[#008200,dashed]-^  ResourceLoader                                     
GenericApplicationContext                           -[#000082,plain]-^  AbstractApplicationContext                         
GenericApplicationContext                           -[#008200,dashed]-^  BeanDefinitionRegistry                             
GenericWebApplicationContext                        -[#008200,dashed]-^  ConfigurableWebApplicationContext                  
GenericWebApplicationContext                        -[#000082,plain]-^  GenericApplicationContext                          
GenericWebApplicationContext                        -[#008200,dashed]-^  ThemeSource                                        
HierarchicalBeanFactory                             -[#008200,plain]-^  BeanFactory                                        
ListableBeanFactory                                 -[#008200,plain]-^  BeanFactory                                        
ResourcePatternResolver                             -[#008200,plain]-^  ResourceLoader                                     
ServletWebServerApplicationContext                  -[#008200,dashed]-^  ConfigurableWebServerApplicationContext            
ServletWebServerApplicationContext                  -[#000082,plain]-^  GenericWebApplicationContext                       
ThemeSource                                         -[#999900,dotted]-  Deprecated                                         
WebApplicationContext                               -[#008200,plain]-^  ApplicationContext                                 
WebServerApplicationContext                         -[#008200,plain]-^  ApplicationContext                                 
@enduml

```

## 2.1 Event
 
`ApplicationEventMulticaster` Interface to be implemented by objects that can manage a number of `Applicationlistener` objects and publish events to them.

`SimpleApplicationEventMulticaster` is the simple implementation of the `ApplicationEventMulticaster` interface.Multicasts all events to all registered listeners.
```plantuml
@startuml

!theme plain
top to bottom direction
skinparam linetype ortho

class ApplicationEvent {
   
}
interface ApplicationListener<E> << interface >> {
     void onApplicationEvent(E event)
}
interface EventListener << interface >>
interface ApplicationEventPublisher {
    void publishEvent(ApplicationEvent event) 
}

interface ApplicationEventMulticaster {
    void addApplicationListener(ApplicationListener<?> listener)
    void addApplicationListenerBean(String listenerBeanName)
    void multicastEvent(ApplicationEvent event)
}

ApplicationListener  -[#595959,dashed]->  ApplicationEvent    
ApplicationListener  -[#008200,plain]-^  EventListener     
ApplicationEventPublisher --> ApplicationEventMulticaster: publish
ApplicationEventMulticaster --> ApplicationListener: multicast
ApplicationEventPublisher <|-- ApplicationContext
@enduml
```



```plantuml
title: SimpleApplicationEventMulticaster
@startuml

!theme plain
top to bottom direction
skinparam linetype ortho

class AbstractApplicationEventMulticaster {
    ClassLoader beanClassLoader
    ConfigurableBeanFactory beanFactory
    DefaultListenerRetriever defaultRetriever
}
interface ApplicationEventMulticaster << interface >> {
    void multicastEvent(ApplicationEvent event)
}
interface Aware << interface >>
interface BeanClassLoaderAware << interface >> {
    void setBeanClassLoader(ClassLoader classLoader)
}
interface BeanFactoryAware << interface >> {
    void setBeanFactory(BeanFactory beanFactory)
}
class SimpleApplicationEventMulticaster {
    Executor taskExecutor
}

class DefaultListenerRetriever {
    Set<ApplicationListener<?>> applicationListeners
    Set<String> applicationListenerBeans
}


AbstractApplicationEventMulticaster *-left- DefaultListenerRetriever

AbstractApplicationEventMulticaster  -[#008200,dashed]-^  ApplicationEventMulticaster         
AbstractApplicationEventMulticaster  -[#008200,dashed]-^  BeanClassLoaderAware                
AbstractApplicationEventMulticaster  -[#008200,dashed]-^  BeanFactoryAware                    
BeanClassLoaderAware                 -[#008200,plain]-^  Aware                               
BeanFactoryAware                     -[#008200,plain]-^  Aware                               
SimpleApplicationEventMulticaster    -[#000082,plain]-^  AbstractApplicationEventMulticaster 
@enduml

```


