---
title: "Spring微服务架构与实现"
date: 2024-03-27T14:39:29+08:00
categories:
- java
- spring
tags:
- java
- spring
keywords:
- spring
- mvc
#thumbnailImage: //example.com/image.jpg
---
本文记录spring微服务架构与实现细节
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

## ApplicationContext

`BeanFactory` interface for accessing a Spring bean container
`ApplicationContext` is a sub-interface of `BeanFactory` . it adds:
1. apo feature
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


### Bean Instantiation
1. `ApplicationContext` refresh will create `BeanFactory`
2. `BeanFactory` will load all beanDefinitions
3. `BeanFactory` postprocess
4. init all Singleton Beans

```plantuml
ApplicationContext--> ApplicationContext:refresh
ApplicationContext --> BeanFactory: create
BeanFactory --> BeanFactory:loadBeanDefinitions
ApplicationContext --> BeanFactory:preparBeanFactory
ApplicationContext --> PostProcessorRegistrationDelegate:invokeBeanFactoryPostProcessors
PostProcessorRegistrationDelegate --> BeanDefinitionRegistryPostProcessor:postProcessBeanDefinitionRegistry
ApplicationContext --> ApplicationContext:finishBeanFactoryInitialization
```


# web on servlet
Servlet-stack web applications built on the servlet API and deployed to Servlet containers

## Tomcat
tomcat works as a servlet container.

```plantuml


    package Tomcat(Server) {
    
        
        component c  [ 
            listener
            globl naming resouce
            jndi
        ] 
        component services {
            component connector
            component Engine {
                component Host {
                    Component Context {
                        Component Servlet
                    }
                }
            }
        }
        
        c --> services
    }
cloud http
http -right-> services
```

## ServletContext

`ServletContext` Defines a set of methods that a servlet uses to communicate with its servlet container

spring uses `ContextLoaderListener` to listen to the initialization of `ServletContext`, then init spring `WebApplicationContext`

```plantuml

package Tomcat {
    interface ServletContextListener {
        + void contextInitialized( sce)
        + void contextDestroyed( sce)
    }

    interface ServletContext {
        + ServletContext getContext(String)
        + URL getResource(String)
        + RequestDispatcher getRequestDispatcher(String)
        + boolean setInitParameter(String,String)
        + void setAttribute(String,Object)
        + ServletRegistration.Dynamic addServlet(String,String)
        + ServletRegistration getServletRegistration(String)
        + FilterRegistration.Dynamic addFilter(String,Filter)
        + SessionCookieConfig getSessionCookieConfig()
        + void addListener(Class<? extends EventListener>)
        + ClassLoader getClassLoader()
        + void setSessionTimeout(int)
    }

    class ApplicationContext implements ServletContext {
        Map<String,Object> attributes

    }
}

package Spring {
    class ContextLoader {
        {static} Map<ClassLoader, WebApplicationContext> currentContextPerThread
        {static} volatile  currentContext
        WebApplicationContext context
        initWebApplicationContext(sc)
        createWebApplicationContext(sc)
        closeWebApplicationContext(sc)
    }
    class ContextLoaderListener   {
        
        contextInitialized(sce)
        contextDestroyed(sce)
    }

    abstract class AbstractRefreshableWebApplicationContext  {
        ServletContext servletContext
        ServletConfig servletConfig
    }

    class XmlWebApplicationContext extends AbstractRefreshableWebApplicationContext {

    }
      ContextLoader <|-up-ContextLoaderListener
    ContextLoader -left-> XmlWebApplicationContext:create
}


ApplicationContext <|-- ConfigurableApplicationContext 


    



 ServletContextListener <|..... ContextLoaderListener
ConfigurableApplicationContext *-- XmlWebApplicationContext

```

# DispatcherServlet

Spring MVC is designed aroud the front controller pattern where a central `servlet`, the `DispatcherServlet`, provides a shared algorithm for request processing, while actual work is performed by configurable delegate components.


```plantuml

package Tomcat {
    interface Servlet {
    + void init(ServletConfig)
    + ServletConfig getServletConfig()
    + void service(ServletRequest,ServletResponse)
    + String getServletInfo()
    + void destroy()
    }

    interface ServletConfig {
    + String getServletName()
    + ServletContext getServletContext()
    + String getInitParameter(String)
    + Enumeration<String> getInitParameterNames()
    }

    abstract class GenericServlet {
    - ServletConfig config
    }

    abstract class HttpServlet {
    - Object cachedAllowHeaderValueLock
    - String cachedAllowHeaderValue
    - boolean cachedUseLegacyDoHead

    # void doGet(HttpServletRequest,HttpServletResponse)
    # long getLastModified(HttpServletRequest)
    # void doHead(HttpServletRequest,HttpServletResponse)
    # void doPatch(HttpServletRequest,HttpServletResponse)
    # void doPost(HttpServletRequest,HttpServletResponse)
    # void doPut(HttpServletRequest,HttpServletResponse)
    # void doDelete(HttpServletRequest,HttpServletResponse)
    # void doOptions(HttpServletRequest,HttpServletResponse)
    # void doTrace(HttpServletRequest,HttpServletResponse)
    # boolean isSensitiveHeader(String)
    # void service(HttpServletRequest,HttpServletResponse)
    + void service(ServletRequest,ServletResponse)
    }
}

package Spring {
    abstract class HttpServletBean  {
        ConfigurableEnvironment environment
        void initServletBean()
    }

    abstract class FrameworkServlet extends HttpServletBean {
        WebApplicationContext webApplicationContext
        String contextId
        String namespace
        String contextConfigLocation
        void processRequest( request,  response)
        abstract void doService( request,  response)
    }

    class DispatcherServlet extends FrameworkServlet {
        List<HandlerMapping> handlerMappings
        List<HandlerAdapter> handlerAdapters
        List<HandlerExceptionResolver> handlerExceptionResolvers
        protected void doService( request,  response) 
        protected void doDispatch( request,  response)
    }
}



Servlet <|.. GenericServlet
ServletConfig <|.. GenericServlet
GenericServlet <|-- HttpServlet
HttpServlet<|-- HttpServletBean
```




