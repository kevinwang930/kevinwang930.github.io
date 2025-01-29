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

本文介绍 Mybatis 以及 spring-mybatis 的架构与实现
<!--more-->

# mybatis

* `SqlSession`  primary interface for working with Mybatis. Through this interface to execute commands,get mappers and manage transactions.
* `SqlSessionFactory` create a `SqlSession` out of connection or dataSource.

```plantuml

interface SqlSession  {
+ void select(String,Object,ResultHandler)
+ int insert(String)
+ int update(String)
+ int delete(String)
+ void commit()
+ void rollback()
+ void close()
+ void clearCache()
+ Configuration getConfiguration()
+ Connection getConnection()
}

interface SqlSessionFactory  {
    + openSession(): SqlSession
    + getConfiguration(): Configuration
    }

    SqlSessionFactory -> SqlSession: create
class DefaultSqlSession implements SqlSession {
    Configuration configuration
    Executor executor
    boolean autoCommit
    boolean dirty
    List<Cursor<?>> cursorList
}


class DefaultSqlSessionFactory implements SqlSessionFactory {
  + DefaultSqlSessionFactory(Configuration): 
  - configuration: Configuration
}



class Configuration {
    Environment environment
    Map<String, MappedStatement> mappedStatements
    ProxyFactory proxyFactory
    InterceptorChain interceptorChain
}

class Environment {
  - transactionFactory: TransactionFactory
  - dataSource: DataSource
}


class InterceptorChain {
    List<Interceptor> interceptors
}
interface Interceptor {
    Object intercept(Invocation invocation)
}
DefaultSqlSession o-- Configuration
DefaultSqlSessionFactory o-- Configuration
Configuration *-- InterceptorChain
Configuration *-- Environment
InterceptorChain o-- Interceptor



```

# mybatis-spring

* `SqlSessionTemplate` Thread-safe,Spring managed `SqlSession` that works with Spring transaction management to ensure that the actual SqlSession used is the one associated with the current Spring transaction.
* `SqlSessionInterceptor` used internally by `SqlSessionTemplate` to intercept `DefaultSqlSession`, to control mybatis session life cycle.

```plantuml
package mybatis {
    interface SqlSession  {
        
    }

    class DefaultSqlSession implements SqlSession {
}

 

    interface SqlSessionFactory {}
    

    SqlSessionFactory -> SqlSession: create

}


package mybatis-spring {
    


    class SqlSessionTemplate {
        - exceptionTranslator: PersistenceExceptionTranslator
        - executorType: ExecutorType
        - sqlSessionFactory: SqlSessionFactory
        - sqlSessionProxy: SqlSession
    }

    class SqlSessionInterceptor implements InvocationHandler


}

SqlSession <|-right. SqlSessionTemplate
SqlSessionTemplate *-- SqlSessionInterceptor
SqlSessionInterceptor -left-> DefaultSqlSession: intercept

```

# pageHelper
```plantuml
interface SqlSession  {
+ void select(String,Object,ResultHandler)
+ int insert(String)
+ int update(String)
+ int delete(String)
+ void commit()
+ void rollback()
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