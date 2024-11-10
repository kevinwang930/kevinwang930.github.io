---
title: "Mysql Metadata"
date: 2024-10-13T18:50:37+08:00
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
- metadata
#thumbnailImage: //example.com/image.jpg
---
This article introduces Mysql Metadata
<!--more-->

Mysql `Metadata` is anything that describes the database as opposed to being the contents of the database. 
`Metadata` is comprised of 2 parts:
* Data Dictionary
* System tables


# 1. Data Dictionary

![dd](images/dd.png)
Mysql Server incorporates a transactional data dictionary that stores information about database objects. 
The data dictionary schema stores dictionary data in transactional(InnoDB) tables. 
Data dictionary tables are located in the `mysql` database.
Data dictionary tables are created in a single `InnoDB` tablespace named `mysql.ibd`, which resides in the MySql data directory.

Basic Data Dictionary Tables
* `catalogs` catalog information
* `schemata` information about schemata
* `tablespaces` active tablespaces
* `tables` tables in databases
* `columns` columns in tables
* `indexes` information about table indexes

`information_schema` is now implemented as views over dictionary tables, requires no extra disc accesses, no creation of temporary tables.



```plantuml
title: database object representation 
class Table_ref  {
    char *db
    char *table_name
    LEX_CSTRING target_tablespace_name
    table_map m_map
    table_map sj_inner_tables
    Table_ref *natural_join
    List<Natural_join_column> *join_columns
    TABLE *table

    ST_SCHEMA_TABLE *schema_table
    Query_block *schema_query_block

    Query_block *query_block


    MDL_request mdl_request
}

class Weak_object <<virtual>>  {

}

class Entity_object<<virtual>> extends Weak_object {
    Object_id id()
    void set_name(name)
}

class Entity_object_impl implements Entity_object {
    Object_id m_id
    String_type m_name
}

class Abstract_table<<virtual>> extends Entity_object 

class Table<<virtual>> extends Abstract_table

class Abstract_table_impl extends Entity_object_impl,Abstract_table {
    Column_collection m_columns
    Object_id m_schema_id
}

class Table_impl extends Abstract_table_impl,Table {
    String_type m_engine
    String_type m_comment
    enum_row_format m_row_format
    enum_partition_type m_partition_type

    Index_collection m_indexes
    Partition_collection m_partitions

    Object_id m_collation_id
    Object_id m_tablespace_id
}

Table_ref --> Table

```

## 1.1 DD Cache and persistance
`Storage_adapter` handling of access to persistent storage.

```plantuml

class Storage_adapter {
    Object_registry m_core_registry
    mysql_mutex_t m_lock

    void core_get(K &key, T **object)
    void core_store(THD *thd, T *object)
    bool core_sync(THD *thd, K &key, T *object)

    bool get(THD *thd, K &key, isolation,bypass_registry, T *object)
    bool store(THD *thd, T *object)
    bool drop(THD *thd, T *object)


}

```