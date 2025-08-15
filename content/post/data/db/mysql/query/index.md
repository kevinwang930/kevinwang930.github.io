---
title: "Mysql internals"
date: 2024-09-13T18:07:46+08:00
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

* `Atomicity`     transaction management
* `Consistency`   protect from Crashes
* `Isolation`     transaction Isolation level
* `Durability`    Mysql software features interacting with particular hardware configuration.


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

## 2.2. SQL processing


* `THD` for each client connection, a separate thread with THD created serving as thread/connection descriptor.
* `LEX` parse and resolve statement, using as a working area, serves different purposes:
  * contains some universal properties of `Sql_cmd`
  * contains some execution state variables  like `m_exec_started`
    (set to true when execution is started), `plugins` (list of `plugins` used
    by `statement`), `insert_update_values_map` (a map of objects used by certain
    INSERT statements), etc.
  * contains a number of members that should be local to subclasses of
    `Sql_cmd`, like `purge_value_list` (for the PURGE command), `kill_value_list`
    (for the KILL command).



procedure:

1. YACC parser parses `select` statement to one kind of `Parse_tree_root`
2. `Parse_tree_root` calls `make_cmd()` method to generate `Sql_cmd`, In this method, `contextualize` of `Parse_tree_node` called to generate `Query_expression` in `LEX`
3. `Sql_cmd` calls its `execute()` to generate result




```plantuml

class Query_arena {
  Item *m_item_list
  MEM_ROOT *mem_root
}

class Open_tables_state {
  TABLE *open_tables
  TABLE *temporary_tables
  MYSQL_LOCK *lock
  MYSQL_LOCK *extra_lock
}

class THD extends Query_arena,Open_tables_state {
  Thd_mem_cnt m_mem_cnt
  MDL_context mdl_context
  LEX *lex
  LEX_CSTRING m_query_string
  LEX_CSTRING m_catalog
  LEX_CSTRING m_db

  Prepared_statement_map stmt_map
  Transaction_ctx m_transaction

  const char *thread_stack


  System_variables variables
  System_status_var status_var

  Cost_model_server m_cost_model

  Protocol *m_protocol
  Query_plan query_plan
  char *m_trans_log_file
  NET net
}

class Query_tables_list {
  enum_sql_command sql_command
  Table_ref *query_tables
  Table_ref **query_tables_last
}

class LEX << (S,#FF7700) >> extends Query_tables_list{
  THD *thd
  Query_expression *unit
  Query_block *query_block
  Query_result *result
  Query_block *all_query_blocks_list
  Query_block *m_current_query_block
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

class Query_block extends Query_term {
  mem_root_deque<Item *> fields
  List<Window> m_windows
  List<Item_func_match> *ftfunc_list
  mem_root_deque<Table_ref *> sj_nests
  SQL_I_List<Table_ref> m_table_list
  SQL_I_List<ORDER> order_list
  SQL_I_List<ORDER> group_list
  LEX *parent_lex
  table_map select_list_tables
  Table_ref *leaf_tables
}

class Sql_cmd {
  Prepared_statement *m_owner

  virtual bool prepare(THD *)
  virtual bool execute(THD *thd)
} 


class Sql_cmd_dml extends Sql_cmd {
  LEX *lex
  Query_result *result
}
class Sql_cmd_select extends Sql_cmd_dml {
  
}

THD *-- LEX

LEX *-right- Query_expression
LEX --> Sql_cmd: make
Query_expression *-right- Query_block

```


```plantuml
title parse procedure

participant "sql_parse.cc" as SP
participant THD
participant YACC
participant LEX
participant Parse_Tree

SP --> SP : dispatch_command()
activate SP
SP --> SP :dispatch_sql_command()
activate SP
SP --> SP: parse_sql
activate SP
SP --> THD : sql_parser()
activate THD
THD--> YACC :my_sql_parser_parse
activate Parse_Tree
THD --> LEX : make_sql_cmd(Parse_tree_root *root)
LEX --> Parse_Tree: make_cmd(thd) 
Parse_Tree --> Parse_Tree:contextualize
deactivate Parse_Tree
SP --> SP: mysql_execute_command
activate SP
SP --> Sql_cmd: execute(thd)
activate Sql_cmd
Sql_cmd --> Sql_cmd: prepare(thd)
Sql_cmd --> Sql_cmd: execute_inner(thd)
```
### 2.2.1 Parse

