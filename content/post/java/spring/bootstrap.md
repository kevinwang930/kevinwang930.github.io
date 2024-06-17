---
title: "Property"
date: 2024-05-30T18:17:31+08:00
categories:
- java
- spring
tags:
- spring
- bootstrap
keywords:
- spring
#thumbnailImage: //example.com/image.jpg
---

本文记录spring启动过程
<!--more-->


# SpringFactoriesLoader

General purpose factory loading mechanism for internal use within the framework.
`SpringFactoriesLoader` loads and instantiates factories of a given type from "META-INF/spring.factories" files which may be present in multiple JAR files in the class path.


```plantuml

class SpringFactoriesLoader {
    ClassLoader classLoader
    Map<String, List<String>> factories
    loadFactoriesResource(classLoader, location)
    <T> T instantiateFactory(name,type,argumentResolver,failureHandler)
}

```

