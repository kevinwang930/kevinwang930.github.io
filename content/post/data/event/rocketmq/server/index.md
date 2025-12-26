---
title: "RocketMq Server Implementation"
date: 2025-12-21T03:03:44+07:00
categories:
- data
- event
- rocketmq
tags:
- data
- event
- rocketmq
keywords:
- rocketmq
#thumbnailImage: //example.com/image.jpg
---
This article introduces RocketMQ server Architecture and Implementation
<!--more-->


# Architecture

* NameServ a stateless application that stores the topic routing information
* Broker a stateful application that handles data computation and storage. The data it computes includes producer requests, consumer requests, management requests. The data it stores includes messages and indexes.
* ![rocketmq](images/arch.png)


# Implementation