```plantuml


title Top level Sql Statements Structure

class Parse_tree_root {
  +virtual Sql_cmd *make_cmd(THD *thd) = 0
}

class PT_select_stmt {
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

title select parse tree
class PT_select_stmt {
  +enum_sql_command m_sql_command
  +PT_query_expression_body *m_qe
  +PT_into_destination *m_into
  +Sql_cmd *make_cmd(THD *thd)
}



class Parse_tree_node {
  Parse_context context_t
  bool contextualized
  {abstract} bool contextualize(Parse_context *pc)
  {abstract} bool do_contextualize(Parse_context *pc)

}

class Parse_context {
  THD *const thd
  MEM_ROOT *mem_root
  Query_block *select
  mem_root_deque<QueryLevel> m_stack
  Show_parse_tree m_show_parse_tree
}


class PT_query_expression_body extends Parse_tree_node
class PT_query_primary extends PT_query_expression_body
class PT_query_specification extends PT_query_primary {
  PT_hint_list *opt_hints
  Query_options options
  PT_item_list *item_list
  PT_into_destination *opt_into1
  const bool m_is_from_clause_implicit
  Mem_root_array_YY<PT_table_reference *> from_clause  
  Item *opt_where_clause
  PT_group *opt_group_clause
  Item *opt_having_clause
  PT_window_list *opt_window_clause
  Item *opt_qualify_clause
}




class PT_query_expression  extends PT_query_expression_body {
   PT_query_expression_body *m_body
   PT_order *m_order
   PT_limit_clause *m_limit
   PT_with_clause *m_with_clause
}

class Item extends  Parse_tree_node

class Parse_tree_item extends  Item

class PTI_context extends  Parse_tree_item {
  Item *expr
  enum_parsing_context m_parsing_place
}

class PTI_where extends PTI_context {

}

class Item_ident extends  Item {
  Name_resolution_context *context
  char *db_name
  char *table_name
  char *field_name
  Table_ref *m_table_ref
}

class Item_field extends Item_ident {
  Field *field
  Field *result_field
  uint16 field_index
  Item_multi_eq *item_equal_all_join_nests
}

class PTI_comp_op extends Parse_tree_item {
  Item *left
  chooser_compare_func_creator boolfunc2creator
  Item *right
}

PT_select_stmt *-- PT_query_expression_body

Parse_tree_node *-- Parse_context: contextualize
PT_query_specification *-- PTI_where

PTI_where *-- PTI_comp_op


```

### 2.2.2 Query block

During `contextualization`, inside `Parse_context`, `Parse_tree_root` is transformed into `Query_block`


* `Query_term` tree structure. 
  Five node types:
  * `Query_block`
  * `Query_term_unary`
  * `Query_term_intersect`
  * `Query_term_except`
  * `Query_term_union`
* `Query_block` a query specification, which is a query consisting of a `SELECT` keyword
* `Query_expression` one query block or several query blocks combined with UNION
* `AccessPath` query planing structure of `Query_expression`
* `RowIterator` an interface class for operating through a single table


