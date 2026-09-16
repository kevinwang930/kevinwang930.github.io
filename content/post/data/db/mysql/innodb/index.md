---
title: "MySQL Storage Engine Internals - InnoDB"
date: 2025-08-17T19:17:35+07:00
draft: false
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

This article introduces the internal architecture and implementation details of MySQL's default storage engine, InnoDB, exploring its memory structures, on-disk storage layouts, physical row formats, and Multi-Version Concurrency Control (MVCC) visibility rules.

<!--more-->

In MySQL's pluggable architecture, the **Storage Engine** is the component responsible for the physical storage, indexing, retrieval, and lock management of relational data.

*   **`handler` Class**: The primary abstract C++ interface through which the SQL Server layer communicates with storage engines. Specific engine drivers inherit from it (e.g., `ha_innobase` for InnoDB). It defines interface methods like `ha_rnd_next()` (scan next row) and `index_read()` (lookup index).
*   **`handlerton`**: A singleton structure—one instance per storage engine—providing global hook registration for engine startup, shutdown, transaction coordination, and log flushes.
*   **`Transaction_ctx`**: Server-layer transaction coordinator associated with a thread/session's `THD`.
*   **`Ha_trx_info`**: Thread-specific transaction state structures registering an active storage engine inside a transaction.

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


