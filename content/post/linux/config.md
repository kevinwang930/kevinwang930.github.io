---
title: "Linux Bash Config"
date: 2024-03-24T21:52:14+08:00
categories:
- linux
tags:
- linux
- config
keywords:
- linux
- shell 
#thumbnailImage: //example.com/image.jpg
---
This article introduces how bash config initialized.
<!--more-->


# bash initialization

for login shell profile and rc config will be loaded, non-login shell will only load rc file.

## system level
1. login shell will read `/etc/profile`
2. `/etc/bashrc` specific for bash

## user level
1. ~/.bash_profile
2. ~/.bashrc

