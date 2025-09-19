---
title: "MySQL storage engine internals - InnoDB"
date: 2025-08-17T19:17:35+07:00
draft: true
categories:
- data
- db
- mysql
tags:
- data
- db
- mysql
keywords:
- InnoDB
#thumbnailImage: //example.com/image.jpg
---

This Article introduces the internal implementation of MySQL storage engine - InnoDB 
<!--more-->





Storage Engine in MySQL refers to the code that actually stores and retrieves the data.



* `handler` class is the interface for accessing data in   dynamically loadable storage engines.
  interface:
    * `ha_rnd_next`  read next row 
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
  ha_rnd_next()
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


## InnoDB
`InnoDB` is a general-purpose storage engine that balances reliability and high performance. `InnoDB` is the default MySQL storage Engine.


![innodb-arch](images/innode-arch.png)


### On Disk Strctures

#### table space

##### file-per-table table space
Each `InnoDB` file-per-table tablespace contains data and indexes for a single `InnoDB` table,   and stored on the file system in a single `.idb` file.


#### Clustered Index
`InnoDB` table itself is a  clustered index that stores row data in the leaf pages of B+ tree ordered by the primary key. If no primary key defined, `InnoDB` creates a hidden one.

#### secondary Index
Indexes other than cluster index are known as secondary indexes. Each secondary index has its own B+ tree. Each record in a secondary index contains the primary key columns for the row, as well as the columns specified for the secondary indexes. `InnoDB` uses this primary key value to search for the row in the clustered index. 

##### Undo table space
Undo tables space contains undo logs which are collections of records containing information about how to undo the lastest change by a transaction to a clustered index record.

##### Undo logs
An undo log is a collection of undo log records associated with a single read-write transaction. 

* `innodb_session_t` InnoDB private data that is cached in THD
* `ha_innobase` a handle to an InnoDB table
* `dict_table_t` Data structure for a database table
* `dict_index_t` Data Structure for an index
* `row_prebuilt_t` per-table, per-open table cached Structure that InnoDB prebuilds to speed up row operations.
* `dtuple_t` Structure for an SQL data tuple of fields (logical record)
* `btr_pcur_t` the persistent B-Tree cursor structure




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
  ha_rnd_next()
}
struct handlerton {
uint slot
}

class ha_innobase extends handler {
  row_prebuilt_t *m_prebuilt
  THD *m_user_thd
  INNOBASE_SHARE *m_share
  rnd_next()
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
  ha_innobase *m_mysql_handler
  dtuple_t *search_tuple
  dtuple_t *m_stop_tuple
  ulint select_lock_type
  mysql_row_templ_t *mysql_template
  ins_node_t *ins_node
  btr_pcur_t *pcur
}

struct btr_pcur_t {
  btr_cur_t m_btr_cur
  
}
row_prebuilt_t *-- btr_pcur_t



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
rw_lock_t lock
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




### MVCC

`Multi-version Concurrency Control` A concurrency control method used by `InnoDB` to handle simultaneous transactions without locking the entire table. 

Old versions of changed rows are stored in undo tablespaces in a data structure called a rollback segment. InnoDB uses the information in the rollback segment to perform the undo operations needed in a transaction rollback. It also uses the info to build earlier versions of a row for a consistent read.

Internally `InnoDB` adds three fields to each row stored in the database:
* `DB_TRX_ID` indicates the transaction identifier for the last transaction that inserted or updated the row.
* `DB_ROLL_PTR` roll pointer points to an undo log record written to the rollback segment. if the row was updated, the undo log record contains the information necessary to rebuild the content of the row before it was updated.
* `DB_ROW_ID` contains a row ID that increases monotonically as new rows are inserted.

```plantuml
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

class ReadView {
  ids_t m_ids
  node_t m_view_list
  trx_id_t m_low_limit_id
  trx_id_t m_up_limit_id
  trx_id_t m_creator_trx_id
}

struct trx_sys_t {
  MVCC *mvcc
  trx_id_t next_trx_id_or_no
  Trx_shard shards[TRX_SHARDS_N]
  trx_ids_t rw_trx_ids
}


struct  row_prebuilt_t {
  dict_table_t *table
  dict_index_t *index
  trx_t *trx
  ha_innobase *m_mysql_handler
  dtuple_t *search_tuple
  dtuple_t *m_stop_tuple
  ulint select_lock_type
  mysql_row_templ_t *mysql_template
  ins_node_t *ins_node
  btr_pcur_t *pcur
}

struct btr_pcur_t {
  btr_cur_t m_btr_cur
  
}
struct btr_cur_t {
dict_index_t *index
page_cur_t page_cur
}

row_prebuilt_t *-- btr_pcur_t
btr_pcur_t *-- btr_cur_t

row_prebuilt_t *-- trx_t
trx_t *-- ReadView
trx_sys_t -> trx_t


```

