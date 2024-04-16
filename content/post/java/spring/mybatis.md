---
title: "Mybatis架构与实现"
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

MyBatis 作为一个流行的java数据层操作与映射框架，大大提升了java数据层开发的效率，本文介绍mybatis的框架，实现及常见应用场景。 引导思考真正高效的数据层开发是什么样的。 
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
}
DefaultSqlSession o-- Configuration

```
