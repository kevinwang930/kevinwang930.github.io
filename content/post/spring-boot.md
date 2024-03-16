---
title: "Spring internals"
date: 2024-01-09T23:29:20+08:00
categories:
- java
- spring
tags: ["spring"]
draft: false
mermaid: true
---

本文记录spring和springBoot 内部实现

# Environment abstraction

Environment Interface is an abstraction in container that models 2 key aspects of application environment.

## profile
A profile is a named, logical group of bean definitions to be registered with the container only if the given profile is active

## properties
Properties play an important role in almost all applications and may originate from a variety of sources: properties files, JVM system properties, system environment variables, JNDI, servlet context parameters, ad-hoc Properties objects, Map objects, and so on

```plantuml
interface PropertyResolver {
+ boolean containsProperty(String)
+ String getProperty(String)
+ String getProperty(String,String)
+ T getProperty(String,Class<T>)
+ T getProperty(String,Class<T>,T)
+ String getRequiredProperty(String)
+ T getRequiredProperty(String,Class<T>)
+ String resolvePlaceholders(String)
+ String resolveRequiredPlaceholders(String)
}

interface Environment {
+ String[] getActiveProfiles()
+ String[] getDefaultProfiles()
+ boolean matchesProfiles(String)
+ boolean acceptsProfiles(String)
+ boolean acceptsProfiles(Profiles)
}

interface ConfigurablePropertyResolver {
    + ConfigurableConversionService getConversionService()
    + void setConversionService(ConfigurableConversionService)
    + void setPlaceholderPrefix(String)
    + void setPlaceholderSuffix(String)
    + void setValueSeparator(String)
    + void setEscapeCharacter(Character)
    + void setIgnoreUnresolvableNestedPlaceholders(boolean)
    + void setRequiredProperties(String)
    + void validateRequiredProperties()
}

interface ConfigurableEnvironment {
+ void setActiveProfiles(String)
+ void addActiveProfile(String)
+ void setDefaultProfiles(String)
+ MutablePropertySources getPropertySources()
+ Map<String,Object> getSystemProperties()
+ Map<String,Object> getSystemEnvironment()
+ void merge(ConfigurableEnvironment)
}



Environment <|-- ConfigurableEnvironment
ConfigurablePropertyResolver <|-- ConfigurableEnvironment

PropertyResolver <|-- ConfigurablePropertyResolver
PropertyResolver <|-- Environment
```


#  Application context
The BeanFactory interface provides an advanced configuration mechanism capable of managing any type of object. ApplicationContext is a sub-interface of BeanFactory
```plantuml
interface BeanFactory
interface HierarchicalBeanFactory extends BeanFactory
interface ListableBeanFactory extends BeanFactory
interface ApplicationContext extends EnvironmentCapable, ListableBeanFactory, HierarchicalBeanFactory,MessageSource, ApplicationEventPublisher, ResourcePatternResolver

class SpringApplication {
    WebApplicationType webApplicationType
    List<ApplicationContextInitializer<?>> initializers
    List<ApplicationListener<?>> listeners
    ApplicationContextFactory applicationContextFactory
    ConfigurableApplicationContext run(String... args)
    void prepareContext()
}
interface ConfigurableApplicationContext extends ApplicationContext {
    void refresh()
}

SpringApplication -right-> ConfigurableApplicationContext:create
```