---
title: "Dubbo RPC Architecture and Implementation"
date: 2026-11-15T10:40:00+01:00
categories:
- network
- dubbo
tags:
- network
- rpc
- dubbo
- nacos
keywords:
- dubbo
- rpc
- nacos
- spi
- netty

#thumbnailImage: //example.com/image.jpg
---

Dubbo is an RPC framework. A service is defined as an ordinary interface, implemented in a provider process, and called from a consumer process as though it were a local object, with a registry telling the consumer where the provider is and a metadata service telling it what that interface looks like. Dubbo has implementations in Go, Python, PHP, Erlang, Rust, and Node.js, and this post covers the Java one.

<!--more-->

---

## 1. Overview

As an RPC framework, Dubbo organises a cluster into four roles.

- A **provider** hosts the implementation. It declares which interfaces it serves and listens on a port to answer calls.
- A **consumer** calls those interfaces as if they were local. It keeps a local list of provider addresses and picks one per call.
- A **registry** holds addresses only. It knows which provider processes exist and tells each consumer when that list changes. It does not store interface definitions.
- A **metadata service** holds the definitions. Every provider exports one alongside its business services; a consumer asks it what an interface looks like — methods, parameter types, method-level settings — for a given revision.

The split between the last two is the change newer Dubbo made. Older versions stored everything about each interface in the registry, so the registry was large and any change meant rewriting a registration. From Dubbo 3 the definitions moved out to the metadata service, and the registry keeps only addresses plus a revision that points at the right definition. Adding an interface now changes that revision instead of churning every consumer's address list.

The loop is short: provider registers, consumer subscribes, consumer receives addresses, consumer calls the provider directly. The registry is not in the call path, and the metadata service is consulted once per revision and then cached.

![Dubbo cluster layout: consumer stack, wire protocol, provider stack, MetadataService, and service discovery through Nacos](images/architecture.svg)

### A minimal example

One shared interface module, so both sides compile against the same type:

```java
public interface GreetingService {
    String greet(String name);
}
```

The provider implements it and exports the interface. The annotation is enough; the same result is available from XML or from the programmatic API.

```java
@DubboService
public class GreetingServiceImpl implements GreetingService {
    public String greet(String name) {
        return "hello, " + name;
    }
}
```

```yaml
dubbo:
  application:
    name: greeting-provider
  registry:
    address: nacos://127.0.0.1:8848
```

The consumer declares a field of the interface type and marks it for injection. It never constructs the implementation and never opens a socket.

```java
@DubboReference
private GreetingService greetingService;

String reply = greetingService.greet("dubbo");
```

Three things happen behind that call. At startup the provider exported `GreetingService` and registered its address and revision with Nacos; the consumer subscribed to the provider's application and got the address list back; and the call itself went from the injected proxy over a TCP connection to the provider's port, where the implementation ran. The interface object the consumer holds is a proxy generated at startup, which is why a call looks like a local method call.

---

## 2. Extension architecture

Dubbo is structured around a microkernel and plugin design pattern. The framework core defines contracts as Service Provider Interfaces (SPIs) — `Protocol`, `Exchanger`, `Transporter`, `Codec2`, `Serialization`, `ThreadPool`, `LoadBalance`, `StateRouterFactory`, and `Filter` — and contains no hard-coded dependency on any concrete transport, serializer, or cluster strategy. Unlike `java.util.ServiceLoader`, which instantiates every declared provider eagerly from a flat list, Dubbo's SPI combines five design patterns into a single container:

- **Name-indexed lazy loading**: implementations are declared as `name=class` pairs in resource files and loaded only when that name is requested.
- **URL-driven late binding (Adaptive Proxy)**: every remote call is described by a `URL` carrying configuration parameters (`protocol=dubbo`, `transporter=netty`, `serialization=hessian2`, `loadbalance=random`). Because collaborators are wired at startup before any service `URL` exists, the container supplies a generated *adaptive* proxy that defers implementation lookup to call time by reading the parameter from the invocation's `URL`.
- **Decorator composition (Wrapper)**: cross-cutting concerns such as filter chains, listener hooks, and reference counting are implemented as wrapper classes around the SPI interface and stacked automatically around every concrete instance.
- **Rule-based chain assembly (Activation)**: ordered pipelines such as `Filter` and `StateRouterFactory` are selected as a group when `@Activate` predicates match the `URL`, rather than looked up one name at a time.
- **Scoped IoC and lifecycle**: extensions live inside a three-tier hierarchy (`FrameworkModel` -> `ApplicationModel` -> `ModuleModel`) and receive collaborator SPIs through setter injection of adaptive instances.

```plantuml
@startuml
top to bottom direction

interface ExtensionAccessor {
  + getExtensionDirector(): ExtensionDirector
  + getExtensionLoader(Class<T>): ExtensionLoader<T>
  + getExtension(Class<T>, String): T
  + getAdaptiveExtension(Class<T>): T
}

abstract class ScopeModel implements ExtensionAccessor {
  - parent: ScopeModel
  - scope: ExtensionScope
  - classLoaders: Set<ClassLoader>
  - extensionDirector: ExtensionDirector
}
class FrameworkModel extends ScopeModel
class ApplicationModel extends ScopeModel
class ModuleModel extends ScopeModel

class ExtensionDirector implements ExtensionAccessor {
  - parent: ExtensionDirector
  - scope: ExtensionScope
  - extensionLoadersMap: ConcurrentMap<Class, ExtensionLoader>
  + getExtensionLoader(Class<T>): ExtensionLoader<T>
}

class ExtensionLoader<T> {
  - type: Class<T>
  - scopeModel: ScopeModel
  - cachedClasses: Holder<Map<String, Class>>
  - cachedInstances: ConcurrentMap<String, Holder<Object>>
  - cachedAdaptiveClass: Class<?>
  - cachedAdaptiveInstance: Holder<Object>
  - cachedWrapperClasses: Set<Class>
  + getExtension(String): T
  + getAdaptiveExtension(): T
  + getActivateExtension(URL, String, String): List<T>
}

class AdaptiveClassCodeGenerator {
  - type: Class<?>
  - defaultExtName: String
  + generate(): String
}

interface Compiler {
  + compile(Class<?>, String, ClassLoader): Class<?>
}
class AdaptiveCompiler implements Compiler
abstract class AbstractCompiler implements Compiler
class JavassistCompiler extends AbstractCompiler
class JdkCompiler extends AbstractCompiler

interface ExtensionAccessorAware {
  + setExtensionAccessor(ExtensionAccessor)
}
interface ExtensionInjector extends ExtensionAccessorAware {
  + getInstance(Class<T>, String): T
}
class AdaptiveExtensionInjector implements ExtensionInjector
class SpiExtensionInjector implements ExtensionInjector
class ScopeBeanExtensionInjector implements ExtensionInjector
class SpringExtensionInjector implements ExtensionInjector

ScopeModel *-- ExtensionDirector
ExtensionDirector *-- ExtensionLoader
ScopeModel --o ExtensionLoader
ExtensionLoader ..> AdaptiveClassCodeGenerator
ExtensionLoader ..> Compiler
ExtensionLoader ..> ExtensionInjector
@enduml
```

Both `ScopeModel` and `ExtensionDirector` implement `ExtensionAccessor`, exposing a uniform entry point (`getExtensionLoader`, `getExtension`, `getAdaptiveExtension`) at every tier of the container.

```java
public interface ExtensionAccessor {
    ExtensionDirector getExtensionDirector();

    default <T> ExtensionLoader<T> getExtensionLoader(Class<T> type) {
        return getExtensionDirector().getExtensionLoader(type);
    }

    default <T> T getExtension(Class<T> type, String name) {
        ExtensionLoader<T> extensionLoader = getExtensionLoader(type);
        return extensionLoader != null ? extensionLoader.getExtension(name) : null;
    }

    default <T> T getAdaptiveExtension(Class<T> type) {
        ExtensionLoader<T> extensionLoader = getExtensionLoader(type);
        return extensionLoader != null ? extensionLoader.getAdaptiveExtension() : null;
    }
}
```

An extension point is declared by annotating an interface with `@SPI`, whose `value` sets the default implementation name and whose `scope` sets instance visibility (`APPLICATION` when omitted):

```java
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE})
public @interface SPI {
    String value() default "";
    ExtensionScope scope() default ExtensionScope.APPLICATION;
}
```

The `ExtensionScope` controls which `ScopeModel` owns the `ExtensionLoader` and what state an instance may reach. `FRAMEWORK`-scoped extensions (`Protocol`, `Serialization`) share one loader on the root `FrameworkModel` across the JVM; `APPLICATION`-scoped extensions (`RegistryFactory`) isolate state per application while sharing across its modules; `MODULE`-scoped extensions (`Filter`) instantiate per module; and `SELF` creates a dedicated instance per owner. `ExtensionDirector.getExtensionLoader` enforces these boundaries by resolving in three steps:

```java
ExtensionLoader<T> loader = extensionLoadersMap.get(type);   // 1. local cache
if (loader == null && scope == ExtensionScope.SELF) {
    loader = createExtensionLoader0(type);                    //    SELF never inherits
}
if (loader == null && this.parent != null) {
    loader = this.parent.getExtensionLoader(type);            // 2. delegate to parent scope
}
if (loader == null) {
    loader = createExtensionLoader(type);                     // 3. create at owning scope
}
```

Each `ExtensionLoader<T>` discovers implementations by scanning three classpath directories in order of decreasing priority:

- `META-INF/dubbo/internal/`: framework built-ins.
- `META-INF/dubbo/`: user or third-party extensions, permitted to override lower-priority entries.
- `META-INF/services/`: `ServiceLoader` compatibility.

