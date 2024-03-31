---
title: "spring ioc - bean container"
date: 2024-03-31T12:56:25+08:00
categories:
- java
- spring
tags:
- spring
- ioc
keywords:
- spring
#thumbnailImage: //example.com/image.jpg
---
本文记录spring bean 容器的架构与实现细节
<!--more-->

Spring web applications built on the Servlet API and deployed to Servlet containers.

# IOC container


`AppliationContext` interface represents the Spring IOC container and is responsible for instantiating, configuring, and assembling the beans.

The container gets its instructions on what objects to instantiate, configure, and assemble by reading configuration metadata. The configuration metadata is represented in XML, java annotations, or java code.

```plantuml
package pojo [business Object (POJOS)
] 
rectangle ioc [Spring IOC container
] 
file config [Configuration Metadata
] 
rectangle service [
Fully Confugured system 
ready for use
]

pojo --> ioc
config -right-> ioc
ioc --> service
```



## Bean 
Beans are created with the configuration metadata that you supply to the container.
In the container, the bean definitions are represented as `BeanDefinition` objects, contains:
1. class
2. Name
3. Scope
4. Construct arguments
5. Properties
6. Autowiring mode
7. Initialization method
8. Destruction method

## BeanFactory
`BeanFactory` interface for accessing a Spring bean container

`ConfigurableBeanFactory` configuration interface to be implemented by most bean factories, provides bean factory configuration methods.
1. parent bean factory
2. bean class loader
4. bean alias
5. bean scope
6. bean register and deletion



## ApplicationContext

`ApplicationContext` is a sub-interface of `BeanFactory` . it adds:
1. aop feature
2. resouce handling
3. event publication
4. application-layer specific contexts for use in web applications.

```plantuml

package Spring {

    interface BeanFactory {
        + {static} String FACTORY_BEAN_PREFIX
        + T getBean()
        + ObjectProvider<T> getBeanProvider(Class<T>)
        + boolean containsBean(String)
        + boolean isSingleton(String)
        + boolean isPrototype(String)
        + boolean isTypeMatch(String,Class<?>)
        + Class<?> getType(String)
        + String[] getAliases(String)
    }

    interface EnvironmentCapable {
        Environment getEnvironment()
    }
    interface HierarchicalBeanFactory extends BeanFactory {
        BeanFactory getParentBeanFactory()
        boolean containsLocalBean()
    }
interface ListableBeanFactory extends BeanFactory

interface ConfigurableBeanFactory {
    void setParentBeanFactory()
    void setBeanClassLoader()
    void setBootstrapExecutor()
    void addBeanPostProcessor()
    void setApplicationStartup()
    void registerDependentBean()
    void destroyBean()
}

interface AutowireCapableBeanFactory extends BeanFactory {
    <T> T createBean()
    void autowireBean()
    Object configureBean()
    Object autowire()
}
interface ApplicationContext extends EnvironmentCapable, ListableBeanFactory, HierarchicalBeanFactory,MessageSource, ApplicationEventPublisher, ResourcePatternResolver {
    ApplicationContext getParent()
}

interface ConfigurableListableBeanFactory {
    boolean isAutowireCandidate()
    BeanDefinition getBeanDefinition()
    void registerResolvableDependency()

}

abstract class AbstractAutowireCapableBeanFactory extends AbstractBeanFactory implements AutowireCapableBeanFactory {
    InstantiationStrategy instantiationStrategy
    ParameterNameDiscoverer parameterNameDiscoverer
    boolean allowCircularReferences
    Set<Class<?>> ignoredDependencyTypes
    ConcurrentMap<String, BeanWrapper> factoryBeanInstanceCache
    ConcurrentMap<Class<?>, Method[]> factoryMethodCandidateCache
}

interface Lifecycle {
    void start()
    void stop()
    boolean isRunning()
}

interface ConfigurableApplicationContext extends Lifecycle {
    void setParent()
    void setEnvironment()
    void refresh()
}

interface WebApplicationContext extends ApplicationContext {
    ServletContext getServletContext()
}



interface BeanDefinitionRegistry {
void registerBeanDefinition()
void removeBeanDefinition() 
BeanDefinition getBeanDefinition()
}

interface SingletonBeanRegistry {
    Object getSingleton()
    void registerSingleton()
}

class DefaultSingletonBeanRegistry extends SimpleAliasRegistry implements SingletonBeanRegistry {
    Map<String, Object> singletonObjects
    Map<String, Consumer<Object>> singletonCallbacks
}

interface ConfigurableBeanFactory extends HierarchicalBeanFactory, SingletonBeanRegistry

interface ConfigurableListableBeanFactory extends ListableBeanFactory, AutowireCapableBeanFactory, ConfigurableBeanFactory

abstract class FactoryBeanRegistrySupport extends DefaultSingletonBeanRegistry

abstract class AbstractBeanFactory extends FactoryBeanRegistrySupport implements ConfigurableBeanFactory {
    List<BeanPostProcessor> beanPostProcessors
    abstract Object createBean()
}

abstract class  AbstractApplicationContext {
    ApplicationContext parent
    ConfigurableEnvironment environment
    LifecycleProcessor lifecycleProcessor
    List<BeanFactoryPostProcessor> beanFactoryPostProcessors
    abstract void refreshBeanFactory()
    abstract void closeBeanFactory()
}

abstract class AbstractRefreshableApplicationContext extends AbstractApplicationContext {
    volatile DefaultListableBeanFactory beanFactory
    createBeanFactory()
    abstract void loadBeanDefinitions()
}

AbstractRefreshableApplicationContext -left-> DefaultListableBeanFactory: create

class DefaultListableBeanFactory extends AbstractAutowireCapableBeanFactory implements ConfigurableListableBeanFactory, BeanDefinitionRegistry {
    Map<String, BeanDefinition> beanDefinitionMap
    Map<Class<?>, Object> resolvableDependencies
    Set<String> primaryBeanNames
    Map<Class<?>, String[]> allBeanNamesByType
    Map<Class<?>, String[]> singletonBeanNamesByType
    volatile List<String> beanDefinitionNames
    preInstantiateSingletons()
}

abstract class AbstractRefreshableConfigApplicationContext extends AbstractRefreshableApplicationContext {
    String[] configLocations
    void setConfigLocation()
    
}

interface ConfigurableWebApplicationContext extends WebApplicationContext, ConfigurableApplicationContext {
    String[] getConfigLocations()
    void setConfigLocation()
    void setServletContext()
}

abstract class AbstractRefreshableWebApplicationContext extends AbstractRefreshableConfigApplicationContext implements ConfigurableWebApplicationContext, ThemeSource {
    ServletContext servletContext
    ServletConfig servletConfig
}

class XmlWebApplicationContext extends AbstractRefreshableWebApplicationContext {

}



ConfigurableApplicationContext <|.. AbstractApplicationContext
DefaultResourceLoader <|-- AbstractApplicationContext





```


