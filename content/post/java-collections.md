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

```plantuml
title:collection
interface Collection<E> {
    int size()
    boolean isEmpty()
    contains()
    Iterator<E> iterator()
    T[] toArray(T[] a)
    boolean add(E e)
    boolean remove(Object o)
    default boolean removeIf(Predicate<? super E> filter)
    void clear()
    default Spliterator<E> spliterator()
    default Stream<E> stream()
}
interface SequencedCollection<E> extends Collection {
    void addFirst(E e)
    void addLast(E e)
    E getFirst()
    E getLast()
    E removeFirst()
    E removeLast()

}
interface List<E> extends SequencedCollection {
    void add(int index, E element)
    E get(int index)
    E set(int index, E element)
    E remove(int index)
    int indexOf(Object o)
    int lastIndexOf(Object o)
    ListIterator<E> listIterator(int index)
    List<E> subList(int fromIndex, int toIndex)
    static <E> List<E> of(E e)
}
interface Set<E> extends Collection {
    static <E> Set<E> of(E... elements)
}
interface SequencedSet<E> extends SequencedCollection, Set {
    SequencedSet<E> reversed()
}
interface SortedSet<E> extends Set, SequencedSet {
    E first()
    E last()
    SortedSet<E> subSet(E fromElement, E toElement)
}
interface Queue<E> extends Collection {
    boolean offer(E e)
    E poll()
    E element()
    E peek()
}
interface Deque<E> extends Queue, SequencedCollection {
    void push(E e)
    E pop()
    E pollLast()
    E pollFirst()
    E peekFirst()
    E peekLast()
    boolean offerFirst()
    boolean offerLast()
}
```

```plantuml
title: map
interface Map<K, V> {
    int size()
    boolean isEmpty()
    boolean containsKey()
    boolean containsValue()
    v get(Object key)
    v put(k key, v value)
    V remove(Object key)
    void clear()
    void putAll(Map<? extends k, ? extends v> m)
    Set<K> keySet()
    Collection<V> values()
    Set<Map.Entry<K, V>> entrySet()
    default void forEach(BiConsumer<? super K, ? super V> action)
    default void replaceAll(BiFunction<? super K, ? super V, ? extends V> function)
    default V putIfAbsent(K key, V value)
    default boolean remove(Object key, Object value)
    default boolean replace(K key, V oldValue, V newValue)
    static <K, V> Map<K, V> of(K k1, V v1)
}
interface Entry<K, V>  {
    K getKey()
    V getValue()
    V setValue(V value)
    boolean equals(Object o)
    
}
Map o-- Entry
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

###  BlockingQueue
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
   实现方式与LinkedBlockingQueue类似，区别采用数组存放元素
3. PriorityBlockingQueue
   元素存储在内部数组中，采用 balancedBinaryHeap 实现排序
### other concurrent collections
DelayQueue
SynchronousQueue
LinkedBlockingDeque
LinkedTransferQueue
CopyOnWriteArrayList
CopyOnWriteArraySet
ConcurrentSkipListSet
ConcurrentHashMap
ConcurrentSkipListMap


