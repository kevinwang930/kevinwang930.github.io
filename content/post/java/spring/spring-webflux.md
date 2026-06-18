---
title: "Spring Webflux"
date: 2024-05-29T19:43:22+08:00
categories:
- java
- spring
tags:
- spring
- webflux
keywords:
- webflux
#thumbnailImage: //example.com/image.jpg
---
WebFlux is non-blocking, asynchronous web framework based on project Reactor.

<!--more-->




# WebFlux Core Architecture & Components

Spring WebFlux is built around a non-blocking handler mapping and processing pipeline designed to handle high concurrency with a low footprint of threads.

## 1. WebFlux Core Components

The following PlantUML diagram shows the main execution contracts of the Spring WebFlux framework and how they interact to process requests:

```plantuml
interface HttpHandler {
    + Mono<Void> handle(ServerHttpRequest request, ServerHttpResponse response)
}

interface WebHandler {
    + Mono<Void> handle(ServerWebExchange exchange)
}

class DispatcherHandler implements WebHandler {
    - List<HandlerMapping> handlerMappings
    - List<HandlerAdapter> handlerAdapters
    - List<HandlerResultHandler> handlerResultHandlers
    + Mono<Void> handle(ServerWebExchange exchange)
}

interface HandlerMapping {
    + Mono<Object> getHandler(ServerWebExchange exchange)
}

interface HandlerAdapter {
    + boolean supports(Object handler)
    + Mono<HandlerResult> handle(ServerWebExchange exchange, Object handler)
}

interface HandlerResultHandler {
    + boolean supports(HandlerResult result)
    + Mono<Void> handleResult(ServerWebExchange exchange, HandlerResult result)
}

class ServerWebExchange {
    + ServerHttpRequest getRequest()
    + ServerHttpResponse getResponse()
    + Mono<WebSession> getSession()
    + Mono<Principal> getPrincipal()
}

DispatcherHandler --> HandlerMapping : 1. resolves handler
DispatcherHandler --> HandlerAdapter : 2. executes handler
DispatcherHandler --> HandlerResultHandler : 3. processes execution result
```

### Roles of Core Classes:

1. **`HttpHandler`**: The lowest-level abstraction that adapts server-specific request/response models (e.g. Netty, Undertow, or Servlets) into the WebFlux-independent `ServerHttpRequest` and `ServerHttpResponse`.
2. **`DispatcherHandler`**: The main orchestration component (acting like Spring MVC's `DispatcherServlet`). It coordinates request routing, execution, and result serialization.
3. **`HandlerMapping`**: Maps incoming requests to an execution target (such as a `@Controller` handler method or a router function).
4. **`HandlerAdapter`**: Adapts execution invocations for different types of handlers.
5. **`HandlerResultHandler`**: Processes the returned result from handler execution (e.g., serializing a `Mono<User>` or `Flux<Event>` response body to JSON).

---

## 2. Request Processing Flow

```
[Inbound Netty Request]
         │
         ▼
 ┌───────────────┐
 │  HttpHandler  │ (Adapts Netty requests to ServerWebExchange)
 └───────┬───────┘
         │
         ▼
 ┌───────────────┐
 │ WebHandler    │ 
 │ (Dispatcher)  │ ───► Mapping: Resolves mapping to controllers or router functions
 └───────┬───────┘
         │
         ▼
 ┌───────────────┐
 │ HandlerAdapter│ ───► Execution: Invokes target endpoint returning Mono<HandlerResult>
 └───────┬───────┘
         │
         ▼
 ┌───────────────┐
 │ ResultHandler │ ───► Serialization: Writes response bytes back asynchronously
 └───────────────┘
```

---

## 3. Programming Models & Examples

Spring WebFlux supports two programming models: **Annotated Controllers** and **Functional Endpoints**.

### A. Annotated Controller Style
This style is very similar to standard Spring MVC but leverages Project Reactor types (`Mono` and `Flux`) to handle threads asynchronously:

```java
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/{id}")
    public Mono<User> getUserById(@PathVariable String id) {
        // Non-blocking query yielding a Mono wrapper.
        // The event loop threads are released while waiting for the query completion.
        return userService.findUserById(id);
    }
}
```

### B. Functional Endpoints Style
A functional, routing-oriented API where routing configuration is separated from the execution logic:

#### 1. Routing Definition (`RouterFunction`)
```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;

import static org.springframework.web.reactive.function.server.RequestPredicates.GET;
import static org.springframework.web.reactive.function.server.RouterFunctions.route;

@Configuration
public class UserRouter {

    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return route(GET("/api/users/{id}"), handler::getUserById);
    }
}
```

#### 2. Request Handling (`HandlerFunction`)
```java
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

@Component
public class UserHandler {

    private final UserService userService;

    public UserHandler(UserService userService) {
        this.userService = userService;
    }

    public Mono<ServerResponse> getUserById(ServerRequest request) {
        String id = request.pathVariable("id");
        return userService.findUserById(id)
                .flatMap(user -> ServerResponse.ok().bodyValue(user))
                .switchIfEmpty(ServerResponse.notFound().build());
    }
}
```