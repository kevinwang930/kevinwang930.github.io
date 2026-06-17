---
title: "MySQL query Internals - Volcano model"
date: 2026-06-17T19:06:44+02:00
categories:
- data
- db
- mysql
tags:
- data
- db
- mysql
keywords:
- MySQL
#thumbnailImage: //example.com/image.jpg
---

For many years, MySQL executed SQL queries using a deeply nested, monolithic executor loop. Functions like `JOIN::exec()` and `evaluate_join_record()` were responsible for traversing tables, checking search conditions, handling joins, and aggregating results. While functional, this monolithic architecture was notoriously difficult to maintain, optimize, or extend.

In MySQL 8.0, the engineering team undertook a massive architectural refactoring: **migrating the query execution engine to the Volcano Iterator Model** (also known as the Pipeline or Iterator Model, pioneered by Goetz Graefe in 1994).

In this post, we will explore the architecture and implementation of MySQL’s Volcano Iterator Model, look at how the query execution tree is built, and trace a concrete SQL query down to the C++ source code level.
<!--more-->



## 1. The Volcano Iterator Architecture

The core philosophy of the Volcano model is **composability**. Instead of one monolithic function doing everything, execution is split into a tree of highly specialized, modular **Iterators**. 

Each iterator represents a single physical execution step (e.g., scanning a table, filtering rows, performing a join, or sorting). Iterators are stacked in a parent-child relationship. The parent iterator pulls rows from its child iterators, processes them, and passes them up to its parent.

### The RowIterator Base Class (`sql/iterators/row_iterator.h`)

Every execution iterator in modern MySQL inherits from the abstract base class `RowIterator`. It defines a remarkably simple and elegant interface:

```cpp
class RowIterator {
 public:
  explicit RowIterator(THD *thd) : m_thd(thd) {}
  virtual ~RowIterator() = default;

  // Initialize or re-initialize the iterator (rewind or reposition)
  bool Init() {
    ++m_num_init_calls;
    return DoInit();
  }

  // Read a single row
  int Read() {
    const int error = DoRead();
    if (error == 0) {
      ++m_num_rows;
    } else if (error == -1) {
      ++m_num_full_reads;
    }
    return error;
  }

  virtual void SetNullRowFlag(bool is_null_row) = 0;
  virtual void UnlockRow() = 0;

 private:
  virtual bool DoInit() = 0; // Implemented by subclasses
  virtual int DoRead() = 0; // Implemented by subclasses
};
```

### Key Design Choice: Buffer-Centric Row Retrieval
In a pure Volcano model, `Read()` might return a `Row` object or a tuple. In MySQL, however, **`Read()` returns an integer error code (`0` for OK, `-1` for EOF, `1` for error)**. 

So, where is the row data?

To avoid expensive copying, allocation, and serialization overhead, MySQL uses a **buffer-centric design**. When `Read()` returns `0`, the row data is placed directly inside pre-allocated record buffers associated with the underlying tables (specifically, `table->record[0]`). Any parent iterator or expression-evaluation engine (e.g., a filter condition or projection) reads the columns directly from these in-place table buffers. This **zero-copy design** maximizes memory efficiency and cache friendliness.

---

## 2. From SQL Query to Iterator Tree: The Lifecycle of a Query

How does a raw SQL string like `SELECT ... FROM ... WHERE ...` transform into a nested structure of physical C++ iterators? MySQL executes this transition through four primary phases:

### Phase A: Parsing & Semantic Resolution (`sql/sql_parse.cc` & `sql/sql_lex.cc`)
1. **The Parsing Step:** The SQL string enters the parser, which is driven by a Bison-generated parser engine (`sql/sql_yacc.yy`). The parser builds an Abstract Syntax Tree (AST).
2. **The Resolution Step:** The resolver walks the AST to perform name resolution (checking table names and column names) and semantic checks (verifying types and rules like `ONLY_FULL_GROUP_BY`). It groups fields and expressions into a tree of `Item` expressions and `Query_block` scopes.

### Phase B: Logical & Physical Optimization (`sql/sql_optimizer.cc`)
Once the AST is resolved, the Query Optimizer (`JOIN::optimize()`) takes over:
1. It analyzes table access order (using dynamic programming or hypergraph-based partitioning).
2. It evaluates index opportunities and estimates the execution costs for different access paths.
3. Instead of outputting the final iterator tree directly, the optimizer outputs an intermediate, highly descriptive representation of the execution plan called **`AccessPath`** (defined in `sql/join_optimizer/access_path.h`). Examples of Access Paths are `AccessPath::TABLE_SCAN`, `AccessPath::FILTER`, and `AccessPath::NESTED_LOOP_JOIN`.

### Phase C: Compiling the Access Path to the Iterator Tree (`sql/join_optimizer/access_path.cc`)
This is the bridge between optimization and physical execution. The function **`CreateIteratorFromAccessPath()`** is responsible for compiling the `AccessPath` graph into concrete physical `RowIterator` subclasses.