Each file is named after the fully qualified interface and contains `name=class` lines, such as `dubbo=org.apache.dubbo.rpc.protocol.dubbo.DubboProtocol`. While reading the file, the loader classifies each class without instantiating it: a class annotated `@Adaptive` becomes the single `cachedAdaptiveClass`; a class whose constructor takes the SPI interface itself goes into `cachedWrapperClasses`; all remaining classes are indexed by name as ordinary implementations, with any `@Activate` metadata recorded alongside them. Duplicate names within the same priority tier fail at startup.

```java
private void loadClass(..., Map<String, Class<?>> extensionClasses, ..., Class<?> clazz, String name, boolean overridden) {
    if (clazz.isAnnotationPresent(Adaptive.class)) {
        cacheAdaptiveClass(clazz, overridden);         // -> cachedAdaptiveClass
    } else if (isWrapperClass(clazz)) {
        cacheWrapperClass(clazz);                      // -> cachedWrapperClasses
    } else {
        String[] names = NAME_SEPARATOR.split(name);
        cacheActivateClass(clazz, names[0]);           // -> cachedActivates
        for (String n : names) {
            cacheName(clazz, n);
            saveInExtensionClass(extensionClasses, clazz, n, overridden); // -> cachedClasses
        }
    }
}
```

An adaptive extension acts as a stateless runtime resolver and dispatcher in front of `getExtension(name)`. When `getAdaptiveExtension()` is called, `ExtensionLoader` checks `cachedAdaptiveClass`: if an implementation class itself is annotated `@Adaptive` (used only by bootstrap components such as `AdaptiveCompiler` and `AdaptiveExtensionInjector` to avoid circular code generation), it instantiates that class directly; otherwise `AdaptiveClassCodeGenerator` emits `<Interface>$Adaptive` source code and compiles it in memory via the `Compiler` SPI:

```java
private Class<?> getAdaptiveExtensionClass() {
    getExtensionClasses();
    if (cachedAdaptiveClass != null) {
        return cachedAdaptiveClass;
    }
    return cachedAdaptiveClass = createAdaptiveExtensionClass();
}

private Class<?> createAdaptiveExtensionClass() {
    ClassLoader classLoader = type.getClassLoader();
    String code = new AdaptiveClassCodeGenerator(type, cachedDefaultName).generate();
    Compiler compiler = extensionDirector
            .getExtensionLoader(Compiler.class)
            .getAdaptiveExtension();
    return compiler.compile(type, code, classLoader);
}
```

Inside each generated `@Adaptive` method (methods without `@Adaptive` throw `UnsupportedOperationException`), execution follows four steps on every call:

