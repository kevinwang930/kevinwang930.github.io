---
title: "spring-Logging"
date: 2024-04-09T14:46:28+08:00
categories:
- java
- spring
tags:
- spring
- logging
keywords:
- logging
#thumbnailImage: //example.com/image.jpg
---
本文记录spring logging 的原理与配置
<!--more-->



Spring Boot uses `Commons Logging` for all internal logging but leaves the underlying log implementation open. 

in `spring-jcl` package 
`LogFactory` is a minimal incarnation of Apache Commons Logging api, it provides log lookup method.
`LogAdaper` detects the presence of log4j 2.x/slf4j
    1. log4j2 detection by `org.apache.logging.log4j.spi.ExtendedLogger`

```plantuml
interface Log {
    void info(Object message)
    void info(Object message, Throwable t)
}
abstract class LogFactory {
    {static} Log getLog()
}

class LogAdapter {
    boolean log4jSpiPresent
}

class Log4jAdapter {
    Log createLog(String name)
}
class Log4jLog implements Log {
    {static} LoggerContext loggerContext
    String name
    ExtendedLogger logger
}

LogFactory --> LogAdapter: detect
LogAdapter --> Log4jAdapter : createLog
Log4jAdapter -down-> Log4jLog : new

```


