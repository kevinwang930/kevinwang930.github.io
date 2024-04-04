---
title: "Security"
date: 2024-04-02T12:25:39+08:00
categories:
- java
- spring
tags:
- spring
- security
keywords:
- security
#thumbnailImage: //example.com/image.jpg
---
本文记录spring 安全相关的内容
<!--more-->


# Architecture

In the [Tomcat](https://kevinwang930.github.io/post/java/tomcat/) Article, we see that request handling will go through FilterChain before invoking servlet. 
Spring security's Servlet support is based on servlet Filters.

* client sends a request to the application
* container creates a FilterChain
* Filter can do 
  1. prevent downstream filter or servlet from being invoked. in this case filter writes the `HttpServletResponse`
  2. Filter can modify `HttpServletRequest` or `HttpServletResponse` used by downstream Filter instances and `Servlet`

 



```plantuml
left to right direction
rectangle client
package FilterChain {
    rectangle Filter0
    rectangle Filter1
    rectangle Filter2
    rectangle Servlet
}
client --> Filter0
Filter0 --> Filter1
Filter1 --> Filter2
Filter2 --> Servlet
```

## DelegatingFilterProxy
Spring provides Filter implementation `DelegatingFilterProxy` that delegate all the work to a Spring bean that implement Filter.

Spring Security provides a special Filter `FilterChainProxy` that allows delegating to many Filter instances through `SecurityFilterChain`


```plantuml

rectangle client
package FilterChain {
    rectangle Filter0
    rectangle DelegatingFilterProxy {
        rectangle FilterChainProxy
    }
    rectangle Filter2
    rectangle Servlet
}
rectangle SecurityFilterChain {
    rectangle sf as "Security Filters"
}
client --> Filter0
Filter0 --> DelegatingFilterProxy
DelegatingFilterProxy --> Filter2
Filter2 --> Servlet
FilterChainProxy -right-> SecurityFilterChain
```

```plantuml

package jakarta {
    interface FilterChain {
        void doFilter( request,  response) 
    }
    interface Filter {
        void init( filterConfig)
        doFilter( request,  response,  chain)
    }

    FilterChain o-right- Filter
}

```


# Authentication

## username and password
username and password is very common way to authentication.
spring identify user with sessionid in cookie.

1. user make unauthenticated request to /page
2. spring responds with 302 redirct to /login
3. client request /login with username and possword
4. spring response with JSESSIONID 

```plantuml
client --> spring: /page
spring --> client: 302 Location: /login
client --> spring: post /login
spring --> client: set-cookie:JSESSIONID 302  /page
client --> spring: /page with cookie: JESSIONID
```


## OAuth2 
The OAuth2 Login feature lets an application have users log into the application by using their existing account at an OAuth2 provider (such as github) or OpenId Connect 1.0 provider(such as google).

Resource Owner: entity that can grant access to a protected resource. Typically this is the end-user.

Client: Application requesting access to a protected resource on behalf of the resource owner.

Resource Server: Server hosting the protected resources. the APi client want to access.

Authorization Server: Server that authenticates the resource owner and issues Access Tokens after getting proper authorization.

User Agent: Agent used by the Resource Owner to interact with the client (a browser or a native application)


A typical oauth2 authorization code grant process:

```plantuml
entity client
participant ua as "User Agent"
actor ro as "resource Owner"
control rs as "Authorization server"

client --> ua : init OAuth2
ua --> rs: Authorization request

rs --> ua: owner request
ro --> ua: owner grant
rs -->  client: authorization code
client --> rs: token endpoint /w auth code
rs --> client: access code

```


# security Filters


## CSRF Protection

cross site request forgery is an attack that tricks a user into accidentally using their credentials to invoke a state changing activity such as funds transferring.

### prevention
#### SOP 
same origin policy restrict scripts on one origin from accessing another origin.
```
origin := (protocol://host:port)
```
#### CORS

cross origin resource sharing is an Http-header based mechanism that allows a server to indicate any origins other than itw own from which a browser should permit loading resources.


simplest access control request and response will be like below
```
request header
    1. origin:https://foo.example
response header
    1. Access-Control-Allow-Origin:https://foo.example
```

There are other related access control [response headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)

#### synchronizer token

1. client request form 
2. server responses form with token
3. client send form with token
4. server compare token with the original one.