### Application context initialization
1. `ApplicationContext` refresh will create `BeanFactory`
2. `BeanFactory` will load all beanDefinitions
3. BeanFactorypostprocess
   1. BeanDefinitionRegistryPostProcessor
      1. spring boot config bean
      2. mybatis mapperscanner
   2. BeanFactoryPostProcessor
      1. configClassEnhancer - proxy to generate bean
4. init all Singleton Beans

```plantuml
title : application context initialization
AbstractApplicationContext--> AbstractApplicationContext:refresh
AbstractApplicationContext --> BeanFactory: create
BeanFactory --> BeanFactory:loadBeanDefinitions
AbstractApplicationContext --> AbstractApplicationContext:prepareBeanFactory
AbstractApplicationContext --> AbstractApplicationContext:postProcessBeanFactory
AbstractApplicationContext --> PostProcessorRegistrationDelegate:invokeBeanFactoryPostProcessors
PostProcessorRegistrationDelegate --> BeanDefinitionRegistryPostProcessor:postProcessBeanDefinitionRegistry
AbstractApplicationContext--> AbstractApplicationContext:registerBeanPostProcessors
AbstractApplicationContext --> AbstractApplicationContext:finishBeanFactoryInitialization
AbstractApplicationContext --> BeanFactory:preInstantiateSingletons
```


## bean Initialization

```plantuml
DefaultListableBeanFactory --> DefaultListableBeanFactory:preInstantiateSingletons

DefaultListableBeanFactory --> DefaultListableBeanFactory:getBean

DefaultListableBeanFactory --> DefaultListableBeanFactory: doGetBean
DefaultListableBeanFactory --> DefaultListableBeanFactory: createBean
DefaultListableBeanFactory --> DefaultListableBeanFactory: resolveBeanClass
alt proxy
DefaultListableBeanFactory --> DefaultListableBeanFactory: resolveBeforeInstantiation
end

DefaultListableBeanFactory --> DefaultListableBeanFactory: doCreateBean
DefaultListableBeanFactory --> DefaultListableBeanFactory: createBeanInstance
alt instanceSupplier
DefaultListableBeanFactory --> DefaultListableBeanFactory: obtainFromSupplier
end
DefaultListableBeanFactory --> BeanDefinition: getFactoryMethodName
alt factoryMethod
DefaultListableBeanFactory --> DefaultListableBeanFactory: instantiateUsingFactoryMethod
end
alt resolved
alt autowireNecesary
DefaultListableBeanFactory --> DefaultListableBeanFactory: autowireConstructor
else 
DefaultListableBeanFactory --> DefaultListableBeanFactory: instantiateBean
end
end
DefaultListableBeanFactory --> DefaultListableBeanFactory: determineConstructorsFromBeanPostProcessors
alt autowiremode
DefaultListableBeanFactory --> ConstructorResolver: new
ConstructorResolver --> ConstructorResolver: autowireConstructor
ConstructorResolver --> ConstructorResolver: instantiate
ConstructorResolver --> DefaultListableBeanFactory:beanWrapper
else 
DefaultListableBeanFactory --> DefaultListableBeanFactory:instantiateBean
end
DefaultListableBeanFactory --> DefaultListableBeanFactory:applyMergedBeanDefinitionPostProcessors
DefaultListableBeanFactory --> DefaultListableBeanFactory:populateBean : properties
DefaultListableBeanFactory --> DefaultListableBeanFactory:initializeBean












DefaultListableBeanFactory --> DefaultListableBeanFactory: getSingleton
```



### post processor

Factory hook that allows for custom modification of new bean instances
```plantuml
interface BeanPostProcessor {
+ Object postProcessBeforeInitialization(Object,String)
+ Object postProcessAfterInitialization(Object,String)
}

interface MergedBeanDefinitionPostProcessor extends BeanPostProcessor  {
    void postProcessMergedBeanDefinition()
}
interface InstantiationAwareBeanPostProcessor extends BeanPostProcessor {
    default Object postProcessBeforeInstantiation()
    default boolean postProcessAfterInstantiation()
    default PropertyValues postProcessProperties()
}
```
