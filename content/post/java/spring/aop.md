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
Aspect-oriented Programming provides another way of thinking about program structure.

Aspect A modularization of a concern that cuts across multiple classes. Example : Transaction management

Joint point A point during the execution of a program.

Advice Action taken by an aspect at a particular join point

Pointcut  A predicate that matches join points. Advice is associated with a pointcut expression that runs at any join point matched by the pointcut.

AOP proxy An object created by the AOP framework in order to implement the aspect contracts

Advice types:
    1. before
    2. after
    3. finally
    4. around

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
# void extendAdvisors(List<Advisor>)
# boolean advisorsPreFiltered()
}


abstract class AbstractAutoProxyCreator extends ProxyProcessorSupport implements SmartInstantiationAwareBeanPostProcessor, BeanFactoryAware {
# {static} Object[] DO_NOT_PROXY
# {static} Object[] PROXY_WITHOUT_ADDITIONAL_INTERCEPTORS
# Log logger
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
+ void setFrozen(boolean)
+ boolean isFrozen()
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