---
title: "Spring MVC"
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
This article describes Spring MVC
<!--more-->


# web on servlet
Servlet-stack web applications built on the servlet API and deployed to Servlet containers


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

# Request Handling

url and form-data parameters will transformed to parameters of request, and binds to the Controller method args.
Request body will read by the converters, and convert to controller args.

## parameter handling
`@RequestBody` indicates a method parameter should be bound to the body of web request.

`@RequestParam` indicates a method parameter should be bound to a web request parameter in url or form-data.

`@ModelAttribute` binds a method parameter or method return value to a named model attribute.


`@PathVariable` indicates that a method parameter should be bound to a URI template variable.
```
@GetMapping("/hello/{name}/{age}")

public void select(@PathVariable("name") String name,
                    @PathVariable("age") int age)
```

`RequestParam` indicates that a method parameter should be bound to a web request parameter.
In spring mvc, request parameters map to a query parameters, form data and parts in multipart request.


# Aspect Oriented Programming

Aspect A modularization of a concern that cuts across multiple classes.

Joint Point A point during the execution of a program. In Spring AOP , a join point always represents a method execution.

Advice: Action taken by an aspect at a particular join point.
advice types:
    * before
    * around
    * after

PointCut: A predicate that matches join points. Advice is associated with a pointCut expression and runs at any join point matched by the pointCut.

## Point cut expression
signature and point cut expression  
```
@Pointcut("execution(* transfer(..))") // the pointcut expression
private void anyOldTransfer() {} // the pointcut signature
```









