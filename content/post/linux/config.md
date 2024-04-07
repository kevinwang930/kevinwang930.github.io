---
title: "Bash Config"
date: 2024-03-24T21:52:14+08:00
categories:
- linux
tags:
- linux
- shell
keywords:
- linux
- shell 
#thumbnailImage: //example.com/image.jpg
---
本文记录bash启动时加载配置文件的方式
<!--more-->


# bash initilization

for login shell profile and rc config will be loaded, non-login shell will only load rc file.

## system
1. login shell will read `/etc/profile`
2. `/etc/bashrc` specific for bash

## user
1. ~/.bash_profile
2. ~/.bashrc

