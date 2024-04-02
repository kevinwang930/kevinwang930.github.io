---
title: "Tomcat- Servlet Container"
date: 2024-04-02T12:50:11+08:00
categories:
- java
- tomcat
tags:
- tomcat
- servlet
keywords:
- tomcat
#thumbnailImage: //example.com/image.jpg
---
本文记录tomcat 架构与实现
<!--more-->

tomcat works as a servlet/jsp container.

# Architecture

## Server
Server represents the whole container

## Service
A service is an intermidiate component which lives inside a server and ties one or more Connectors to exactly one Engine




## Connector
A Connector handles communications with the client. 








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



```plantuml
interface Lifecycle {

+ void addLifecycleListener(LifecycleListener)
+ LifecycleListener[] findLifecycleListeners()
+ void removeLifecycleListener(LifecycleListener)
+ void init()
+ void start()
+ void stop()
+ void destroy()
+ LifecycleState getState()
+ String getStateName()
}

interface Server extends Lifecycle {
+ NamingResourcesImpl getGlobalNamingResources()
+ void setGlobalNamingResources(NamingResourcesImpl)
+ javax.naming.Context getGlobalNamingContext()
+ int getPort()
+ void setPort(int)
+ int getPortOffset()
+ void setPortOffset(int)
+ int getPortWithOffset()
+ String getAddress()
+ void setAddress(String)
+ String getShutdown()
+ void setShutdown(String)
+ ClassLoader getParentClassLoader()
+ void setParentClassLoader(ClassLoader)
+ Catalina getCatalina()
+ void setCatalina(Catalina)
+ File getCatalinaBase()
+ void setCatalinaBase(File)
+ File getCatalinaHome()
+ void setCatalinaHome(File)
+ int getUtilityThreads()
+ void setUtilityThreads(int)
+ void addService(Service)
+ void await()
+ Service findService(String)
+ Service[] findServices()
+ void removeService(Service)
+ Object getNamingToken()
+ ScheduledExecutorService getUtilityExecutor()
}

interface Service extends Lifecycle {
+ Engine getContainer()
+ void setContainer(Engine)
+ String getName()
+ void setName(String)
+ Server getServer()
+ void setServer(Server)
+ ClassLoader getParentClassLoader()
+ void setParentClassLoader(ClassLoader)
+ String getDomain()
+ void addConnector(Connector)
+ Connector[] findConnectors()
+ void removeConnector(Connector)
+ void addExecutor(Executor)
+ Executor[] findExecutors()
+ Executor getExecutor(String)
+ void removeExecutor(Executor)
+ Mapper getMapper()
}

abstract class LifecycleBase implements Lifecycle {
- {static} Log log
- {static} StringManager sm
- List<LifecycleListener> lifecycleListeners
- LifecycleState state
- boolean throwOnFailure
+ boolean getThrowOnFailure()
+ void setThrowOnFailure(boolean)
+ void addLifecycleListener(LifecycleListener)
+ LifecycleListener[] findLifecycleListeners()
+ void removeLifecycleListener(LifecycleListener)
# void fireLifecycleEvent(String,Object)
+ void init()
# {abstract}void initInternal()
+ void start()
# {abstract}void startInternal()
+ void stop()
# {abstract}void stopInternal()
+ void destroy()
# {abstract}void destroyInternal()
+ LifecycleState getState()
+ String getStateName()
# void setState(LifecycleState)
# void setState(LifecycleState,Object)
}

interface MBeanRegistration {
    ObjectName preRegister(MBeanServer server,
                                  ObjectName name)
    void postRegister(Boolean registrationDone)
    void preDeregister()
    void postDeregister()
}
interface JmxEnabled extends MBeanRegistration {
~ String getDomain()
~ void setDomain(String)
~ ObjectName getObjectName()
}

abstract class LifecycleMBeanBase extends LifecycleBase implements JmxEnabled {
- {static} Log log
- {static} StringManager sm
- String domain
- ObjectName oname
# void initInternal()
# void destroyInternal()
+ void setDomain(String)
+ String getDomain()
# {abstract}String getDomainInternal()
+ ObjectName getObjectName()
# {abstract}String getObjectNameKeyProperties()
# ObjectName register(Object,String)
# void unregister(String)
# void unregister(ObjectName)
+ void postDeregister()
+ void postRegister(Boolean)
+ void preDeregister()
+ ObjectName preRegister(MBeanServer,ObjectName)
}


class Connector extends LifecycleMBeanBase {
- {static} Log log
+ {static} String INTERNAL_EXECUTOR_NAME
# Service service
# boolean allowBackslash
# boolean allowTrace
# long asyncTimeout
# boolean enableLookups
# boolean enforceEncodingInGetWriter
# boolean xpoweredBy
# String proxyName
# int proxyPort
# boolean discardFacades
# int redirectPort
# String scheme
# boolean secure
# {static} StringManager sm
- int maxCookieCount
# int maxParameterCount
# int maxPostSize
# int maxSavePostSize
# String parseBodyMethods
# HashSet<String> parseBodyMethodsSet
# boolean useIPVHosts
# String protocolHandlerClassName
# String configuredProtocol
# ProtocolHandler protocolHandler
# Adapter adapter
- Charset uriCharset
- EncodedSolidusHandling encodedSolidusHandling
# boolean useBodyEncodingForURI
- boolean rejectSuspiciousURIs
+ Object getProperty(String)
+ boolean setProperty(String,String)
+ Service getService()
+ void setService(Service)
+ boolean getAllowBackslash()
+ void setAllowBackslash(boolean)
+ boolean getAllowTrace()
+ void setAllowTrace(boolean)
+ long getAsyncTimeout()
+ void setAsyncTimeout(long)
+ boolean getDiscardFacades()
+ void setDiscardFacades(boolean)
+ boolean getEnableLookups()
+ void setEnableLookups(boolean)
+ boolean getEnforceEncodingInGetWriter()
+ void setEnforceEncodingInGetWriter(boolean)
+ int getMaxCookieCount()
+ void setMaxCookieCount(int)
+ int getMaxParameterCount()
+ void setMaxParameterCount(int)
+ int getMaxPostSize()
+ void setMaxPostSize(int)
+ int getMaxSavePostSize()
+ void setMaxSavePostSize(int)
+ String getParseBodyMethods()
+ void setParseBodyMethods(String)
# boolean isParseBodyMethod(String)
+ int getPort()
+ void setPort(int)
+ int getPortOffset()
+ void setPortOffset(int)
+ int getPortWithOffset()
+ int getLocalPort()
+ String getProtocol()
+ String getProtocolHandlerClassName()
+ ProtocolHandler getProtocolHandler()
+ String getProxyName()
+ void setProxyName(String)
+ int getProxyPort()
+ void setProxyPort(int)
+ int getRedirectPort()
+ void setRedirectPort(int)
+ int getRedirectPortWithOffset()
+ String getScheme()
+ void setScheme(String)
+ boolean getSecure()
+ void setSecure(boolean)
+ String getURIEncoding()
+ Charset getURICharset()
+ void setURIEncoding(String)
+ boolean getUseBodyEncodingForURI()
+ void setUseBodyEncodingForURI(boolean)
+ boolean getXpoweredBy()
+ void setXpoweredBy(boolean)
+ void setUseIPVHosts(boolean)
+ boolean getUseIPVHosts()
+ String getExecutorName()
+ void addSslHostConfig(SSLHostConfig)
+ SSLHostConfig[] findSslHostConfigs()
+ void addUpgradeProtocol(UpgradeProtocol)
+ UpgradeProtocol[] findUpgradeProtocols()
+ String getEncodedSolidusHandling()
+ void setEncodedSolidusHandling(String)
+ EncodedSolidusHandling getEncodedSolidusHandlingInternal()
+ boolean getRejectSuspiciousURIs()
+ void setRejectSuspiciousURIs(boolean)
+ Request createRequest(org.apache.coyote.Request)
+ Response createResponse(org.apache.coyote.Response)
# String createObjectNameKeyProperties(String)
+ void pause()
+ void resume()
# void initInternal()
# void startInternal()
# void stopInternal()
# void destroyInternal()
+ String toString()
# String getDomainInternal()
# String getObjectNameKeyProperties()
}

Server o-- Service
Service o-- Connector
```

