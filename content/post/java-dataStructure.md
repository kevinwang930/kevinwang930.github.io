---
title: "Java基础数据类型"
date: 2024-02-24T19:16:25+08:00
categories:
- java
- 数据结构
tags:
- java
#thumbnailImage: //example.com/image.jpg
---

<!--more-->

# 1. CollectionsFramework concept

 A collection is an object that represents a group of objects (such as the classic Vector class). A collections framework is a unified architecture for representing and manipulating collections, enabling collections to be manipulated independently of implementation details.

 ## 1.1 Collection interfaces

 1. java.util.collection
    ```
    java.util.Set
    java.util.SortedSet
    java.util.NavigableSet
    java.util.Queue
    java.util.concurrent.BlockingQueue
    java.util.concurrent.TransferQueue
    java.util.Deque
    java.util.concurrent.BlockingDeque
    ```
2. java.util.map and offspring
    ```
    java.util.SortedMap
    java.util.NavigableMap
    java.util.concurrent.ConcurrentMap
    java.util.concurrent.ConcurrentNavigableMap
    ```
## 1.2 Collection implementations
| Interface | Hash Table                                              | Resizable                                                     | Balanced Tree    | Linked List                                                   | Hash Table + Linked List |
| :-------- | :------------------------------------------------------ | :------------------------------------------------------------ | :--------------- | :------------------------------------------------------------ | :----------------------- |
| `List`    |                                                         | <tt>ArrayList</tt> |                  | <tt>LinkedList</tt> |                          |
| `Deque`   |                                                         | <tt>ArrayDeque</tt> |                  | <tt>LinkedList</tt> |                          |
| `Map`     | <tt>HashMap</tt> |                                                               | <tt>TreeMap</tt> |                                                               | <tt>LinkedHashMap</tt>   |

## 1.3 concurrent collection interfaces

```
BlockingQueue
TransferQueue
BlockingDeque
ConcurrentMap
ConcurrentNavigableMap
```

## 1.4 concurrent collection implementations
```
LinkedBlockingQueue
ArrayBlockingQueue
PriorityBlockingQueue
DelayQueue
SynchronousQueue
LinkedBlockingDeque
LinkedTransferQueue
CopyOnWriteArrayList
CopyOnWriteArraySet
ConcurrentSkipListSet
ConcurrentHashMap
ConcurrentSkipListMap
```


# 2. Implementations

