---
title: "MySQL query internals- Group By"
date: 2026-06-16T22:58:03+02:00
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

Grouping and aggregation are cornerstones of relational databases. In MySQL, executing a `GROUP BY` statement involves a sophisticated dance between the query optimizer and the execution engine. With the introduction of the **Volcano Iterator Model** in modern MySQL (8.0+), this process has become highly modular, structured as a tree of self-contained iterators.

In this post, we'll take a deep dive into the source code level of MySQL's `GROUP BY` execution. We'll start with the general flow and then dissect each major optimization and execution strategy with concrete SQL examples.
<!--more-->



---

## The General Flow of GROUP BY

Whenever you execute a query containing a `GROUP BY` clause, MySQL processes it through three main logical phases:

1. **The Parsing and Resolution Phase (`sql/sql_resolver.cc`):**
   The parser constructs a syntax tree, and the resolver validates that all fields in the `GROUP BY` clause and `SELECT` list are valid and semantic (checking against rules like `ONLY_FULL_GROUP_BY`).
2. **The Optimization Phase (`sql/sql_optimizer.cc`):**
   This is where the magic happens. The optimizer determines whether the data needs to be sorted, whether an index can be used to skip sorting, or whether an internal temporary table must be created. It produces an execution plan represented as an **Access Path**.
3. **The Execution Phase (`sql/iterators/`):**
   The executor compiles the Access Path into a tree of physical **Iterators**. The query is executed by calling `Init()` once and then repeatedly invoking `Read()` on the root iterator, which pulls rows from child iterators, aggregates them, and streams results back to the client.

Let's look at the specific optimization and execution types MySQL employs.

---

## 1. Streaming Aggregation (`AggregateIterator`)

### The Concept
When the input data stream is already sorted by the grouping columns, MySQL can aggregate rows **on-the-fly**. It reads rows sequentially and holds the running totals for the "current" group. The moment it detects a change in the grouping columns, it outputs the aggregated row for the completed group, resets the aggregate functions, and begins the next group. This is highly memory-efficient because MySQL only needs to hold a single group's state in memory.

### SQL Example & Plan
Imagine we have an `employees` table with an index on `department_id`:
```sql
CREATE TABLE employees (
    id INT PRIMARY KEY,
    department_id INT,
    salary DECIMAL(10,2),
    KEY idx_dept (department_id)
);

-- Query:
SELECT department_id, COUNT(*), SUM(salary)
FROM employees
GROUP BY department_id;
```
Because of `idx_dept`, the index scan returns rows already sorted by `department_id`. 
* **Optimizer decision:** The optimizer (`JOIN::test_skip_sort()`) detects that sorting can be bypassed. It sets `m_ordered_index_usage = ORDERED_INDEX_GROUP_BY`.
* **Access Path:** `AccessPath::AGGREGATE`
* **Execution Iterator:** `AggregateIterator`

### Code-Level Implementation (`sql/iterators/composite_iterators.cc`)
Inside the `AggregateIterator::DoRead()` method:
1. **Initialize the Group:** On the very first read, it fetches the first row and caches the grouping fields:
   ```cpp
   int err = m_source->Read();
   // ...
   (void)update_item_cache_if_changed(m_join->group_fields);
   ```
2. **Sequential Scan & Accumulate:** It loops to read subsequent rows. If the grouping fields haven't changed, it updates the aggregate functions:
   ```cpp
   for (;;) {
       int err = m_source->Read();
       // ...
       int first_changed_idx = update_item_cache_if_changed(m_join->group_fields);
       if (first_changed_idx >= 0) {
           // Group has changed!
           StoreFromTableBuffers(m_tables, &m_first_row_next_group);
           LoadIntoTableBuffers(m_tables, m_first_row_this_group.ptr());
           m_state = LAST_ROW_STARTED_NEW_GROUP;
           return 0; // Return current aggregated row to caller
       }
       // Accumulate aggregates
       for (Item_sum **item = m_join->sum_funcs; *item != nullptr; ++item) {
           (*item)->aggregator_add();
       }
   }
   ```

---

## 2. Hash / Temporary Table Aggregation (`TemptableAggregateIterator`)

### The Concept
If the input data is unsorted and no suitable index is available to skip sorting, MySQL must group the rows using an internal **Temporary Table**. This functions as a **Hash Aggregation** strategy. MySQL reads rows from the source and uses the `GROUP BY` column values as a unique key (or hash key) in a temporary table. If the group key already exists, it updates the aggregates in-place; if not, it inserts a new group row.

### SQL Example & Plan
Suppose we want to group by a column without any index:
```sql
SELECT country, COUNT(*)
FROM orders
GROUP BY country; -- Assuming 'country' is not indexed
```
* **Optimizer decision:** Since the stream is unsorted, the optimizer elects to materialize the results into a temporary table.
* **Access Path:** `AccessPath::TEMPTABLE_AGGREGATE`
* **Execution Iterator:** `TemptableAggregateIterator`