```plantuml
class Query_term {
  Query_term_set_op *m_parent
  uint m_sibling_idx
  Query_result *m_setop_query_result
  bool m_owning_operand
  Table_ref *m_result_table
  mem_root_deque<Item *> *m_fields
}
class Query_block extends Query_term {
  mem_root_deque<Item *> fields
  Item *m_where_cond
  Item *m_having_cond
  List<Window> m_windows
  SQL_I_List<Table_ref> m_table_list
  SQL_I_List<ORDER> order_list
  SQL_I_List<ORDER> group_list
  char *db
  LEX *parent_lex
  table_map select_list_tables
  mem_root_deque<Table_ref *> *m_current_table_nest
  table_map outer_join
  Name_resolution_context context
  JOIN *join
  Item *select_limit
  Item *offset_limit
  Item::cond_result cond_value
  Item::cond_result having_value
  prepare()
  optimize()
}

class Table_ref {

}

class Parse_context {
  THD *const thd
  MEM_ROOT *mem_root
  Query_block *select
  mem_root_deque<QueryLevel> m_stack
  Show_parse_tree m_show_parse_tree
}

class  Query_expression {
  Query_expression *next
  Query_expression **prev
  Query_block *master
  Query_block *slave
  Query_term *m_query_term
  AccessPath *m_root_access_path
  RowIterator m_root_iterator
}

struct AccessPath {
 Type type
 RowIterator *iterator
}

class RowIterator {
  THD *const m_thd
}

class TableRowIterator extends RowIterator

class FilterIterator extends RowIterator
class TableScanIterator extends TableRowIterator
class IndexScanIterator extends TableRowIterator
class SortingIterator extends RowIterator


Query_expression *-- RowIterator



Query_expression *- AccessPath

class Query_term {

}

class Item extends  Parse_tree_node {
  uint8 m_data_type
}
class Item_ident extends  Item {
  Name_resolution_context *context
  char *db_name
  char *table_name
  char *field_name
  Table_ref *m_table_ref
}

class Item_field extends Item_ident {
  Field *field
  Field *result_field
  uint16 field_index
  Item_multi_eq *item_equal_all_join_nests
}

class Item_result_field extends Item {
  Field *result_field
}

class Item_func extends Item_result_field {
  Item **args
  Item *m_embedded_arguments[]
  uint arg_count
}

Parse_context *-- Query_block
Query_expression *-- Query_block
Query_block *-- Table_ref
Query_block *-- Item



```

### 2.2.3 Sql_cmd
* `Sql_cmd` representation of an SQL command, an interface between the parser and the runtime. The parser builds the appropriate `Sql_cmd` to represent a SQL statement in the parsed tree. The `execute()` method in the derived classes of `Sql_cmd` contains the runtime implementation.

```plantuml
class Sql_cmd {
  Prepared_statement *m_owner

}
class Sql_cmd_dml extends Sql_cmd {
  LEX *lex
  Query_result *result
}
class Sql_cmd_select extends Sql_cmd_dml {

}

class Query_tables_list {
  enum_sql_command sql_command
  Table_ref *query_tables
  Table_ref **query_tables_last
}

class LEX << (S,#FF7700) >> extends Query_tables_list{
  THD *thd
  Query_expression *unit
  Query_block *query_block
  Sql_cmd *m_sql_cmd
  Query_result *result
  Query_block *all_query_blocks_list
  Query_block *m_current_query_block
  make_sql_cmd(Parse_tree_root *parse_tree)
}
LEX *- Sql_cmd

```

### 2.2.4 Table
* `Table_ref` table reference in the from clause
* `Table` struct that represents a single open instance of table within a connection or query execution.
* `Table_share` shared between table objects, there is one instance of `Table_share` per one table in the database.
* `Table_cache` cache for opened tables
* `Table_cache_manager` container class for all the `Table_cache` instances in the system
* `Table_cache_element` Element that represents the table in the specific table cache
* `KEY` represents `Table`'s indexes on server layer

