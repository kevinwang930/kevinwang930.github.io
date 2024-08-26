---
title: "spring aop 架构与实现"
date: 2024-04-01T12:44:12+08:00
categories:
- java
- spring
tags:
- spring
- aop
keywords:
- aop
#thumbnailImage: //example.com/image.jpg
---
本文记录 spring aop 架构与实现
<!--more-->

# Concept
`Aspect-oriented Programming (AOP)` is a programming paradigm that aims to increase modularity by allowing the separation of cross-cutting concerns. It does so by adding behavior to existing code(advice) without modifying the code.

`Aspect` A modularization of a concern that cuts across multiple classes. Example : Transaction management

`Joinpoint` represents a generic runtime joinpoint. A runtime joinPoint is an event that occurs on a static joinpoint.

`Advice` Action taken by an aspect at a particular joinpoint

Advice types:
    1. before
    2. after
    3. finally
    4. around

`Advisor` interface holding AOP `advice` and a filter determing the applicability of the advice(such as a `pointcut`)

`Pointcut`  A predicate that matches joinpoint. Advice is associated with a pointcut expression that runs at any `Joinpoint` matched by the `pointcut`.

`Proxy` An object created by the AOP framework in order to implement the aspect contracts



```plantuml
top to bottom direction
title: transaction advisor 
interface Advisor {
    Advice getAdvice()
}
interface PointcutAdvisor extends Advisor {
    Pointcut getPointcut()
}
abstract class AbstractPointcutAdvisor implements PointcutAdvisor {
    String adviceBeanName
    BeanFactory beanFactory
    transient volatile Advice advice

}
abstract class AbstractBeanFactoryPointcutAdvisor extends AbstractPointcutAdvisor {

}
class BeanFactoryTransactionAttributeSourceAdvisor extends AbstractBeanFactoryPointcutAdvisor {
    TransactionAttributeSourcePointcut pointcut = new TransactionAttributeSourcePointcut()
}
```

# Mechanism

AOP uses either JDK dynamic proxies or CGLIB to create proxy
dynamicProxy only works when proxied object  implements at least one  interface

ProxyCreator implements PostProcessor interface, when `postProcessAfterInitialization` get invoked, a prxy object is created with the target advisor  incapsulated, the proxy object will replace the origial bean.


```plantuml
interface ImportBeanDefinitionRegistrar {
+ void registerBeanDefinitions()
}

class AspectJAutoProxyRegistrar implements ImportBeanDefinitionRegistrar {
}


class AnnotationAwareAspectJAutoProxyCreator extends AspectJAwareAdvisorAutoProxyCreator{
- List<Pattern> includePatterns
- AspectJAdvisorFactory aspectJAdvisorFactory
- BeanFactoryAspectJAdvisorsBuilder aspectJAdvisorsBuilder
+ void setIncludePatterns(List<String>)
+ void setAspectJAdvisorFactory(AspectJAdvisorFactory)

}

class AspectJAwareAdvisorAutoProxyCreator extends AbstractAdvisorAutoProxyCreator {
}


abstract class AbstractAdvisorAutoProxyCreator extends AbstractAutoProxyCreator {
- BeanFactoryAdvisorRetrievalHelper advisorRetrievalHelper
+ void setBeanFactory(BeanFactory)
# void initBeanFactory(ConfigurableListableBeanFactory)
# Object[] getAdvicesAndAdvisorsForBean(Class<?>,String,TargetSource)
# List<Advisor> findEligibleAdvisors(Class<?>,String)
# List<Advisor> findCandidateAdvisors()
# List<Advisor> findAdvisorsThatCanApply(List<Advisor>,Class<?>,String)
# boolean isEligibleAdvisorBean(String)
# List<Advisor> sortAdvisors(List<Advisor>)

}


abstract class AbstractAutoProxyCreator extends ProxyProcessorSupport implements SmartInstantiationAwareBeanPostProcessor, BeanFactoryAware {

- AdvisorAdapterRegistry advisorAdapterRegistry
- boolean freezeProxy
- String[] interceptorNames
- boolean applyCommonInterceptorsFirst
- TargetSourceCreator[] customTargetSourceCreators
- BeanFactory beanFactory
- Set<String> targetSourcedBeans
- Map<Object,Object> earlyBeanReferences
- Map<Object,Class<?>> proxyTypes
- Map<Object,Boolean> advisedBeans

+ void setAdvisorAdapterRegistry(AdvisorAdapterRegistry)
+ void setCustomTargetSourceCreators(TargetSourceCreator)
+ void setInterceptorNames(String)
+ void setApplyCommonInterceptorsFirst(boolean)
+ void setBeanFactory(BeanFactory)
+ Class<?> predictBeanType(Class<?>,String)
+ Class<?> determineBeanType(Class<?>,String)
+ Constructor<?>[] determineCandidateConstructors(Class<?>,String)
+ Object getEarlyBeanReference(Object,String)
+ Object postProcessBeforeInstantiation(Class<?>,String)
+ PropertyValues postProcessProperties(PropertyValues,Object,String)
+ Object postProcessAfterInitialization(Object,String)

}

class ProxyProcessorSupport {
- int order
- ClassLoader proxyClassLoader
- boolean classLoaderConfigured
+ void setOrder(int)
+ int getOrder()
+ void setProxyClassLoader(ClassLoader)
# ClassLoader getProxyClassLoader()
+ void setBeanClassLoader(ClassLoader)
# void evaluateProxyInterfaces(Class<?>,ProxyFactory)
# boolean isConfigurationCallbackInterface(Class<?>)
# boolean isInternalLanguageInterface(Class<?>)
}

AspectJAutoProxyRegistrar  -right-> AnnotationAwareAspectJAutoProxyCreator:register

```


# Target Source


`TargetClassAware` Minimal interface for exposing the target class behind a proxy

`TargetSource` is used to obtain the current target of the AOP invocation, which will be invoked via reflection if no around advice chooses to end the interceptor chain itself

```plantuml
interface TargetClassAware {
    Class<?> getTargetClass()
}

interface TargetSource extends TargetClassAware {
    Object getTarget()
    void releaseTarget(Object target)
}

abstract class AbstractBeanFactoryBasedTargetSource implements TargetSource, BeanFactoryAware {
    String targetBeanName
    Class<?> targetClass
    BeanFactory beanFactory
    void setBeanFactory(BeanFactory beanFactory)
}

class SimpleBeanTargetSource extends AbstractBeanFactoryBasedTargetSource
```