## Container
container is an object that can execute requests received from a client, and return responses based on those requests
A container may optionally support a pipeline of Valves that processes the request in an order confiugured at runtime, by implementing the pipeline interface as well.
Containers will exist at serverl levels within catlina:
1. engine
2. host
3. context
4. wrapper

A container may also be associated with a number of support components that provide functionality which may be shared (by attching it to a parent container) or individually customized. the following support components are currently recognized.
1. loader
2. logger
3. manager  manager for the pool of sessions
4. realm read-only interface to a security domain, for authenticating user identities and their corresponding roles.
5. resources JNDI directory context enabling access to static resources.





### Engine
Engine represents request processing pipeline for a specific service. As a Service may have multiple Connectors, the Engine receives and processes all reqeusts from these connectors, handling the response back to the appropriate connector for transmission to the client.

### Host
A Host is a Container that represents a virtual host in the catalina servlet engine. 
Multiple host can be configured in catalina, each has its own request processing logic 

### Context
A context represents a web application. A host may contain multiple contexts,each with a unique path.

### wrapper
A wrapper is a container that represents an individual sevlet definition from the deployment descriptor of the web application. 
It provides mechanism to use interceptors that see every single request to the servlet represented by this definition.
Implementations are responsible for managing the sevlet life circle.

### Valve
A valve is a request processing component associated with a Container. A series of Valves are associated with each other into a pipeline.