```plantuml

class Open_tables_state {
  TABLE *open_tables
  TABLE *temporary_tables
  MYSQL_LOCK *lock
  MYSQL_LOCK *extra_lock
}

class THD extends Query_arena,Open_tables_state {
  MDL_context mdl_context
  Locked_tables_list locked_tables_list
}



struct Table {
    THD *in_use
    Field **field
    TABLE_SHARE *s
    handler *file
    TABLE *next
    TABLE *prev
    TABLE *cache_next
    TABLE **cache_prev
    partition_info *part_info
    char *alias
    Table_ref *pos_in_table_list
    Table_ref *pos_in_locked_tables
    MY_BITMAP *read_set
    MY_BITMAP *write_set
    reginfo
    KEY *key_info
}

struct reginfo {
  thr_lock_type lock_type
}

struct TABLE_SHARE {
  long m_version
  Field **field

}

class KEY {
  KEY_PART_INFO *key_part
  TABLE *table
  ha_key_alg algorithm
}

class KEY_PART_INFO {
  Field *field
  uint offset
}

class Table_cache_manager {
    Table_cache m_table_cache[MAX_TABLE_CACHES]
}

class Table_cache {
    TABLE *m_unused_tables
    map<string, Table_cache_element > m_cache
}

class Table_cache_element {
    TABLE_list used_tables
    TABLE_list free_tables_slim
    TABLE_SHARE *share
}

class Table_ref {
  TABLE *table
}

class Sql_cmd {
  Prepared_statement *m_owner

}
class Sql_cmd_dml extends Sql_cmd {
  LEX *lex
  Query_result *result
}

class Query_tables_list {
  enum_sql_command sql_command
  Table_ref *query_tables
  Table_ref **query_tables_last
}

struct LEX  extends Query_tables_list{
  THD *thd
  Query_expression *unit
  Query_block *query_block
  Query_result *result
  Query_block *all_query_blocks_list
  Query_block *m_current_query_block
  make_sql_cmd(Parse_tree_root *parse_tree)
}

class Field {
  TABLE *table
  char **table_name, 
  char *field_name
  Key_map part_of_key
}

class Field_num extends Field

class Field_str extends Field

class Field_blob extends Field



THD o- Table
Table *- TABLE_SHARE
Table *-- reginfo
Table_cache_manager o-- Table_cache
Table_cache o-- Table_cache_element
Table_cache_element o-- Table
Table_ref o-- Table
Sql_cmd_dml *-- LEX
LEX o-- Table_ref
Table *-- Field
Table O-- KEY
KEY O-- KEY_PART_INFO
```


### 2.2.5 Table lock
```plantuml
struct MYSQL_LOCK {
  TABLE **table
  uint table_count 
  unit lock_count
  THR_LOCK_DATA **locks
}

struct THR_LOCK_DATA {
  THR_LOCK_INFO *owner
  THR_LOCK_DATA *next
  THR_LOCK_DATA **prev
  THR_LOCK *lock
  mysql_cond_t *cond
  thr_lock_type type
}

MYSQL_LOCK o-- THR_LOCK_DATA

```
#### Refrence
1. https://kernelmaker.github.io/MySQL_Lock

### 2.2.4 Query Execution

```plantuml
participant sql_parse
participant Sql_cmd_select
participant sql_base.cc
participant Query_block
participant Item
participant lock.cc
participant ha_innodb.cc
participant TrxInInnoDB
participant Query_expression
participant Query_result



sql_parse --> Sql_cmd_select: mysql_execute_command

Sql_cmd_select --> Sql_cmd_select: execute
activate Sql_cmd_select
Sql_cmd_select --> Sql_cmd_select: prepare

activate Sql_cmd_select
Sql_cmd_select --> sql_base.cc: open_tables_for_query
activate sql_base.cc
sql_base.cc --> sql_base.cc: open_tables
deactivate 
Sql_cmd_select --> Query_block: prepare
Query_block --> Item: fix_field
deactivate Sql_cmd_select
Sql_cmd_select --> sql_base.cc: lock_tables
sql_base.cc --> lock.cc: mysql_lock_tables
activate lock.cc
lock.cc --> ha_innodb.cc: store_lock
lock.cc --> lock.cc: lock_external
activate lock.cc
lock.cc --> ha_innodb.cc: external_lock
ha_innodb.cc --> TrxInInnoDB: begin_stmt
deactivate lock.cc
deactivate lock.cc
Sql_cmd_select --> Sql_cmd_select: execute_inner
activate Sql_cmd_select
Sql_cmd_select --> Query_expression: optimize
Sql_cmd_select --> Query_expression: create_iterators
Sql_cmd_select --> Query_expression: execute
activate Query_expression
Query_expression --> Query_expression: ExecuteIteratorQuery
Query_expression --> Query_result: start_execution
loop 
  Query_expression --> RowIterator: read
  Query_expression --> Query_result: send_data
  Query_expression --> Query_result: send_eof
end




```


