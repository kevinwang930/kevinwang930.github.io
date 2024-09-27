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
# 1. Architecture
![architecture](images/arch.png)

source code dir:
* `libmysql`    generate `libmysqlclient.so`
* `sql`         main codebase 
  * `dd`        Data dictionary
  * `server_component` server component


## 1.1. ACID


* Atomicity     transaction management
* Consistency   protect from Crashes
* Isolation     transaction Isolation level
* Durability    Mysql software features interacting with particular hardware configuration.


# 2. Server


## 2.1. Network

Mysql Server maintains a one thread per connection model. 

```plantuml

actor Client

participant "Event Loop" as EL
participant "Per Thread Connection Handler" as CH
participant "Protocol" as Protocol
participant "sql_parse.cc" as DC


== Establishing Connection ==
Client -> EL : Initiate Connection
activate EL
EL -> CH : add_connection(channel_info)
activate CH  
CH -> CH : handle_connection (THD)
deactivate EL

== Processing Commands ==
loop Handle Multiple Commands
    Client -> Protocol : Send SQL Command
    CH -> DC : do_command(thd)
    activate DC
    DC -> Protocol : get_command(&com_data, &command)
    activate Protocol
    Protocol --> DC : com_data & command
    deactivate Protocol
    DC -> DC : dispatch_command(thd, command)
    DC --> Protocol : Execution Result
    deactivate DC 
    Protocol -> Client : Send Command Result
end

== Terminating Connection ==
Client -> CH : Disconnect
CH -> Client : Close Connection


```

## 2.2. Parser
* `Query_expression` one query block or several query blocks combined with UNION
* `Query_term` tree structure. 
  Five node types:
  * `Query_block`
  * `Query_term_unary`
  * `Query_term_intersect`
  * `Query_term_except`
  * `Query_term_union`
* `Sql_cmd` representation of an SQL command, an interface between the parser and the runtime. The parser builds the appropriate Sql_cmd to represent a SQL statement in teh parsed tree. The `execute()` method in the derived classes of `Sql_cmd` contains the runtime implementation.

```plantuml

class THD {
  Thd_mem_cnt m_mem_cnt
  MDL_context mdl_context
  LEX *lex
  LEX_CSTRING m_query_string
  LEX_CSTRING m_catalog
  LEX_CSTRING m_db

  Prepared_statement_map stmt_map
  const char *thread_stack

  Protocol *m_protocol
  Query_plan query_plan
  char *m_trans_log_file
  NET net
}

class LEX << (S,#FF7700) >> {
  THD *thd
  Query_expression *unit
  Table_ref *insert_table
  enum_tx_isolation tx_isolation
  LEX_STRING create_view_query_block
  Sql_cmd *m_sql_cmd
  make_sql_cmd(Parse_tree_root *parse_tree)
}

class Query_expression {
  Query_expression *next
  Query_expression **prev
  Query_block *master
  Query_block *slave
  Query_term *m_query_term
  bool prepared
  bool executed
  Query_result *m_query_result
}

class Query_term {
  Query_term_set_op *m_parent

}

class Query_block extends Query_term

class Sql_cmd {
  Prepared_statement *m_owner

  bool execute(THD *thd)
} 

THD *-- LEX

LEX *-right- Query_expression
LEX --> Sql_cmd: make
Query_expression *-right- Query_block

```


```plantuml
title parse procedure

participant "sql_parse.cc" as SP

SP --> SP : dispatch_command()
activate SP
SP --> SP :dispatch_sql_command()
activate SP
SP --> SP: parse_sql
activate SP
SP --> THD : sql_parser()
activate THD
THD--> YACC :my_sql_parser_parse
THD --> LEX : make_sql_cmd(*parse_tree)
LEX --> Parse_Tree: make_cmd(thd) 
SP --> SP: mysql_execute_command
```


```plantuml


title Top level Sql Statements Structure

class Parse_tree_root {
  +virtual Sql_cmd *make_cmd(THD *thd) = 0
}

class PT_select_stmt {
  +enum_sql_command m_sql_command
  +PT_query_expression_body *m_qe
  +PT_into_destination *m_into
  +Sql_cmd *make_cmd(THD *thd)
}

class PT_insert
class PT_update
class PT_delete
class PT_explain
class PT_table_ddl_stmt_base
class PT_show_base


class PT_show_engine_base
class PT_show_engine_status

Parse_tree_root <|-- PT_select_stmt
Parse_tree_root <|-- PT_insert
Parse_tree_root <|-- PT_update
Parse_tree_root <|-- PT_delete
Parse_tree_root <|-- PT_explain
Parse_tree_root <|-- PT_table_ddl_stmt_base
Parse_tree_root <|-- PT_show_base



PT_show_base <|-- PT_show_engine_base
PT_show_engine_base <|-- PT_show_engine_status


```