### Code-Level Implementation (`sql/iterators/composite_iterators.cc`)
During initialization (`DoInit()`), `TemptableAggregateIterator` executes the entire aggregation pipeline before returning any rows:
1. **Create Temporary Table:** Instantiates an in-memory temporary table with a unique index/hash key on the grouping column (`country`).
2. **Read & Check Group Existence:**
   ```cpp
   for (;;) {
       int read_error = m_subquery_iterator->Read();
       if (read_error < 0) break; // EOF
       
       bool group_found = !table()->file->ha_index_read_map(
           table()->record[1], key, HA_WHOLE_KEY, HA_READ_KEY_EXACT);
       
       if (group_found) {
           // Update existing row
           restore_record(table(), record[1]);
           update_tmptable_sum_func(m_join->sum_funcs, table());
           table()->file->ha_update_row(table()->record[1], table()->record[0]);
       } else {
           // Insert new row
           init_tmptable_sum_functions(m_join->sum_funcs);
           table()->file->ha_write_row(table()->record[0]);
       }
   }
   ```
3. **In-Memory to Disk Promotion:** If the in-memory temporary table size exceeds the `tmp_table_size` or `max_heap_table_size` system variables, it throws `HA_ERR_RECORD_FILE_FULL`. MySQL dynamically calls `move_table_to_disk()`, converts the heap table into an on-disk InnoDB table, and resumes execution.
4. **Stream Results:** Once all source records are processed and aggregated into the temporary table, subsequent calls to `Read()` simply scan the temporary table sequentially (`m_table_iterator`) to return the results.

---

## 3. Loose Index Scan (`GroupIndexSkipScanIterator`)

### The Concept
A **Loose Index Scan** (internally called Group Index Skip Scan) is the most efficient aggregation strategy. It is used when an index can be used to read only a fraction of the rows. Instead of scanning every single row in a group, MySQL leverages the B-Tree index structure to **jump (skip)** directly to the first or last key of each group. This is exceptionally fast for queries like `MIN()` or `MAX()`.

### SQL Example & Plan
Consider a composite index on `(department_id, salary)`:
```sql
CREATE TABLE employees (
    id INT PRIMARY KEY,
    department_id INT,
    salary DECIMAL(10,2),
    KEY idx_dept_sal (department_id, salary)
);

-- Query:
SELECT department_id, MIN(salary)
FROM employees
GROUP BY department_id;
```
* **Optimizer decision:** The optimizer (`get_best_group_skip_scan()`) recognizes that it only needs the minimum salary for each department. Rather than scanning all employee rows under each department, it can jump to the first entry of each `department_id` in the B-Tree.
* **Access Path:** `AccessPath::GROUP_INDEX_SKIP_SCAN`
* **Execution Iterator:** `GroupIndexSkipScanIterator`

### Code-Level Implementation (`sql/range_optimizer/group_index_skip_scan.cc`)
Instead of reading all matching rows and aggregating them in a separate iterator, the `GroupIndexSkipScanIterator` handles both navigation and aggregation within its read loop:
1. It requests the storage engine to fetch the first unique prefix (`department_id`).
2. It fetches the corresponding first record (which is automatically the `MIN(salary)` due to the index sorting order).
3. It then asks the storage engine to skip all remaining keys for that `department_id` and position the cursor on the next unique department key using key-skipping index APIs.
4. This completely avoids temporary tables, sorting, and scanning most index pages.

---

## 4. Temporary Table + Filesort (`SortingIterator` -> `AggregateIterator`)

### The Concept
When the optimizer decides that creating a hash-based temporary table is too expensive (e.g., due to high cardinality or size limits), or when the query explicitly requires sorted output that cannot be satisfied by an index, MySQL fallback to a hybrid approach: **Materialization followed by Filesort**. It first copies/materializes the raw rows into a temporary table, runs a `filesort` on the grouping columns, and then streams the sorted temporary table through the `AggregateIterator`.

### SQL Example & Plan
```sql
SELECT country, SUM(sales)
FROM orders
GROUP BY country
ORDER BY country; -- Force sorted output on non-indexed column
```
* **Optimizer decision:** To satisfy both the grouping and sorting on a non-indexed column, the optimizer chooses to materialize, sort, and then aggregate.
* **Access Path:** `AccessPath::FILESORT` wrapping `AccessPath::AGGREGATE`
* **Execution Iterator:** `SortingIterator` acting as the source of `AggregateIterator`.

---

## Summary of MySQL GROUP BY Execution Strategies

Below is a cheat sheet mapping MySQL's physical execution choices to their internal C++ iterators:

| Optimization Strategy | Access Path Type | Key Iterator Class | Performance Profile |
| :--- | :--- | :--- | :--- |
| **Loose Index Scan** | `GROUP_INDEX_SKIP_SCAN` | `GroupIndexSkipScanIterator` | **O(Number of Groups)**. Best efficiency; skips irrelevant rows. |
| **Streaming Aggregation** | `AGGREGATE` | `AggregateIterator` | **O(N)** space-wise O(1). Fast, low memory footprint. |
| **Hash Aggregation** | `TEMPTABLE_AGGREGATE` | `TemptableAggregateIterator` | **O(N)** space-wise O(Groups). Moderate; uses in-memory or disk temp tables. |
| **Filesort + Group** | `FILESORT` -> `AGGREGATE` | `SortingIterator` -> `AggregateIterator` | **O(N log N)**. Used when explicit sorting is needed on unsorted data. |

By separating these execution profiles into dedicated, modular iterator classes, modern MySQL ensures that queries are executed with the leanest memory footprint and optimal storage engine access patterns.