## 2.3. optimizer


## 2.4. Storage Engine 

Storage Engine refers to the code that actually stores and retrieves the data.





* `handler` class is the interface for accessing data in   dynamically loadable storage engines.
* `handlerton` is a singleton structure -one instance per storage engine, to provide access to storage engine functionality that works on global level.
* `Transaction_ctx` server layer transaction coordinator for `THD` (session)
* `Ha_trx_info` transaction related thread-specific storage engine data



```plantuml

struct Table {
  handler *file
}

class handler {
  TABLE_SHARE *table_share
  TABLE *table
  handlerton *ht
  uchar *ref
  uchar *dup_ref
  Table_flags cached_table_flags
  uint active_index
  store_lock()
}
struct handlerton {
uint slot
}





class Open_tables_state {
  TABLE *open_tables
  TABLE *temporary_tables
  MYSQL_LOCK *lock
  MYSQL_LOCK *extra_lock
}



class THD extends Query_arena,Open_tables_state {
  MDL_context mdl_context
  Locked_tables_list locked_tables_list
  Ha_data[] ha_data
  Transaction_ctx m_transaction
}

struct  Ha_data {
  void *ha_ptr
  Ha_trx_info ha_info[2]
}




class Transaction_ctx {
  SAVEPOINT *m_savepoints
  THD_TRANS m_scope_info[]
  int64 sequence_number
}


struct THD_TRANS {
  Ha_trx_info *m_ha_list
}

class Ha_trx_info {
  Ha_trx_info *m_next
  handlerton *m_ht

}


THD o-- Table
THD o- Ha_data
THD *-- Transaction_ctx

Table *-- handler
handler *- handlerton

Transaction_ctx *-- THD_TRANS
THD_TRANS *-- Ha_trx_info

```


### 2.4.1. InnoDB
`InnoDB` is a general-purpose storage engine that balances reliability and high performance. `InnoDB` is the default MySQL storage Engine.


![innodb-arch](images/innode-arch.png)

