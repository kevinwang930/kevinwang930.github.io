---
title: "Mysql internals"
date: 2024-09-13T18:07:46+08:00
categories:
- database
- mysql
tags:
- mysql
keywords:
- mysql
#thumbnailImage: //example.com/image.jpg
---
this article introduce Mysql internals
<!--more-->
# Architecture
![architecture](images/arch.png)

source code dir:
* libmysql generate `libmysqlclient.so`
* 


# Connector

Mysql provides different APIs for different languages. 
* C API provides low-level access to the MySql client/Server protocol through `libmysqlclient` client
* X DevApi for document store
* JDBC Api for Java relational db connection
* ODBC Api


# Server





## Mysqld

Configs
* `--defaults-file=#` read defaults options from the given file
* `--datadir=#` path to the database root directory 
* `--init-file=name` Read SQL commands from this file at startup
* `--open_files_limit=#`   number of file descriptors available to `mysqld`
* `--max-connections=#` max number of simultaneous client connections
* `--thread-cache-size=#` number of threads the server should cache for reuse

# admin

```
show [full] processlist                      display the current running threads
SELECT * FROM performance_schema.threads    
show status like '%thread%'
```


# Reference

[参考链接](https://github.com/Jeanhwea/mysql-source-course/blob/master/slides/p04-mysql-startup.pdf)