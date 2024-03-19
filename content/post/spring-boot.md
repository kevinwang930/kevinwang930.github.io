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

# 1. Environment abstraction

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


# 2. Application context
The BeanFactory interface provides an advanced configuration mechanism capable of managing any type of object. ApplicationContext is a sub-interface of BeanFactory
```plantuml

top to bottom direction
package Spring {

    interface BeanFactory {
        + {static} String FACTORY_BEAN_PREFIX
        + Object getBean(String)
        + T getBean(String,Class<T>)
        + Object getBean(String,Object)
        + T getBean(Class<T>)
        + T getBean(Class<T>,Object)
        + ObjectProvider<T> getBeanProvider(Class<T>)
        + ObjectProvider<T> getBeanProvider(ResolvableType)
        + boolean containsBean(String)
        + boolean isSingleton(String)
        + boolean isPrototype(String)
        + boolean isTypeMatch(String,ResolvableType)
        + boolean isTypeMatch(String,Class<?>)
        + Class<?> getType(String)
        + Class<?> getType(String,boolean)
        + String[] getAliases(String)
    }
    interface HierarchicalBeanFactory extends BeanFactory
interface ListableBeanFactory extends BeanFactory
interface ApplicationContext extends EnvironmentCapable, ListableBeanFactory, HierarchicalBeanFactory,MessageSource, ApplicationEventPublisher, ResourcePatternResolver

interface ConfigurableApplicationContext  {
    void refresh()
}

class GenericApplicationContext {
- DefaultListableBeanFactory beanFactory
- ResourceLoader resourceLoader
- boolean customClassLoader
- AtomicBoolean refreshed
+ void setParent(ApplicationContext)
+ void setApplicationStartup(ApplicationStartup)
+ void setAllowBeanDefinitionOverriding(boolean)
+ void setAllowCircularReferences(boolean)
+ void setResourceLoader(ResourceLoader)
+ Resource getResource(String)
+ Resource[] getResources(String)
+ void setClassLoader(ClassLoader)
+ ClassLoader getClassLoader()
# void refreshBeanFactory()
# void cancelRefresh(Throwable)
# void closeBeanFactory()
+ ConfigurableListableBeanFactory getBeanFactory()
+ DefaultListableBeanFactory getDefaultListableBeanFactory()
+ AutowireCapableBeanFactory getAutowireCapableBeanFactory()
+ void registerBeanDefinition(String,BeanDefinition)
+ void removeBeanDefinition(String)
+ BeanDefinition getBeanDefinition(String)
+ boolean isBeanDefinitionOverridable(String)
+ boolean isBeanNameInUse(String)
+ void registerAlias(String,String)
+ void removeAlias(String)
+ boolean isAlias(String)
+ void refreshForAotProcessing(RuntimeHints)
- void preDetermineBeanTypes(RuntimeHints)
+ void registerBean(Class<T>,Object)
+ void registerBean(String,Class<T>,Object)
+ void registerBean(Class<T>,BeanDefinitionCustomizer)
+ void registerBean(String,Class<T>,BeanDefinitionCustomizer)
+ void registerBean(Class<T>,Supplier<T>,BeanDefinitionCustomizer)
+ void registerBean(String,Class<T>,Supplier<T>,BeanDefinitionCustomizer)
}


class GenericApplicationContext$ClassDerivedBeanDefinition {
+ Constructor<?>[] getPreferredConstructors()
+ RootBeanDefinition cloneBeanDefinition()
}

abstract class AbstractApplicationContext {

}


class GenericWebApplicationContext {
- ServletContext servletContext
- ThemeSource themeSource
+ void setServletContext(ServletContext)
+ ServletContext getServletContext()
+ String getApplicationName()
+ Theme getTheme(String)
+ void setServletConfig(ServletConfig)
+ ServletConfig getServletConfig()
+ void setNamespace(String)
+ String getNamespace()
+ void setConfigLocation(String)
+ void setConfigLocations(String)
+ String[] getConfigLocations()
}




ConfigurableWebApplicationContext <|.. GenericWebApplicationContext
ThemeSource <|.. GenericWebApplicationContext
GenericApplicationContext <|-- GenericWebApplicationContext





ConfigurableApplicationContext <|.. AbstractApplicationContext
DefaultResourceLoader <|-- AbstractApplicationContext



BeanDefinitionRegistry <|.. GenericApplicationContext
AbstractApplicationContext <|-- GenericApplicationContext
GenericApplicationContext +.. GenericApplicationContext$ClassDerivedBeanDefinition
RootBeanDefinition <|-- GenericApplicationContext$ClassDerivedBeanDefinition

ApplicationContext <|-- ConfigurableApplicationContext 
}

package SpringBoot {


class SpringApplication {
    WebApplicationType webApplicationType
    List<ApplicationContextInitializer<?>> initializers
    List<ApplicationListener<?>> listeners
    ApplicationContextFactory applicationContextFactory
    ConfigurableApplicationContext run(String... args)
    void prepareContext()
}


interface ApplicationContextFactory {
    ConfigurableApplicationContext create(webApplicationType)
}


class ServletWebServerApplicationContext {
- {static} Log logger
+ {static} String DISPATCHER_SERVLET_NAME
- WebServer webServer
- ServletConfig servletConfig
- String serverNamespace
+ void refresh()
+ String getServerNamespace()
+ void setServerNamespace(String)
+ void setServletConfig(ServletConfig)
+ ServletConfig getServletConfig()
+ WebServer getWebServer()
}


class ServletWebServerApplicationContext$ExistingWebApplicationScopes {
- {static} Set<String> SCOPES
- ConfigurableListableBeanFactory beanFactory
- Map<String,Scope> scopes
+ void restore()
}




ConfigurableWebServerApplicationContext <|.. ServletWebServerApplicationContext
GenericWebApplicationContext <|----- ServletWebServerApplicationContext
ServletWebServerApplicationContext +.. ServletWebServerApplicationContext$ExistingWebApplicationScopes


class ServletWebServerApplicationContextFactory implements ApplicationContextFactory
SpringApplication *-- ApplicationContextFactory
ServletWebServerApplicationContextFactory -right-> ServletWebServerApplicationContext: create
}




```

# 3. spring boot startup

```plantuml
SpringApplication--> SpringApplication:createBootstrapContext
SpringApplication--> SpringApplication:prepareEnvironment
SpringApplication--> SpringApplication:createApplicationContext
SpringApplication--> SpringApplication:prepareContext
SpringApplication--> SpringApplication:refreshContext
SpringApplication--> SpringApplication:afterRefresh
```