```plantuml

title Top level  ddl statements 

Parse_tree_root <|-- PT_table_ddl_stmt_base
class PT_table_ddl_stmt_base {
  Alter_info m_alter_info
}
PT_table_ddl_stmt_base <|-- PT_create_table_stmt
PT_table_ddl_stmt_base <|-- PT_alter_table_stmt
PT_table_ddl_stmt_base <|-- PT_create_index_stmt
PT_table_ddl_stmt_base <|-- PT_drop_index_stmt
PT_table_ddl_stmt_base <|-- PT_show_create_table
```
```plantuml
title Parse Tree nodes
class Parse_tree_node {
  Parse_context context_t
  bool contextualized
  {abstract} bool contextualize(Parse_context *pc)

}

class PT_query_expression extends Parse_tree_node
```

## 2.3. optimizer

## 2.4. Service

A `Service` is a struct of C function pointers
The server has all `service` structs defined and initialized so that the function pointers point to a actual `service` implementation functions



The big picture of plugin services


```plantuml


  actor "SQL client" as client
  box "MySQL Server" #LightBlue
    participant "Server Code" as server
    participant "Plugin" as plugin
  endbox

  == INSTALL PLUGIN ==
  server -> plugin : initialize
  activate plugin

  loop zero or many
    plugin -> server : service API call
    server --> plugin : service API result
  end
  plugin --> server : initialization done

  == CLIENT SESSION ==
  loop many
    client -> server : SQL command
    server -> server : Add reference for Plugin if absent
    loop one or many
      server -> plugin : plugin API call
      loop zero or many
        plugin -> server : service API call
        server --> plugin : service API result
      end
      plugin --> server : plugin API call result
    end
    server -> server : Optionally release reference for Plugin
    server --> client : SQL command reply
  end

  == UNINSTALL PLUGIN ==
  server -> plugin : deinitialize
  loop zero or many
    plugin -> server : service API call
    server --> plugin : service API result
  end
  plugin --> server : deinitialization done
  deactivate plugin

```

## 2.5. Data Dictionary

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


## 2.6. Storage Engine

### 2.6.1. InnoDB
`InnoDB` is a general-purpose storage engine that balances reliability and high performance. `InnoDB` is the default MySQL storage Engine.

![innodb-arch](images/innode-arch.png)



#### 2.6.1.1. MVCC

`Multi-version Concurrency Control` A concurrency control method used by `InnoDB` to handle simultaneous transactions without locking the entire table. 

Old versions of changed rows are stored in undo tablespaces in a data structure called a rollback segment. InnoDB uses the information in the rollback segment to perform the undo operations needed in a transaction rollback. It also uses the info to build earlier versions of a row for a consistent read.

Internally `InnoDB` adds three fields to each row stored in the database:
* `DB_TRX_ID` indicates the transaction identifier for the last transaction that inserted or updated the row.
* `DB_ROLL_PTR` roll pointer points to an undo log record written to the rollback segment. if the row was updated, the undo log record contains the information necessary to rebuild the content of the row before it was updated.
* `DB_ROW_ID` contains a row ID that increases monotonically as new rows are inserted.



#### 2.6.1.2. In Memory Structure

`Buffer pool` is an area in main memory where `InnoDB` caches table and index data as it is accessed. The buffer pool permits frequently used data to be accessed directly from memory

#### 2.6.1.3. On Disk Structure

A `file-per-table` tablespace contains data and indexes for a single `InnoDB` table, and is stored on the file system in a single data file.


## 2.7. Bin log





## 2.8. Config

Configs
* `--defaults-file=#` read defaults options from the given file
* `--datadir=#` path to the database root directory 
* `--init-file=name` Read SQL commands from this file at startup
* `--open_files_limit=#`   number of file descriptors available to `mysqld`
* `--max-connections=#` max number of simultaneous client connections
* `--thread-cache-size=#` number of threads the server should cache for reuse

# 3. admin

```
show [full] processlist                      display the current running threads
SELECT * FROM performance_schema.threads    
show status like '%thread%'
```


# 4. Reference

* [mysql源码解析](https://github.com/Jeanhwea/mysql-source-course/blob/master/slides/p04-mysql-startup.pdf)
* [Mysql limitations](https://www.percona.com/blog/mysql-limitations-part-1-single-threaded-replication/)
* [MySQL · 源码分析 · 详解 Data Dictionary](http://mysql.taobao.org/monthly/2021/08/02)
* [InnoDB internals](https://blog.jcole.us/innodb/)