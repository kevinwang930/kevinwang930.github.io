---
title: "Mysql Source Code Compile and Debug"
date: 2024-10-17T23:49:24+08:00
categories:
- data
- db
- mysql
tags:
- data
- db
- mysql
keywords:
- mysql
- debug
#thumbnailImage: //example.com/image.jpg
---
This Article illustrates how to compile and debug Mysql from source code.
<!--more-->


## 1.1 Build from source


cmake build
```
cmake -B debug
cmake --build debug --target mysqld
```

## 1.2 Initialize 
```
mysqld  --defaults-file=./debug/my.cnf --initialize  // generate random root password

mysqld  --defaults-file=/code/git/mysql/debug/my.cnf 

mysql --socket=/code/git/mysql/debug/mysqlx.sock -u root -p


ALTER USER 'root'@'localhost' IDENTIFIED BY '123456'

UPDATE mysql.user SET Host='%' WHERE User='root' AND Host='localhost'    // set login ip
```

conf file content 

```
[mysqld]
port=3310
mysqlx_port=33061
socket=/code/git/mysql/debug/mysqlx.sock
default_storage_engine=InnoDB
datadir=/code/git/mysql/debug/data
## general_log
general_log=1
general_log_file=/code/git/mysql/debug/log/general.log

## error log
log-error=/code/git/mysql/debug/log/error.log
## slow query log
slow_query_log=1
slow_query_log_file=/code/git/mysql/debug/log/slow.log
```

## Debug config