class ha_innobase extends handler {
  
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

---

## InnoDB Architecture Overview

InnoDB is a general-purpose transactional storage engine that balances high reliability with peak execution performance. It is the default storage engine in modern MySQL.

![InnoDB Architecture](images/innodb-structures.svg)

---

## 1. In-Memory Structures

To minimize latency caused by slow disk I/O, InnoDB operates a large, highly structured pool of memory:

### A. The Buffer Pool
The **Buffer Pool** is the heart of InnoDB. It caches table and index pages (with a default page size of 16KB)—and **undo pages** when they are read or dirtied—directly in memory, allowing read and write operations to happen at RAM speeds. It is managed via three primary linked lists:
*   **Free List**: Keeps track of unused/empty memory pages ready to be allocated.
*   **Flush List**: Tracks "dirty pages" (pages modified in-memory whose changes have not yet been written to the physical tablespace files).
*   **LRU (Least Recently Used) List**: Implements the page eviction policy when the buffer pool becomes full.
    *   *Midpoint Insertion Strategy*: To prevent large, sequential table scans (e.g., `SELECT * FROM table`) from completely flushing out hot/frequently accessed pages, InnoDB splits the LRU list into two sublists: **New (Young)** (5/8 of the list) and **Old** (3/8 of the list).
    *   Newly fetched pages are initially inserted at the "midpoint" (the boundary between old and young). A page is only promoted to the Young sublist if it is accessed again after a configurable time duration (`innodb_old_blocks_time`), effectively buffering hot pages from sequential scan pollution.

### B. The Change Buffer
Caches insert, update, and delete changes to **secondary indexes** when the corresponding index pages are not currently cached in the Buffer Pool. This avoids expensive random disk reads.
*   When secondary index pages are eventually read into the Buffer Pool for subsequent queries, the cached changes are physically merged.
*   The Change Buffer is itself a physical B+ Tree stored inside the System Tablespace.

### C. The Adaptive Hash Index (AHI)
InnoDB monitors search profiles on index B+ Trees. If it detects that certain leaf pages are queried repeatedly with exact matches (point lookups), it automatically builds a memory-based hash table on top of those leaf nodes.
*   This shifts point lookup speeds from $O(\log N)$ B-Tree traversals to direct $O(1)$ memory hash retrievals.

### D. The Log Buffer
Stores transactional log records (**Redo Logs**) in memory before flushing them to disk tablespace logs.
*   Its flushing behavior is governed by the critical parameter **`innodb_flush_log_at_trx_commit`**:
    *   `1` (Default): Redo log is written to files and flushed/synced to disk at every transaction commit. Guaranteed ACID durability.
    *   `0`: Redo log is written and synced to disk once per second. High speed, but up to 1 second of transaction data can be lost in a crash.
    *   `2`: Redo log is written to the OS file cache at commit, but flushed/synced to disk once per second. Safely survives a `mysqld` crash, but data can be lost during an OS/power failure.

### E. Undo (memory objects, not a redo-style buffer)
Unlike redo, InnoDB does **not** keep a dedicated circular “undo log buffer.” Undo **pages** are ordinary pages: written through the Buffer Pool and persisted in **undo tablespaces**. What lives as first-class RAM objects are:

*   **`trx_t::rsegs`** (`trx_rsegs_t`): durable undo via **`m_redo`**, temp via **`m_noredo`**; each is a **`trx_undo_ptr_t`** holding **`rseg`**, **`insert_undo`**, **`update_undo`**.
*   **`trx_undo_t`**: one assigned undo log (`hdr_page_no`, `top_page_no`, `top_offset`, `guess_block` into the Buffer Pool).
*   **`trx_rseg_t`**: rollback-segment mirror with update/insert undo lists and cached reusable undo logs, plus the history list used by purge.

Physical undo layout and how **`DB_ROLL_PTR`** addresses a record are in §4.

---

## 2. On-Disk Structures

---

### 2.1. Tablespaces & Storage Units
Relational data inside InnoDB is organized into logical tablespace structures containing pages, extents, and segments:

*   **System Tablespace**: Stores the doublewrite buffer pages, change buffer pages, and historical system data.
*   **File-Per-Table Tablespaces**: If `innodb_file_per_table` is enabled (default), each table and its associated indexes are stored on the file system in an independent `.ibd` file.
*   **Undo Tablespaces**: Durable home of undo log **pages**—rollback segment headers, undo slots, and undo log segments used for rollback and MVCC. In-memory counterparts are **`trx_rseg_t` / `trx_undo_t`** (§1.E, §4); page frames may also sit in the Buffer Pool when hot.
*   **Temporary Tablespaces**: Dedicated tablespace files utilized for temporary tables generated during complex aggregations (like `TemptableAggregateIterator` outputs).

---

### 2.2. Index Structures & Physical Storage

InnoDB tables are stored as **Index-Organized Tables** using B+ Trees:

*   **Clustered Index**: The table itself. Relational row data is stored physically inside the **leaf pages** of the B+ Tree, sorted by the **Primary Key**. If no primary key is defined, InnoDB automatically allocates a hidden 6-byte row ID (`DB_ROW_ID`) to organize the cluster index.

![Clustered Index Structure](images/clustered-index.svg)

*   **Secondary Index**: Auxiliary B+ Trees built on non-primary columns. Unlike clustered indexes, secondary index leaf pages do **not** store actual data rows; instead, they store the value of the indexed columns along with the corresponding **Primary Key** value. Finding a row via a secondary index requires a secondary lookup (bookmark lookup) in the clustered index.

![Secondary Index Lookup](images/secondary-index.svg)

*   **Index page frame (on-disk / buffer-pool image).** A leaf or non-leaf index page is a fixed-size byte array (commonly 16 KiB). Its durable layout comprises the file-page header (`FIL_PAGE_*`), the index page header (`PAGE_*`), the record heap (infimum, supremum, user records addressed by `heap_no`), the page directory, and the file trailer. Representative header fields include:

| Field | Role |
|-------|------|
| `PAGE_N_DIR_SLOTS` | Number of page-directory slots |
| `PAGE_HEAP_TOP` | Offset of the free space boundary in the heap |
| `PAGE_N_HEAP` | Number of records allocated in the heap (including system records) |
| `PAGE_N_RECS` | Number of user records currently in the page |
| `PAGE_LEVEL` / `PAGE_INDEX_ID` | B+tree level and owning index identity |

The page header and record heap describe **physical layout and index keys only**. They do **not** contain record locks, gap locks, next-key locks, or insert-intention locks. There is no lock bitmap, wait queue, or `lock_t` payload in the `.ibd` page image.

*   **Where concurrency locks reside.** Explicit InnoDB row locks are process-memory objects (`lock_t`) allocated from the owning transaction’s lock heap (`trx_t::lock.lock_heap`, or a fixed `rec_pool` entry) and indexed by `lock_sys->rec_hash` under `page_id`. For a record lock, a bitmap packed immediately after the `lock_t` header marks which `heap_no` slots on that page the request covers; `type_mode` encodes shared/exclusive strength and gap versus record-only versus next-key versus insert-intention semantics. Those structures are discarded when the transaction releases its locks; they are not written by page flush or recovery redo for ordinary DML. (See [MySQL DML Internals](/post/data/db/mysql/dml/) §3.4 for identity `(page_id, heap_no)` and bitmap placement.)

*   **Redo Logs**: A Write-Ahead Log (WAL) structure ensuring transactional durability (D of ACID). It resides physically on disk as circular ring files (`ib_logfile0`, `ib_logfile1`). The circular buffer operates using a Checkpoint pointer (representing page changes already flushed from RAM to disk tablespace blocks) and a Write pointer (the current active logging head). The active space between checkpoint and write pointers represents logs that must not be overwritten.

![Redo Log Circular Buffer](images/redo-log.svg)

---

### 2.3. Key InnoDB Source Code Descriptors

At the C++ source code level, InnoDB structures are represented by these key classes:

*   **`ha_innobase`**: The primary C++ handler class implementing the server's abstract `handler` interface for InnoDB operations.
*   **`innodb_session_t`**: Stores session-specific cached transactional states inside `THD` connection descriptors.
*   **`row_prebuilt_t`**: A highly cached, per-open table structure prebuilt by InnoDB to accelerate repeated index lookups and row cursoring.
*   **`dict_table_t`** & **`dict_index_t`**: Logical descriptors representing tables and index schemas.
*   **`dtuple_t`**: Represents a logical database row tuple.
*   **`btr_pcur_t`**: A persistent B-Tree cursor used to hold positions on index leaf nodes across transactional operations.

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
  undo_no_t undo_no
  trx_savept_t last_sql_stat_start
  trx_rsegs_t rsegs
  trx_mod_tables_t mod_tables
}