* `innodb_session_t` InnoDB private data that is cached in THD
* `ha_innobase` a handle to an InnoDB table
* `dict_table_t` Data structure for a database table
* `dict_index_t` Data Structure for an index
* `dtuple_t` Structure for an SQL data tuple of fields (logical record)
```plantuml

struct Table {
  handler *file
}

class handler {
  TABLE_SHARE *table_share
  TABLE *table
  handlerton *ht
  uchar *ref
  uchar *dup_ref
  Table_flags cached_table_flags
  uint active_index
  Record_buffer *m_record_buffer
  store_lock()
}
struct handlerton {
uint slot
}

class ha_innobase extends handler {
  row_prebuilt_t *m_prebuilt
  THD *m_user_thd
  INNOBASE_SHARE *m_share
}


class Open_tables_state {
  TABLE *open_tables
  TABLE *temporary_tables
  MYSQL_LOCK *lock
  MYSQL_LOCK *extra_lock
}



class THD extends Query_arena,Open_tables_state {
  MDL_context mdl_context
  Locked_tables_list locked_tables_list
  Ha_data[] ha_data
  Transaction_ctx m_transaction
}

struct  Ha_data {
  void *ha_ptr
  Ha_trx_info ha_info[2]
}

class innodb_session_t {
 trx_t *m_trx
 table_cache_t m_open_tables
 Tablespace *m_usr_temp_tblsp
 Tablespace *m_intrinsic_temp_tblsp
}

struct  row_prebuilt_t {
  dict_table_t *table
  dict_index_t *index
  trx_t *trx
  dtuple_t *search_tuple
  dtuple_t *m_stop_tuple
  ulint select_lock_type
  mysql_row_templ_t *mysql_template
  ins_node_t *ins_node
}


struct trx_t {
  trx_id_t id
  trx_state_t state
  ReadView *read_view
  ut_list_node trx_list
  trx_lock_t lock
  isolation_level_t isolation_level
  THD *mysql_thd
  trx_savept_t last_sql_stat_start
  trx_mod_tables_t mod_tables
}



class Transaction_ctx {
  SAVEPOINT *m_savepoints
  THD_TRANS m_scope_info[]
  int64 sequence_number
}


struct THD_TRANS {
  Ha_trx_info *m_ha_list
}

class Ha_trx_info {
  Ha_trx_info *m_next
  handlerton *m_ht

}
struct dict_table_t {
  mem_heap_t *heap
  table_name_t name
  char *data_dir_path
  id_name_t tablespace
  dict_col_t *cols
  List<dict_index_t> indexes
}

struct dict_index_t {
space_index_t id
mem_heap_t *heap
id_name_t name
dict_table_t *table
dict_field_t *fields
}




THD o-- Table
THD o-- Ha_data
THD *-- Transaction_ctx
Ha_data *-- innodb_session_t
innodb_session_t *-- trx_t
Table *-- handler
handler *- handlerton
ha_innobase *-- row_prebuilt_t
row_prebuilt_t *-- dict_table_t
row_prebuilt_t *-- dict_index_t
row_prebuilt_t *-- trx_t
dict_table_t o- dict_index_t
Transaction_ctx *-- THD_TRANS
THD_TRANS *-- Ha_trx_info

```




#### 2.4.1.1. MVCC

`Multi-version Concurrency Control` A concurrency control method used by `InnoDB` to handle simultaneous transactions without locking the entire table. 

Old versions of changed rows are stored in undo tablespaces in a data structure called a rollback segment. InnoDB uses the information in the rollback segment to perform the undo operations needed in a transaction rollback. It also uses the info to build earlier versions of a row for a consistent read.

Internally `InnoDB` adds three fields to each row stored in the database:
* `DB_TRX_ID` indicates the transaction identifier for the last transaction that inserted or updated the row.
* `DB_ROLL_PTR` roll pointer points to an undo log record written to the rollback segment. if the row was updated, the undo log record contains the information necessary to rebuild the content of the row before it was updated.
* `DB_ROW_ID` contains a row ID that increases monotonically as new rows are inserted.



#### 2.4.1.2. In Memory Structure

`Buffer pool` is an area in main memory where `InnoDB` caches table and index data as it is accessed. The buffer pool permits frequently used data to be accessed directly from memory

#### 2.4.1.3. On Disk Structure

A `file-per-table` tablespace contains data and indexes for a single `InnoDB` table, and is stored on the file system in a single data file.


## 2.5. Bin log





## 2.6. Config

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
* [mysql源码解读cnblog](https://www.cnblogs.com/jkin)
* [阿里云开发者mysql解析](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MzIzOTU0NTQ0MA==&action=getalbum&album_id=1970265915745239045&scene=173&subscene=&sessionid=svr_19b6b9d1b73&enterid=1727505362&from_msgid=2247504340&from_itemidx=1&count=3&nolastread=1#wechat_redirect)
* [mysql源码解析github](https://github.com/Jeanhwea/mysql-source-course/blob/master/slides/p04-mysql-startup.pdf)
* [Mysql limitations](https://www.percona.com/blog/mysql-limitations-part-1-single-threaded-replication/)
* [MySQL · 源码分析 · 详解 Data Dictionary](http://mysql.taobao.org/monthly/2021/08/02)
* [InnoDB internals](https://blog.jcole.us/innodb/)
* [understanding mysql internals](https://theswissbay.ch/pdf/Gentoomen%20Library/Databases/mysql/O%27Reilly%20Understanding%20MySQL%20Internals.pdf)