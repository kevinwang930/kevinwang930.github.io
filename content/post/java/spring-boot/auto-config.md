---
title: "Spring Boot Auto Config"
date: 2024-10-07T17:50:38+08:00
draft: true
categories:
- java
- spring
tags:
- spring
keywords:
- spring
#thumbnailImage: //example.com/image.jpg
---
Spring Boot auto-configuration attempts to automatically configure  Spring application based on the jars in the classPath. 
<!--more-->

```plantuml
annotation EnableAutoConfiguration {
    @AutoConfigurationPackage
    @Import(AutoConfigurationImportSelector.class)


}
annotation AutoConfigurationPackage {
    @Import(AutoConfigurationPackages.Registrar.class)
}

EnableAutoConfiguration *-up- AutoConfigurationPackage

```