#### The Stack-Based Compilation Pattern
Because query plans can be deeply nested (e.g., joining dozens of tables), a naive recursive compilation of the `AccessPath` could result in a massive C++ stack frame and trigger a stack overflow. 
To prevent this, MySQL's `CreateIteratorFromAccessPath()` compiles the plan using a **MEM_ROOT-backed stack (a manual `todo` stack)**:

```cpp
unique_ptr_destroy_only<RowIterator> CreateIteratorFromAccessPath(
    THD *thd, MEM_ROOT *mem_root, AccessPath *top_path, JOIN *top_join,
    bool top_eligible_for_batch_mode) {
  
  unique_ptr_destroy_only<RowIterator> ret;
  Mem_root_array<IteratorToBeCreated> todo(mem_root);
  todo.push_back({top_path, top_join, top_eligible_for_batch_mode, &ret, {}});

  while (!todo.empty()) {
    IteratorToBeCreated job = todo.back();
    todo.pop_back();

    AccessPath *path = job.path;
    unique_ptr_destroy_only<RowIterator> iterator;
    // ...

    switch (path->type) {
      case AccessPath::TABLE_SCAN: {
        const auto &param = path->table_scan();
        iterator = NewIterator<TableScanIterator>(thd, mem_root, param.table, ...);
        break;
      }
      case AccessPath::FILTER: {
        // ... pushes child jobs onto stack first, then compiles FilterIterator ...
        iterator = NewIterator<FilterIterator>(thd, mem_root, std::move(child_iterator), path->filter().condition);
        break;
      }
      case AccessPath::NESTED_LOOP_JOIN: {
        iterator = NewIterator<NestedLoopIterator>(thd, mem_root, std::move(outer_iterator), std::move(inner_iterator), ...);
        break;
      }
      // Over 40 physical paths mapped here...
    }
    // ...
  }
  return ret; // Returns the single, fully nested root RowIterator
}
```

By mapping `AccessPath` node types directly to iterator class templates via `NewIterator<T>()`, this phase outputs a single, nested C++ execution tree. The root iterator recursively owns all its child iterators, meaning reclaiming memory at the end of the query is as simple as letting the root iterator's `unique_ptr` go out of scope.

### Phase D: Physical Execution
The executor calls `Init()` once on the root `RowIterator` (propagating down to all leaves), and then enters a loop invoking `Read()` until it returns `-1` (EOF) or an error occurs.

---

## 3. A Concrete Query & Its Iterator Tree

To see how these iterators compose together, let's analyze a standard query:

```sql
SELECT employees.name, departments.name 
FROM employees 
JOIN departments ON employees.department_id = departments.id
WHERE employees.salary > 50000
LIMIT 10;
```

When MySQL runs this query, the optimizer generates an **Access Path** tree, which is compiled into the following **RowIterator** tree:

```text
               [ LimitOffsetIterator ]  <-- (Root) Enforces LIMIT 10
                         │
                 [ FilterIterator ]     <-- Filters WHERE salary > 50000
                         │
               [ NestedLoopIterator ]   <-- Executes the INNER JOIN
                /                  \
   [ TableScanIterator ]    [ IndexLookupIterator ]
     (employees: Outer)       (departments: Inner, on PK 'id')
```

### The Pull-Based Execution Loop
Query execution is completely **pull-based** (or demand-driven). The root iterator initiates execution, and the client pulls rows from the top of the tree:

1. The client calls `Read()` on the `LimitOffsetIterator`.
2. `LimitOffsetIterator` calls `Read()` on its child, the `FilterIterator`.
3. `FilterIterator` calls `Read()` on its child, the `NestedLoopIterator`.
4. `NestedLoopIterator` reads a row from the outer `TableScanIterator` (`employees`), then uses the `department_id` to query the inner `IndexLookupIterator` (`departments`).
5. Once a joined row is found, it is evaluated by `FilterIterator`. If the salary condition is met, the row is returned to `LimitOffsetIterator`.
6. This continues until `LimitOffsetIterator` has yielded 10 rows, at which point it returns `-1` (EOF), stopping the entire pipeline early.

---

## 4. Dissecting the Source Code

Let's look at the actual C++ implementations of two core composite iterators to see how this pipeline operates in the MySQL source code.

### A. The Filter Iterator (`FilterIterator::DoRead`)
* **Location:** `sql/iterators/composite_iterators.cc`

The `FilterIterator` is a passive pass-through node that evaluates a `WHERE` or `HAVING` condition.

```cpp
int FilterIterator::DoRead() {
  for (;;) {
    // 1. Pull a row from the child source iterator
    int err = m_source->Read();
    if (err != 0) return err; // If EOF (-1) or error (1), propagate up immediately

    // 2. Evaluate the WHERE condition on the current table buffer values
    bool matched = m_condition->val_int();

    if (thd()->killed) {
      thd()->send_kill_message();
      return 1;
    }

    /* Check for errors during evaluation of the condition */
    if (thd()->is_error()) return 1;

    // 3. If the row doesn't match the condition, unlock and continue pulling
    if (!matched) {
      m_source->UnlockRow();
      continue;
    }

    // 4. Row matched! Return success (0). The table buffers contain the valid row.
    return 0;
  }
}
```

