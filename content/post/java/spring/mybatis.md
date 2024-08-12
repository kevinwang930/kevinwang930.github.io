---
title: "Mybatis internals"
date: 2024-04-15T18:45:41+08:00
categories:
- java
- spring
tags:
- spring
- mybatis
keywords:
- tech
#thumbnailImage: //example.com/image.jpg
---

本文介绍 Mybatis 以及拦截器内部实现 
<!--more-->

# Architecture

```plantuml

interface SqlSession  {
+ T selectOne(String)
+ List<E> selectList(String)
+ Map<K,V> selectMap(String,String)
+ Cursor<T> selectCursor(String)
+ void select(String,Object,ResultHandler)
+ int insert(String)
+ int update(String)
+ int delete(String)
+ void commit()
+ void rollback()
+ List<BatchResult> flushStatements()
+ void close()
+ void clearCache()
+ Configuration getConfiguration()
+ Connection getConnection()
}
class DefaultSqlSession implements SqlSession {
    Configuration configuration
    Executor executor
    boolean autoCommit
    boolean dirty
    List<Cursor<?>> cursorList
}

class Configuration {
    Map<String, MappedStatement> mappedStatements
    InterceptorChain interceptorChain
}

class InterceptorChain {
    List<Interceptor> interceptors
}
DefaultSqlSession o-- Configuration
Configuration *-- InterceptorChain

interface Interceptor {
    Object intercept(Invocation invocation)
}

package pageHelper {

    class PageInterceptor  {
        Dialect dialect
    }

interface Dialect  {
}

class AbstractDialect implements Dialect{
}
class AbstractRowBoundsDialect extends AbstractDialect {
}

class MySqlRowBoundsDialect extends AbstractRowBoundsDialect{
}

PageInterceptor *-- Dialect
}


InterceptorChain *-- Interceptor
Interceptor <|--  PageInterceptor 
```