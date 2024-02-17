---
title: "Spring boot 启动流程"
date: 2024-01-09T23:29:20+08:00
tags: ["spring"]
draft: false
mermaid: true
---


# 1. 概述

```plantuml
class SpringApplication {
    WebApplicationType webApplicationType
    List<ApplicationContextInitializer<?>> initializers
    List<ApplicationListener<?>> listeners
    ApplicationContextFactory applicationContextFactory
    ConfigurableApplicationContext run(String... args)
    void prepareContext()
}

interface ConfigurableApplicationContext {
    void refresh()
}

SpringApplication --> ConfigurableApplicationContext:create

```

```mermaid
flowchart 
a --> b 
```