```plantuml
scale 1536 width
interface Lifecycle {

+ void addLifecycleListener(LifecycleListener)
+ LifecycleListener[] findLifecycleListeners()
+ void removeLifecycleListener(LifecycleListener)
+ void init()
+ void start()
+ void stop()
+ void destroy()
+ LifecycleState getState()
+ String getStateName()
}


abstract class LifecycleBase implements Lifecycle {
- List<LifecycleListener> lifecycleListeners
- LifecycleState state
- boolean throwOnFailure
}

interface MBeanRegistration {
    ObjectName preRegister(MBeanServer server,
                                  ObjectName name)
    void postRegister(Boolean registrationDone)
    void preDeregister()
    void postDeregister()
}
interface JmxEnabled extends MBeanRegistration {
~ String getDomain()
~ void setDomain(String)
~ ObjectName getObjectName()
}

abstract class LifecycleMBeanBase extends LifecycleBase implements JmxEnabled {

- String domain
- ObjectName oname
}


interface Container extends Lifecycle {

+ Pipeline getPipeline()
+ Container getParent()
+ Realm getRealm()
+ {static} String getConfigPath(Container,String)
+ {static} Service getService(Container)
+ void addChild(Container)
+ void addContainerListener(ContainerListener)
+ void fireContainerEvent(String,Object)
+ void logAccess(Request,Response,long,boolean)
+ File getCatalinaBase()
+ File getCatalinaHome()
}

interface Engine extends Container {
+ String getDefaultHost()
+ void setDefaultHost(String)
+ String getJvmRoute()
+ void setJvmRoute(String)
+ Service getService()
+ void setService(Service)
}

interface Host extends Container {

+ String getXmlBase()
+ void setXmlBase(String)
+ File getConfigBaseFile()
+ String getAppBase()
+ File getAppBaseFile()
+ void setAppBase(String)
}

abstract class ContainerBase extends LifecycleMBeanBase implements Container {
# Pipeline pipeline
# HashMap<String,Container> children
# Container parent
# List<ContainerListener> listeners
# String name
# ClassLoader parentClassLoader
- Realm realm
# ExecutorService startStopExecutor
}
class StandardHost extends ContainerBase implements Host {

- String[] aliases
- String appBase
- File appBaseFile
- String legacyAppBase
- File legacyAppBaseFile
- String xmlBase
- File hostConfigBase
- boolean autoDeploy
- String configClass
- String contextClass
- boolean deployOnStartup
- boolean deployXML
- boolean copyXML
- String errorReportValveClass
- boolean unpackWARs
- String workDir
- boolean createDirs
- Map<ClassLoader,String> childClassLoaders
- Pattern deployIgnore
- boolean undeployOldVersions
- boolean failCtxIfServletStartFails
}

interface Context extends Container, ContextBind{

}

class StandardContext extends ContainerBase implements Context {
    CopyOnWriteArrayList<String> applicationListeners
    Set<Object> noPluggabilityListeners
    List<Object> applicationEventListenersList
    Map<ServletContainerInitializer,Set<Class<?>>> initializers
    ApplicationParameter applicationParameters[]
    URL configFile
    ApplicationContext context
    String path
    Map<String,ApplicationFilterConfig> filterConfigs
    Map<String,FilterDef> filterDefs
    Loader loader
    LoginConfig loginConfig
    NamingContextListener namingContextListener
    NamingResourcesImpl namingResources
    Map<String,String> mimeMappings
    Map<String,String> parameters
    Map<String,String> roleMappings
    Map<String,String> servletMappings
    Class<?> wrapperClass
    Set<String> resourceOnlyServlets
    Set<Servlet> createdServlets
}


interface Wrapper extends Container  {

+ long getAvailable()
+ void setAvailable(long)
+ Servlet getServlet()
+ void setServlet(Servlet)
+ void addInitParameter(String,String)
+ void addMapping(String)
+ void addSecurityReference(String,String)
+ Servlet allocate()
+ void deallocate(Servlet)
+ void load()
+ void unload()
}


class StandardWrapper extends ContainerBase implements ServletConfig, Wrapper {
# StandardWrapperFacade facade
# Servlet instance
# StandardWrapperValve swValve
}



interface Contained {
    Container getContainer()
    void setContainer(Container container)
}

interface Pipeline extends Contained {
    Valve getBasic()
    void setBasic(Valve valve)
    void addValve(Valve valve)
    Valve[] getValves()
    Valve getFirst()
}

interface Valve {
    Valve getNext()
    void setNext(Valve valve)
    void backgroundProcess()
    void invoke(Request request, Response response)
}

abstract class ValveBase extends LifecycleMBeanBase implements Contained, Valve {
    Container container
    Log containerLog
    Valve next

}

class StandardWrapperValve extends ValveBase {
    invoke(request,response)
}


Engine o-- Host
Host o-- Context
Context o-- Wrapper
ContainerBase *-- Pipeline
Pipeline o-- Valve
StandardWrapper *-right- StandardWrapperValve

```