1. **Locate `URL`**: reads a `URL` argument directly, or invokes a `URL` getter on an argument (such as `invoker.getUrl()`). In application code this `URL` is rarely built by hand — `ServiceConfig` and `ReferenceConfig` assemble it automatically from `@DubboService`, `@DubboReference`, YAML/XML configuration, and registry metadata.
2. **Resolve `extName`**: evaluates the keys declared in `@Adaptive({"k1", "k2"})` (or splits the interface's camel-case name with dots when omitted), reading `url.getProtocol()` for `"protocol"`, `url.getMethodParameter(methodName, key, defaultExtName)` when an `Invocation` parameter is present, or `url.getParameter(key, defaultExtName)` with `@SPI`'s value as fallback.
3. **Resolve target extension**: obtains the `ScopeModel` from `url.getScopeModel()` and calls `scopeModel.getExtensionLoader(Type.class).getExtension(extName)`.
4. **Dispatch**: forwards the original arguments to the resolved instance.

When a concrete name is resolved through `getExtension(name)`, `createExtension` instantiates the target class, runs `injectExtension` across public setters (querying `AdaptiveExtensionInjector` across `SpiExtensionInjector`, `ScopeBeanExtensionInjector`, and `SpringExtensionInjector`, skipping unresolved setters and `@DisableInject`, and supplying `ScopeModelAware` / `ExtensionAccessorAware` callbacks), applies matching wrappers, and invokes `Lifecycle.initialize()` on the outermost object. For multi-element pipelines rather than single named targets, `getActivateExtension(url, key, group)` evaluates `@Activate(group, value, before, after, order)` against the `URL` and merges explicit additions or removals from the `URL` parameter named by `key` (`service.filter` on `provider`, `reference.filter` on `consumer`).

```java
public T getExtension(String name, boolean wrap) {
    if ("true".equals(name)) {
        return getDefaultExtension();
    }
    String cacheKey = wrap ? name : name + "_origin";
    final Holder<Object> holder = getOrCreateHolder(cacheKey);
    Object instance = holder.get();
    if (instance == null) {
        synchronized (holder) {
            instance = holder.get();
            if (instance == null) {
                instance = createExtension(name, wrap);
                holder.set(instance);
            }
        }
    }
    return (T) instance;
}

private T createExtension(String name, boolean wrap) {
    Class<?> clazz = getExtensionClasses().get(name);
    T instance = (T) extensionInstances.get(clazz);
    if (instance == null) {
        extensionInstances.putIfAbsent(clazz, createExtensionInstance(clazz));
        instance = (T) extensionInstances.get(clazz);
        instance = postProcessBeforeInitialization(instance, name);
        injectExtension(instance);
        instance = postProcessAfterInitialization(instance, name);
    }

    if (wrap && cachedWrapperClasses != null) {
        List<Class<?>> wrapperClassesList = new ArrayList<>(cachedWrapperClasses);
        wrapperClassesList.sort(WrapperComparator.COMPARATOR);
        Collections.reverse(wrapperClassesList);
        for (Class<?> wrapperClass : wrapperClassesList) {
            if (matchesWrapper(wrapperClass, name)) {
                instance = (T) wrapperClass.getConstructor(type).newInstance(instance);
                instance = postProcessBeforeInitialization(instance, name);
                injectExtension(instance);
                instance = postProcessAfterInitialization(instance, name);
            }
        }
    }
    initExtension(instance);
    return instance;
}

private T injectExtension(T instance) {
    for (Method method : instance.getClass().getMethods()) {
        if (!isSetter(method) || method.isAnnotationPresent(DisableInject.class)) {
            continue;
        }
        Class<?> pt = method.getParameterTypes()[0];
        if (ReflectUtils.isPrimitives(pt)) {
            continue;
        }
        String property = getSetterProperty(method);
        Object object = injector.getInstance(pt, property);
        if (object != null) {
            method.invoke(instance, object);
        }
    }
    return instance;
}
```

### Example: Adaptive and Wrapper

```java
package com.example.spi;

import org.apache.dubbo.common.URL;
import org.apache.dubbo.common.extension.Adaptive;
import org.apache.dubbo.common.extension.SPI;

@SPI("stripe")
public interface PaymentGateway {
    @Adaptive("gateway")
    String pay(URL url, int amountCents);
}
```

```java
package com.example.spi;

import org.apache.dubbo.common.URL;

public class StripeGateway implements PaymentGateway {
    @Override
    public String pay(URL url, int amountCents) {
        return "Stripe charged " + amountCents + " cents";
    }
}

public class PaypalGateway implements PaymentGateway {
    @Override
    public String pay(URL url, int amountCents) {
        return "PayPal charged " + amountCents + " cents";
    }
}
```

```java
package com.example.spi;

import org.apache.dubbo.common.URL;

public class LoggingPaymentWrapper implements PaymentGateway {
    private final PaymentGateway delegate;

    public LoggingPaymentWrapper(PaymentGateway delegate) {
        this.delegate = delegate;
    }

    @Override
    public String pay(URL url, int amountCents) {
        System.out.println("[Before] paying " + amountCents);
        String receipt = delegate.pay(url, amountCents);
        System.out.println("[After]  result = " + receipt);
        return receipt;
    }
}
```

`META-INF/dubbo/com.example.spi.PaymentGateway`:

```properties
stripe=com.example.spi.StripeGateway
paypal=com.example.spi.PaypalGateway
logging=com.example.spi.LoggingPaymentWrapper
```

Generated `PaymentGateway$Adaptive` compiled at runtime by `AdaptiveClassCodeGenerator`:

```java
package com.example.spi;

import org.apache.dubbo.rpc.model.ScopeModel;
import org.apache.dubbo.rpc.model.ScopeModelUtil;

public class PaymentGateway$Adaptive implements com.example.spi.PaymentGateway {
    public java.lang.String pay(org.apache.dubbo.common.URL arg0, int arg1) {
        if (arg0 == null) throw new IllegalArgumentException("url == null");
        org.apache.dubbo.common.URL url = arg0;
        String extName = url.getParameter("gateway", "stripe");
        if (extName == null)
            throw new IllegalStateException("Failed to get extension (com.example.spi.PaymentGateway) name from url (" + url.toString() + ") use keys([gateway])");
        ScopeModel scopeModel = ScopeModelUtil.getOrDefault(url.getScopeModel(), com.example.spi.PaymentGateway.class);
        com.example.spi.PaymentGateway extension = (com.example.spi.PaymentGateway) scopeModel
                .getExtensionLoader(com.example.spi.PaymentGateway.class)
                .getExtension(extName);
        return extension.pay(arg0, arg1);
    }
}
```

```java
ExtensionLoader<PaymentGateway> loader = ApplicationModel.defaultModel()
        .getExtensionLoader(PaymentGateway.class);

PaymentGateway gateway = loader.getAdaptiveExtension();

URL url1 = URL.valueOf("test://localhost/order");
gateway.pay(url1, 500);

URL url2 = URL.valueOf("test://localhost/order?gateway=paypal");
gateway.pay(url2, 1200);
```

```text
[Before] paying 500
[After]  result = Stripe charged 500 cents
[Before] paying 1200
[After]  result = PayPal charged 1200 cents
```

---

## 3. Protocol

`Protocol` is the core RPC boundary extension in Dubbo. It reduces remote service exposure and consumption to two operations: `export` turns a provider-side `Invoker` into a reachable `Exporter`, and `refer` turns a target `URL` into a consumer-side `Invoker`.

```java
@SPI(value = "dubbo", scope = ExtensionScope.FRAMEWORK)
public interface Protocol {
    @Adaptive <T> Exporter<T> export(Invoker<T> invoker) throws RpcException;
    @Adaptive <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException;
    int getDefaultPort();
}
```

Every call into `Protocol` is driven by a `URL` that carries not only the network endpoint, but also the interface, version, group, timeout, serializer, thread pool, and load balancer:

```text
dubbo://10.0.0.7:20880/org.apache.dubbo.GreetingService
  ?interface=org.apache.dubbo.GreetingService
  &version=1.0.0
  &group=blue
  &timeout=3000
  &serialization=hessian2
  &threadpool=limited
  &loadbalance=random
```

Parameters may be method-specific: `getMethodParameter(method, "timeout", 1000)` checks `methodName.timeout`, then `timeout`, then returns the default, allowing per-method timeouts and retries inside one flat `URL`.

`Protocol` coordinates export and refer through three shared mechanisms:

- **Per-method adaptive dispatch**: `export` and `refer` are marked `@Adaptive` (dispatching on `url.getProtocol()`), whereas `getDefaultPort()` has no `URL` parameter and throws `UnsupportedOperationException` on `Protocol$Adaptive`. The provider path enters through `export(Invoker)` (extracting `invoker.getUrl()`), while the consumer path enters through `refer(Class, URL)`. Because `RegistryProtocol` receives `Protocol$Adaptive` via `setProtocol(Protocol)`, a registry-backed export or refer traverses `Protocol$Adaptive` twice — first on the registry scheme and then on the wire scheme.
- **Shared state in `AbstractProtocol`**: wire and local protocols extend `AbstractProtocol`, which maintains `exporterMap` (keyed by `group/path:version:port` on the provider), `invokers` (active consumer `Invoker` references), and `serverMap` (reusing one `ProtocolServer` per `host:port` across all exported services on that port).
- **Automatic wrapper chain**: `ExtensionLoader` wraps every concrete `Protocol` with `ProtocolFilterWrapper` (builds provider/consumer `Filter` chains), `ProtocolListenerWrapper` (fires exporter/invoker listeners), `ProtocolSerializationWrapper` and `ProtocolSecurityWrapper` (enforce serialization allow-lists), `InvokerCountWrapper` (tracks active references), and `QosProtocolWrapper` (starts the QoS diagnostic server). Concrete protocol classes therefore contain no filter, listener, or security boilerplate.

Dubbo ships the following `Protocol` implementations across its modules:

- **`service-discovery-registry` (`RegistryProtocol`) and `registry` (`InterfaceCompatibleRegistryProtocol`)**: outer registry-integration protocols that register/subscribe endpoints in the registry and delegate local binding and remote invoker creation to a wire protocol.
- **`dubbo` (`DubboProtocol`, default port `20880`)**: Dubbo's default TCP binary RPC protocol built over `Exchanger` and `Transporter`.
- **`tri` (`TripleProtocol`, default port `50051`), `grpc` (`GrpcProtocol`), and `rest2` (`RestProtocol`)**: HTTP/2 and HTTP/1.1 protocols supporting unary and streaming RPC, gRPC interoperability, and RESTful mapping.
- **`injvm` (`InjvmProtocol`)**: local in-process protocol that invokes providers in the same JVM directly without network I/O or serialization.
- **`mock` (`MockProtocol`)**: consumer-side stub and fallback protocol used for service degradation.

```plantuml
@startuml
top to bottom direction

interface Protocol {
  + getDefaultPort(): int
  + export(Invoker<T>): Exporter<T>
  + refer(Class<T>, URL): Invoker<T>
}
abstract class AbstractProtocol implements Protocol {
  # exporterMap: Map<String, Exporter<?>>
  # invokers: Set<Invoker<?>>
  # serverMap: ConcurrentMap<String, ProtocolServer>
  # protocolBindingRefer(Class<T>, URL): Invoker<T>
}
class DubboProtocol extends AbstractProtocol
class TripleProtocol extends AbstractProtocol
class GrpcProtocol extends TripleProtocol
class RestProtocol extends TripleProtocol
class InjvmProtocol extends AbstractProtocol
class MockProtocol extends AbstractProtocol
class RegistryProtocol implements Protocol
class InterfaceCompatibleRegistryProtocol extends RegistryProtocol

interface Exporter<T> {
  + getInvoker(): Invoker<T>
  + unexport()
}
abstract class AbstractExporter<T> implements Exporter {
  - invoker: Invoker<T>
}

interface Invoker<T> {
  + getInterface(): Class<T>
  + invoke(Invocation): Result
}
abstract class AbstractInvoker<T> implements Invoker {
  - type: Class<T>
  - url: URL
}

AbstractProtocol *-- Exporter
AbstractProtocol *-- Invoker
AbstractExporter o-- Invoker
@enduml
```

### 3.1 Export: the provider runtime

`export` turns a local service implementation into a remotely reachable endpoint and announces it to the cluster. Each `@DubboService` (or programmatic service definition) is represented at runtime by one `ServiceConfig<T>` instance, which sits at the boundary between declarative configuration and the SPI runtime: its inheritance chain (`AbstractConfig` -> `AbstractMethodConfig` -> `AbstractInterfaceConfig` -> `AbstractServiceConfig` -> `ServiceConfigBase<T>` -> `ServiceConfig<T>`) aggregates method-, interface-, registry-, and protocol-level settings into `ServiceConfigURL`s, holds `protocolSPI` (`Protocol$Adaptive`) and `proxyFactory` (`ProxyFactory$Adaptive`), and tracks the resulting `Exporter` list for shutdown.

Application code rarely instantiates or invokes `ServiceConfig` directly; Dubbo's deployer drives it through two entry paths that converge on the same startup pipeline:

- **Spring / `@DubboService` path**: `DubboSpringInitializer.initialize(registry)` binds a `ModuleModel` to the Spring container and registers `DubboDeployApplicationListener` (via `DubboBeanUtils.registerCommonBeans`); `ServiceAnnotationPostProcessor` (`BeanDefinitionRegistryPostProcessor`) scans `@DubboService` classes and registers `ServiceBean<T>` bean definitions; during bean initialization, `ServiceBean.afterPropertiesSet()` (`InitializingBean`) adds itself to `ModuleConfigManager`. When Spring finishes refreshing and publishes `ContextRefreshedEvent`, `DubboDeployApplicationListener` (`ApplicationListener`) catches the event and invokes `moduleModel.getDeployer().start()` (`DefaultModuleDeployer.start()` -> `applicationDeployer.initialize()` -> `startSync()`).
- **Programmatic `DubboBootstrap` path**: `DubboBootstrap.getInstance().service(serviceConfig).start()` registers `ServiceConfig<T>` in `ModuleConfigManager` and calls `DefaultApplicationDeployer.start()`, which starts each module's `DefaultModuleDeployer`.

`DefaultModuleDeployer.startSync()` first runs `exportServices()`, calling `serviceConfig.export()` to wrap `ref` into an `Invoker` and bind the local wire server via `RegistryProtocol.export`, and then runs `registerServices()` followed by `applicationDeployer.refreshServiceInstance()` so consumers never discover an unready port.

Services belong to a `ModuleModel` rather than directly to `ApplicationModel`. While `ApplicationModel` represents one logical Dubbo application (`dubbo.application.name`) and owns shared infrastructure (`RegistryConfig`, `ProtocolConfig`, `ExecutorRepository`, and the Nacos `ServiceDiscovery` client), a `ModuleModel` is an independently deployable unit of `@DubboService` and `@DubboReference` definitions with its own `ClassLoader` set, `ModuleConfigManager`, and `ModuleDeployer`. Every `ApplicationModel` maintains at least two modules: an `internalModule` (hosting framework services such as `MetadataService`) and a `defaultModule` (bound to the primary Spring `ApplicationContext`). Multi-context Spring setups or dynamic plugin containers create additional `ModuleModel`s via `applicationModel.newModule()`, allowing a single module's services and `ClassLoader` to start or stop without tearing down the rest of the application.

```plantuml
@startuml
top to bottom direction

class DubboSpringInitializer {
  - REGISTRY_CONTEXT_MAP: Map<BeanDefinitionRegistry, DubboSpringInitContext>
  + initialize(BeanDefinitionRegistry)
  - initContext(DubboSpringInitContext, BeanDefinitionRegistry, ConfigurableListableBeanFactory)
}

interface BeanDefinitionRegistryPostProcessor {
  + postProcessBeanDefinitionRegistry(BeanDefinitionRegistry)
}
class ServiceAnnotationPostProcessor implements BeanDefinitionRegistryPostProcessor {
  - registerServiceBean(BeanDefinitionHolder, BeanDefinitionRegistry, ...)
}

interface InitializingBean {
  + afterPropertiesSet()
}
interface ApplicationListener<E> {
  + onApplicationEvent(E)
}
class DubboDeployApplicationListener implements ApplicationListener {
  - applicationModel: ApplicationModel
  - moduleModel: ModuleModel
  + onApplicationEvent(ApplicationContextEvent)
  - onContextRefreshedEvent(ContextRefreshedEvent)
}

abstract class AbstractConfig {
  # scopeModel: ScopeModel
  + refresh()
}
abstract class AbstractMethodConfig extends AbstractConfig {
  # timeout: Integer
  # retries: Integer
  # loadbalance: String
}
abstract class AbstractInterfaceConfig extends AbstractMethodConfig {
  # application: ApplicationConfig
  # registries: List<RegistryConfig>
}
abstract class AbstractServiceConfig extends AbstractInterfaceConfig {
  # version: String
  # group: String
  # protocols: List<ProtocolConfig>
}
abstract class ServiceConfigBase<T> extends AbstractServiceConfig {
  # interfaceClass: Class<?>
  # ref: T
  + export()
  + unexport()
}
class ServiceConfig<T> extends ServiceConfigBase {
  - protocolSPI: Protocol
  - proxyFactory: ProxyFactory
  - providerModel: ProviderModel
  - exporters: ConcurrentHashMap<RegisterTypeEnum, List<Exporter<?>>>
  + export()
  # doExport()
  - doExportUrls()
}
class ServiceBean<T> extends ServiceConfig implements InitializingBean {
  + afterPropertiesSet()
  + destroy()
}

abstract class ScopeModel {
  - parent: ScopeModel
  - scope: ExtensionScope
  - classLoaders: Set<ClassLoader>
}
class FrameworkModel extends ScopeModel {
  - applicationModels: List<ApplicationModel>
}
class ApplicationModel extends ScopeModel {
  - internalModule: ModuleModel
  - defaultModule: ModuleModel
  - moduleModels: List<ModuleModel>
}
class ModuleModel extends ScopeModel {
  - applicationModel: ApplicationModel
  - moduleConfigManager: ModuleConfigManager
  - deployer: ModuleDeployer
  + getConfigManager(): ModuleConfigManager
  + getDeployer(): ModuleDeployer
}

class ModuleConfigManager {
  + addService(ServiceConfigBase)
  + getServices(): Collection<ServiceConfigBase>
}
interface ModuleDeployer {
  + start(): Future
  + setPending()
}
class DefaultModuleDeployer implements ModuleDeployer {
  - configManager: ModuleConfigManager
  - applicationDeployer: ApplicationDeployer
  + start(): Future
  - startSync(): Future
  - exportServices()
  - registerServices()
}

class ServiceModel {
  - serviceKey: String
  - proxyObject: Object
  - moduleModel: ModuleModel
  - serviceModel: ServiceDescriptor
  - serviceMetadata: ServiceMetadata
}
class ProviderModel extends ServiceModel {
  - urls: List<RegisterStatedURL>
  - methods: Map<String, List<ProviderMethodModel>>
  - serviceUrls: List<URL>
}
class ConsumerModel extends ServiceModel {
  - apps: Set<String>
  - methodModels: Map<Method, ConsumerMethodModel>
}

interface Protocol {
  + export(Invoker<T>): Exporter<T>
}
interface ProxyFactory {
  + getInvoker(T, Class<T>, URL): Invoker<T>
}

FrameworkModel *-- ApplicationModel
ApplicationModel *-- ModuleModel
DubboSpringInitializer ..> DubboDeployApplicationListener
DubboSpringInitializer ..> ModuleModel
ServiceAnnotationPostProcessor ..> ServiceBean
ServiceBean ..> ModuleModel
DubboDeployApplicationListener o-- ModuleModel
ModuleModel *-- ModuleConfigManager
ModuleModel *-- ModuleDeployer
ModuleModel --o ServiceModel
DefaultModuleDeployer --> ModuleConfigManager
ModuleConfigManager o-- ServiceConfigBase
DefaultModuleDeployer ..> ServiceConfig
ServiceConfig *-- ProviderModel
ServiceConfig --> ProxyFactory
ServiceConfig --> Protocol
@enduml
```

```java
// 1. Scan & register ServiceBean: @DubboService -> ServiceAnnotationPostProcessor -> ServiceBean.afterPropertiesSet()
public void afterPropertiesSet() {
    ModuleModel moduleModel = DubboBeanUtils.getModuleModel(applicationContext);
    moduleModel.getConfigManager().addService(this);            // register ServiceBean into ModuleConfigManager
    moduleModel.getDeployer().setPending();
}

// 2. ContextRefreshedEvent -> DubboDeployApplicationListener.onContextRefreshedEvent() -> DefaultModuleDeployer.start()
private void onContextRefreshedEvent(ContextRefreshedEvent event) {
    ModuleDeployer deployer = moduleModel.getDeployer();
    Future future = deployer.start();                           // calls applicationDeployer.initialize() -> startSync()
}

private synchronized Future startSync() {
    exportServices();                                           // Phase A: bind local server + publish service definition
    prepareInternalModule();                                    // ensure internal module (MetadataService) is ready
    referServices();
    onModuleStarted();                                          // triggers prepareApplicationInstance() -> registerServiceInstance()
    registerServices();                                         // Phase B: populate MetadataInfo + refresh registry instance
    return startFuture;
}

// 3. Build URLs in ServiceConfig.doExportUrls(): rewrite nacos:// -> service-discovery-registry:// and publish definition
private void doExportUrls(RegisterTypeEnum registerType) {
    // Rewrites nacos://127.0.0.1:8848 -> service-discovery-registry://127.0.0.1:8848?registry=nacos
    List<URL> registryURLs = ConfigValidationUtils.loadRegistries(this, true);
    for (ProtocolConfig protocolConfig : protocols) {
        URL url = buildUrl(protocolConfig, map);                // wire URL: dubbo://10.0.0.7:20880/GreetingService?...
        exportLocal(url);                                       // export injvm://127.0.0.1/... for in-process calls
        for (URL registryURL : registryURLs) {
            // Attach wire URL under EXPORT_KEY; AUTO_REGISTER_BY_DEPLOYER defers registry.register to registerServices()
            doExportUrl(registryURL.putAttribute(EXPORT_KEY, url), true, registerType);
        }
        // Upload per-service FullServiceDefinition to remote MetadataReport (when configured)
        MetadataUtils.publishServiceDefinition(url, providerModel.getServiceModel(), getApplicationModel());
    }
}

// 4. Wrap ref as Invoker, dispatch to RegistryProtocol.export() for local Netty bind, then map interface -> app
private void doExportUrl(URL url, boolean withMetaData, RegisterTypeEnum registerType) {
    if (registerType == RegisterTypeEnum.AUTO_REGISTER_BY_DEPLOYER) {
        url = url.addParameter(REGISTER_KEY, false);            // defer registration until all services finish binding
    }
    Invoker<?> invoker = proxyFactory.getInvoker(ref, (Class) interfaceClass, url); // Javassist Wrapper, no reflection
    Exporter<?> exporter = protocolSPI.export(new DelegateProviderMetaDataInvoker(invoker, this));
    exporters.computeIfAbsent(registerType, k -> new CopyOnWriteArrayList<>()).add(exporter);
}

protected void exported() {
    serviceNameMapping.map(url);                                // upload interface -> applicationName mapping
    getScopeModel().getDeployer().getApplicationDeployer().exportMetadataService(); // export local MetadataService
}

// 5. RegistryProtocol.export(): unwrap EXPORT_KEY and bind local Netty port via DubboProtocol
public <T> Exporter<T> export(final Invoker<T> originInvoker) throws RpcException {
    URL registryUrl = getRegistryUrl(originInvoker);            // unwrap nacos://127.0.0.1:8848
    URL providerUrl = getProviderUrl(originInvoker);            // read EXPORT_KEY -> dubbo://10.0.0.7:20880/...
    final ExporterChangeableWrapper<T> exporter = doLocalExport(originInvoker, providerUrl); // DubboProtocol.export()
    exporter.setRegisterUrl(customizeURL(providerUrl, registryUrl));
    return new DestroyableExporter<>(exporter);
}

// 6. Accumulate exported service URLs into MetadataInfo: registerServices() -> sc.register(true) -> AbstractServiceDiscovery
private void registerServices() {
    for (ServiceConfigBase sc : configManager.getServices()) {
        sc.register(true);                                      // exporter.register() -> ServiceDiscoveryRegistry.doRegister(url)
    }
    applicationDeployer.refreshServiceInstance();               // recompute revision, upload MetadataInfo, update Nacos instance
}

public void register(URL url) {                                 // AbstractServiceDiscovery.register(URL)
    metadataInfo.addService(url);                               // record interface, version, group, protocol, and method params
}

// 7. Upload MetadataInfo and register ServiceInstance in Nacos: AbstractServiceDiscovery.register() / update()
public synchronized void register() throws RuntimeException {
    if (this.serviceInstance == null) {
        this.serviceInstance = createServiceInstance(this.metadataInfo); // host, port, app name, endpoints
    }
    boolean revisionUpdated = calOrUpdateInstanceRevision(this.serviceInstance); // compute dubbo.metadata.revision digest
    if (revisionUpdated) {
        reportMetadata(this.metadataInfo);                      // upload MetadataInfo + snapshot for local MetadataService
        doRegister(this.serviceInstance);                       // NacosServiceDiscovery -> namingService.registerInstance(...)
    }
}

protected void reportMetadata(MetadataInfo metadataInfo) {
    if (metadataReport != null) {
        SubscriberMetadataIdentifier id = new SubscriberMetadataIdentifier(serviceName, metadataInfo.getRevision());
        metadataReport.publishAppMetadata(id, metadataInfo);    // remote MetadataReport upload (when configured)
    }
    metadataInfos.put(metadataInfo.getRevision(), new MetadataInfoStat(metadataInfo.clone())); // served by MetadataService
}
```

### 3.2 Refer: the consumer side

`refer` turns a service interface and target `URL` into a local proxy backed by remote providers. When backed by a registry, `ReferenceConfig` delegates through `Protocol$Adaptive` to `RegistryProtocol.refer`, which subscribes a `Directory` to the registry and joins all discovered provider `Invoker`s behind a single fault-tolerant `ClusterInvoker` before wrapping it in a dynamic proxy for the caller:

```plantuml
@startuml
top to bottom direction

interface Invoker {
  + getInterface(): Class
  + invoke(Invocation): Result
}
class DubboInvoker implements Invoker
interface ClusterInvoker extends Invoker
class FailoverClusterInvoker implements ClusterInvoker

interface Directory {
  + list(Invocation): List
}
class RegistryDirectory implements Directory
class ServiceDiscoveryRegistryDirectory implements Directory

interface Cluster {
  + join(Directory): Invoker
}
class FailoverCluster implements Cluster

interface LoadBalance {
  + select(List, URL, Invocation): Invoker
}

FailoverCluster ..> FailoverClusterInvoker
FailoverClusterInvoker o-- Directory
FailoverClusterInvoker ..> LoadBalance
@enduml
```

```java
// 1. ReferenceConfig refers the registry URL and wraps the returned Invoker in a dynamic proxy
invoker = protocolSPI.refer(interfaceClass, registryUrl);
return (T) proxyFactory.getProxy(invoker, ProtocolUtils.isGeneric(generic));

// 2. RegistryProtocol.refer -> doRefer resolves Registry + Cluster and builds MigrationInvoker
public <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException {
    url = getRegistryUrl(url);                                  // unwrap nacos://...
    Registry registry = getRegistry(url);
    Cluster cluster = Cluster.getCluster(url.getScopeModel(), qs.get(CLUSTER_KEY));
    return doRefer(cluster, registry, type, url, qs);           // creates ServiceDiscoveryMigrationInvoker
}

// 3. RegistryProtocol.doCreateInvoker wires Directory, RouterChain, subscription, and ClusterInvoker
protected <T> ClusterInvoker<T> doCreateInvoker(
        DynamicDirectory<T> directory, Cluster cluster, Registry registry, Class<T> type) {
    directory.setRegistry(registry);
    directory.setProtocol(protocol);                            // Protocol$Adaptive for per-instance refer
    if (directory.isShouldRegister()) {
        registry.register(urlToRegistry);                       // optional consumer registration
    }
    directory.buildRouterChain(urlToRegistry);                  // assemble activated StateRouters
    directory.subscribe(toSubscribeUrl(urlToRegistry));         // subscribe addresses + revisions
    return (ClusterInvoker<T>) cluster.join(directory, true);   // wrap Directory in ClusterInvoker
}

// 4. InvokerInvocationHandler intercepts application calls on the generated proxy
RpcInvocation rpcInvocation = new RpcInvocation(serviceModel, method.getName(),
        invoker.getInterface().getName(), protocolServiceKey,
        method.getParameterTypes(), args);
return InvocationUtil.invoke(invoker, rpcInvocation);           // sets RpcContext, invokes, calls recreate()
```

#### Directory refresh

```mermaid
flowchart LR
    A["notify(urls)"] --> B["instance urls, address + revision"]
    B --> C{"single empty:// url?"}
    C -->|"yes"| D["forbid, destroy all invokers"]
    C -->|"no"| E["distinct, drop duplicates"]
    E --> F["reuse invokers whose url is unchanged"]
    F --> G["refer new instances"]
    G --> H["swap urlInvokerMap atomically"]
    H --> I["refresh router chain"]
```

An ordinary empty notification list triggers empty protection (retaining the previous `urlInvokerMap`), whereas a single `empty://` URL explicitly forbids the service and destroys all invokers.

#### Cluster invocation

```java
// FailoverClusterInvoker.doInvoke (default Cluster = "failover")
int len = calculateInvokeTimes(methodName);                     // retries + 1 (default 3 attempts)
List<Invoker<T>> invoked = new ArrayList<>(copyInvokers.size());
for (int i = 0; i < len; i++) {
    if (i > 0) {
        copyInvokers = list(invocation);                        // re-fetch routed candidates before retry
        checkInvokers(copyInvokers, invocation);
    }
    // select applies sticky check, availablecheck, LoadBalance (default weighted random), and skips invoked
    Invoker<T> invoker = select(loadbalance, invocation, copyInvokers, invoked);
    invoked.add(invoker);
    try {
        return invokeWithContext(invoker, invocation);          // runs ClusterFilter + reference.filter chains
    } catch (RpcException e) {
        if (e.isBiz()) throw e;                                 // business exception: never retried
        le = e;                                                 // framework exception: failover to next node
    }
}
throw le;
```

### 3.3 RegistryProtocol

`RegistryProtocol` (`service-discovery-registry`) and its subclass `InterfaceCompatibleRegistryProtocol` (`registry`) do no socket framing or network transport themselves; they implement `Protocol` solely to bridge `ServiceConfig` and `ReferenceConfig` to the `Registry` / `ServiceDiscovery` SPI without special-casing registry logic in the config layer:

- **On `export`**: unwraps the registry `URL` (`getRegistryUrl`) and the nested wire `URL` (`EXPORT_KEY`), delegates local port binding to `protocol.export(...)` (`ExporterChangeableWrapper`), and hands the provider `URL` to `registry.register(...)` (wrapped in `DestroyableExporter` so `unexport()` unregisters before closing).
- **On `refer`**: resolves the `Registry` and `Cluster` SPIs, constructs a `ServiceDiscoveryMigrationInvoker` (capable of switching between application-level `ServiceDiscoveryRegistryDirectory` and interface-level `RegistryDirectory`), and subscribes the `Directory` to provider address changes. When a direct point-to-point `URL` (`dubbo://host:port`) is configured instead of a registry, `Protocol$Adaptive` bypasses `RegistryProtocol` completely and dispatches straight to the wire protocol.

### 3.4 DubboProtocol

`DubboProtocol` is Dubbo's default wire protocol (`dubbo://`, port `20880`), pairing `DubboExporter` on the provider with `DubboInvoker` on the consumer over persistent Netty TCP channels.

#### Local export and server binding

Local export descends from `RegistryProtocol.doLocalExport` through the protocol wrappers into `DubboProtocol.export`:

```java
String key = serviceKey(url);                       // group/path:version:port
DubboExporter<T> exporter = new DubboExporter<>(invoker, key, exporterMap);
openServer(url);
```

`openServer` keeps one server per `host:port` in `serverMap`, so all services sharing a port share a single Netty server; `server.reset(url)` applies URL changes to the existing server. `createServer` binds through `Exchangers.bind(url, requestHandler)`, which resolves the `Exchanger` SPI (`header` by default), whose `HeaderExchanger.bind` wraps the handler as `DecodeHandler(HeaderExchangeHandler(handler))` and delegates to `Transporters.bind` — `NettyServer` with the `DubboCountCodec` on the pipeline. The `EventLoop` and `ChannelPipeline` mechanics underneath are those of [Netty](/post/java/netty/); Dubbo adds one codec and one handler chain on top of a standard bootstrap.

The `exporterMap` key is what the provider uses to route an incoming request. `AbstractProtocol.serviceKey` composes `group/path:version:port`, with the port included so two services with the same interface on different ports do not collide.

#### Provider-side dispatch and threading

An arriving frame is decoded on the Netty I/O thread into a `Request` whose payload is a `DecodeableRpcInvocation`; the argument bytes are not yet deserialized. The handler chain installed by `ChannelHandlers.wrap` is:

```text
MultiMessageHandler -> HeartbeatHandler -> Dispatcher(all) -> DecodeHandler -> HeaderExchangeHandler
```

`AllChannelHandler.received` submits a `ChannelEventRunnable` to the business thread pool, so `DecodeHandler` — and therefore argument deserialization — runs on a business thread, not on the event loop. `decode.in.io.thread=false` is the default and exists to keep long deserialization off the I/O threads.

`HeaderExchangeHandler.handleRequest` then calls the `ExchangeHandler.reply` implemented inside `DubboProtocol`:

```java
Invocation inv = (Invocation) message;
Invoker<?> invoker = inv.getInvoker() == null ? getInvoker(channel, inv) : inv.getInvoker();
RpcContext.getServiceContext().setRemoteAddress(channel.getRemoteAddress());
Result result = invoker.invoke(inv);
return result.thenApply(Function.identity());
```

`getInvoker` extracts `path`, `version`, and `group` from the invocation attachments, rebuilds the service key with the local port, and looks it up in `exporterMap`. A miss produces a `RemotingException` naming the key and the channel pair, which the caller observes as a "not found exported service" error rather than a timeout. On a hit the invocation is stamped with the provider's `ServiceModel`, which is what lets the subsequent filter chain and the generated wrapper resolve methods and switch the context class loader.

The reply is completed asynchronously: `HeaderExchangeHandler` attaches a completion stage that writes a `Response` with status `OK` on success, or status `70` (`SERVICE_ERROR`) with the exception text. Because the `Result` may complete on a different thread than the one that received the request, the response write is not tied to the business thread that ran the service method.

The thread pool itself is the `ThreadPool` extension selected by the `threadpool` parameter. Its SPI default is `fixed`, which is also what a provider gets when nothing is configured: `threads` (default `200`) fixed-size workers, `SynchronousQueue` when `queues=0` (the default), and `AbortPolicyWithReport` as the rejection handler. `cached` is the default for *client* URLs, because a consumer's executor services replies and callbacks rather than business methods; `limited` and `eager` are also available. Saturation is not silent: the rejection policy throws, and `AllChannelHandler.sendFeedback` converts that into a `Response` with status `100` (`SERVER_THREADPOOL_EXHAUSTED_ERROR`) for two-way requests, so the consumer receives an immediate server-side rejection instead of waiting for its timeout.

#### Shutdown

`DubboProtocol` participates in `DubboGracefulShutdown`. The server sends a read-only event to every connected channel; the consumer's `HeaderExchangeHandler` records the event on the channel and marks the corresponding client unavailable, so the directory stops selecting new invocations toward it while in-flight requests complete. The server then waits for the configured shutdown timeout before closing.

#### Frame layout

The protocol layer on both sides reduces to one frame format. `ExchangeCodec` fixes a 16-byte header for both directions, followed by a serialized body.

| Offset | Size | Content |
|--------|------|---------|
| 0 | 2 | Magic `0xdabb` |
| 2 | 1 | Bit 7: request; bit 6: two-way; bit 5: event; bits 0–4: serialization id |
| 3 | 1 | Status, meaningful in responses only |
| 4 | 8 | Request id |
| 12 | 4 | Body length |
| 16 | var | Serialized body |

The request flag in bit 7 and the serialization id in the low five bits of byte 2 give a reader everything needed to classify the frame and pick a body codec before any deserialization. A request sets bit 7; a response leaves it clear and fills byte 3 with a status code. The status byte is present but ignored in requests, so the fixed layout is symmetric and cheap to parse. Responses carry `20` (`OK`), `30` (`CLIENT_TIMEOUT`), `35` (`CHANNEL_INACTIVE`), `40` (`BAD_REQUEST`), `50` (`BAD_RESPONSE`), `60` (`SERVICE_NOT_FOUND`), `70` (`SERVICE_ERROR`), `90` (`CLIENT_ERROR`), or `100` (`SERVER_THREADPOOL_EXHAUSTED_ERROR`).

Requests are encoded by `DubboCodec.encodeRequestData`, which writes a fixed sequence into the serialized stream:

```text
protocol version (UTF) | service name (UTF) | service version (UTF) |
method name (UTF) | parameter type descriptor (UTF) | arguments | attachments
```

The service name is taken from the `interface` attachment with the `path` attachment as fallback. The parameter descriptor is a JVM type descriptor string (`Ljava/lang/String;IZ`) rather than a serialized `Class[]`; the provider resolves the `Method` from its own service model, so a consumer compiled against the same interface can invoke it without transmitting class metadata. Attachments (trace ids, timeouts, tags) travel in the same body, so the invocation context is carried by the protocol rather than by a side channel.

Responses are typed by a leading byte: value, null, exception, and each with attachments. Attachments on the response are omitted for peers older than protocol version 2.0.2, detected by parsing the version string from the request.

`DubboCountCodec` decodes in a loop, accumulating messages until the buffer is exhausted or decoding returns `NEED_MORE_INPUT`, rewinding the reader index in the latter case. A single `decode` call therefore yields one `MultiMessage` holding every complete frame in the buffer, and `MultiMessageHandler` at the head of the handler chain dispatches each element in turn, isolating a failure in one message from the rest of the batch. One TCP read carrying several small requests costs one decode call, not one per read event.

Payload size is enforced by `checkPayload` against the `payload` parameter, default 8 MiB, on both encode and decode. Exceeding it on the response path is converted into a `BAD_RESPONSE` frame so the consumer fails immediately rather than waiting for a timeout.

Serialization is negotiated per request, not per connection. `DubboCodec.getSerialization` checks the `Invocation` for a `serialization id` attachment and, when present, uses that codec id; otherwise it resolves `UrlUtils.serializationOrDefault(url)`, which tries `prefer.serialization` in order, then `serialization`, then the framework default — `hessian2` unless `DUBBO_DEFAULT_SERIALIZATION` overrides it. On the provider, the `AppResponse` carries its `Invocation`, so the reply is encoded with the same id the request used. Because that id occupies the low five bits of the header, the receiver needs no out-of-band agreement, and one connection can carry requests encoded with different serializers.

#### Request/response correlation and timeouts

The RPC layer is synchronous in appearance but asynchronous in structure. `DubboInvoker.doInvoke` builds a `Request` with `twoWay=true`, then:

```java
CompletableFuture<AppResponse> appResponseFuture =
        currentClient.request(request, timeout, executor).thenApply(AppResponse.class::cast);
AsyncRpcResult result = new AsyncRpcResult(appResponseFuture, inv);
```

`HeaderExchangeChannel.request` creates a `DefaultFuture` before sending, registers it in a static `FUTURES` map keyed by request id, and arms a `HashedWheelTimer` timeout task. When a `Response` arrives, `HeaderExchangeHandler.handleResponse` calls `DefaultFuture.received`, which removes the entry, cancels the timeout task, and completes the future. An id with no live future — a response that arrived after its timeout — is logged and discarded.

A late response is therefore not an error path in the transport; it is simply dropped. The consequence is that a timed-out request may still execute on the provider, which is why the fault-tolerance policy treats timeouts as retryable only under the caller's explicit configuration, and why the retry loop excludes business exceptions.

Timeout values compose before the call. `RpcUtils.calculateTimeout` honours a `TIME_COUNTDOWN` attachment (used for nested calls that must fit inside the caller's remaining budget), otherwise reads `methodName.timeout` then `timeout`, defaulting to 1000 ms. When a countdown is present, or when `enable-timeout-countdown` is set on the method, the resolved value is written into a `TIMEOUT_ATTACHMENT_KEY` attachment so the provider can apply the same budget.

Connection loss is handled explicitly. `DefaultFuture.closeChannel` walks the channels for uncompleted futures, waits up to the configured close timeout for a response, and then synthesizes a `CHANNEL_INACTIVE` response, so a broken connection fails fast instead of consuming the RPC timeout.

#### Keepalive and reconnection

`HeaderExchangeClient` owns two timer tasks per client. `HeartbeatTimerTask` sends an event request when neither a read nor a write has occurred within `heartbeat` (default 60 s); `HeartbeatHandler` answers heartbeat requests on the I/O thread, without entering the business pool. `ReconnectTimerTask` reconnects a channel that is not connected, and also one whose last read is older than the idle timeout, which defaults to three heartbeat intervals. `getCloseTimeout` enforces the corresponding invariant: the close timeout may not be shorter than twice the heartbeat interval, and the idle timeout may not be either.

One client per provider address is the default: `connections=0` selects shared clients (`shareconnections`, default `1`), which are reference counted (`ReferenceCountExchangeClient`) so that two services on the same port share one connection and closing one does not close the socket. `connections=n` with `n>0` instead creates `n` dedicated clients per service, round-robined by `DubboInvoker`. `lazy=true` defers the TCP connect to the first call.

#### One invocation across the boundary

```mermaid
sequenceDiagram
    participant App as Application
    participant Px as Proxy
    participant Cl as FailoverClusterInvoker
    participant Dir as RegistryDirectory
    participant Inv as DubboInvoker
    participant Ch as NettyClient channel
    participant Srv as NettyServer
    participant Ex as Provider dispatch

    App->>Px: method call
    Px->>Cl: invoke RpcInvocation
    Cl->>Dir: list invocation
    Dir-->>Cl: routed provider invokers
    Cl->>Cl: select via LoadBalance
    Cl->>Inv: invoke invocation
    Inv->>Ch: Request id, twoWay, via DefaultFuture
    Ch->>Srv: 16-byte header and Hessian2 body
    Srv->>Srv: decode header, dispatch to business pool
    Srv->>Ex: decoded Invocation
    Ex->>Ex: exporterMap lookup by serviceKey
    Ex->>Ex: provider filter chain, service method
    Ex-->>Ch: Response id, status=20, value
    Ch->>Inv: DefaultFuture.received completes
    Inv-->>Cl: AsyncRpcResult
    Cl-->>Px: Result
    Px-->>App: recreate returns value
```

The provider filter chain runs inside `invoker.invoke(inv)` on the business thread, so the service key resolution, the context class loader switch, and the filters all precede the business method, while the response is written from the completion callback that `HeaderExchangeHandler` attaches to the returned stage — on the business thread for a synchronous service method, and on whichever thread completes the future otherwise.

---

## 4. Exchanger

`Exchanger` sits between the protocol and the transport, and it is where request/response semantics enter. The transport moves bytes and knows nothing about correlation; the exchanger adds request identity, two-way versus one-way, event frames, and futures.

```java
@SPI(value = HeaderExchanger.NAME, scope = ExtensionScope.FRAMEWORK)
public interface Exchanger {
    @Adaptive ExchangeServer bind(URL url, ExchangeHandler handler);
    @Adaptive ExchangeClient connect(URL url, ExchangeHandler handler);
}
```

`HeaderExchanger` is the only implementation. `bind` wraps the handler as `HeaderExchangeHandler` inside the transport's server, `connect` wraps the channel as `HeaderExchangeClient`. `HeaderExchangeHandler.handleResponse` routes a `Response` to `DefaultFuture.received`, the single point where a waiting call is completed, and `HeaderExchangeClient` owns the heartbeat and reconnect timers.

```plantuml
@startuml
top to bottom direction

interface Exchanger {
  + bind(URL, ExchangeHandler): ExchangeServer
  + connect(URL, ExchangeHandler): ExchangeClient
}
class HeaderExchanger implements Exchanger

interface ExchangeServer
class HeaderExchangeServer implements ExchangeServer

interface ExchangeChannel {
  + request(Object, int): CompletableFuture
}
interface ExchangeClient extends ExchangeChannel
class HeaderExchangeClient implements ExchangeClient {
  - idleTimeout: int
  + request(Object): CompletableFuture
}
class HeaderExchangeHandler {
  + received(Channel, Object)
  + handleRequest(ExchangeChannel, Request)
}
class DefaultFuture {
  - FUTURES: Map<Long, DefaultFuture>
  + received(Channel, Response)
}

HeaderExchanger ..> HeaderExchangeServer
HeaderExchanger ..> HeaderExchangeClient
HeaderExchangeHandler ..> DefaultFuture
@enduml
```

---

## 5. Transporter

`Transporter` is the network implementation: it opens server sockets and client connections. The name is chosen by `server` for binding and `client` for connecting, both falling back to `transporter`, with `netty` as the default.

```java
@SPI(value = "netty", scope = ExtensionScope.FRAMEWORK)
public interface Transporter {
    @Adaptive({SERVER_KEY, TRANSPORTER_KEY}) RemotingServer bind(URL url, ChannelHandler handler);
    @Adaptive({CLIENT_KEY, TRANSPORTER_KEY}) Client connect(URL url, ChannelHandler handler);
}
```

`NettyTransporter` returns a `NettyServer` or a `NettyClient`; the state and behaviour live in `AbstractServer`/`AbstractClient`, which handle bind retry, port detection, channel bookkeeping, and the connection listener set, while the subclass builds only the Netty `ServerBootstrap`. The SPI name `netty` maps to the Netty 4 module; the Netty 3 module registers as `netty3`.

```plantuml
@startuml
top to bottom direction

interface Transporter {
  + bind(URL, ChannelHandler): RemotingServer
  + connect(URL, ChannelHandler): Client
}
class NettyTransporter implements Transporter

interface RemotingServer
abstract class AbstractServer implements RemotingServer {
  # url: URL
  # handler: ChannelHandler
  + send(Object)
  # doOpen()
  # doClose()
}
class NettyServer extends AbstractServer {
  - bootstrap: ServerBootstrap
  - bossGroup: EventLoopGroup
  - workerGroup: EventLoopGroup
  # initServerBootstrap(NettyServerHandler)
}

interface Client
abstract class AbstractClient implements Client {
  # connectLock: ReentrantLock
  + reconnect()
  + send(Object)
}
class NettyClient extends AbstractClient

NettyTransporter ..> NettyServer
NettyTransporter ..> NettyClient
@enduml
```

---

## 6. Codec2

`Codec2` converts between a `ChannelBuffer` and a message object. It is a separate extension from the protocol so that the framing can be reused: the `dubbo` protocol's codec also serves the telnet path through inheritance.

```java
@SPI(scope = ExtensionScope.FRAMEWORK)
public interface Codec2 {
    @Adaptive({CODEC_KEY}) void encode(Channel channel, ChannelBuffer buffer, Object message) throws IOException;
    @Adaptive({CODEC_KEY}) Object decode(Channel channel, ChannelBuffer buffer) throws IOException;
    enum DecodeResult { NEED_MORE_INPUT, SKIP_SOME_INPUT }
}
```

The adaptive key is `codec`, but the transport does not require it: `AbstractEndpoint.getChannelCodec` falls back to the protocol name when the parameter is absent, which is how `dubbo://` resolves `DubboCountCodec` with no configuration. `decode` returning `NEED_MORE_INPUT` is the contract that lets a partial frame stay in the buffer instead of being parsed twice.

```plantuml
@startuml
top to bottom direction

interface Codec2 {
  + encode(Channel, ChannelBuffer, Object)
  + decode(Channel, ChannelBuffer): Object
}
abstract class AbstractCodec implements Codec2
class TransportCodec extends AbstractCodec
class TelnetCodec extends TransportCodec
class ExchangeCodec extends TelnetCodec {
  # HEADER_LENGTH: int = 16
  # MAGIC: short = 0xdabb
  + encode(Channel, ChannelBuffer, Object)
  + decode(Channel, ChannelBuffer): Object
}
class DubboCodec extends ExchangeCodec {
  # encodeRequestData(...)
  # decodeBody(...)
}
class DubboCountCodec implements Codec2 {
  - codec: DubboCodec
  + decode(Channel, ChannelBuffer): Object
}

DubboCountCodec *-- DubboCodec
@enduml
```

---

## 7. Serialization

`Serialization` is the body format, and it is the one extension chosen per request rather than per connection. Its two methods return stream wrappers rather than byte arrays, so a large argument can be written without materialising it.

```java
@SPI(scope = ExtensionScope.FRAMEWORK)
public interface Serialization {
    byte getContentTypeId();
    String getContentType();
    @Adaptive ObjectOutput serialize(URL url, OutputStream output) throws IOException;
    @Adaptive ObjectInput deserialize(URL url, InputStream input) throws IOException;
}
```

`getContentTypeId` is constrained to five bits because the `dubbo` header stores it there. The implementations registered in this tree are `hessian2` and `fastjson2`; others exist in separate modules, and `DefaultSerializationExceptionWrapper` wraps whichever is selected to normalise exception handling. Selection order is `prefer.serialization`, then `serialization`, then the framework default.

```plantuml
@startuml
top to bottom direction

interface Serialization {
  + getContentTypeId(): byte
  + getContentType(): String
  + serialize(URL, OutputStream): ObjectOutput
  + deserialize(URL, InputStream): ObjectInput
}
class Hessian2Serialization implements Serialization
class FastJson2Serialization implements Serialization
class DefaultSerializationExceptionWrapper implements Serialization
class DefaultSerializationSelector {
  - DEFAULT_REMOTING_SERIALIZATION: String
  + getDefaultRemotingSerialization(): String
}

DefaultSerializationExceptionWrapper o-- Serialization
DefaultSerializationSelector ..> Serialization
@enduml
```

---

## 8. ThreadPool

`ThreadPool` decides how a decoded request reaches business code. Its single method returns a `java.util.concurrent.Executor` configured from the URL.

```java
@SPI(value = "fixed", scope = ExtensionScope.FRAMEWORK)
public interface ThreadPool {
    @Adaptive({THREADPOOL_KEY}) Executor getExecutor(URL url);
}
```

Four implementations differ only in the queue and the sizing: `fixed` uses a fixed worker count with a `SynchronousQueue` by default, `cached` allows growth and idle reclamation, `limited` grows to a maximum and then queues, and `eager` hands work to a new thread before queuing. All four share `AbortPolicyWithReport` as the rejection handler, which is what produces the `SERVER_THREADPOOL_EXHAUSTED_ERROR` response instead of a silent drop. The pool is owned by `DefaultExecutorRepository`, not by the protocol, so one executor serves every service on a port.

```plantuml
@startuml
top to bottom direction

interface ThreadPool {
  + getExecutor(URL): Executor
}
class FixedThreadPool implements ThreadPool
class CachedThreadPool implements ThreadPool
class LimitedThreadPool implements ThreadPool
class EagerThreadPool implements ThreadPool
class AbortPolicyWithReport

class DefaultExecutorRepository {
  - data: ConcurrentMap<String, ExecutorService>
  + createExecutorIfAbsent(URL): ExecutorService
  + getExecutor(URL): ExecutorService
}

FixedThreadPool ..> AbortPolicyWithReport
DefaultExecutorRepository ..> ThreadPool
@enduml
```

---

## 9. LoadBalance

`LoadBalance` picks one invoker from the candidates routing left behind.

```java
@SPI(RandomLoadBalance.NAME)
public interface LoadBalance {
    @Adaptive("loadbalance") <T> Invoker<T> select(List<Invoker<T>> invokers, URL url, Invocation invocation);
}
```

Six implementations: `random`, `roundrobin`, `leastactive`, `shortestresponse`, `consistenthash`, and `adaptive`. All six extend `AbstractLoadBalance`, which supplies the weight calculation including the warm-up ramp. The method-level key means a single service can use different strategies per method, and the lookup happens per call rather than at refer time.

```plantuml
@startuml
top to bottom direction

interface LoadBalance {
  + select(List, URL, Invocation): Invoker
}
abstract class AbstractLoadBalance implements LoadBalance {
  + select(List, URL, Invocation): Invoker
  # doSelect(List, URL, Invocation): Invoker
  # getWeight(Invoker, Invocation): int
}
class RandomLoadBalance extends AbstractLoadBalance
class RoundRobinLoadBalance extends AbstractLoadBalance
class LeastActiveLoadBalance extends AbstractLoadBalance
class ShortestResponseLoadBalance extends AbstractLoadBalance
class ConsistentHashLoadBalance extends AbstractLoadBalance
class AdaptiveLoadBalance extends AbstractLoadBalance
@enduml
```

---

## 10. StateRouterFactory

Routing narrows the candidate list before load balancing sees it, and in this version the live interface is `StateRouterFactory` rather than the older `RouterFactory`, which is kept only for compatibility.

```java
@SPI
public interface StateRouterFactory {
    <T> StateRouter<T> getRouter(Class<T> interfaceClass, URL url);
}
```

Factories registered in this tree are `condition`, `tag`, `script-app`, `app`, `service`, `provider-app`, `standard-mesh-rule`, and `mock`. A router factory is not named by a call-site parameter: `RouterChain.buildSingleChain` collects them with `getActivateExtension(url, ROUTER_KEY)`, so which routers exist is decided by the URL conditions on each factory. `getRouter` is itself `@Adaptive` on the `protocol` key, which matters when a factory has several internal variants.

```plantuml
@startuml
top to bottom direction

interface StateRouterFactory {
  + getRouter(Class, URL): StateRouter
}
abstract class CacheableStateRouterFactory implements StateRouterFactory {
  - cache: ConcurrentMap<String, StateRouter>
  + getRouter(Class, URL): StateRouter
}
class ConditionStateRouterFactory extends CacheableStateRouterFactory
class TagStateRouterFactory extends CacheableStateRouterFactory
class ScriptStateRouterFactory extends CacheableStateRouterFactory

interface StateRouter {
  + route(BitList, URL, Invocation): BitList
}
abstract class AbstractStateRouter implements StateRouter {
  # url: URL
  # enabled: boolean
  + route(BitList, URL, Invocation): BitList
}
class ConditionStateRouter extends AbstractStateRouter

class RouterChain {
  - stateRouters: List<StateRouter>
  + route(URL, BitList, Invocation): List
  + buildSingleChain(Class, URL): SingleRouterChain
}

ConditionStateRouterFactory ..> ConditionStateRouter
RouterChain o-- StateRouter
RouterChain ..> StateRouterFactory
@enduml
```

---

## 11. Filter

`Filter` is the extension with the most implementations, and the only one applied twice per call — once on the consumer side and once on the provider side.

```java
@SPI(scope = ExtensionScope.MODULE)
public interface Filter extends BaseFilter {}
```

A filter is a pair of callbacks, not a single method: `invoke` runs before the next node, and the `Listener` methods `onResponse` and `onError` run after it. Eighteen are registered in the core module, among them `echo`, `generic`, `token`, `accesslog`, `classloader`, `context`, `exception`, `timeout`, and `tps`. Selection is entirely by `@Activate`: the consumer chain takes group `consumer` filtered by the `reference.filter` parameter, the provider chain takes group `provider` filtered by `service.filter`, and order comes from the annotation's `order`. A filter therefore never appears at a call site by name.

```plantuml
@startuml
top to bottom direction

interface BaseFilter {
  + invoke(Invoker, Invocation): Result
}
interface Filter extends BaseFilter
interface Listener {
  + onResponse(Result, Invoker, Invocation)
  + onError(Throwable, Invoker, Invocation)
}

abstract class ListenableFilter implements Filter {
  - nextListener: Listener
  + invoke(Invoker, Invocation): Result
}
class ContextFilter implements Filter, Listener
class ExceptionFilter implements Filter, Listener
class TimeoutFilter implements Filter, Listener
class TokenFilter implements Filter
class AccessLogFilter implements Filter

class DefaultFilterChainBuilder {
  + buildInvokerChain(Invoker, String, String): Invoker
}

DefaultFilterChainBuilder ..> Filter
@enduml
```

---

## 12. The registry

The registry answers one question: which provider processes are running and where do they listen. It holds no interface definitions, only an address and a revision per instance.

`NacosServiceDiscovery` extends `AbstractServiceDiscovery`, which extends `AbstractRegistry`, which `FailbackRegistry` builds on. The layering is inherited from the interface-level registry that predates application-level discovery, and it is still where the useful mechanics live: `AbstractRegistry` maintains the registered/subscribed/notified maps and a local disk cache, `FailbackRegistry` retries failed operations, and `NacosServiceDiscovery` maps Dubbo concepts onto Nacos naming.

### 12.1 The address model

At application level a Nacos service name is the application name, and one instance represents one provider process:

```java
// NacosServiceDiscovery.doRegister
Instance instance = toInstance(serviceInstance);   // ip, port, metadata = revision, storage-type, endpoints
service.registerInstance(instance.getServiceName(), group, instance);
```

The instance metadata is deliberately small. `dubbo.metadata.revision` identifies the interface definitions the process currently exports, `dubbo.metadata.storage-type` says where a consumer should resolve that revision, and `dubbo.endpoints` lists the protocol/port pairs. Nothing describes a single interface. A provider deploying five interfaces produces one registration, and adding a sixth changes the revision rather than the address list.

The registry `group` defaults to `DEFAULT_GROUP` and is overridable by `nacos.group`. Names containing `$` — nested interfaces from generated stubs — are rewritten to `___` before reaching the Nacos client, because Nacos restricts service-name characters.

### 12.2 Subscription

```mermaid
flowchart TD
    A["doSubscribe(url, listener)"] --> B["resolve interface to application"]
    B --> C["ServiceNameMapping lookup"]
    C --> D["subscribe application name"]
    D --> E["Nacos EventListener per app"]
    E --> F["onEvent: RegistryNotifier coalesces"]
    F --> G["getInstances: filter enabled"]
    G --> H["build URLs from revision and endpoints"]
    H --> I["registry.notify -> Directory refresh"]
```

`ServiceDiscoveryRegistry.doSubscribe` first resolves the interface to a set of application names, then registers one `ServiceInstancesChangedListener` per application. `NacosServiceDiscovery.addServiceInstancesChangedListener` maps each application to a single Nacos `EventListener`, shared by every interface that application serves — so a consumer of three interfaces from one application holds one subscription, not three.

Two behaviours matter here. Instances with `enabled=false` are dropped before addresses are built. And an empty notification is not treated as a scale-to-zero: `ServiceDiscoveryRegistryDirectory` keeps the previous address list and logs it as empty protection, because an empty notification is far more often a transient Nacos fault than a real teardown.

The mapping from interface to application is not in Nacos naming. `ServiceNameMapping` maintains it (with `provided-by` on the consumer URL and a metadata-center mapping), and `ServiceDiscoveryRegistry.doSubscribe` consults the mapping before subscribing; with no mapping it stops and waits for the mapping listener, because a consumer cannot name an application it has never been told about. The Nacos client side of that model is covered in [Nacos service and configuration management](/post/java/spring-cloud/nacos/).

### 12.3 Coalescing, failure recovery, and local cache

`RegistryNotifier` bounds the cost of a flapping provider set. The first ten notifications are delivered immediately (`DEFAULT_DELAY_EXECUTE_TIMES = 10`); afterwards the notifier enforces the `delay-notification` window (default 5000 ms) and keeps only the most recent payload, comparing a timestamp so that a superseded task produces no notification. A burst of registrations at deployment time therefore yields one directory refresh instead of one per instance.

`FailbackRegistry` handles transport-level failures with a `HashedWheelTimer`. `register`, `unregister`, `subscribe`, and `unsubscribe` each catch exceptions, throw immediately when `check=true` (so a bad configuration fails fast at startup), and otherwise record a task that is retried every `retry.period` (default 5000 ms) until it succeeds. `SkipFailbackWrapperException` bypasses the retry when retrying cannot succeed.

`AbstractRegistry` persists every notified address set into a local properties file at `~/.dubbo/dubbo-registry-{application}-{registry-address}.cache`. The file is loaded into memory at construction. Its purpose is the failure path: when `doSubscribe` throws, `FailbackRegistry.subscribe` calls `getCacheUrls`, which prefers the in-memory `notified` map and falls back to the file, and if it finds entries it notifies the listener with them before logging the failure — so the consumer starts from the last known provider list rather than an empty directory. Writes are serialized through `lastCacheChanged` and written asynchronously unless `save.file=true`, and `file-cache=false` disables the mechanism entirely.

`APPLICATION_FIRST` is the consumer-side default for the migration rule. In a configuration that still publishes both levels — `register-mode=all`, the provider default for a plain `nacos://` URL — the application-level invoker is preferred and the interface-level one remains available as a fallback, which is why `RegistryProtocol.refer` returns a `MigrationInvoker` holding up to two cluster invokers and switching between them by rule:

| Step | Selection |
|------|-----------|
| `APPLICATION_FIRST` (default) | Application-level, falling back to interface-level when its address count is below the threshold; a `promotion` percentage below 100 sends only that fraction of calls to the application-level invoker |
| `FORCE_APPLICATION` | Always the application-level invoker, destroying the interface-level one |
| `FORCE_INTERFACE` | Always the interface-level invoker, the compatibility mode |

---

## 13. MetadataService

The metadata service answers the other question: what does that interface look like. It is an ordinary RPC service exported by every provider, so a consumer reaches it the same way it reaches a business service, without going through the registry again.

### 13.1 The service itself

`MetadataService` is a small fixed interface. It exposes `getMetadataInfo(revision)` and `getMetadataInfos()`, plus `getServiceDefinition(serviceKey)` for a single interface. Because it is an ordinary service, it is exported through the same `ServiceConfig` machinery as business services: `ConfigurableMetadataServiceExporter` builds a `ServiceConfig` for it with its own protocol and port (`metadata-service-protocol`, `metadata-service-port`) and exports it on startup. A consumer refers it through `MetadataUtils.referMetadataService`, which builds a URL from the coordinates in the instance metadata and calls it like any other remote service.

The definition returned is a `MetadataInfo`: the set of services the provider exports, each with its interface name, version, group, protocol, and method signatures with parameter type descriptors.

### 13.2 Resolving the revision

`dubbo.metadata.revision` is the link back to the interface definitions. It is a digest computed by `MetadataInfo.calRevision` over the application name and the description of every exported service, so it changes whenever the set or shape of those services changes. A consumer reads the revision from the instance and resolves it via the provider's `MetadataService`. `AbstractServiceDiscovery.getRemoteMetadata` performs that resolution behind a revision-keyed cache, retrying three times with a one-second pause before giving up with an empty `MetadataInfo`. The cache is what keeps the per-revision fetch off the steady-state path.


---

## References

- [Apache Dubbo source repository](https://github.com/apache/dubbo)
- [Apache Dubbo documentation](https://dubbo.apache.org/)
- [Nacos naming service](https://nacos.io/docs/latest/guide/user/open-api/)
- [Hessian 2 serialization specification](http://hessian.caucho.com/doc/hessian-serialization.html)
