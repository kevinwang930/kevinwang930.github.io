---
title: "Function Pointer"
date: 2024-03-23T22:27:40+08:00
categories:
- cpp
tags:
- cpp
- 函数指针
keywords:
- 函数指针
#thumbnailImage: //example.com/image.jpg
---
本文记录cpp函数指针及其调用方式
<!--more-->

# syntax

* pointer syntax
    ```
    datatype *var_name; 
    ```
* function pointer syntax
    ```
    // Declaring
    return_type (*FuncPtr) (parameter type, ....); 

    // Referencing
    FuncPtr= function_name;

    // Dereferencing
    data_type x=*FuncPtr; 
    ```