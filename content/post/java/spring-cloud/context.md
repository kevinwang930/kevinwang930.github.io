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


```plantuml
class GenericScope implements Scope, BeanFactoryPostProcessor,BeanDefinitionRegistryPostProcessor,DisposableBean 
class RefreshScope extends GenericScope implements ApplicationContextAware,ApplicationListener

class LockedScopedProxyFactoryBean<S extends GenericScope> extends ScopedProxyFactoryBean implements MethodInterceptor

GenericScope --> LockedScopedProxyFactoryBean: proxy
```