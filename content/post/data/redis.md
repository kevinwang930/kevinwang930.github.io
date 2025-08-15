---
title: "Redis"
date: 2025-01-26T10:38:29+07:00
draft: true
categories:
- data
- redis
tags:
- data
- redis
keywords:
- redis
- cache
#thumbnailImage: //example.com/image.jpg
---
This article introduces Redis config and usages
<!--more-->

# Key 
Redis Keys are binary safe
The max key size is 512MB
Conventionally using `:` to separate different level of schemas
the following keys are legal
```
foo
jpg image content
empty string
comment:4321:reply
```