### B. The Nested Loop Join Iterator (`NestedLoopIterator::DoRead`)
* **Location:** `sql/iterators/composite_iterators.cc`

The `NestedLoopIterator` joins two iterators. It operates as a state machine with states like `NEEDS_OUTER_ROW`, `READING_FIRST_INNER_ROW`, `READING_INNER_ROWS`, and `END_OF_ROWS`.

```cpp
int NestedLoopIterator::DoRead() {
  if (m_state == END_OF_ROWS) {
    return -1;
  }

  for (;;) {
    if (m_state == NEEDS_OUTER_ROW) {
      // 1. Fetch a row from the outer iterator (e.g., TableScanIterator on employees)
      int err = m_source_outer->Read();
      if (err == 1) return 1;    // Propagate error
      if (err == -1) {
        m_state = END_OF_ROWS;
        return -1;               // No more outer rows; we are finished!
      }

      // 2. Prepare the inner iterator for a new scan using the current outer row values
      m_source_inner->SetNullRowFlag(false);
      if (m_source_inner->Init()) {
        return 1;
      }
      m_state = READING_FIRST_INNER_ROW;
    }

    // 3. Fetch a matching row from the inner iterator (e.g., IndexLookupIterator on departments)
    int err = m_source_inner->Read();
    if (err == 1) return 1;      // Propagate error

    if (err == -1) {
      // Out of inner rows for the current outer row.
      // If this is an OUTER join and no inner row matched, return a null-complemented row
      if (m_join_type == JoinType::OUTER && m_state == READING_FIRST_INNER_ROW) {
        m_source_inner->SetNullRowFlag(true);
        m_state = NEEDS_OUTER_ROW; // Next call will read a new outer row
        return 0;                  // Return the null-complemented row
      }
      
      // Otherwise, go back and fetch a new outer row
      m_state = NEEDS_OUTER_ROW;
      continue;
    }

    // 4. A matching inner row has been found! 
    // If it's a Semi-join, we only need the first match, so reset state to NEEDS_OUTER_ROW
    if (m_join_type == JoinType::SEMI) {
      m_state = NEEDS_OUTER_ROW;
    } else {
      m_state = READING_INNER_ROWS; // Regular joins continue scanning the inner iterator
    }
    return 0; // Return success! Table buffers for both tables contain the joined columns
  }
}
```

---

## 5. Key Advantages of the Iterator Design

By migrating query execution from a monolithic engine to this modular Volcano model, MySQL realized several game-changing benefits:

1. **Flawless Composability:** Adding new features is as simple as writing a new iterator. For example, when Hash Joins were introduced in MySQL 8.0.18, they were implemented entirely as a self-contained `HashJoinIterator`, with zero modifications needed to the existing query execution loop.
2. **Simple early-termination**: Operators like `LimitOffsetIterator` can stop pulling rows simply by returning `-1`, which cleanly short-circuits execution and avoids scanning any extra records.
3. **Painless EXPLAIN ANALYZE**: Because every operator is a class wrapper around child iterators, MySQL can wrap any standard iterator inside a `TimingIterator`. This timing decorator automatically records the number of loops, rows processed, and exact execution times at each node of the tree, providing highly granular runtime profiles for `EXPLAIN ANALYZE`.

## Summary of Core MySQL Iterators

Here's a quick map of some of the most common physical operators you'll encounter in `EXPLAIN` and the modern C++ iterators that power them under the hood:

| SQL Operator / Plan | MySQL Access Path | Underlying C++ Iterator Class |
| :--- | :--- | :--- |
| **Table Scan** | `TABLE_SCAN` | `TableScanIterator` |
| **Index Scan / Range Scan** | `INDEX_SCAN` / `INDEX_RANGE_SCAN` | `IndexScanIterator` / `IndexRangeScanIterator` |
| **Index Lookup** | `EQ_REF` / `REF` | `EQRefIterator` / `RefIterator` |
| **Filter (WHERE/HAVING)** | `FILTER` | `FilterIterator` |
| **LIMIT / OFFSET** | `LIMIT_OFFSET` | `LimitOffsetIterator` |
| **Nested Loop Join** | `NESTED_LOOP_JOIN` | `NestedLoopIterator` |
| **Hash Join** | `HASH_JOIN` | `HashJoinIterator` |
| **Materialization** | `MATERIALIZE` | `MaterializeIterator` |
| **Sorting (ORDER BY)** | `SORT` | `SortingIterator` |

---

The Volcano Iterator Model is one of the most significant engineering achievements in modern MySQL history, transforming a legacy execution engine into an elegant, highly modular, and blazing-fast query processor.
