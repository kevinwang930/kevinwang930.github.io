---
title: "java Concurrency - Fork Join Framework"
date: 2024-04-06T13:02:58+08:00
categories:
- java
- concurrency
tags:
- concurrency
- forkJoin
keywords:
- forkJoin
#thumbnailImage: //example.com/image.jpg
---
本文记录java并发编程- fork join framework 的设计与实现
<!--more-->

Fork join Framework supports a style of parallel programming in which Problems are solved by (recursively) splitting them into subtasks that are solved in parallel, waiting for them to complete, and then composing results.

# Concept

1. fork starts a new parallel fork/join subtask. 
2. jon causes the current task not to proceed until the forked subtask has completed