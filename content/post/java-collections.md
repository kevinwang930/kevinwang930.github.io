---
title: "java collections internals"
date: 2024-02-24T19:16:25+08:00
categories:
- java
- 数据结构
tags:
- java
- 数据结构
#thumbnailImage: //example.com/image.jpg
---

<!--more-->

# 1. Collections

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



1. ArrayList
    ```plantuml
    class ArrayList {
        transient Object[] elementData
        private int size
    }
    ```
2. LinkedList
    ```plantuml
    class LinkedList {
        transient int size = 0;
        transient Node<E> first;
        transient Node<E> last;
    }
    class Node<E> {
        E item;
        Node<E> next;
        Node<E> prev;
    }
    LinkedList *-- Node
    ```
3. ArrayDeque
   ```plantuml
   class ArrayDeque {
    transient Object[] elements
    transient int head
    transient int tail
   }
   ```
4. HashMap
    ```plantuml
    class HashMap {
        transient Node<K,V>[] table
        transient Set<Map.Entry<K,V>> entrySet
        transient int size
        transient int modCount
        int threshold
        final float loadFactor
    } 
    class Node<K,V> {
        final int hash;
        final K key;
        V value;
        Node<K,V> next;
    } 
    class TreeNode<K,V> {
        TreeNode<K,V> parent;  // red-black tree links
        TreeNode<K,V> left;
        TreeNode<K,V> right;
        TreeNode<K,V> prev;    // needed to unlink next upon deletion
        boolean red;
    }
    HashMap *-- Node
    HashMap *-- TreeNode
    ```

5. TreeMap
   ```plantuml
    class TreeMap {
        private final Comparator<? super K> comparator
        private transient Entry<K,V> root
        private transient int size = 0
        private transient int modCount = 0
    }
    class Entry<K,V>  {
        K key;
        V value;
        Entry<K,V> left;
        Entry<K,V> right;
        Entry<K,V> parent;
        boolean color = BLACK;
    }
    TreeMap *-- Entry
   ```
6. LinkedHashMap
   ```plantuml
    class HashMap {
        transient Node<K,V>[] table
        transient Set<Map.Entry<K,V>> entrySet
        transient int size
        transient int modCount
        int threshold
        final float loadFactor
    } 
    class Node<K,V> {
        final int hash;
        final K key;
        V value;
        Node<K,V> next;
    } 
    class TreeNode<K,V> {
        TreeNode<K,V> parent;  // red-black tree links
        TreeNode<K,V> left;
        TreeNode<K,V> right;
        TreeNode<K,V> prev;    // needed to unlink next upon deletion
        boolean red;
    }

   class LinkedHashMap<K,V> extends HashMap {
    transient LinkedHashMap.Entry<K,V> head
    transient LinkedHashMap.Entry<K,V> tail
    final boolean accessOrder

   }
    class Entry<K,V> extends Node {
        Entry<K,V> before
        Entry<K,V> after
    }
    HashMap *-right- Node
    HashMap *-down-- TreeNode
    LinkedHashMap *-right- Entry
    Entry <|--TreeNode
   ```
7. TreeSet
    ```plantuml
    title: tree set backed by treeMap
    class TreeSet {
        private transient NavigableMap<E,Object> m
        private static final Object PRESENT = new Object()
    }
    ```


# 1. concurrent collection
## 1.1 concurrent collection interfaces

```
BlockingQueue
TransferQueue
BlockingDeque
ConcurrentMap
ConcurrentNavigableMap
```

## 1.2 concurrent collection implementations

### 1.2.1 BlockingQueue
使用reentrantLock + condition 
1. LinkedBlockingQueue
    ```plantuml
    class LinkedBlockingQueue {
        private final int capacity
    private final AtomicInteger count = new AtomicInteger();
    transient Node<E> head;
    private transient Node<E> last;
    private final ReentrantLock takeLock = new ReentrantLock();
    private final Condition notEmpty = takeLock.newCondition();
    private final ReentrantLock putLock = new ReentrantLock();
    private final Condition notFull = putLock.newCondition();
    }
    class Node<E> {
        E item;
        Node<E> next;
    }
    LinkedBlockingQueue *-- Node
    ```
2. ArrayBlockingQueue
   实现方式与LinkeBlockingQueue类似，区别采用数组存放元素
3. PriorityBlockingQueue
   元素存储在内部数组中，采用 balancedBinaryHeap 实现排序
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


# 2. Red black tree
