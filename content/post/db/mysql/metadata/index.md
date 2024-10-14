---
title: "Mysql Metadata"
date: 2024-10-13T18:50:37+08:00
categories:
- database
- mysql
tags:
- database
- mysql
- metadata
keywords:
- mysql
- metadata
#thumbnailImage: //example.com/image.jpg
---
This article introduces Mysql Metadata
<!--more-->

Mysql `Metadata` is anything that describes the database as opposed to being the contents of the database. 


# 1. Data Dictionary

![dd](images/dd.png)
Mysql Server incorporates a transactional data dictionary that stores information about database objects. 
The data dictionary schema stores dictionary data in transactional(InnoDB) tables. Data. 
Data dictionary tables are located in the `mysql` database together with non-data dictionary system tables.
Data dictionary tables are created in a single `InnoDB` tablespace named `mysql.ibd`, which resides in the MySql data directory.

Basic Data Dictionary Tables
* `catalogs` catalog information
* `schemata` information about schemata
* `tablespaces` active tablespaces
* `tables` tables in databases
* `columns` columns in tables
* `indexes` information about table indexes


Many Data Dictionary tables are exposed in `INFORMATION_SCHEMA` as table views.
