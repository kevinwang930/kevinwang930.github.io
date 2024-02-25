---
title: "数据结构-树"
date: 2024-02-25T23:56:03+08:00
categories:
- 数据结构
tags:
- 数据结构
- 树

#thumbnailImage: //example.com/image.jpg
---



# 1.  Tree

## 1.1 Binary tree 
each node has at most 2 child nodes called left node and right node.

### 1.1.1 Complete Binary Tree
definitions:
   1. binary tree
   2. every level is completely filled except the last level
   3. all nodes in the last level are as far left as possible
   
Complete Binary tree can be stored in array 
1. root node is arr[0]
2. for the ith node
   1. parent node arr[(i-1)/2]
   2. left child node arr[(2*i)+1]
   3. right child node arr[(2*i)+2]



```plantuml
title complete binary tree
usecase A
usecase B
usecase C
usecase D
usecase E
usecase F

A --> B
A --> C
B --> D
B --> E
C --> F

```

# 2. Tree based data Structures

<!--more-->
## 2.1 Balanced Binary Heap
Based on completed binary tree, usually backed by array, used in PriorityBlockingQueue
# 2. Red Black Tree

