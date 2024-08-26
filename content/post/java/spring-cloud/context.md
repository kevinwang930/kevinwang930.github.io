---
title: "Context"
date: 2024-08-22T18:11:59+08:00
categories:
- java
- spring-cloud
tags:
- spring-cloud-context
keywords:
- spring-cloud-context
---

This article introduces spring-cloud-context
<!--more-->

Spring cloud context contains utilities and special services for `ApplicationContext` of a Spring cloud application.
* bootstrap context
* encryption
* refresh scope
* environment endpoints



# Refresh Scope

`@RefreshScope` annotation to put a `@Bean` definition in `RefreshScope`  refresh scope.

`RefreshScope` A `Scope` implementation that allows for beans to be refreshed dynamically at runtime

`ScopedProxyFactoryBean` Convenient proxy factory bean for scoped objects. Proxies returned by this class implement the `ScopedObject` interface. This presently allows for removing the corresponding object from the scope, seamlessly creating a new instance in the scope on next access.

`RefreshEventListener` Calls `ContextRefresher.refresh` when a `RefreshEvent` is received.



```plantuml
class GenericScope implements Scope, BeanFactoryPostProcessor,BeanDefinitionRegistryPostProcessor,DisposableBean  {
    ConfigurableListableBeanFactory beanFactory
    BeanLifecycleWrapperCache cache
    void setBeanFactory(BeanFactory beanFactory)
}
class RefreshScope extends GenericScope implements ApplicationContextAware,ApplicationListener {
    ApplicationContext context
    BeanDefinitionRegistry registry
    void refreshAll()
}
class ScopedProxyFactoryBean extends ProxyConfig implements FactoryBean, BeanFactoryAware,AopInfrastructureBean {
    String targetBeanName
    Object proxy
}

class LockedScopedProxyFactoryBean<S extends GenericScope> extends ScopedProxyFactoryBean implements MethodInterceptor {
    S scope
    String targetBeanName
    
}

class BeanLifecycleWrapper {
    String name
    ObjectFactory<?> objectFactory
    Object bean
    Runnable callback
    Object getBean()
    void destroy()
}
abstract class ContextRefresher {
    RefreshScope scope
    Set<String> refresh()
}
class ConfigDataContextRefresher extends ContextRefresher

GenericScope -------> LockedScopedProxyFactoryBean: beanClass
ContextRefresher o------ RefreshScope : refresh
GenericScope *-- BeanLifecycleWrapper
```