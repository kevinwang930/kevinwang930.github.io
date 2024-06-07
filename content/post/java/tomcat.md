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

# Servlet
A servlet is a small java program that runs within a web server.Servlets receive and respond to requests from web clients.

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
    # void service(HttpServletRequest,HttpServletResponse)
    + void service(ServletRequest,ServletResponse)
    }

    interface ServletRequest {}
    interface HttpServletRequest extends ServletRequest

    interface ServletResponse {}
    interface HttpServletResponse extends ServletResponse

}
Servlet <|.. GenericServlet
ServletConfig <|.. GenericServlet
GenericServlet <|-- HttpServlet
HttpServletRequest -right-> HttpServlet
HttpServlet -right-> HttpServletResponse

```
# Tomcat Architecture

## Server
Server represents the whole container

## Service
A service is an intermediate component which lives inside a server and ties one or more Connectors to exactly one Engine




## Connector
A Connector handles communications with the client. 








```plantuml

title: Tomcat Architecture
cloud http
    package Tomcat {
    
        
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
        
        c -right-> services
    }

http -right-> Tomcat
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

# Service service

# long asyncTimeout
# String scheme

- int maxCookieCount
# int maxParameterCount
# int maxPostSize
# int maxSavePostSize
# String parseBodyMethods
# HashSet<String> parseBodyMethodsSet

# String protocolHandlerClassName
# String configuredProtocol
# ProtocolHandler protocolHandler
# Adapter adapter


+ String getExecutorName()
+ void addSslHostConfig(SSLHostConfig)
+ SSLHostConfig[] findSslHostConfigs()

+ EncodedSolidusHandling getEncodedSolidusHandlingInternal()

+ Request createRequest(org.apache.coyote.Request)
+ Response createResponse(org.apache.coyote.Response)
# String createObjectNameKeyProperties(String)

# String getDomainInternal()
# String getObjectNameKeyProperties()
}

Server o-- Service
Service o-- Connector
```

## Container
container is an object that can execute requests received from a client, and return responses based on those requests
A container may optionally support a pipeline of Valves that processes the request in an order configured at runtime, by implementing the pipeline interface as well.
Containers will exist at several levels within catalina:
1. engine
2. host
3. context
4. wrapper

A container may also be associated with a number of support components that provide functionality which may be shared (by attaching it to a parent container) or individually customized. the following support components are currently recognized.
1. loader
2. logger
3. manager  manager for the pool of sessions
4. realm read-only interface to a security domain, for authenticating user identities and their corresponding roles.
5. resources JNDI directory context enabling access to static resources.





### Engine
Engine represents request processing pipeline for a specific service. As a Service may have multiple Connectors, the Engine receives and processes all requests from these connectors, handling the response back to the appropriate connector for transmission to the client.

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

`StandardWrapperValve` in tomcat call FilterChain to filter request before invoke servlet.


```plantuml
title: Tomcat Container Architecture
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


# Request handling pipeline

In `Container` section, we see that `Container` contains `Pipeline`,`Pipeline` contains `Valves` in order. the request handling is actually invoke the `Valves` in the `Pipeline` of the specified container one by one. 


```plantuml
rectangle OrderedPipelineValves {
    rectangle Engine
    rectangle Host
    rectangle context
    rectangle wrapper
Engine --> Host
Host --> context
context --> wrapper
}
rectangle FilterChain
rectangle Servlet
wrapper --> FilterChain
FilterChain --> Servlet
```

## Connector Internals

`Adapter` represents the entry point in a coyote-based servlet container.

`ProtocolHandler` abstract the protocol implementation, including threading.

`EndPoint` handles the low level interactions with network socket.

```plantuml

interface Handler {
    SocketState process(socket,SocketEvent status)
}

abstract class AbstractEndpoint<S,U> {
    SynchronizedStack<SocketProcessorBase<S>> processorCache
    Map<U, SocketWrapperBase<S>> connections
    int port
    InetAddress address
    Acceptor<U> acceptor
    Handler<S> handler
    HashMap<String, Object> attributes
    abstract void bind()
}
abstract class AbstractNetworkChannelEndpoint<S extends Channel, U extends NetworkChannel> extends AbstractEndpoint {
    abstract NetworkChannel getServerSocket()
    abstract S createChannel(SocketBufferHandler buffer)
}
class NioEndpoint extends AbstractNetworkChannelEndpoint {
    ServerSocketChannel serverSock
    CountDownLatch stopLatch
    SynchronizedStack<PollerEvent> eventCache
    Poller poller
}

interface Adapter {
    void service(Request req,Response res)
    boolean prepare(Request req, Response res)
}
interface ProtocolHandler {
    Adaptor getAdaptor()
    void setAdaptor(Adaptor adaptor)
    Executor getExecutor()
    void init()
    void start()
    void stop()
    void destroy()
}

abstract class AbstractProtocol<S> implements ProtocolHandler {
    AbstractEndpoint<S, ?> endpoint
    Handler<S> handler
    Adapter adapter
    Set<Processor> waitingProcessors
    ScheduledFuture<?> timeoutFuture
}

abstract class AbstractHttp11Protocol<S> extends AbstractProtocol

class Http11NioProtocol extends AbstractHttp11Protocol {

}

class Connector {
    ProtocolHandler protocolHandler
    Service service
    Adapter adapter
}

class CoyoteAdapter implements Adapter {
    Connector connector
}

AbstractProtocol *-left- Handler
AbstractProtocol *-down- AbstractEndpoint

Connector *-down- ProtocolHandler
Connector *-left- Adapter
```


## EndPoint Internals

```plantuml


!theme plain
top to bottom direction
skinparam linetype ortho

class AbstractEndpoint<S, U>
class AbstractJsseEndpoint<S, U>
class NioEndpoint {
    ServerSocketChannel serverSock
    CountDownLatch stopLatch
    SynchronizedStack<PollerEvent> eventCache
    SynchronizedStack<NioChannel> nioChannels
    Poller poller
    initServerSocket()
}

AbstractJsseEndpoint  -[#000082,plain]-^  AbstractEndpoint     
NioEndpoint           -[#000082,plain]-^  AbstractJsseEndpoint 


```



