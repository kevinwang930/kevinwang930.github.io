---
title: "OpenJDK build and debug"
date: 2025-03-12T01:22:42+07:00
categories:
- java
- jvm
tags:
- jvm
keywords:
- jvm
#thumbnailImage: //example.com/image.jpg
---
This article introduces how to build and debug OpenJDK source code
<!--more-->

# Build

## prepare

* install latest version of jdk as boot jdk

## configure jdk

bash configure --with-debug-level=slowdebug  

## run make

make images

## verify your newly built JDK:
./build/*/images/jdk/bin/java -version

## Run basic tests:
make test-tier1

reference: [https://openjdk.org/groups/build/doc/building.html](https://openjdk.org/groups/build/doc/building.html)


# debug

Openjdk has command to generate compilation database which can be used in ide.

1. generate compile database
    ```
    make compile-commands
    ```
2. open the generated `compile_commands.json` as a project in CLion

## Clion custom debug tool
In Clion custom debug tools add external tools
* make images
* make clean