struct trx_rsegs_t {
  trx_undo_ptr_t m_redo
  trx_undo_ptr_t m_noredo
}

struct trx_undo_ptr_t {
  trx_rseg_t *rseg
  trx_undo_t *insert_undo
  trx_undo_t *update_undo
}

struct trx_undo_t {
  trx_rseg_t *rseg
  space_id_t space
  page_no_t hdr_page_no
  page_no_t top_page_no
  ulint top_offset
  undo_no_t top_undo_no
  buf_block_t *guess_block
}

struct trx_rseg_t {
  size_t id
  space_id_t space_id
  page_no_t page_no
  Undo_list update_undo_list
  Undo_list insert_undo_list
  Undo_list update_undo_cached
  Undo_list insert_undo_cached
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
trx_t *-- trx_rsegs_t : rsegs
trx_rsegs_t *-- trx_undo_ptr_t : m_redo
trx_rsegs_t *-- trx_undo_ptr_t : m_noredo
trx_undo_ptr_t o-- trx_rseg_t : rseg
trx_undo_ptr_t o-- trx_undo_t : insert_undo
trx_undo_ptr_t o-- trx_undo_t : update_undo
trx_undo_t o-- trx_rseg_t : rseg
trx_rseg_t o-- trx_undo_t : undo lists

```

---

## 3. Physical Row Formats & BLOB Off-Page Storage

InnoDB supports multiple physical row storage formats: `Compact`, `Redundant`, `Dynamic`, and `Compressed`.
In modern MySQL, the default format is **Dynamic**. 

### The Dynamic Row Format & Off-Page Storage
When columns are exceptionally large (such as text, large `VARCHAR`, or binary `BLOB` fields), storing them inline inside a B+ Tree leaf page can severely reduce index density, forcing more page splits and increasing the B+ Tree height.

*   To combat this, the **Dynamic** row format uses **Off-Page Storage**:
    *   If a row's size exceeds physical page restrictions, InnoDB stores only a **20-byte pointer** inline inside the leaf node.
    *   This 20-byte descriptor contains the **Tablespace ID**, **Page Number**, and **Offset** pointing directly to external off-page tablespace allocation blocks containing the raw BLOB data.
    *   This ensures that B+ Tree leaf pages remain densely populated, keeping search times for key columns exceptionally fast.

---

## 4. Multi-Version Concurrency Control (MVCC)

**MVCC** is the architectural framework used by InnoDB to handle simultaneous, high-throughput transactions without the massive performance penalty of locking entire tables (non-blocking reads).

To implement MVCC, InnoDB appends three hidden metadata fields to every clustered index record:
1.  **`DB_TRX_ID`** (6 bytes): Tracks the transaction identifier of the last transaction that modified (inserted or updated) this row.
2.  **`DB_ROLL_PTR`** (7 bytes): The rollback pointer. Points directly to the undo log record containing the previous state of the row.
3.  **`DB_ROW_ID`** (6 bytes): The row ID used to uniquely organize clustered records if no primary key was specified.

### Undo log: memory and physical layout

The architecture overview shows undo on both sides of the Memory/Disk split for a reason: **control objects** live in process memory; **bytes** live in undo tablespace pages (often cached in the Buffer Pool).

![Undo log memory vs physical layout](images/undo-log-layout.svg)

**Memory.** A read-write **`trx_t`** is assigned undo from a rollback segment:

| Object | Role |
|--------|------|
| **`trx_t::rsegs`** | **`m_redo` / `m_noredo`**: assigned rollback segment + undo logs for durable / temp tables |
| **`trx_undo_ptr_t`** | **`rseg`**, **`insert_undo`**, **`update_undo`** |
| **`trx_undo_t`** | In-memory description of one undo log: tablespace, header page/offset, current top page/offset, size, optional `guess_block` |
| **`trx_rseg_t`** | Rollback segment: active and cached insert/update undo lists; history list of committed undo for purge |

There is no redo-like dedicated undo buffer. Appending an undo record dirties an undo page in the Buffer Pool; durability of that page change is covered by **redo**, same as index pages.

**Physical (undo tablespace).** On disk (e.g. `undo_001`):

1. **Rollback segment header page** — history-list metadata and an array of **undo slots** (`page_size / 16` slots; 1024 at the default 16 KiB page). Each non-empty slot points at the first page of an undo log segment.
2. **Undo log segment first page** — `TRX_UNDO_PAGE_HDR`, then `TRX_UNDO_SEG_HDR` (segment state, last log, page list), then undo log header and early records.
3. **Continuation undo pages** — page header plus undo records. An **update** record stores old `DB_TRX_ID` / `DB_ROLL_PTR`, the primary key, and **old values of columns in the update vector only** (not a full prior row). An **insert** record stores enough to undo the insert.

**`DB_ROLL_PTR`** packs whether the undo is insert-type, which rollback segment, and the **page number + offset** of the undo record. Following that pointer is how MVCC walks older versions.

**What an update undo record actually stores** (from `trx_undo_page_report_modify` on the clustered index record **before** the in-place change):

1. Type (`TRX_UNDO_UPD_EXIST_REC` / delete-mark variants), `undo_no`, `table_id`
2. Old record `info_bits`, old **`DB_TRX_ID`**, old **`DB_ROLL_PTR`**
3. Clustered **unique key** columns (to find the row)
4. **`n_updated`**, then for each entry in the update vector: field number + **old column value** copied from the still-unmodified record (`/* Save the old value of field */`)

It does **not** store a full previous row image. Unchanged columns (e.g. `Name` when only `Salary` is updated) are omitted. MVCC rebuilds an older version by starting from the current clustered record and overlaying those old column values from the undo chain (`trx_undo_prev_version_build`). INSERT undo is a different record type: enough information to remove the inserted row on rollback.

(LOB columns may additionally record partial binary patches via `trx_undo_report_blob_update`; ordinary in-row columns are whole old values, not byte diffs.)

**Worked example.** Same row as §5 / the version-chain figure: transaction **202** runs

```sql
UPDATE employees SET salary = 75000 WHERE id = 10;
```

Before the statement, the clustered leaf holds `(10, 'Charlie', 70000)` with `DB_TRX_ID = 198`. InnoDB appends an **update** undo record with the **old `Salary`**, then rewrites the leaf.

![Undo log example: memory objects and page contents for salary update](images/undo-log-example.svg)

Concrete bindings after the undo append (illustrative addresses):

| Location | Content |
|----------|---------|
| **`trx_t`** | `id = 202`, `rsegs.m_redo.update_undo → U1` |
| **`trx_undo_t U1`** | `space = undo_001`, `hdr_page_no = 40`, `top_page_no = 57`, `top_offset = 0x7F03`, `top_undo_no = 5`, `rseg = #2` |
| **`trx_rseg_t #2`** | header page 5; `slots[17] = 40`; `U1` on `update_undo_list` |
| **Buffer Pool / disk page 57** | at `0x7F03`: `TRX_UNDO_UPD_EXIST_REC`, PK `ID=10`, **old `Salary = 70000`**, old `DB_TRX_ID = 198`, old roll pointer; **`Name` not present** |
| **Clustered leaf** | `Salary = 75000`, `DB_TRX_ID = 202`, `DB_ROLL_PTR = {update, rseg 2, page 57, offset 0x7F03}` |

An INSERT undo for the original row (version-chain figure at `0x6A05`) is a separate **`insert_undo`** log and stores what is needed to undo the insert, not an update-style column vector. Page/slot numbers above are pedagogical; the field set matches the source writer.

### Version chain (logical view)

![Undo Log Version Chain](images/undo-log.svg)

### The ReadView Visibility Logic

When a transaction starts a consistent read query (under `REPEATABLE READ` or `READ COMMITTED` isolation levels), InnoDB instantiates a **`ReadView`** descriptor. The `ReadView` is a snapshot of the transaction landscape at a precise point in time.

The `ReadView` contains four critical variables:
*   **`m_ids`**: A list of all active (running, uncommitted) transaction IDs at the time of view creation.
*   **`m_up_limit_id`**: The lower bound of active transactions. Any transaction with `trx_id < m_up_limit_id` was already committed before the `ReadView` was created and is always visible.
*   **`m_low_limit_id`**: The upper limit of allocated transaction IDs. Any transaction with `trx_id >= m_low_limit_id` started after the `ReadView` was created and is always invisible.
*   **`m_creator_trx_id`**: The ID of the transaction that created this view. Modifications made by the creator transaction are always visible to itself.

#### The Transaction Visibility Algorithm:
For any record in the clustered index with metadata `DB_TRX_ID = trx_id`:

```text
               ReadView Created (Landscape snapshot)
  ───────────┼─────────────────────────────────────────────┼───────────>
             │             Active List [m_ids]             │
   trx_id <  │                                             │  trx_id >=
m_up_limit_id│       m_up_limit_id <= trx_id <             │m_low_limit_id
             │             m_low_limit_id                  │
             │                                             │
   VISIBLE   │   In m_ids? ──► YES ──> INVISIBLE           │  INVISIBLE
             │             └──► NO  ──> VISIBLE            │
```

1.  **Self-Visibility**: If `trx_id == m_creator_trx_id`, the change is **visible**.
2.  **Committed Before ReadView**: If `trx_id < m_up_limit_id`, the transaction was committed before this view was created. The change is **visible**.
3.  **Started After ReadView**: If `trx_id >= m_low_limit_id`, the transaction started after the view's creation. The change is **invisible**.
4.  **Active Transaction Window**: If `m_up_limit_id <= trx_id < m_low_limit_id`:
    *   If `trx_id` is present in the active list `m_ids`, the transaction was still running and had not committed when the view was created. The change is **invisible**.
    *   Otherwise, the transaction committed before the view was created. The change is **visible**.

#### Reconstructing Historical Row States
If the visibility algorithm determines that a record version is **invisible**, InnoDB follows the rollback pointer `DB_ROLL_PTR` to locate the corresponding undo log block. It reconstructs the previous version of the row, retrieves its `DB_TRX_ID`, and runs the visibility evaluation again.

This recursive reconstruction continues down the undo log chain until a visible version of the row is located. If it reaches the end of the undo chain (meaning the row did not exist yet when the `ReadView` was created), the record is treated as non-existent (filtered out of the query result).

```plantuml
struct trx_t {
  trx_id_t id
  trx_state_t state
  ReadView *read_view
  ut_list_node trx_list
  trx_lock_t lock
  isolation_level_t isolation_level
  THD *mysql_thd
  undo_no_t undo_no
  trx_savept_t last_sql_stat_start
  trx_rsegs_t rsegs
  trx_mod_tables_t mod_tables
}

struct trx_rsegs_t {
  trx_undo_ptr_t m_redo
  trx_undo_ptr_t m_noredo
}

struct trx_undo_ptr_t {
  trx_rseg_t *rseg
  trx_undo_t *insert_undo
  trx_undo_t *update_undo
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
trx_t *-- trx_rsegs_t : rsegs
trx_rsegs_t *-- trx_undo_ptr_t : m_redo
trx_undo_ptr_t o-- trx_undo_t : update_undo
trx_sys_t -> trx_t


```

---

## 5. End-to-End SQL Write Lifecycle

To see how InnoDB coordinates clustered indexes, secondary indexes, undo logs, redo logs, and the Buffer Pool in a single unified flow, let’s trace the execution of a concrete SQL query:

```sql
UPDATE employees SET salary = 75000 WHERE name = 'Charlie';
```

When this statement is processed under transaction `Tx 202`, InnoDB coordinates across its subcomponents through the following step-by-step lifecycle:

```text
 1. Index Lookup ──> 2. Bookmark Lookup ──> 3. Create Undo Record ──> 4. Redo Log (WAL)
 (Name='Charlie')     (Get ID=10 Row)        (Save Salary=70000)      (Log modifications)
                                                                             │
 8. Async Flush   <── 7. Commit & Redo  <── 6. Modify Memory  <── 5. Lock & Update view
 (Checkpoint LSN)      (ib_logfile Write)   (Mark page Dirty)         (DB_TRX_ID, ROLL_PTR)
```

1.  **Secondary Index Lookup**:
    *   The optimizer recognizes that `name` has a secondary index. InnoDB traverses the secondary B+ Tree index on `name` for `'Charlie'`.
    *   It finds the secondary index leaf entry containing the key value `'Charlie'` and retrieves the primary key value: **`ID = 10`**.
2.  **Clustered Index Bookmark Lookup**:
    *   Using `ID = 10`, InnoDB queries its **Clustered Index**. It traverses the main table B+ Tree to find the leaf page holding the actual row record for `ID = 10`.
    *   If the target leaf page is not in the **Buffer Pool** memory, it issues a synchronous disk read to load the page from the `.ibd` tablespace file, placing it inside the Buffer Pool LRU list.
3.  **Generate Undo Log Record (MVCC Setup)**:
    *   Before updating the row, InnoDB must back up the current state of the row. It constructs an **Undo Log Record** containing the column state to be overwritten (`Salary = 70000`).
    *   It writes this record to the Undo log buffer/tablespace at page offset `0x7f03`.
4.  **Write Redo Log (Write-Ahead Logging)**:
    *   InnoDB writes a physical **Redo Log record** to the **Log Buffer** in memory, describing the exact byte modifications about to be made on the physical Clustered index leaf page (securing Durability).
5.  **Modify Record Inline (Buffer Pool Update)**:
    *   In the Buffer Pool memory, InnoDB updates the record's user column: **`Salary = 75000`**.
    *   It updates the record's hidden metadata columns:
        *   Sets **`DB_TRX_ID = 202`** (flagging this active transaction).
        *   Sets **`DB_ROLL_PTR = 0x7f03`** (linking the active record to the Undo Log version chain).
    *   The leaf page is now flagged as **Dirty** and linked to the Buffer Pool **Flush List**.
6.  **Transaction Commit & Redo Flush**:
    *   When the client issues `COMMIT`, the SQL layer executes the two-phase commit.
    *   Under Phase 2, the **Log Buffer** contents representing the page write are flushed and synchronized to disk `ib_logfile0` or `ib_logfile1` (governed by `innodb_flush_log_at_trx_commit = 1`), advancing the **`Write LSN`**. The transaction is now legally durable.
7.  **Asynchronous Dirty Page Flushing (Page Sync)**:
    *   Later, an asynchronous InnoDB background thread sweeps the **Flush List**. It writes the dirty page containing `Salary = 75000` to the physical `.ibd` file on disk.
    *   Once the dirty page is safely flushed, InnoDB pushes the **`Checkpoint LSN`** forward in the Redo circular ring, reclaiming that log sector as overwriteable **Free Space**.
