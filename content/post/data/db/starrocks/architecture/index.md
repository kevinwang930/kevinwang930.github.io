---
title: "StarRocks: FE query planning and the MPP path"
date: 2026-08-22T15:00:00+02:00
categories:
- data
- db
- starrocks
tags:
- data
- db
- starrocks
keywords:
- starrocks
- mpp
#thumbnailImage: //example.com/image.jpg
---
**StarRocks** is a MySQL-compatible MPP OLAP engine. A cluster is **Frontend (FE)** nodes for metadata and query coordination plus **Backend (BE)** or **Compute Node (CN)** workers for execution. This post follows **FE query planning**—logical plan, Cascades optimize, fragmentize—and the **MPP** path through schedule, deploy, and result pull. Worker process internals are in [Backend and Compute Node](../backend/).
<!--more-->

Related: [Backend and Compute Node](../backend/).

---

## 1. Overview

StarRocks speaks the **MySQL protocol** and ANSI SQL. Clients connect to any FE; the **leader FE** owns metadata writes and schedules work onto compute nodes. **MPP** is the fundamental character of OLAP: a statement is a large **computation** over sharded tablets, so it must run as parallel stages on many workers. The FE that accepts SQL does **not** execute operators.

| Piece | Language | Role in the cluster |
|-------|----------|---------------------|
| **FE** | Java | Catalog, SQL plan, **Coordinator**, tablet/replica scheduling |
| **BE** | C++ | Local OLAP storage + vectorized execution (shared-nothing) |
| **CN** | C++ (same binary as BE) | Compute + cache; data on object storage (shared-data) |

Deployment mode is fixed at cluster init via **`Config.run_mode`**, detected in **`RunMode.detectRunMode()`**:

| Mode | Compute nodes | Storage |
|------|---------------|---------|
| **`shared_nothing`** | **Backend** with local disks | **`LocalTablet`** replicas on BEs |
| **`shared_data`** | **ComputeNode** (`starrocks_be --cn`) | **`LakeTablet`** segments on S3/HDFS/MinIO; StarOS manages shards |

There is no external metadata service: FE metadata is replicated with **BDB JE**, and tablet placement lives in the FE catalog. How a BE/CN process starts, stores tablets, and runs the pipeline engine is covered in [Backend and Compute Node](../backend/).

![StarRocks cluster topology](images/starrocks-cluster-topology.svg)

---

## 2. Cluster topology

StarRocks keeps the surface small: **FE + BE** (shared-nothing) or **FE + CN + object storage** (shared-data). Nodes scale horizontally; FE metadata and data replicas have internal redundancy.

**Clients** send SQL to any FE (typically via a load balancer). **FEs** form an HA group:

| FE role (`FrontendNodeType`) | Metadata | Leader election |
|------------------------------|----------|-----------------|
| **Leader** | Read/write; replicates journal to followers | Elected from followers (> half alive) |
| **Follower** | Read; replays leader journal | Participates in election |
| **Observer** | Read; replays journal | Does **not** vote — scales read/metadata fan-out |

Each FE holds a full in-memory catalog copy backed by **BDB JE** (Berkeley DB Java Edition). Metadata writes go to the leader and must replicate to a quorum of followers before they are considered durable.

**Compute registration.** BEs and CNs heartbeat to the **leader FE** over Thrift **`HeartbeatService`**, reporting ports (`be_port`, `brpc_port`, `starlet_port`), disk capacity, and liveness. **`SystemInfoService`** tracks **`Backend`** and **`ComputeNode`** instances; **`HeartbeatMgr`** drives the heartbeat loop. Worker-side heartbeat and service ports are detailed in [Backend and Compute Node](../backend/).

**Tablets as placement units.** OLAP tables are partitioned; each partition holds one or more **tablets** (the unit of sharding and replication). In shared-nothing, each **`LocalTablet`** has **`Replica`** objects on BEs; the FE **`TabletScheduler`** repairs and balances them. In shared-data, **`LakeTablet`** maps to a StarOS shard and object-storage segments. The Coordinator uses that placement map when assigning scan **`FragmentInstance`**s—worker storage layout is in the [Backend](../backend/) post.

### 2.1 Frontend (FE)

The FE process entry is **`StarRocksFE`** → **`StarRocksFEServer`**. **`GlobalStateMgr`** is the central singleton: it wires catalog, node registry, load/transaction managers, and HA state.

| Subsystem | Responsibility |
|-----------|----------------|
| **`CatalogMgr` / `InternalCatalog`** | Databases, tables, partitions, materialized views |
| **`NodeMgr` / `SystemInfoService`** | FE and BE/CN membership |
| **`TabletInvertedIndex`, `TabletScheduler`** | Tablet health, replica repair, balance |
| **SQL engine** (`sql/`, `planner/`, optimizer) | Parse, analyze, CBO, physical **`PlanFragment`** generation |
| **`Coordinator`** | Deploy fragments to BE/CN, collect status, return results |
| **`QeService`** | MySQL wire protocol to clients |

**FE composition.** **`StarRocksFEServer`** bootstraps **`GlobalStateMgr`** and network services. The singleton owns catalog and node registries, tablet scheduling, and the metadata journal; **`QeService`** accepts MySQL sessions and drives **`Coordinator`** instances per query.

```plantuml
@startuml

class StarRocksFEServer {
  main()
  initialize()
  start()
}

class GlobalStateMgr {
  getCurrentState()
  initialize()
  waitForReady()
}

class CatalogMgr {
  catalogs : external Catalog map
}

class LocalMetastore {
  databases
  tables
  partitions
}

class NodeMgr {
  frontends : FE membership
}

class Frontend {
  nodeType : LEADER/FOLLOWER/OBSERVER
}

class SystemInfoService {
  backends : Backend map
  computeNodes : ComputeNode map
}

class HeartbeatMgr {
  heartbeatLoop()
}

class TabletInvertedIndex {
  tabletId to replica map
}

class TabletScheduler {
  schedule()
  balance()
}

class TabletChecker {
  check()
}

class EditLog {
  logEdit()
  loadJournal()
}

interface Journal {
  write()
  read()
}

class BDBJEJournal {
  replicate()
}

class BDBEnvironment {
  bdbEnv : replicated JE
}

class JournalWriter {
  writeQueue()
}

class QeService {
  mysqlPort
}

class ConnectScheduler {
  connectionMap
}

class ConnectContext {
  session state
}

class Coordinator {
  exec()
  deployFragments()
}

class StarMgrServer {
  starOS metadata
}

StarRocksFEServer ..> GlobalStateMgr
StarRocksFEServer ..> QeService
StarRocksFEServer ..> StarMgrServer

GlobalStateMgr *-- CatalogMgr
GlobalStateMgr *-- LocalMetastore
GlobalStateMgr *-- NodeMgr
GlobalStateMgr *-- HeartbeatMgr
GlobalStateMgr *-- TabletInvertedIndex
GlobalStateMgr *-- TabletScheduler
GlobalStateMgr *-- TabletChecker
GlobalStateMgr *-- EditLog
GlobalStateMgr o-- JournalWriter

NodeMgr *-- SystemInfoService
NodeMgr o-- Frontend

EditLog --> Journal
Journal <|-- BDBJEJournal
BDBJEJournal *-- BDBEnvironment

QeService *-- ConnectScheduler
ConnectScheduler o-- ConnectContext
ConnectContext ..> Coordinator

TabletChecker --> TabletScheduler
TabletScheduler ..> TabletInvertedIndex
HeartbeatMgr ..> SystemInfoService
Coordinator ..> SystemInfoService

@enduml
```

On **shared-data** clusters the FE also starts **`StarMgrServer`** (StarOS metadata) alongside the BDB JE journal.

### 2.2 Metadata hierarchy: catalog, database, table

**StarRocks** names the product and the cluster. **`Database`** is not that product: it is a **catalog namespace** inside the cluster—the same idea as MySQL’s `CREATE DATABASE`—owned by the FE metastore and journaled through BDB JE.

The internal catalog (`default_catalog` / **`InternalCatalog`**) holds the objects load and query planning resolve:

```text
cluster
  └── catalog (InternalCatalog; optional external catalogs via CatalogMgr)
        └── database          -- Database, keyed by dbId / fullName
              └── table       -- OlapTable, …
                    └── partition
                          └── tablet → replica (shared-nothing) or LakeTablet shard (shared-data)
```

**`LocalMetastore`** keeps **`fullNameToDb`**: database name → **`Database`**. Each **`Database`** holds **`idToTable` / `nameToTable`**. Partitions and tablets hang under the table; **`TabletInvertedIndex`** indexes tablet → replica placement for scheduling. DDL that creates or drops any of these objects is a metadata write on the **leader FE**.

That hierarchy is what “database” means in the rest of the FE: **`DatabaseTransactionMgr`** is one map entry per catalog **`dbId`**, not one manager for the whole cluster. Concurrent load on different catalog databases only shares the global txn-id generator; label checks and the running-txn limit (**`max_running_txn_num_per_db`**, see §4) stay per **`Database`**. Session SQL resolves names as `catalog.database.table` (default catalog omitted when unqualified). The catalog database is a **metadata and load-admin** boundary, not a join performance domain: tablets still sit on the same BEs/CNs.

```plantuml
@startuml

class CatalogMgr {
  catalogs : Map
}

class InternalCatalog

class LocalMetastore {
  fullNameToDb : Map<String, Database>
}

class Database {
  id : long
  fullQualifiedName : String
  idToTable : Map<Long, Table>
  nameToTable : Map<String, Table>
}

abstract class Table

class OlapTable {
  partitions
  indexIdToMeta
}

class PhysicalPartition {
  tablets
}

class LocalTablet {
  replicas : List<Replica>
}

class LakeTablet {
  shardId
}

CatalogMgr o-- InternalCatalog
CatalogMgr ..> LocalMetastore
LocalMetastore *-- "N" Database : fullNameToDb
Database *-- "N" Table : idToTable
Table <|-- OlapTable
OlapTable *-- "N" PhysicalPartition : partitions
PhysicalPartition o-- LocalTablet
PhysicalPartition o-- LakeTablet

@enduml
```

### 2.3 FE ↔ worker protocols (query path)

| Direction | Protocol | Typical use |
|-----------|----------|-------------|
| Client → FE | MySQL | Interactive SQL, auth, result sets |
| BE/CN → FE leader | Thrift **`HeartbeatService`** | Registration, master info, run mode |
| BE → FE leader | Thrift **`FrontendService`** | `reportExecStatus`, task finish, load txn |
| FE leader → BE/CN | brpc **`PInternalService`** | **`exec_plan_fragment`**, **`transmit_chunk`**, runtime filters, tablet writer |
| FE leader → BE/CN | Thrift **`BackendService`** | Agent tasks, legacy sync APIs |
| BE ↔ BE | brpc | Shuffle exchange, broadcast filters |

The hot query path is **brpc/protobuf** on each node's **`brpc_port`**. Thrift remains for heartbeat, reporting, and tablet maintenance agents.

![StarRocks query path](images/starrocks-query-path.svg)

---

## 3. MPP: the OLAP execution model

**MPP (Massively Parallel Processing)** is the fundamental character of OLAP, not an optional accelerator. An analytical statement is a large **computation** over data that is already sharded into tablets. The only way to finish that computation at interactive latency is to run the same operators on **many machines at once** and move intermediate batches by **shuffle**—not to walk one operator tree in one process. StarRocks is built around that model: the FE plans and coordinates; BE/CN workers execute.

A stage is a **`PlanFragment`**: a **`PlanNode`** subtree that can run without an in-process call to another machine, plus a **`DataSink`**. An **edge** is the **Exchange** that connects two stages—the producer’s sink and the consumer’s **`ExchangeNode`**, carrying **`transmit_chunk`**. The **DAG** is those stages and edges: **`ExecPlan.fragments`** after **`visitPhysicalDistribution`** cuts the physical tree at every **`PhysicalDistributionOperator`**. The FE never joins those batches in its own heap.

That is the opposite of classic OLTP, where the cost is the **SQL transaction** (one node’s log and locks) and a distributed shuffle would make every small write a distributed commit.

| | OLTP | StarRocks MPP (OLAP) |
|--|------|----------------------|
| What the statement *is* | A transaction | A computation |
| Bottleneck | Commit, isolation, locks | Scan / join / agg CPU and IO |
| Plan shape | One local operator tree | **`PlanFragment`** DAG + **`FragmentInstance`**s |
| SQL endpoint | Executes | Plans, deploys, pulls the root |

A typical analytical plan is two-phase: scan stages, a join stage (often with a local aggregate), a merge-aggregate stage, and a root GATHER into **`ResultSink`**. Data flows along edges toward the root (fragment 0 in **`EXPLAIN`**). Each Exchange is not drawn by hand: **`QueryOptimizer`** CBO picks a **join distribution** (shuffle / broadcast / colocate) and an **aggregate distribution** (local then global), then **`EnforceAndCostTask`** inserts a **`PhysicalDistributionOperator`**. **`visitPhysicalDistribution`** cuts the fragment DAG at those operators.

![Fragment DAG: planning PlanFragments, then scheduling FragmentInstances](images/starrocks-mpp-fragment-dag.svg)

The left half of the figure is **planning**: **`ExecPlan.fragments`**, one **`PlanFragment`** per stage, Exchange edges from **`PhysicalDistributionOperator`**. The right half is **scheduling**: **`ExecutionDAG`** unfolds each stage into **`FragmentInstance`**s (tablet replicas on the scan side, hash buckets on join/agg). The same edge becomes a many-to-many **`transmit_chunk`**.

| DAG piece | Planning (`ExecPlan`) | Scheduling (`ExecutionDAG`) |
|-----------|----------------------|------------------------------|
| **Stage** | one **`PlanFragment`** (`planRoot`, `dataPartition`, `sink`) | N **`FragmentInstance`**s on BE/CN |
| **Edge** | producer **`DataSink`** → dest **`ExchangeNode`** | instance × instance **`transmit_chunk`** |
| **DAG** | fragment list after **`visitPhysicalDistribution`** | instances after **`computeFragmentInstances`** |

```plantuml
@startuml

class ConnectContext {
  queryId : UUID
  executionId : TUniqueId
  sessionVariable : SessionVariable
  mysqlChannel : MysqlChannel
  executor : StmtExecutor
  computeResource : ComputeResource
}

class ConnectProcessor {
  ctx : ConnectContext
  --
  dispatch()
  handleQuery()
}

class StmtExecutor {
  context : ConnectContext
  parsedStmt : StatementBase
  coord : Coordinator
  --
  execute()
  generateExecPlan()
  handleQueryStmt()
}

class StatementPlanner {
  --
  plan()
  createQueryPlan()
  analyzeStatement()
}

class Analyzer {
  --
  analyze()
}

class RelationTransformer {
  transformerContext : TransformerContext
  --
  transformWithSelectLimit()
}

class LogicalPlan {
  root : OptExpression
  outputColumn : List<ColumnRefOperator>
}

abstract class Optimizer {
  --
  optimize()
}

class QueryOptimizer {
  memo : Memo
  --
  optimize()
}

class OptExpression {
  op : Operator
  inputs : List<OptExpression>
  cost : double
  outputProperty : PhysicalPropertySet
}

class PlanFragmentBuilder {
  --
  createPhysicalPlan()
  finalizeFragments()
}

class PhysicalPlanTranslator {
  columnRefFactory : ColumnRefFactory
  --
  translate()
}

class ExecPlan {
  fragments : List<PlanFragment>
  scanNodes : List<ScanNode>
  descTbl : DescriptorTable
  outputExprs : List<Expr>
  physicalPlan : OptExpression
  connectContext : ConnectContext
}

class PlanFragment {
  fragmentId : PlanFragmentId
  planRoot : PlanNode
  dataPartition : DataPartition
  outputPartition : DataPartition
  sink : DataSink
  destNode : ExchangeNode
  pipelineDop : int
}

abstract class PlanNode {
  id : PlanNodeId
  fragmentId : PlanFragmentId
  conjuncts : List<Expr>
  limit : long
  fragment_ : PlanFragment
}

class ExchangeNode {
  partitionType : TPartitionType
}

abstract class DataSink {
  --
  toThrift()
}

class ResultSink {
  sinkType : TResultSinkType
  exchNodeId : PlanNodeId
  outputColumnNames : List<String>
}

abstract class Coordinator {
  --
  execWithQueryDeployExecutor()
}

class DefaultCoordinator {
  jobSpec : JobSpec
  executionDAG : ExecutionDAG
  connectContext : ConnectContext
  coordinatorPreprocessor : CoordinatorPreprocessor
  receiver : ResultReceiver
  queryStatus : Status
  --
  prepareExec()
  getNext()
}

class CoordinatorPreprocessor {
  executionDAG : ExecutionDAG
  connectContext : ConnectContext
  jobSpec : JobSpec
  workerProviderFactory : WorkerProvider.Factory
  --
  computeFragmentInstances()
}

class ExecutionDAG {
  fragments : List<ExecutionFragment>
  instanceIdToInstance : Map<TUniqueId, FragmentInstance>
  jobSpec : JobSpec
}

class ExecutionFragment {
  planFragment : PlanFragment
  instances : List<FragmentInstance>
  scanRangeAssignment : FragmentScanRangeAssignment
  destinations : List<TPlanFragmentDestination>
}

class FragmentInstance {
  instanceId : TUniqueId
  worker : ComputeNode
  execFragment : ExecutionFragment
  node2ScanRanges : Map<Integer, List<TScanRangeParams>>
  pipelineDop : int
  execution : FragmentInstanceExecState
}

class Deployer {
  executionDAG : ExecutionDAG
  jobSpec : JobSpec
  context : ConnectContext
  deployedWorkerIds : Set<Long>
  --
  deployFragments()
}

class FragmentInstanceExecState {
  instanceId : TUniqueId
  fragmentId : PlanFragmentId
  worker : ComputeNode
  address : TNetworkAddress
  requestToDeploy : TExecPlanFragmentParams
  deployFuture : Future<PExecPlanFragmentResult>
  state : State
  --
  deployAsync()
}

class BackendServiceClient {
  --
  execPlanFragmentAsync()
  fetchDataAsync()
}

class ResultReceiver {
  address : TNetworkAddress
  finstId : PUniqueId
  backendId : Long
  packetIdx : long
  timeoutMs : int
  isDone : boolean
  --
  getNext()
}

ConnectProcessor --> ConnectContext
ConnectProcessor ..> StmtExecutor : execute()

StmtExecutor --> ConnectContext
StmtExecutor ..> StatementPlanner : plan()
StmtExecutor ..> DefaultCoordinator : create, exec, getNext()

StatementPlanner ..> Analyzer : analyzeStatement()
StatementPlanner ..> RelationTransformer
RelationTransformer --> LogicalPlan
StatementPlanner ..> QueryOptimizer : optimize()
Optimizer <|-- QueryOptimizer
QueryOptimizer --> OptExpression
StatementPlanner ..> PlanFragmentBuilder : createPhysicalPlan()
PlanFragmentBuilder ..> PhysicalPlanTranslator : translate()
PhysicalPlanTranslator --> ExecPlan
PlanFragmentBuilder --> ExecPlan

ExecPlan *-- PlanFragment
PlanFragment *-- PlanNode
PlanNode <|-- ExchangeNode
PlanFragment --> DataSink : sink
DataSink <|-- ResultSink

Coordinator <|-- DefaultCoordinator
DefaultCoordinator *-- CoordinatorPreprocessor
DefaultCoordinator *-- ExecutionDAG
DefaultCoordinator --> ResultReceiver
CoordinatorPreprocessor ..> ExecutionDAG : assign workers
ExecutionDAG *-- ExecutionFragment
ExecutionFragment *-- FragmentInstance

DefaultCoordinator ..> Deployer
Deployer *-- FragmentInstanceExecState
FragmentInstanceExecState --> FragmentInstance
FragmentInstanceExecState ..> BackendServiceClient : exec_plan_fragment
ResultReceiver ..> BackendServiceClient : fetch_data
FragmentInstance ..> PlanFragment : deploys

@enduml
```

A MySQL **`COM_QUERY`** is how a session enters this machinery. **`StmtExecutor`** builds the DAG, **`DefaultCoordinator`** instantiates and deploys it, and the FE only **`fetch_data`**s the root.

### 3.1 Statement generation

**`ConnectProcessor.handleQuery()`** decodes the MySQL **`COM_QUERY`** payload to a SQL string. **`SqlParser.parse`** splits the string, walks the ANTLR tree with **`AstBuilder`**, and returns one **`StatementBase`** per statement. **`AstBuilder`** is the constructor: each `visit*` allocates the subclass and fills its fields. Names are still unresolved; this step does not plan or execute.

```java
// ConnectProcessor.handleQuery
originStmt = new String(bytes, 1, ending, StandardCharsets.UTF_8);
List<StatementBase> stmts = parseStatements(originStmt);

// ConnectProcessor.parseStatements
return SqlParser.parse(originStmt, ctx.getSessionVariable());
```

```java
// SqlParser.parseWithStarRocksDialect
for (int idx = 0; idx < singleStatementContexts.size(); ++idx) {
    HintCollector collector = new HintCollector(tokenStream, sessionVariable);
    collector.collect(singleStatementContexts.get(idx));
    AstBuilder astBuilder = astBuilderFactory.create(sqlMode, caseInsensitive, collector.getContextWithHintMap());
    StatementBase statement = (StatementBase) astBuilder.visitSingleStatement(singleStatementContexts.get(idx));
    statement.setOrigStmt(new OriginStatement(sql, idx));
    statements.add(statement);
}
```

A **`SELECT`** becomes **`QueryStatement(queryRelation)`**. **`INSERT VALUES`** wraps a **`ValuesRelation`** in a **`QueryStatement`** and hangs it on **`InsertStmt.queryStatement`**. **`UPDATE`** / **`DELETE`** store **`TableRef`**, assignments or USING, and **`wherePredicate`** only.

```java
// AstBuilder.visitQueryStatement
QueryRelation queryRelation = (QueryRelation) visit(context.queryRelation());
QueryStatement queryStatement = new QueryStatement(queryRelation);
queryStatement.setQueryStartIndex(context.queryRelation().start.getStartIndex());
return queryStatement;

// AstBuilder.visitInsertStatement
if (context.VALUES() != null) {
    queryStatement = new QueryStatement(new ValuesRelation(rows, colNames, pos));
} else {
    queryStatement = (QueryStatement) visit(context.queryStatement());  // INSERT SELECT
}
return new InsertStmt(tableRef, partitionNames, label, columnAliases, queryStatement,
        context.OVERWRITE() != null, properties, pos);

// AstBuilder.visitUpdateStatement
List<ColumnAssignment> assignments = visit(context.assignmentList().assignment(), ColumnAssignment.class);
Expr where = context.where != null ? (Expr) visit(context.where) : null;
return new UpdateStmt(tableRef, assignments, fromRelations, where, ctes, pos);

// AstBuilder.visitDeleteStatement
return new DeleteStmt(tableRef, partitionNames, usingRelations, where, ctes, pos);
```

```plantuml
@startuml

interface ParseNode {
  + getPos() : NodePosition
}

abstract class StatementBase {
  - pos : NodePosition
  - explainLevel : ExplainLevel
  - isExplain : boolean
  # origStmt : OriginStatement
  # hintNodes : List<HintNode>
  # allQueryScopeHints : List<HintNode>
}

abstract class DmlStmt {
  - txnId : long
  # properties : Map<String, String>
  + {abstract} getTableRef() : TableRef
}

class QueryStatement {
  - queryRelation : QueryRelation
  # outFileClause : OutFileClause
  - queryStartIndex : int
}

class InsertStmt {
  - tableRef : TableRef
  - targetPartitionRef : PartitionRef
  - targetPartitionIds : List<Long>
  - targetColumnNames : List<String>
  - queryStatement : QueryStatement
  - resultExprs : ArrayList<Expr>
  - targetTable : Table
  - isOverwrite : boolean
  - label : String
}

class UpdateStmt {
  - tableRef : TableRef
  - assignments : List<ColumnAssignment>
  - fromRelations : List<Relation>
  - wherePredicate : Expr
  - commonTableExpressions : List<CTERelation>
  - table : Table
  - queryStatement : QueryStatement
  - usePartialUpdate : boolean
}

class DeleteStmt {
  - tableRef : TableRef
  - partitionRef : PartitionRef
  - usingRelations : List<Relation>
  - wherePredicate : Expr
  - commonTableExpressions : List<CTERelation>
  - table : Table
  - queryStatement : QueryStatement
  - deleteConditions : List<Predicate>
  - jobId : long
}

abstract class Relation {
  - scope : Scope
  # alias : TableName
}

abstract class QueryRelation {
  # sortClause : List<OrderByElement>
  # limit : LimitElement
  - cteRelations : List<CTERelation>
}

class SelectRelation {
  - selectList : SelectList
  - outputExpr : List<Expr>
  - predicate : Expr
  - groupBy : List<Expr>
  - aggregate : List<FunctionCallExpr>
  - having : Expr
  - isDistinct : boolean
  - relation : Relation
}

class ValuesRelation {
  - rows : List<List<Expr>>
  - outputColumnTypes : List<Type>
  - isNullValues : boolean
}

class TableRef {
  - tableName : QualifiedName
  - partitionRef : PartitionRef
  - alias : String
  - pos : NodePosition
}

class ColumnAssignment {
  - column : String
  - expr : Expr
  - pos : NodePosition
}

ParseNode <|.. StatementBase
ParseNode <|.. Relation
ParseNode <|.. TableRef
ParseNode <|.. ColumnAssignment
StatementBase <|-- QueryStatement
StatementBase <|-- DmlStmt
DmlStmt <|-- InsertStmt
DmlStmt <|-- UpdateStmt
DmlStmt <|-- DeleteStmt
Relation <|-- QueryRelation
QueryRelation <|-- SelectRelation
QueryRelation <|-- ValuesRelation

QueryStatement *-- QueryRelation : queryRelation
InsertStmt *-- QueryStatement : queryStatement
InsertStmt --> TableRef : tableRef
UpdateStmt *-- QueryStatement : queryStatement
UpdateStmt --> TableRef : tableRef
UpdateStmt *-- ColumnAssignment : assignments
DeleteStmt *-- QueryStatement : queryStatement
DeleteStmt --> TableRef : tableRef

@enduml
```

Generation ends when each **`StatementBase`** is on the list. The next object is **`StmtExecutor`**: **`execute()`** → **`generateExecPlan()`** → **`StatementPlanner.plan(parsedStmt, context)`**. That call is the whole plan: it returns an **`ExecPlan`**.

```java
executor = new StmtExecutor(ctx, parsedStmt);
ctx.setExecutor(executor);
executor.execute();
// StmtExecutor.generateExecPlan:
execPlan = StatementPlanner.plan(parsedStmt, context);
```

### 3.2 Plan

**`StatementPlanner.plan()`** turns a **`StatementBase`** into an **`ExecPlan`**. Analyze is the first phase inside that method, not a separate pipeline. For DML, **`beginTransaction()`** may set **`DmlStmt.txnId`** (a load transaction, not a SQL `BEGIN`). After analyze and **`Authorizer.check`**, the method branches: a **`QueryStatement`** goes to **`createQueryPlan()`** (or **`createQueryPlanWithReTry`**); **`InsertStmt`** / **`UpdateStmt`** / **`DeleteStmt`** / **`MergeIntoStmt`** go to their planners.

```java
public static ExecPlan plan(StatementBase stmt, ConnectContext session, TResultSinkType resultSinkType) {
    if (stmt instanceof DmlStmt) {
        beginTransaction((DmlStmt) stmt, session);
    }
    plannerMetaLocker = new PlannerMetaLocker(session, stmt);
    analyzeStatement(stmt, session, plannerMetaLocker);
    Authorizer.check(stmt, session);

    if (stmt instanceof QueryStatement) {
        return createQueryPlan(queryStmt, session, resultSinkType);
    } else if (stmt instanceof InsertStmt) {
        return planInsertStmt(plannerMetaLocker, (InsertStmt) stmt, session);
    } else if (stmt instanceof UpdateStmt) {
        return new UpdatePlanner().plan((UpdateStmt) stmt, session);
    } else if (stmt instanceof DeleteStmt) {
        return new DeletePlanner().plan((DeleteStmt) stmt, session);
    } else if (stmt instanceof MergeIntoStmt) {
        return new MergeIntoPlanner().plan((MergeIntoStmt) stmt, session);
    }
}
```

**`analyzeStatement()`** takes the metadata lock and **`Analyzer.analyze()`** visits the AST: resolve names, types, and partition metadata. For **`UpdateStmt`** / **`DeleteStmt`** it also writes the rewritten source **`queryStatement`**. No fragments yet.

```java
analyzeStatement(stmt, session, plannerMetaLocker);
// Analyzer.analyze(statement, session) → AnalyzerVisitor.visit(...)
```

For a query, **`createQueryPlan()`** is the rest of **`plan()`**: transform → optimize → fragmentize. The three phases below are that body.

```java
logicalPlan = new RelationTransformer(transformerContext).transformWithSelectLimit(query);
optimizedPlan = optimizer.optimize(logicalPlan.getRoot(),
        new PhysicalPropertySet(), new ColumnRefSet(logicalPlan.getOutputColumn()));
return PlanFragmentBuilder.createPhysicalPlan(
        optimizedPlan, session, logicalPlan.getOutputColumn(), columnRefFactory, colNames,
        resultSinkType, !session.getSessionVariable().isSingleNodeExecPlan(), isShortCircuit);
```

### 3.3 Logical plan

First phase of **`createQueryPlan()`**: turn the analyzed **`QueryRelation`** into a tree of **`OptExpression`**s. **`LogicalPlan`** is not a subclass of that tree; it holds the **root** **`OptExpression`** and the output **`ColumnRefOperator`**s.

Each **`OptExpression`** is one node:

- **`op`** — this node’s own operator (`LogicalOlapScanOperator`, `LogicalJoinOperator`, …).
- **`inputs`** — the child **`OptExpression`**s. A scan has none; a filter or agg has one; a join has two.

```plantuml
@startuml

class OptExpression {
  - op : Operator
  - inputs : List<OptExpression>
}

abstract class Operator

abstract class LogicalOperator

OptExpression *-- Operator : op
OptExpression o-- OptExpression : inputs
Operator <|-- LogicalOperator

@enduml
```

**`QueryTransformer.plan()`** stacks one **`OptExpression`** per clause (`OptExprBuilder` wraps **`op`** + child builders until **`getRoot()`**). **`SqlToScalarOperatorTranslator`** turns each **`Expr`** into a **`ScalarOperator`** on that **`op`**.

```java
OptExprBuilder builder = planFrom(queryBlock.getRelation(), cteContext);  // FROM
builder = filter(builder, queryBlock.getPredicate());                     // WHERE
builder = aggregate(builder, queryBlock.getGroupBy(), queryBlock.getAggregate(), ...);
builder = filter(builder, queryBlock.getHaving());                        // HAVING
builder = window(builder, analyticExprList);                              // OVER()
builder = project(...);                                                   // SELECT / ORDER BY exprs
builder = distinct(builder, queryBlock, queryBlock.isDistinct(), ...);
builder = sort(builder, queryBlock.getOrderBy(), orderByColumns);         // ORDER BY
builder = limit(builder, queryBlock.getLimit());                          // LIMIT / OFFSET
return new LogicalPlan(builder, outputColumns, correlation);
```

| SQL clause | AST field | Logical operator |
|------------|-----------|------------------|
| `FROM t` | `SelectRelation.relation` (`TableRelation`) | **`LogicalOlapScanOperator`** (or other **`LogicalScanOperator`**) |
| `JOIN … ON` | **`JoinRelation`** (`joinOp`, `onPredicate`) | **`LogicalJoinOperator`** (`onPredicate` kept distinct from WHERE) |
| `WHERE` | `SelectRelation.predicate` | **`LogicalFilterOperator`** (below agg) |
| `GROUP BY` / `SUM()` | `groupBy`, `aggregate` | **`LogicalAggregationOperator`** (`groupingKeys`, `aggregations` → **`CallOperator`**) |
| `GROUPING SETS` | `groupingSetsList` | **`LogicalRepeatOperator`** under the agg |
| `HAVING` | `having` | **`LogicalFilterOperator`** (above agg) |
| `SELECT` list | `outputExpr` | **`LogicalProjectOperator`** (`columnRefMap`) |
| `DISTINCT` | `isDistinct` | **`LogicalAggregationOperator`** (group keys = output, empty agg map) |
| `ORDER BY` | `orderBy` | **`LogicalTopNOperator`** |
| `LIMIT` / `OFFSET` | `limit` | **`LogicalLimitOperator`**; session **`sql_select_limit`** is an extra wrap in **`transformWithSelectLimit()`** |
| `OVER()` | analytic exprs | **`LogicalWindowOperator`** |
| `UNION` / `EXCEPT` / `INTERSECT` | **`SetOperationRelation`** | **`LogicalUnionOperator`** / **`Except`** / **`Intersect`** |
| subquery in expr | `Subquery` | **`LogicalApplyOperator`** |

WHERE and HAVING are the same operator class; only stack position differs. A join’s **`onPredicate`** stays on **`LogicalJoinOperator`** so MV rewrite can tell ON from WHERE. Filter pushdown into the scan is a later CBO rewrite, not this transform.

```plantuml
@startuml

abstract class Relation {
  - scope : Scope
  # alias : TableName
}

class SelectRelation {
  - relation : Relation
  - predicate : Expr
  - groupBy : List<Expr>
  - aggregate : List<FunctionCallExpr>
  - having : Expr
  - outputExpr : List<Expr>
  - isDistinct : boolean
}

class JoinRelation {
  - joinOp : JoinOperator
  - left : Relation
  - right : Relation
  - onPredicate : Expr
  - lateral : boolean
}

class LogicalPlan {
  - root : OptExprBuilder
  - outputColumn : List<ColumnRefOperator>
  - correlation : List<ColumnRefOperator>
}

class OptExprBuilder {
  - root : Operator
  - inputs : List<OptExprBuilder>
  - expressionMapping : ExpressionMapping
}

class OptExpression {
  - op : Operator
  - inputs : List<OptExpression>
}

abstract class LogicalOperator {
  # predicate : ScalarOperator
  # limit : long
}

class LogicalOlapScanOperator {
  # table : Table
  # colRefToColumnMetaMap : ImmutableMap<ColumnRefOperator, Column>
}

class LogicalJoinOperator {
  - joinType : JoinOperator
  - onPredicate : ScalarOperator
}

class LogicalFilterOperator

class LogicalAggregationOperator {
  - type : AggType
  - groupingKeys : ImmutableList<ColumnRefOperator>
  - aggregations : ImmutableMap<ColumnRefOperator, CallOperator>
}

class LogicalProjectOperator {
  - columnRefMap : Map<ColumnRefOperator, ScalarOperator>
}

abstract class ScalarOperator {
  # opType : OperatorType
  # type : Type
}

class ColumnRefOperator {
  - id : int
  - name : String
  - nullable : boolean
}

class CallOperator {
  - fnName : String
  - fn : Function
  - isDistinct : boolean
}

Relation <|-- SelectRelation
Relation <|-- JoinRelation

SelectRelation ..> LogicalPlan : QueryTransformer.plan()
LogicalPlan *-- OptExprBuilder : root
OptExprBuilder --> OptExpression : getRoot()
OptExpression *-- LogicalOperator
OptExpression o-- OptExpression : inputs
LogicalOperator <|-- LogicalOlapScanOperator
LogicalOperator <|-- LogicalJoinOperator
LogicalOperator <|-- LogicalFilterOperator
LogicalOperator <|-- LogicalAggregationOperator
LogicalOperator <|-- LogicalProjectOperator

LogicalJoinOperator --> ScalarOperator : onPredicate
LogicalFilterOperator --> ScalarOperator : predicate
LogicalProjectOperator --> ScalarOperator : columnRefMap
LogicalAggregationOperator --> CallOperator : aggregations
ScalarOperator <|-- ColumnRefOperator
ScalarOperator <|-- CallOperator

@enduml
```

The running query is revenue by customer region. Tables are not colocated: **`orders`** is hashed on **`cust_id`**, **`customers`** on **`id`**.

```sql
CREATE TABLE orders (
    dt      DATE,
    cust_id BIGINT,
    amount  DECIMAL(12, 2)
)
DUPLICATE KEY(dt, cust_id)
PARTITION BY RANGE(dt) (
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01'))
)
DISTRIBUTED BY HASH(cust_id) BUCKETS 8;

CREATE TABLE customers (
    id     BIGINT,
    region VARCHAR(32)
)
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

SELECT c.region, SUM(o.amount)
FROM orders o
JOIN customers c ON o.cust_id = c.id
WHERE o.dt BETWEEN '2024-01-01' AND '2024-06-30'
GROUP BY c.region;
```

**`planFrom`** builds the join; **`filter`** hangs WHERE on top of the join (not yet on the **`orders`** scan); **`aggregate`** then **`project`** produce the SELECT list. Each line below is one **`OptExpression`**: the name is **`op`**; indentation is **`inputs`**.

```
OptExpression  op=LogicalProject  { region, sum_amount }
  OptExpression  op=LogicalAggregation  groupingKeys=[region]  aggregations={sum_amount: SUM(amount)}
    OptExpression  op=LogicalFilter  predicate=(dt BETWEEN ...)
      OptExpression  op=LogicalJoin  INNER  onPredicate=(cust_id = id)
        OptExpression  op=LogicalOlapScan  orders     inputs=[]
        OptExpression  op=LogicalOlapScan  customers  inputs=[]
```

### 3.4 Optimize

**`QueryOptimizer.optimize()`** is the second phase of **`createQueryPlan()`**. The framework follows Graefe’s Cascades paper [[2]](#5-references): **Memo**, task-stack search, transformation and implementation **Rules**, and **property enforce**. A normal **`SELECT`** uses **`optimizeByCost`** (`OptimizerOptions` defaults to **`COST_BASED`**). **`optimizeByRule`** is rewrite only (MV’s own tree) and never initializes the Memo.

![QueryOptimizer: rewrite, Cascades Memo search, extract, rewrite](images/starrocks-optimize-overview.svg)

#### 3.4.1 Overall procedure

**`optimizeByCost`** is a fixed pipeline. Logical rewrite still runs on the concrete tree; from **`memo.init`** onward, Cascades search happens **inside the Memo**.

1. **Logical rewrite** — `rewriteAndValidatePlan` → `logicalRuleRewrite` (subquery, CTE inline, prune, pushdown) on the concrete **`OptExpression`** tree.
2. **Init Memo** — `memo.init(logicOperatorTree)` then `deriveAllGroupLogicalProperty` (§3.4.2).
3. **Memo search** — `memoOptimize`: prepare join rules, push `OptimizeGroupTask(rootGroup)`, run the task stack until physical alternatives are costed (§3.4.2–3.4.4).
4. **Extract** — `extractBestPlan(requiredProperty, rootGroup)` rebuilds one physical **`OptExpression`** from the cheapest physical **`GroupExpression`**.
5. **Physical rewrite** — `physicalRuleRewrite`, then feedback `dynamicRewrite`.

What changes on the tree is **`op`** and which **`GroupExpression`** CBO kept. **`PlanFragmentBuilder`** later cuts at every **`PhysicalDistributionOperator`**.

```java
Optimizer optimizer = OptimizerFactory.create(optimizerContext);
OptExpression optimizedPlan = optimizer.optimize(
        logicalPlan.getRoot(),
        new PhysicalPropertySet(),
        new ColumnRefSet(logicalPlan.getOutputColumn()));

OptExpression optimize(OptExpression logicOperatorTree, PhysicalPropertySet requiredProperty,
        ColumnRefSet requiredColumns) {
    prepare(logicOperatorTree);
    prepareMvRewrite(...);
    return optimizerOptions.isRuleBased() ?
            optimizeByRule(logicOperatorTree, requiredProperty, requiredColumns) :
            optimizeByCost(connectContext, logicOperatorTree, requiredProperty, requiredColumns);
}

OptExpression optimizeByCost(ConnectContext connectContext, OptExpression logicOperatorTree,
        PhysicalPropertySet requiredProperty, ColumnRefSet requiredColumns) {
    TaskContext rootTaskContext =
            new TaskContext(context, requiredProperty, requiredColumns.clone(), Double.MAX_VALUE);
    logicOperatorTree = rewriteAndValidatePlan(logicOperatorTree, rootTaskContext);
    memo.init(logicOperatorTree);
    memo.deriveAllGroupLogicalProperty();
    memoOptimize(connectContext, memo, rootTaskContext);
    OptExpression result = extractBestPlan(requiredProperty, memo.getRootGroup());
    result = physicalRuleRewrite(connectContext, rootTaskContext, result);
    result = dynamicRewrite(connectContext, rootTaskContext, result);
    return result;
}

OptExpression extractBestPlan(PhysicalPropertySet requiredProperty, Group rootGroup) {
    GroupExpression groupExpression = rootGroup.getBestExpression(requiredProperty);
    List<PhysicalPropertySet> inputProperties = groupExpression.getInputProperties(requiredProperty);
    List<OptExpression> childPlans = Lists.newArrayList();
    for (int i = 0; i < groupExpression.arity(); ++i) {
        childPlans.add(extractBestPlan(inputProperties.get(i), groupExpression.inputAt(i)));
    }
    return OptExpression.create(groupExpression.getOp(), childPlans);
}
```

#### 3.4.2 Memo

All cost-based search after logical rewrite runs **against the Memo**. A **`Group`** holds **logically equivalent** alternatives. A **`GroupExpression`** is one alternative: an **`op`** whose **`inputs`** are **`Group`s**. Identity **`(op, input group ids)`** makes **`copyIn`** share duplicates.

```plantuml
@startuml

class Memo {
  - groups : List<Group>
  - groupExpressions : Map
  - rootGroup : Group
  + init()
  + copyIn()
}

class Group {
  - id : int
  - logicalExpressions : List<GroupExpression>
  - physicalExpressions : List<GroupExpression>
  - lowestCostExpressions : Map
}

class GroupExpression {
  - op : Operator
  - inputs : List<Group>
  - lowestCostTable : Map
  - outputPropertyMap : Map
}

Memo o-- Group : groups
Memo --> Group : rootGroup
Group o-- GroupExpression : logical / physical
GroupExpression o-- Group : inputs
GroupExpression *-- Operator : op

@enduml
```

**`memo.init`** loads groups → **`memoOptimize`** prepares join rules and drains the task stack from the root → **`extractBestPlan`** (§3.4.1) reads the filled memo.

After init the running query is a **group DAG** (`memo.rootGroup` = **G5**). 

```
memo.rootGroup ──► G5  { LogicalProject          inputs=[G4] }
                         │
                         ▼
                       G4  { LogicalAggregation    inputs=[G3] }
                         │
                         ▼
                       G3  { LogicalFilter         inputs=[G2] }
                         │
                         ▼
                       G2  { LogicalJoin           inputs=[G0, G1] }
                        / \
                       ▼   ▼
        G0 { LogicalOlapScan(orders) }   G1 { LogicalOlapScan(customers) }
             inputs=[]                        inputs=[]
```

**`memoOptimize` traversal.** The scheduler is a **stack** (LIFO). Only **`OptimizeGroupTask(G5)`** is pushed at entry.

Two different orders share that stack:

- **Explore (transform-only).** **`OptimizeExpressionTask`** pushes **`ExploreGroupTask`** on each input group *after* other work, so children are popped first: logical exploration descends **G5 → G4 → G3 → G2 → (G0, G1)** before the parent’s own transform rules finish draining.
- **Implement + enforce/cost.** Full **`OptimizeGroupTask`** (with implement rules) on a child is usually started from a parent’s **`EnforceAndCostTask`**: the parent physical expression is already **`copyIn`**, costing begins at the parent, then the parent **suspends** and pushes **`OptimizeGroupTask(child)`**. So for the join group **G2**, implement/enforce **starts on G2 first**; **G0** / **G1** run **after** that suspension, while G2’s cost task waits; G2 **resumes** when the scans have a best expression. How that suspend/resume walk works is §3.4.4.

```java
// --- 1. memo.init: bottom-up copy into groups ---
GroupExpression init(OptExpression originExpression) {
    GroupExpression rootGroupExpression = copyIn(null, originExpression).second;
    rootGroup = rootGroupExpression.getGroup();  // G5
    return rootGroupExpression;
}

Pair<Boolean, GroupExpression> copyIn(Group targetGroup, OptExpression expression) {
    List<Group> inputs = Lists.newArrayList();
    for (OptExpression input : expression.getInputs()) {
        inputs.add(copyIn(null, input).second.getGroup());
    }
    GroupExpression groupExpression = new GroupExpression(expression.getOp(), inputs);
    return insertGroupExpression(groupExpression, targetGroup);
}

// --- 2–4. memoOptimize: bookkeeping, extend RuleSet, push root, drain stack ---
void memoOptimize(ConnectContext connectContext, Memo memo, TaskContext rootTaskContext) {
    context.setInMemoPhase(true);
    OptExpression tree = memo.getRootGroup().extractLogicalTree();
    CTEUtils.collectCteOperators(tree, context);

    int innerCrossJoinNode = Utils.countJoinNodeSize(tree, JoinOperator.innerCrossJoinSet());
    if (!sessionVariable.isDisableJoinReorder()
            && innerCrossJoinNode < sessionVariable.getCboMaxReorderNode()) {
        if (innerCrossJoinNode > sessionVariable.getCboMaxReorderNodeUseExhaustive()) {
            new ReorderJoinRule().transform(tree, context);
            context.getRuleSet().addJoinCommutativityWithoutInnerRule();
        } else {
            context.getRuleSet().addJoinTransformationRules();
        }
    }
    context.getRuleSet().addAutoJoinImplementationRule();

    scheduler.pushTask(new OptimizeGroupTask(rootTaskContext, memo.getRootGroup())); // G5
    scheduler.executeTasks(rootTaskContext);
}

// --- 5. OptimizeGroupTask: explore logical exprs, cost physical exprs ---
void OptimizeGroupTask.execute() {
    if (group.getCostLowerBound(context.getRequiredProperty()) >= context.getUpperBoundCost()
            || group.hasBestExpression(context.getRequiredProperty())) {
        return;
    }
    for (int i = group.getLogicalExpressions().size() - 1; i >= 0; i--) {
        pushTask(new OptimizeExpressionTask(context, group.getLogicalExpressions().get(i)));
    }
    for (int i = group.getPhysicalExpressions().size() - 1; i >= 0; i--) {
        pushTask(new EnforceAndCostTask(context, group.getPhysicalExpressions().get(i)));
    }
}

// --- descend explore: children before parent ApplyRuleTasks (LIFO) ---
void OptimizeExpressionTask.execute() {
    for (Rule rule : getValidRules()) {
        pushTask(new ApplyRuleTask(context, groupExpression, rule, isExplore));
    }
    pushTask(new DeriveStatsTask(context, groupExpression));
    for (int i = groupExpression.arity() - 1; i >= 0; i--) {
        pushTask(new ExploreGroupTask(context, groupExpression.getInputs().get(i)));
    }
}

// --- 6. ApplyRuleTask: copyIn substitutes; logical → explore, physical → enforce/cost ---
void ApplyRuleTask.execute() {
    Binder binder = new Binder(optimizerContext, rule.getPattern(), groupExpression, ...);
    List<OptExpression> newExpressions = Lists.newArrayList();
    for (OptExpression extractExpr = binder.next(); extractExpr != null; extractExpr = binder.next()) {
        if (rule.check(extractExpr, optimizerContext)) {
            newExpressions.addAll(rule.transform(extractExpr, optimizerContext));
        }
    }
    for (OptExpression expression : newExpressions) {
        GroupExpression neu = memo.copyIn(groupExpression.getGroup(), expression).second;
        if (neu.getOp().isLogical()) {
            pushTask(new OptimizeExpressionTask(context, neu, isExplore));
        } else {
            pushTask(new EnforceAndCostTask(context, neu));
        }
    }
    groupExpression.setRuleExplored(rule);
}
```

Match / check / transform details are §3.4.3; EnforceAndCost top→bottom→top walk is §3.4.4; distribution enforcers are §3.4.5. After commute and hash-join implement:

```
G2  {
  LogicalJoin(G0, G1)           // from init
  LogicalJoin(G1, G0)           // JoinCommutativityRule
  PhysicalHashJoin(G0, G1)      // HashJoinImplementationRule
  PhysicalHashJoin(G1, G0)      // implement the commute
}
```

#### 3.4.3 Rules

**How a rule runs.** Cascades explores plans by applying **`Rule`s**. Each rule is one rewrite of a matched fragment. Inside the memo the steps are:

1. **Match** — **`Pattern`** is a tree of operator-type placeholders. The binder walks a **`GroupExpression`** and its child groups until the shape fits (for example `LOGICAL_JOIN` over two unconstrained leaves).
2. **Gate** — optional **`check(input, context)`** rejects matches that are structurally valid but semantically wrong (for example nest-loop implement refusing an equi-join).
3. **Rewrite** — **`transform(input, context)`** builds zero or more new **`OptExpression`** trees. An empty list means “no change.” The matched expression is not mutated.
4. **Insert** — each substitute is **`copyIn`** into the same equivalence group as a new **`GroupExpression`**. Later search sees it as another alternative.

**`COST_BASED`** means: apply rules to grow the search space, then pick the cheapest physical alternative — not a separate non-rule planner.

**Two subclasses.** **`Rule`** splits by what **`transform`** puts at the root of each substitute:

- **`TransformationRule`** — **logical → logical**. Same result, different logical shape (join commute, split agg into local/global, …). The search space grows before any executable operator exists. Example: **`JoinCommutativityRule`** produces `LogicalJoin(B, A)` from `LogicalJoin(A, B)`.
- **`ImplementationRule`** — **logical → physical**. Replaces a logical operator with one the executor can run, usually keeping the same children. Example: **`HashJoinImplementationRule`** produces `PhysicalHashJoin` from `LogicalJoin`.

Both share **`Pattern` / `check` / `transform`**. Transformation widens logical alternatives; implementation adds executable ones. Cost chooses among physical alternatives. Implementation rules use higher **`promise`** so they are tried before more transforms on the same expression. **`RuleSet`** keeps **`transformRules`** and **`implementRules`**.

```plantuml
@startuml

abstract class Rule {
  - type : RuleType
  - pattern : Pattern
  + check()
  + transform()
  + promise()
}

abstract class Pattern {
  - children : List<Pattern>
}

abstract class TransformationRule
abstract class ImplementationRule

class JoinCommutativityRule
class SplitTwoPhaseAggRule
class HashJoinImplementationRule
class OlapScanImplementationRule
class HashAggImplementationRule

class RuleSet {
  - transformRules : List<Rule>
  - implementRules : List<Rule>
}

Rule o-- Pattern : pattern
Rule <|-- TransformationRule
Rule <|-- ImplementationRule
TransformationRule <|-- JoinCommutativityRule
TransformationRule <|-- SplitTwoPhaseAggRule
ImplementationRule <|-- HashJoinImplementationRule
ImplementationRule <|-- OlapScanImplementationRule
ImplementationRule <|-- HashAggImplementationRule
RuleSet o-- Rule : transformRules
RuleSet o-- Rule : implementRules

@enduml
```

```java
// ImplementationRule: logical join → physical hash join (same children)
List<OptExpression> transform(OptExpression input, OptimizerContext context) {
    LogicalJoinOperator join = (LogicalJoinOperator) input.getOp();
    PhysicalHashJoinOperator hashJoin =
            new PhysicalHashJoinOperator(join.getJoinType(), join.getOnPredicate(), ...);
    return Lists.newArrayList(OptExpression.create(hashJoin, input.getInputs()));
}
```

**Physical operators from implementation rules.** After a successful implement **`copyIn`**, the new expression is physical and the optimizer costs it (and may insert distribution enforcers — §3.4.4–3.4.5). **`RuleSet`** starts with **`ALL_IMPLEMENT_RULES`** (scan, hash agg, filter, project, top-n, … — not join). **`memoOptimize`** adds **`HashJoinImplementationRule`** and **`NestLoopJoinImplementationRule`**. **`PhysicalDistributionOperator`** is not from an implementation rule; **`EnforceAndCostTask`** inserts it when delivered layout does not satisfy the parent requirement. Its **`distributionSpec`** is the required layout (`SHUFFLE_JOIN` / **`SHUFFLE_AGG`** / **`BUCKET`** / **`BROADCAST`** / **`GATHER`**).

| Implementation rule | Logical input | Physical operator |
|---------------------|---------------|-------------------|
| **`OlapScanImplementationRule`** | **`LogicalOlapScanOperator`** | **`PhysicalOlapScanOperator`** (`table`, `selectedPartitionId`, `selectedTabletId`; residual **`predicate`**; **`distributionSpec`** = **`LOCAL`**) |
| **`HashJoinImplementationRule`** | **`LogicalJoinOperator`** (equi-join; not CROSS) | **`PhysicalHashJoinOperator`** (`joinType`, `onPredicate`) |
| **`NestLoopJoinImplementationRule`** | **`LogicalJoinOperator`** (when **`check`** allows) | **`PhysicalNestLoopJoinOperator`** |
| **`HashAggImplementationRule`** | **`LogicalAggregationOperator`** | **`PhysicalHashAggregateOperator`** (`type` **`LOCAL`** / **`GLOBAL`**, `isSplit`, `groupBys`, `partitionByColumns`) |
| **`FilterImplementationRule`** | **`LogicalFilterOperator`** | **`PhysicalFilterOperator`** (or residual **`Operator.predicate`** on the scan when pushed earlier) |
| **`ProjectImplementationRule`** | **`LogicalProjectOperator`** | **`PhysicalProjectOperator`** (`columnRefMap`; or folded **`Operator.projection`**) |
| **`TopNImplementationRule`** | **`LogicalTopNOperator`** | **`PhysicalTopNOperator`** (`orderSpec`, `sortPhase` **`PARTIAL`** / **`FINAL`**, `isSplit`) |
| *(enforcer, not a rule)* | — | **`PhysicalDistributionOperator`** — **`appendEnforcers`**; carries **`distributionSpec`** |

```plantuml
@startuml

class OptExpression {
  - op : Operator
  - inputs : List<OptExpression>
  - requiredProperties : List<PhysicalPropertySet>
  - outputProperty : PhysicalPropertySet
}

abstract class Operator {
  # opType : OperatorType
  # limit : long
  # predicate : ScalarOperator
  # projection : Projection
}

abstract class LogicalOperator

abstract class PhysicalOperator {
  # distributionSpec : DistributionSpec
  # orderSpec : OrderSpec
}

abstract class PhysicalScanOperator {
  # table : Table
  # outputColumns : List<ColumnRefOperator>
}

class PhysicalOlapScanOperator {
  - distributionSpec : DistributionSpec
  - selectedPartitionId : List<Long>
  - selectedTabletId : List<Long>
}

abstract class PhysicalJoinOperator {
  # joinType : JoinOperator
  # onPredicate : ScalarOperator
}

class PhysicalHashJoinOperator

class PhysicalHashAggregateOperator {
  - type : AggType
  - groupBys : List<ColumnRefOperator>
  - partitionByColumns : List<ColumnRefOperator>
  - isSplit : boolean
}

class PhysicalDistributionOperator

class PhysicalProjectOperator
class PhysicalFilterOperator

class PhysicalTopNOperator {
  - orderSpec : OrderSpec
  - sortPhase : SortPhase
  - isSplit : boolean
}

class PhysicalPropertySet {
  - distributionProperty : DistributionProperty
  - sortProperty : SortProperty
}

class DistributionProperty {
  - spec : DistributionSpec
}

abstract class DistributionSpec {
  # type : DistributionType
}

class HashDistributionSpec {
  - hashDistributionDesc : HashDistributionDesc
}

class ReplicatedDistributionSpec
class GatherDistributionSpec
class AnyDistributionSpec

class HashDistributionDesc {
  - distributionCols : List<DistributionCol>
  - sourceType : SourceType
}

enum SourceType <<enumeration>> {
  LOCAL
  SHUFFLE_JOIN
  SHUFFLE_AGG
  BUCKET
}

OptExpression *-- Operator : op
OptExpression o-- OptExpression : inputs
OptExpression --> PhysicalPropertySet : outputProperty
OptExpression o-- PhysicalPropertySet : requiredProperties

Operator <|-- LogicalOperator
Operator <|-- PhysicalOperator
PhysicalOperator <|-- PhysicalScanOperator
PhysicalOperator <|-- PhysicalJoinOperator
PhysicalOperator <|-- PhysicalHashAggregateOperator
PhysicalOperator <|-- PhysicalDistributionOperator
PhysicalOperator <|-- PhysicalProjectOperator
PhysicalOperator <|-- PhysicalFilterOperator
PhysicalOperator <|-- PhysicalTopNOperator
PhysicalScanOperator <|-- PhysicalOlapScanOperator
PhysicalJoinOperator <|-- PhysicalHashJoinOperator

PhysicalPropertySet *-- DistributionProperty : distributionProperty
DistributionProperty *-- DistributionSpec : spec
DistributionSpec <|-- HashDistributionSpec
DistributionSpec <|-- ReplicatedDistributionSpec
DistributionSpec <|-- GatherDistributionSpec
DistributionSpec <|-- AnyDistributionSpec
HashDistributionSpec *-- HashDistributionDesc : hashDistributionDesc
HashDistributionDesc --> SourceType : sourceType

PhysicalOperator o-- DistributionSpec : distributionSpec

@enduml
```

Scan **`LOCAL`** lives on **`PhysicalOlapScanOperator.distributionSpec`** (from **`DISTRIBUTED BY`**). Join / agg carry the keys that required-property derivation turns into child requirements (`onPredicate`, **`partitionByColumns`**). The enforcer’s **`PhysicalDistributionOperator.distributionSpec`** is the required layout that did not satisfy the delivered output.

#### 3.4.4 EnforceAndCostTask

**`EnforceAndCostTask`** runs only after a physical **`GroupExpression`** exists (`copyIn` from an implementation rule). The physical DAG shape is already there (input **Group**s link parent to children); this task does **not** build the tree leaf-first. It costs and enforces properties on that existing expression.

**Top → bottom → top (suspend / resume).** The walk is a stack, not a recursive Java call. A parent is **not** finished when a child runs — on the join/scans example, **G2** (physical hash join) **starts first**; **G0** / **G1** run **while G2 is suspended**; G2 **resumes** afterward:

1. **Start at the parent** (e.g. physical join in **G2** / **E3**). Read **`requiredProperty`**, derive each child’s requirement (steps 1–2 below). The parent has only *started*.
2. **Suspend the parent.** **`optimizeChildGroup`** pushes a **clone** of this **`EnforceAndCostTask`** (resume later), then **`OptimizeGroupTask(child)`** — that is what runs implement+cost on **G0** / **G1** if they still lack a best expression under the derived requirement.
3. **Run the child to completion** (e.g. **E1**): leaf steps 1–4, **`outputProperty`**, maybe an enforcer.
4. **Resume the parent.** After all inputs have a best expression, derive this node’s **`outputProperty`**, compare, maybe **`appendEnforcers`** (steps 3–4), then return to *its* parent.

Required properties flow **down** as the stack deepens; output properties and enforcers are decided **up** as clones resume. The same pattern links **E5 → E4 → E3 → E1/E2** and back.

Each visit is four steps:

1. Read **`TaskContext.requiredProperty`**.
2. **`RequiredPropertyDeriver`** → **`childrenRequiredProperties`** (each becomes that child’s **`TaskContext.requiredProperty`**).
3. After children return: **`OutputPropertyDeriver`** → this **`outputProperty`**.
4. **`recordCostsAndEnforce`**: if not **`isSatisfy`**, insert **`PhysicalDistributionOperator(required spec)`**.

```java
void initRequiredProperties() {
    RequiredPropertyDeriver requiredPropertyDeriver = new RequiredPropertyDeriver(context);
    childrenRequiredPropertiesList = requiredPropertyDeriver.getRequiredProps(groupExpression);
}

void execute() {
    initRequiredProperties();  // parent → child requirements (down)
    for (List<PhysicalPropertySet> childrenRequiredProperties : childrenRequiredPropertiesList) {
        for (; curChildIndex < groupExpression.getInputs().size(); curChildIndex++) {
            PhysicalPropertySet childRequiredProperty = childrenRequiredProperties.get(curChildIndex);
            Group childGroup = groupExpression.getInputs().get(curChildIndex);
            GroupExpression childBestExpr = childGroup.getBestExpression(childRequiredProperty);
            if (childBestExpr == null) {
                // G2 suspends here; G0/G1 OptimizeGroupTask (+ implement) run next
                optimizeChildGroup(childRequiredProperty, childGroup);
                return;
            }
            childrenOutputProperties.add(childBestExpr.getOutputProperty(childRequiredProperty));
        }
        // all children done → outputProperty / enforce (up); G2 resumes after G0/G1
        OutputPropertyDeriver outputPropertyDeriver = new OutputPropertyDeriver(groupExpression,
                context.getRequiredProperty(), childrenOutputProperties);
        recordCostsAndEnforce(outputPropertyDeriver.getOutputProperty(), childrenRequiredProperties);
    }
}

void optimizeChildGroup(PhysicalPropertySet inputProperty, Group childGroup) {
    pushTask((EnforceAndCostTask) clone());
    TaskContext taskContext = new TaskContext(context.getOptimizerContext(), inputProperty,
            context.getRequiredColumns(), context.getUpperBoundCost() - curTotalCost);
    pushTask(new OptimizeGroupTask(taskContext, childGroup));
}

void recordCostsAndEnforce(PhysicalPropertySet outputProperty,
        List<PhysicalPropertySet> childrenOutputProperties) {
    PhysicalPropertySet requiredProperty = context.getRequiredProperty();
    if (!outputProperty.getDistributionProperty()
            .isSatisfy(requiredProperty.getDistributionProperty())) {
        enforceDistribute(outputProperty);
    }
}

PhysicalPropertySet enforceDistribute(PhysicalPropertySet oldOutputProperty) {
    PhysicalPropertySet requiredPropertySet = oldOutputProperty.copy();
    requiredPropertySet.setDistributionProperty(context.getRequiredProperty()
            .getDistributionProperty().getNullStrictProperty());
    GroupExpression enforcer = requiredPropertySet.getDistributionProperty()
            .appendEnforcers(groupExpression.getGroup());
    return updateCostAndOutputPropertySet(enforcer, oldOutputProperty, requiredPropertySet);
}

GroupExpression appendEnforcers(Group child) {
    return new GroupExpression(new PhysicalDistributionOperator(spec), Lists.newArrayList(child));
}
```

On the running statement, solid edges are **down** (`requiredProperty`); dotted edges are **up** (`outputProperty`):

```plantuml
@startuml
top to bottom direction

rectangle "GLOBAL HashAggregate\nrequiredProperty = EMPTY" as G
rectangle "LOCAL HashAggregate\nrequiredProperty = SHUFFLE_AGG(region)" as L
rectangle "HashJoin ON cust_id = id\nrequiredProperty = EMPTY" as J
rectangle "OlapScan orders\nrequired = SHUFFLE_JOIN(cust_id)\noutput = LOCAL(cust_id)" as So
rectangle "OlapScan customers\nrequired = SHUFFLE_JOIN(id)\noutput = LOCAL(id)" as Sc

G --> L : requiredProperty
L --> J : requiredProperty
J --> So : requiredProperty
J --> Sc : requiredProperty

So ..> J : outputProperty
Sc ..> J : outputProperty
J ..> L : outputProperty
L ..> G : outputProperty

@enduml
```

```plantuml
@startuml

class EnforceAndCostTask {
  - groupExpression : GroupExpression
  - childrenRequiredPropertiesList : List
}

class RequiredPropertyDeriver {
  + visitPhysicalHashJoin()
  + visitPhysicalHashAggregate()
}

class OutputPropertyDeriver {
  + visitPhysicalHashJoin()
  + visitPhysicalHashAggregate()
}

EnforceAndCostTask --> RequiredPropertyDeriver : getRequiredProps
EnforceAndCostTask --> OutputPropertyDeriver : getOutputProperty
EnforceAndCostTask ..> OptimizeGroupTask : pushTask child
EnforceAndCostTask ..> EnforceAndCostTask : pushTask clone
RequiredPropertyDeriver ..> PhysicalHashJoinOperator : visitPhysicalHashJoin
RequiredPropertyDeriver ..> PhysicalHashAggregateOperator : visitPhysicalHashAggregate
OutputPropertyDeriver ..> PhysicalHashJoinOperator : visitPhysicalHashJoin
OutputPropertyDeriver ..> PhysicalHashAggregateOperator : visitPhysicalHashAggregate

@enduml
```

#### 3.4.5 Distribution

**Distribution** is how a node’s output rows are laid out across **tablets / hash buckets**. Catalog metadata is **`DistributionInfo`**. CBO carries a **`DistributionSpec`** inside **`PhysicalPropertySet.distributionProperty`**, and inserts a **`PhysicalDistributionOperator`** only when delivered layout does not **`isSatisfy`** the parent requirement. Fragmentize later cuts only where that operator exists; root **`ResultSink`** GATHER is **`createOutputFragment()`**, not this path.

**`DistributionInfo`** is table metadata from `CREATE TABLE` on **`OlapTable`**. **`PARTITION BY`** (date ranges) is a different catalog object. **`DISTRIBUTED BY`** is this one: how **each partition** splits into tablets. For **`orders`**, **`DISTRIBUTED BY HASH(cust_id) BUCKETS 8`** is **`HashDistributionInfo`** (`cust_id`, `bucketNum = 8`). **`RANDOM`** is **`RandomDistributionInfo`**. Replica placement is not this object.

```plantuml
@startuml

class OlapTable {
  - defaultDistributionInfo : DistributionInfo
}

abstract class DistributionInfo {
  # type : DistributionInfoType
}

class HashDistributionInfo {
  - distributionColumnIds : List<ColumnId>
  - bucketNum : int
}

class RandomDistributionInfo

OlapTable *-- DistributionInfo : defaultDistributionInfo
DistributionInfo <|-- HashDistributionInfo
DistributionInfo <|-- RandomDistributionInfo

@enduml
```

**`DistributionSpec`** is CBO’s encoding of a layout on an **`OptExpression`**, not a catalog field. Two specs are built independently and compared by **`isSatisfy`**.

```plantuml
@startuml

class PhysicalPropertySet {
  - distributionProperty : DistributionProperty
  - sortProperty : SortProperty
}

class DistributionProperty {
  - spec : DistributionSpec
}

class DistributionSpec {
  # type : DistributionType
}

class HashDistributionSpec {
  - hashDistributionDesc : HashDistributionDesc
}

class ReplicatedDistributionSpec
class GatherDistributionSpec
class AnyDistributionSpec

class HashDistributionDesc {
  - distributionCols : List<DistributionCol>
  - sourceType : SourceType
}

enum SourceType <<enumeration>> {
  LOCAL
  SHUFFLE_JOIN
  SHUFFLE_AGG
  BUCKET
}

PhysicalPropertySet *-- DistributionProperty : distributionProperty
DistributionProperty *-- DistributionSpec : spec
DistributionSpec <|-- HashDistributionSpec
DistributionSpec <|-- ReplicatedDistributionSpec
DistributionSpec <|-- GatherDistributionSpec
DistributionSpec <|-- AnyDistributionSpec
HashDistributionSpec *-- HashDistributionDesc : hashDistributionDesc
HashDistributionDesc --> SourceType : sourceType

@enduml
```

**`HashDistributionDesc.sourceType`** distinguishes delivered scan layout from a required shuffle: **`LOCAL`** on the scan, **`SHUFFLE_JOIN`** / **`SHUFFLE_AGG`** / **`BUCKET`** on a parent. **`ReplicatedDistributionSpec`** is broadcast; **`GatherDistributionSpec`** is one stream; **`AnyDistributionSpec`** is **`EMPTY`**.

| Spec | Origin | Layout |
|------|--------|--------|
| **`LOCAL`** | scan **`DISTRIBUTED BY HASH`** | Table tablets |
| **`SHUFFLE_JOIN`** | required by hash join | Hash on ON-key column-refs |
| **`SHUFFLE_AGG`** | required by **`GLOBAL`** agg | Hash on group keys |
| **`BUCKET`** | bucket-shuffle join | Right child of a local-bucket join |
| **`BROADCAST`** | required by hash join | Full copy on every consumer |
| **`GATHER`** | scalar **`GLOBAL`** agg | One stream |
| **`ANY`** | no requirement | **`EMPTY`**, root **`optimize()`** |

**`PhysicalDistributionOperator`** is never produced by an implementation rule. It appears in two places during **`EnforceAndCostTask`**: (1) when this node’s **`outputProperty`** fails **`isSatisfy(requiredProperty)`**, and (2) when **`ChildOutputPropertyGuarantor`** rewrites a join child’s delivered layout to **`BUCKET`**.

**1. Parent writes the child’s required `DistributionSpec`.** **`RequiredPropertyDeriver`** fills **`childrenRequiredPropertiesList`**. For a hash join it records a broadcast pair and, unless **`onlyBroadcast()`**, a shuffle pair on the ON keys. For a non-local hash aggregate it requires **`GATHER`** (no group keys) or **`SHUFFLE_AGG`** on **`partitionByColumns`**; a local aggregate requires **`EMPTY`**.

```java
// RequiredPropertyDeriver — hash join
PhysicalPropertySet rightBroadcastProperty = new PhysicalPropertySet(
        DistributionProperty.createProperty(DistributionSpec.createReplicatedDistributionSpec()));
requiredProperties.add(Lists.newArrayList(PhysicalPropertySet.EMPTY, rightBroadcastProperty));
if (joinHelper.onlyShuffle()) {
    requiredProperties.clear();
}
requiredProperties.add(computeShuffleJoinRequiredProperties(requirementsFromParent, leftCols, rightCols));
// → SHUFFLE_JOIN(cust_id) / SHUFFLE_JOIN(id) on the two children

// RequiredPropertyDeriver — hash aggregate
if (!node.getType().isLocal()) {
    if (columns.isEmpty()) {
        requiredProperties.add(Lists.newArrayList(createGatherPropertySet()));  // GATHER
    } else {
        requiredProperties.add(Lists.newArrayList(computeAggRequiredShuffleProperties(columns)));
        // → SHUFFLE_AGG(region)
    }
} else {
    requiredProperties.add(Lists.newArrayList(PhysicalPropertySet.EMPTY));
}
```

**2. Mismatch inserts the enforcer on this group.** After children return, **`recordCostsAndEnforce`** compares this node’s **`outputProperty`** to **`TaskContext.requiredProperty`**. If distribution does not satisfy, **`enforceDistribute`** takes the *required* distribution property and **`appendEnforcers`** builds a new **`GroupExpression`** whose **`op`** is **`PhysicalDistributionOperator(spec)`** and whose sole input is **this** group. That expression is costed and recorded as satisfying the required property; the parent later reads the enforced spec as the child’s output.

```java
// EnforceAndCostTask.recordCostsAndEnforce
boolean satisfyDistributionProperty =
        outputProperty.getDistributionProperty().isSatisfy(requiredProperty.getDistributionProperty());
if (!satisfyOrderProperty || !satisfyDistributionProperty) {
    enforcedProperty = enforceProperty(outputProperty, requiredProperty,
            satisfyOrderProperty, satisfyDistributionProperty);
}

PhysicalPropertySet enforceDistribute(PhysicalPropertySet oldOutputProperty) {
    PhysicalPropertySet requiredPropertySet = oldOutputProperty.copy();
    requiredPropertySet.setDistributionProperty(context.getRequiredProperty()
            .getDistributionProperty().getNullStrictProperty());
    GroupExpression enforcer = requiredPropertySet.getDistributionProperty()
            .appendEnforcers(groupExpression.getGroup());
    return updateCostAndOutputPropertySet(enforcer, oldOutputProperty, requiredPropertySet);
}

// DistributionProperty.appendEnforcers — the only constructor of the enforcer op
GroupExpression appendEnforcers(Group child) {
    return new GroupExpression(new PhysicalDistributionOperator(spec), Lists.newArrayList(child));
}
```

On the running query this path inserts **`PhysicalDistributionOperator(SHUFFLE_AGG(region))`** between LOCAL and GLOBAL aggregate: LOCAL’s **`outputProperty`** is still **`LOCAL(cust_id)`**, which does not **`isSatisfy`** **`SHUFFLE_AGG(region)`**. The same path inserts **`SHUFFLE_JOIN`** or **`BROADCAST`** at a scan when **`LOCAL`** fails **`isSatisfy`** of the join’s child requirement (several selected partitions, not colocate-eligible).

**3. Bucket shuffle inserts on the join’s right child.** Before **`OutputPropertyDeriver`** on a hash join, **`ChildOutputPropertyGuarantor`** may decide the two **`LOCAL`** children cannot colocate. **`transToBucketShuffleJoin`** builds a **`HashDistributionSpec`** with **`SourceType.BUCKET`** and calls **`enforceChildDistribution`**, which again ends in **`appendEnforcers`** — but the child of the enforcer is the *right child’s group*, not the join’s group.

```java
// ChildOutputPropertyGuarantor.transToBucketShuffle
DistributionSpec rightDistributionSpec = DistributionSpec.createHashDistributionSpec(
        new HashDistributionDesc(bucketShuffleColumns, HashDistributionDesc.SourceType.BUCKET));
enforceChildDistribution(rightDistributionSpec, rightChild, rightChildOutputProperty);

Pair<GroupExpression, PhysicalPropertySet> enforceChildDistribution(
        DistributionSpec distributionSpec, GroupExpression child, PhysicalPropertySet childOutputProperty) {
    DistributionProperty newDistributionProperty = DistributionProperty.createProperty(distributionSpec);
    GroupExpression enforcer = newDistributionProperty.appendEnforcers(child.getGroup());
    // insertEnforceExpression / setBestExpression for BUCKET on that child group
    return new Pair<>(enforcer, newOutputProperty);
}
```

**Join / aggregate requirements (summary).** Shuffle join: both children **`SHUFFLE_JOIN`** on ON keys (or **`LOCAL`** if **`isSatisfy`**). Broadcast: left **`EMPTY`**, right **`ReplicatedDistributionSpec`**. Colocate: both **`LOCAL`**, no join-side enforcer. Bucket shuffle: left **`LOCAL`**, right **`BUCKET`**. Two-phase **`GROUP BY`**: GLOBAL requires **`SHUFFLE_AGG`** of the LOCAL child; scalar **`SUM`** requires **`GATHER`**.

**Worked example — adding enforcers step by step.** Same **`EnforceAndCostTask`** four steps as §3.4.4 on the running statement. Depth-first: steps 1–2 on the way down, children, then steps 3–4 on the way up. Each node is an expression; **`inputs`** are its children.

```sql
SELECT c.region, SUM(o.amount)
FROM orders o
JOIN customers c ON o.cust_id = c.id
WHERE o.dt BETWEEN '2024-01-01' AND '2024-06-30'
GROUP BY c.region;
```

Before enforcers:

```
E5  PhysicalHashAggregate GLOBAL  groupBys=[region]                    inputs=[E4]
 └─ E4 PhysicalHashAggregate LOCAL  groupBys=[region]                  inputs=[E3]
     └─ E3 PhysicalHashJoin INNER  onPredicate=(cust_id = id)          inputs=[E1, E2]
         ├─ E1 PhysicalOlapScan orders     LOCAL(cust_id)              inputs=[]
         └─ E2 PhysicalOlapScan customers  LOCAL(id)                   inputs=[]
```

**Visit E5 (`GLOBAL` HashAggregate) — steps 1–2.** Expression **E5**, input **E4**.

1. **`requiredProperty`** = **`EMPTY`** (root).
2. Child requirement for **E4** = **`SHUFFLE_AGG(region)`** (`partitionByColumns` = **`c.region`**).

**Visit E4 (`LOCAL` HashAggregate) — steps 1–2.** Expression **E4**, input **E3**.

1. **`requiredProperty`** = **`SHUFFLE_AGG(region)`** (from E5).
2. Child requirement for **E3** = **`EMPTY`** (`isLocal()`).

**Visit E3 (`HashJoin`) — steps 1–2.** Expression **E3**, inputs **E1** (left), **E2** (right).

1. **`requiredProperty`** = **`EMPTY`** (from E4).
2. Child-requirement pairs from ON (`cust_id = id`):
   - (**`EMPTY`**, **`BROADCAST`**) on (**E1**, **E2**)
   - (**`SHUFFLE_JOIN(cust_id)`**, **`SHUFFLE_JOIN(id)`**) on (**E1**, **E2**)
   Shuffle pair drives the scan visits below.

**Visit E1 (`OlapScan` orders) — steps 1–4.** Expression **E1**, **`inputs=[]`**.

1. **`requiredProperty`** = **`SHUFFLE_JOIN(cust_id)`**.
2. No child requirements.
3. **`outputProperty`** = **`LOCAL(cust_id)`** (`DISTRIBUTED BY HASH(cust_id)`).
4. **`LOCAL(cust_id)`** **`isSatisfy`** **`SHUFFLE_JOIN(cust_id)`** (one selected partition **`p2024`**). **No enforcer.** Parent E3 reads **E1** output **`LOCAL(cust_id)`**.

**Visit E2 (`OlapScan` customers) — steps 1–4.** Expression **E2**, **`inputs=[]`**.

1. **`requiredProperty`** = **`SHUFFLE_JOIN(id)`**.
2. No child requirements.
3. **`outputProperty`** = **`LOCAL(id)`**.
4. **`isSatisfy`** succeeds. **No enforcer.** Parent E3 reads **E2** output **`LOCAL(id)`**.

**Visit E3 — steps 3–4.** Inputs **E1**, **E2** returned **`LOCAL(cust_id)`** and **`LOCAL(id)`**. **`requiredProperty`** still **`EMPTY`**.

**`ChildOutputPropertyGuarantor`**: the two **`LOCAL`** specs cannot colocate across tables. **`appendEnforcers`** on **E2**’s group inserts **E2′** = **`PhysicalDistributionOperator(BUCKET)`** with **`inputs=[E2]`**. E3’s right input becomes **E2′** (path **3**).

3. **`outputProperty`** of **E3** = **`LOCAL(cust_id)`** (left dominates; right is **`BUCKET`**).
4. **`LOCAL(cust_id)`** satisfies **`EMPTY`**. **No enforcer on E3.** Parent E4 reads **E3** as **`LOCAL(cust_id)`**.

**Visit E4 — steps 3–4.** Input **E3** returned **`LOCAL(cust_id)`**. **`requiredProperty`** still **`SHUFFLE_AGG(region)`**.

3. **`outputProperty`** of **E4** = **`LOCAL(cust_id)`** (copy child).
4. Not **`isSatisfy(SHUFFLE_AGG(region))`**. **`appendEnforcers`** inserts **E4′** = **`PhysicalDistributionOperator(SHUFFLE_AGG(region))`** with **`inputs=[E4]`** (path **2**). Parent E5 reads **E4′** as **`SHUFFLE_AGG(region)`**.

**Visit E5 — steps 3–4.** Input **E4′** returned **`SHUFFLE_AGG(region)`**. **`requiredProperty`** still **`EMPTY`**.

3. **`outputProperty`** of **E5** = **`SHUFFLE_AGG(region)`**.
4. Satisfies **`EMPTY`**. **No enforcer on E5.**

After enforcers:

```
E5  PhysicalHashAggregate GLOBAL  groupBys=[region]  output=SHUFFLE_AGG(region)   inputs=[E4′]
 └─ E4′ PhysicalDistribution SHUFFLE_AGG(region)                                   inputs=[E4]
     └─ E4 PhysicalHashAggregate LOCAL  groupBys=[region]  output=LOCAL(cust_id)   inputs=[E3]
         └─ E3 PhysicalHashJoin INNER  onPredicate=(cust_id = id)  output=LOCAL(cust_id)
                                                                       inputs=[E1, E2′]
             ├─ E1 PhysicalOlapScan orders     LOCAL(cust_id)          inputs=[]
             └─ E2′ PhysicalDistribution BUCKET(id)                    inputs=[E2]
                 └─ E2 PhysicalOlapScan customers  LOCAL(id)           inputs=[]
```

CBO also costs the join’s broadcast pair on (**E1**, **E2**): E1 keeps **`LOCAL`**; E2 fails **`isSatisfy(BROADCAST)`** and path **2** inserts a broadcast enforcer with **`inputs=[E2]`**. If a scan is not colocate-eligible, **`LOCAL`** fails **`isSatisfy(SHUFFLE_JOIN)`** at E1/E2 and path **2** inserts **`PhysicalDistributionOperator(SHUFFLE_JOIN)`** with that scan as its sole input.

### 3.5 Fragmentize (the MPP cut)

Last phase of **`createQueryPlan()`**. Input is the physical **`OptExpression`** from CBO; output is **`ExecPlan.fragments`**: a DAG of **`PlanFragment`**s linked by Exchange edges. Cuts happen only at **`PhysicalDistributionOperator`**.

**`PhysicalDistributionOperator`** cuts become **`ExchangeNode`**s inside new **`PlanFragment`**s. Broadcast keeps one scan with the join:

![Fragmentize: PhysicalOperators to PlanFragments with ExchangeNodes](images/starrocks-mpp-fragmentize.svg)

Both-side **`SHUFFLE_JOIN`** plus **`SHUFFLE_AGG`** (§3.8): three distribution cuts, five fragments after GATHER:

![Fragmentize: both join sides SHUFFLE_JOIN plus SHUFFLE_AGG](images/starrocks-mpp-fragmentize-shuffle.svg)

Bucket shuffle (§3.4.5 **`E2′`**) is between those shapes: the left scan stays with the join (**`LOCAL`** satisfies), the right scan is cut by **`PhysicalDistributionOperator(BUCKET)`**, and **`SHUFFLE_AGG`** still cuts local from global aggregate.

```plantuml
@startuml

class PlanFragmentBuilder {
  + createPhysicalPlan()
  + createOutputFragment()
  + finalizeFragments()
}

class PhysicalPlanTranslator {
  + translate()
  + visitPhysicalDistribution()
  + visitPhysicalHashJoin()
  + visitPhysicalOlapScan()
}

class ExecPlan {
  - fragments : List~PlanFragment~
  - scanNodes : List~ScanNode~
  - outputExprs : List~Expr~
}

abstract class TreeNode {
  # children : List
  + getChildren()
  + getChild()
  + addChild()
  + addChildren()
}

class PlanFragment {
  - fragmentId : PlanFragmentId
  - planRoot : PlanNode
  - dataPartition : DataPartition
  - outputPartition : DataPartition
  - destNode : ExchangeNode
  - sink : DataSink
  + setDestination()
  + setOutputPartition()
}

abstract class PlanNode {
  - id : PlanNodeId
  - fragment : PlanFragment
}

class ExchangeNode {
  - dataPartition : DataPartition
}

class OlapScanNode
class HashJoinNode
class AggregationNode
class ProjectNode

abstract class DataSink
class DataStreamSink
class ResultSink {
  - sinkType : TResultSinkType
}

class DataPartition {
  - type : TPartitionType
  - partitionExprs : List~Expr~
}

class OptExpression {
  - op : Operator
  - inputs : List~OptExpression~
}

class PhysicalDistributionOperator {
  - distributionSpec : DistributionSpec
}

PlanFragmentBuilder --> PhysicalPlanTranslator : translate
PhysicalPlanTranslator ..> OptExpression : visit
PhysicalPlanTranslator ..> PhysicalDistributionOperator : cut
PhysicalPlanTranslator --> ExecPlan : context
ExecPlan o-- PlanFragment : fragments

TreeNode <|-- PlanFragment
TreeNode <|-- PlanNode
PlanFragment --> PlanNode : planRoot
PlanFragment --> DataPartition : dataPartition
PlanFragment --> DataPartition : outputPartition
PlanFragment --> ExchangeNode : destNode
PlanFragment --> DataSink : sink
PlanNode --> PlanFragment : fragment
PlanNode <|-- ExchangeNode
PlanNode <|-- OlapScanNode
PlanNode <|-- HashJoinNode
PlanNode <|-- AggregationNode
PlanNode <|-- ProjectNode
DataSink <|-- DataStreamSink
DataSink <|-- ResultSink
OptExpression --> PhysicalDistributionOperator : op

@enduml
```

**`PlanFragment`** and **`PlanNode`** both extend **`TreeNode`** (as **`TreeNode<PlanFragment>`** and **`TreeNode<PlanNode>`**). **`PlanFragment`** uses **`children`** for the fragment DAG: **`setDestination`** adds the producer as a child of the consumer. **`PlanNode`** uses the same **`TreeNode`** API for the in-fragment operator graph—**`getChild` / `addChild`** hold join inputs, agg/project children, and so on—so a **`HashJoinNode`** (or any non-leaf) is a **`PlanNode`** that can have children. Each fragment’s **`planRoot`** is the root of that operator graph (join, scan, exchange, …).

**`ExchangeNode` and `DataSink`** are the two ends of one MPP edge. They are not interchangeable.

- **`ExchangeNode`** is a **`PlanNode`**: the **receive** side. **`visitPhysicalDistribution`** (and root GATHER in **`createOutputFragment`**) creates it as the **`planRoot`** of the **consumer** fragment. At runtime it pulls batches that remote producers have already shipped (**`transmit_chunk`**). Its **`dataPartition`** is how those producers must hash or broadcast rows (HASH / BROADCAST / UNPARTITIONED). **`EXPLAIN`** prints it as **`EXCHANGE`**.

- **`DataSink`** is attached to a **`PlanFragment`**, not to a **`PlanNode`**: the **send** side of that fragment’s output. **`finalizeFragments` → `createDataSink`** chooses the concrete type from whether the fragment has a destination:
  - **`destNode != null`** → **`DataStreamSink`**: stream to that **`ExchangeNode`** id, partitioned by **`outputPartition`** (the same layout the exchange expects). **`EXPLAIN`**: **`STREAM DATA SINK`** / **`EXCHANGE ID: …`**.
  - **`destNode == null`** (root) → **`ResultSink`**: hand rows to the FE (**`fetch_data`**, usually **`MYSQL_PROTOCAL`**). **`EXPLAIN`**: **`RESULT SINK`**.

So after a cut: producer fragment has **`destNode = ExchangeNode`**, **`outputPartition`**, and later a **`DataStreamSink`**; consumer fragment has that **`ExchangeNode`** as **`planRoot`**. One edge = one sink + one exchange.

**Overall procedure.** **`PlanFragmentBuilder.createPhysicalPlan()`** is a fixed pipeline: allocate the plan shell, walk the physical tree into fragments, optionally GATHER at the root, then attach sinks.

1. **Allocate `ExecPlan`** — holds the growing **`fragments`** list, scan nodes, and column metadata.
2. **Translate** — **`PhysicalPlanTranslator.translate`** does a post-order visit of the physical **`OptExpression`**. Each visitor returns the **`PlanFragment`** whose root is the node just built:
   - **Scan** — new **`PlanFragment`** with **`OlapScanNode`** (or other scan), **`DataPartition.RANDOM`**, append to **`fragments`**.
   - **Join / agg / project / …** — visit children; build a **`PlanNode`**; set it as **`planRoot`** on the surviving fragment (no new fragment unless a child already cut).
   - **`PhysicalDistributionOperator`** — visit the child fragment, then **cut**: new **`ExchangeNode`**, new consumer **`PlanFragment`**, **`inputFragment.setDestination` / `setOutputPartition`**, append consumer to **`fragments`**, return the consumer.
3. **`createOutputFragment`** — if the top fragment is still partitioned (multi-tablet, not short-circuit), add a GATHER **`ExchangeNode`** fragment so the client sees one stream; otherwise hang output exprs on the current top.
4. **`finalizeFragments`** — for every fragment **`createDataSink`**: **`DataStreamSink`** toward **`destNode`** when the fragment has a destination, else **`ResultSink`** on the root. Reverse the fragment list for **`EXPLAIN`** numbering (root = fragment 0), then runtime-filter bookkeeping.

```java
// --- createPhysicalPlan: steps 1-4 ---
ExecPlan createPhysicalPlan(OptExpression plan, ConnectContext connectContext,
        List<ColumnRefOperator> outputColumns, ColumnRefFactory columnRefFactory,
        List<String> colNames, TResultSinkType resultSinkType,
        boolean hasOutputFragment, boolean isShortCircuit) {
    // 1. Allocate ExecPlan
    ExecPlan execPlan = new ExecPlan(connectContext, colNames, plan, outputColumns, isShortCircuit);
    // 2. Translate OptExpression → PlanFragment DAG (cuts at PhysicalDistributionOperator)
    PlanFragment top = new PhysicalPlanTranslator(columnRefFactory).translate(plan, execPlan);
    // 3. Optional root GATHER
    createOutputFragment(top, execPlan, outputColumns, hasOutputFragment);
    // 4. Sinks + EXPLAIN order
    return finalizeFragments(execPlan, resultSinkType);
}

// --- step 2a. translate entry ---
PlanFragment translate(OptExpression optExpression, ExecPlan context) {
    PlanFragment fragment = visit(optExpression, context);  // dispatch by op type
    computeFragmentCost(context, fragment);
    context.setExecGroups(execGroups.getExecGroups());
    return fragment;
}

// --- step 2b. scan: new fragment ---
PlanFragment visitPhysicalOlapScan(OptExpression optExpr, ExecPlan context) {
    OlapScanNode scanNode = /* build from PhysicalOlapScanOperator */;
    PlanFragment fragment =
            new PlanFragment(context.getNextFragmentId(), scanNode, DataPartition.RANDOM);
    context.getFragments().add(fragment);
    return fragment;
}

// --- step 2c. join: visit children, attach HashJoinNode (no cut by itself) ---
PlanFragment visitPhysicalHashJoin(OptExpression optExpr, ExecPlan context) {
    PlanFragment leftFragment = visit(optExpr.inputAt(0), context);
    PlanFragment rightFragment = visit(optExpr.inputAt(1), context);
    return visitPhysicalJoin(leftFragment, rightFragment, ..., optExpr, context);
    // HashJoinNode becomes planRoot of the left-side fragment when right is already an Exchange
}

// --- step 2d. THE CUT: one PhysicalDistributionOperator → one new fragment ---
PlanFragment visitPhysicalDistribution(OptExpression optExpr, ExecPlan context) {
    PlanFragment inputFragment = visit(optExpr.inputAt(0), context);  // producer subtree
    PhysicalDistributionOperator distribution = (PhysicalDistributionOperator) optExpr.getOp();
    ExchangeNode exchangeNode = new ExchangeNode(context.getNextNodeId(),
            inputFragment.getPlanRoot(), distribution.getDistributionSpec().getType());
    DataPartition dataPartition =
            translateDistributionToDataPartition(distribution.getDistributionSpec(), context);
    exchangeNode.setDataPartition(dataPartition);

    PlanFragment fragment =
            new PlanFragment(context.getNextFragmentId(), exchangeNode, dataPartition);
    inputFragment.setDestination(exchangeNode);       // producer → this Exchange
    inputFragment.setOutputPartition(dataPartition);  // HASH / BROADCAST / ...
    context.getFragments().add(fragment);
    return fragment;  // consumer continues above the Exchange
}

// --- step 3. createOutputFragment: GATHER when top is still partitioned ---
void createOutputFragment(PlanFragment inputFragment, ExecPlan execPlan,
        List<ColumnRefOperator> outputColumns, boolean hasOutputFragment) {
    if (inputFragment.getPlanRoot() instanceof ExchangeNode
            || !inputFragment.isPartitioned() || !hasOutputFragment) {
        inputFragment.setOutputExprs(/* output exprs */);
        return;
    }
    // single-tablet / short-circuit: ResultSink on this fragment, no extra GATHER
    if (/* one tablet or shortCircuit */) {
        inputFragment.setOutputExprs(/* output exprs */);
        return;
    }
    ExchangeNode exchangeNode = new ExchangeNode(execPlan.getNextNodeId(),
            inputFragment.getPlanRoot(), DataPartition.UNPARTITIONED);
    PlanFragment exchangeFragment =
            new PlanFragment(execPlan.getNextFragmentId(), exchangeNode, DataPartition.UNPARTITIONED);
    inputFragment.setDestination(exchangeNode);
    inputFragment.setOutputPartition(DataPartition.UNPARTITIONED);
    execPlan.getFragments().add(exchangeFragment);
}

// --- step 4. finalizeFragments: DataStreamSink vs ResultSink, reverse list ---
ExecPlan finalizeFragments(ExecPlan execPlan, TResultSinkType resultSinkType) {
    for (PlanFragment fragment : execPlan.getFragments()) {
        fragment.createDataSink(resultSinkType, execPlan);
    }
    Collections.reverse(execPlan.getFragments());  // root → fragment 0 in EXPLAIN
    // runtime-filter waiting sets / adaptive DOP ...
    return execPlan;
}

void PlanFragment.createDataSink(TResultSinkType resultSinkType, ExecPlan execPlan) {
    if (destNode != null) {
        DataStreamSink streamSink = new DataStreamSink(destNode.getId());
        streamSink.setPartition(outputPartition);
        sink = streamSink;           // intermediate edge → Exchange
    } else {
        sink = new ResultSink(planRoot.getId(), resultSinkType);  // root → FE fetch_data
    }
}
```

A shuffle join sets the child’s output to **`TPartitionType.HASH_PARTITIONED`** on the join keys (`computeShuffleHashBucketPlanFragment`). A two-phase aggregate sets the local (update serialize) fragment’s output partition to **`DataPartition.hashPartitioned(group keys)`** so the merge (merge finalize) fragment receives one group on one worker.

### 3.6 Schedule

After fragmentize, **`ExecPlan`** holds **`fragments`**, **`scanNodes`**, and the descriptor table. Schedule turns that into an **`ExecutionDAG`**: every **`PlanFragment`** becomes an **`ExecutionFragment`** with **`FragmentInstance`**s bound to workers. CBO only named bucket layouts; this step chooses machines, tablet scan ranges, and the exact peer list each producer will shuffle to. Deploy (§3.7) only serializes that binding and ships it—the FE succeeds at distributed execution because **schedule already finished the hard decisions**.

**Mechanism: build a complete execution contract.** A worker can start without calling the FE for topology only if its **`TExecPlanFragmentParams`** already answers four questions: *where do I run*, *what do I scan*, *whom do I send to*, and *when is an Exchange input complete*. Schedule answers them in order.

| Decision | Where it lands | How schedule decides |
|----------|----------------|----------------------|
| Worker for each instance | **`FragmentInstance.worker`** | Scan fragments: **`LocalFragmentAssignmentStrategy`** + **`BackendSelector`** (tablet replica / lake shard → BE or CN). Exchange-only fragments: **`RemoteFragmentAssignmentStrategy`** (GATHER → one worker; shuffle/join stages → workers derived from child instances or the compute-node set). |
| Tablets / files per instance | **`FragmentInstance.node2ScanRanges`** | After range→worker assignment, pack that worker’s **`TScanRangeParams`** onto one instance so each replica is scanned once and locality is preserved. |
| Producer → consumer peers | **`ExecutionFragment.destinations`** (`TPlanFragmentDestination`: peer **`fragment_instance_id`** + **`brpc_server`**) | **`ExecutionDAG.finalizeDAG()` → `connectFragmentToDestFragments`**: for each non-root fragment, enumerate the dest fragment’s instances (or bucket→instance map for local bucket shuffle) and record brpc addresses. |
| Exchange completeness | **`numSendersPerExchange`** | Same connect step: dest Exchange id ← sum of producer **`instances.size()`** (multiple upstream fragments may feed one merge Exchange). |
| FE result pull | **`ResultReceiver`** | **`prepareResultSink`**: root fragment must have a single instance; bind its id and worker brpc address for later **`fetch_data`**. |

**Post-order is required.** **`computeFragmentInstances`** walks **`getFragmentsInPostorder()`** so child (producer) instances exist before a parent (consumer) is assigned. Remote stages can then copy or expand from child worker sets; **`finalizeDAG`** can point each producer at concrete consumer instance ids. Pre-order would leave destinations unresolved.

**Local vs remote assignment.** A fragment whose leftmost node is a scan is *local*: data location drives placement. A fragment whose inputs arrive only through **`ExchangeNode`** is *remote*: placement follows parallelism and child hosts (or preferred CNs), not tablet maps. GATHER collapses to one instance so the FE has a single **`ResultSink`** endpoint.

**Invariants checked before deploy.** **`validateExecutionDAG`** rejects multi-instance roots with **`ResultSink`** (and similar single-sink constraints). After **`finalizeDAG`**, every producer’s **`destinations`** and every consumer’s sender counts are fixed; intermediate **`transmit_chunk`** never needs the FE.

**Overall procedure.** From **`handleQueryStmt(execPlan)`** through assignment (deploy is §3.7):

1. **Read `ExecPlan`** — **`getFragments()`**, **`getScanNodes()`**, **`descTbl.toThrift()`**.
2. **Build coordinator** — **`createQueryScheduler`** wraps them in a **`JobSpec`** and constructs **`DefaultCoordinator`** (builds **`ExecutionDAG`** / **`CoordinatorPreprocessor`** from those fragments).
3. **Register** — **`QeProcessorImpl.registerQuery`** so status reports can find this **`coord`**.
4. **Start scheduling** — **`execWithQueryDeployExecutor` → `startScheduling`**: queue wait, then **`prepareExec`**, then deploy.
5. **`prepareExec`** — **`computeFragmentInstances`** (assign each fragment to workers), **`prepareResultSink`** (root instance → **`ResultReceiver`**).
6. **Assign instances** — for each **`ExecutionFragment`** in post-order: scan fragments use **`LocalFragmentAssignmentStrategy`** (tablet → replica BE / lake shard → CN); exchange-only fragments use **`RemoteFragmentAssignmentStrategy`**. Then **`executionDAG.finalizeDAG()`** fills Exchange **`destinations`** and **`numSendersPerExchange`**.

```plantuml
@startuml

class ExecPlan {
  - fragments : List~PlanFragment~
  - scanNodes : List~ScanNode~
  + getFragments()
  + getScanNodes()
  + getDescTbl()
}

class JobSpec {
  - fragments : List~PlanFragment~
  - scanNodes : List~ScanNode~
  - descTable : TDescriptorTable
  - queryId : TUniqueId
  + fromQuerySpec()
  + getFragments()
}

class DefaultCoordinator {
  - jobSpec : JobSpec
  - coordinatorPreprocessor : CoordinatorPreprocessor
  - executionDAG : ExecutionDAG
  - receiver : ResultReceiver
  + prepareExec()
  + startScheduling()
  + prepareResultSink()
  + deliverExecFragments()
  + getNext()
}

class CoordinatorPreprocessor {
  - jobSpec : JobSpec
  - executionDAG : ExecutionDAG
  - lazyWorkerProvider : LazyWorkerProvider
  + prepareExec()
  + computeFragmentInstances()
}

class FragmentAssignmentStrategyFactory {
  + create()
}

interface FragmentAssignmentStrategy {
  + assignFragmentToWorker()
}

class LocalFragmentAssignmentStrategy
class RemoteFragmentAssignmentStrategy

class ExecutionDAG {
  - fragments : List~ExecutionFragment~
  - idToFragment : Map~PlanFragmentId, ExecutionFragment~
  - instanceIdToInstance : Map~TUniqueId, FragmentInstance~
  + build()
  + getFragmentsInPostorder()
  + getRootFragment()
  + finalizeDAG()
}

class ExecutionFragment {
  - planFragment : PlanFragment
  - instances : List~FragmentInstance~
  - destinations : List~TPlanFragmentDestination~
  - scanRangeAssignment : FragmentScanRangeAssignment
  + addInstance()
  + getInstances()
  + addDestination()
  + getScanNodes()
}

class FragmentInstance {
  - instanceId : TUniqueId
  - worker : ComputeNode
  - execFragment : ExecutionFragment
  - node2ScanRanges : Map~Integer, List~TScanRangeParams~~
  + getWorkerId()
  + addScanRanges()
}

class PlanFragment {
  - fragmentId : PlanFragmentId
  - planRoot : PlanNode
  - sink : DataSink
  - destNode : ExchangeNode
}

class ResultReceiver {
  - finstId : TUniqueId
  - address : TNetworkAddress
  + getNext()
}

class ComputeNode {
  - id : long
  + getBrpcAddress()
}

ExecPlan ..> JobSpec : fromQuerySpec
JobSpec --> PlanFragment : fragments
DefaultCoordinator --> JobSpec : jobSpec
DefaultCoordinator --> CoordinatorPreprocessor
DefaultCoordinator --> ExecutionDAG
DefaultCoordinator --> ResultReceiver : receiver
CoordinatorPreprocessor --> ExecutionDAG
CoordinatorPreprocessor --> FragmentAssignmentStrategyFactory
FragmentAssignmentStrategyFactory --> FragmentAssignmentStrategy : create
FragmentAssignmentStrategy <|-- LocalFragmentAssignmentStrategy
FragmentAssignmentStrategy <|-- RemoteFragmentAssignmentStrategy
FragmentAssignmentStrategy ..> ExecutionFragment : assignFragmentToWorker
ExecutionDAG o-- ExecutionFragment : fragments
ExecutionFragment --> PlanFragment : planFragment
ExecutionFragment o-- FragmentInstance : instances
FragmentInstance --> ComputeNode : worker
FragmentInstance --> ExecutionFragment : execFragment
ResultReceiver ..> FragmentInstance : root instanceId

@enduml
```

A **`PlanFragment`** is still one stage. **`ExecutionFragment`** is that stage plus assignment: **`instances`** and Exchange **`destinations`**. Each **`FragmentInstance`** is one run of the stage on one **`worker`**, with **`node2ScanRanges`** (tablet ids) for scans.

```java
// --- steps 1-4: ExecPlan → coordinator → register → schedule ---
void handleQueryStmt(ExecPlan execPlan) throws Exception {
    List<PlanFragment> fragments = execPlan.getFragments();
    List<ScanNode> scanNodes = execPlan.getScanNodes();
    TDescriptorTable descTable = execPlan.getDescTbl().toThrift();

    coord = getCoordinatorFactory().createQueryScheduler(
            context, fragments, scanNodes, descTable, execPlan);

    QeProcessorImpl.INSTANCE.registerQuery(context.getExecutionId(),
            new QeProcessorImpl.QueryInfo(context, ..., coord));

    coord.execWithQueryDeployExecutor(context);  // → startScheduling
    // then getNext() / collect results (§3.7)
}

DefaultCoordinator createQueryScheduler(ConnectContext context, List<PlanFragment> fragments,
        List<ScanNode> scanNodes, TDescriptorTable descTable, ExecPlan execPlan) {
    JobSpec jobSpec = JobSpec.Factory.fromQuerySpec(
            context, fragments, scanNodes, descTable, TQueryType.SELECT, execPlan);
    return new DefaultCoordinator(context, jobSpec);  // ExecutionDAG from jobSpec fragments
}

void startScheduling(ScheduleOption option) throws Exception {
    QueryQueueManager.getInstance().maybeWait(connectContext, this);
    prepareExec();                 // step 5: instances + ResultReceiver
    deliverExecFragments(option);  // §3.7 deploy + collect
}

// --- step 5: prepareExec ---
void DefaultCoordinator.prepareExec() throws StarRocksException {
    coordinatorPreprocessor.prepareExec();  // computeFragmentInstances
    prepareResultSink();
    prepareProfile();
}

void CoordinatorPreprocessor.prepareExec() throws StarRocksException {
    resetExec();                 // capture available workers
    computeFragmentInstances();  // step 6
}

// --- step 6: PlanFragment → FragmentInstance on workers ---
void computeFragmentInstances() throws StarRocksException {
    for (ExecutionFragment execFragment : executionDAG.getFragmentsInPostorder()) {
        fragmentAssignmentStrategyFactory
                .create(execFragment, lazyWorkerProvider.get())
                .assignFragmentToWorker(execFragment);
    }
    executionDAG.finalizeDAG();  // destinations[] + numSendersPerExchange per Exchange
}

// LocalFragmentAssignmentStrategy (scan fragments):
void assignFragmentToWorker(ExecutionFragment execFragment) throws StarRocksException {
    for (ScanNode scanNode : execFragment.getScanNodes()) {
        assignScanRangesToWorker(execFragment, scanNode);  // tablet → BackendSelector → BE/CN
    }
    assignScanRangesToFragmentInstancePerWorker(execFragment);
    // one FragmentInstance per chosen worker, node2ScanRanges = that worker's tablets
}

// RemoteFragmentAssignmentStrategy (exchange-only): GATHER → 1 instance;
// otherwise workers from child instances / compute nodes (parallelism)

// finalizeDAG (normal fragment): producer destinations = every dest instance
void connectNormalFragmentToDestFragments(ExecutionFragment execFragment) {
    ExecutionFragment dest = idToFragment.get(fragment.getDestFragment().getFragmentId());
    dest.getNumSendersPerExchange().compute(exchangeId, (k, n) ->
            (n == null ? 0 : n) + execFragment.getInstances().size());
    for (FragmentInstance destInstance : dest.getInstances()) {
        TPlanFragmentDestination d = new TPlanFragmentDestination();
        d.setFragment_instance_id(destInstance.getInstanceId());
        d.setBrpc_server(destInstance.getWorker().getBrpcIpAddress());
        execFragment.addDestination(d);
    }
}

// after instances exist: root ResultReceiver for FE fetch_data
void prepareResultSink() {
    ExecutionFragment root = executionDAG.getRootFragment();
    FragmentInstance rootInstance = root.getInstances().get(0);
    ComputeNode worker = workerProvider.getWorkerById(rootInstance.getWorkerId());
    receiver = new ResultReceiver(rootInstance.getInstanceId(), workerId,
            worker.getBrpcAddress(), timeoutMs);
}
```

A scan fragment becomes one **`FragmentInstance`** per chosen worker, each carrying that worker’s **`TScanRangeParams`**. The same **`PlanFragment`** therefore runs in parallel without the FE copying rows. After **`finalizeDAG`**, every shuffle edge is an instance-to-instance address list; deploy only has to deliver that contract to each worker.

### 3.7 Deploy and collect results

Schedule (§3.6) produced an **`ExecutionDAG`** of **`FragmentInstance`**s with workers, scan ranges, Exchange **`destinations`**, and sender counts already fixed. Deploy ships each instance to its worker so the BE/CN can build the pipeline. The FE does **not** send rows on deploy—only the plan, descriptors, scan ranges, and those destinations. Intermediate batches then move worker-to-worker as **`transmit_chunk`**; the FE only **`fetch_data`**s the root. Pipeline internals are in [Backend and Compute Node](../backend/). Workers report progress via Thrift **`FrontendService.reportExecStatus`** → **`DefaultCoordinator.updateFragmentExecStatus()`** (cancel on failure, know when the root finishes).

![Deploy and collect: FE control plane vs BE-to-BE data plane](images/starrocks-mpp-deploy-collect.svg)

```plantuml
@startuml

class DefaultCoordinator {
  - executionDAG : ExecutionDAG
  - receiver : ResultReceiver
  + deliverExecFragments()
  + prepareResultSink()
  + getNext()
  + updateFragmentExecStatus()
}

interface ExecutionSchedule {
  + prepareSchedule()
  + schedule()
}

class AllAtOnceExecutionSchedule
class PhasedExecutionSchedule

class Deployer {
  - jobSpec : JobSpec
  - executionDAG : ExecutionDAG
  - needDeploy : boolean
  + createFragmentExecStates()
  + deployFragments()
}

class DeployState {
  - threeStageExecutionsToDeploy : List
}

class TFragmentInstanceFactory {
  + create()
  + toThriftFromCommonParams()
  + toThriftForUniqueParams()
}

class FragmentInstanceExecState {
  - instanceId : TUniqueId
  - worker : ComputeNode
  - requestToDeploy : TExecPlanFragmentParams
  - serializedRequest : byte[]
  - deployFuture : Future
  + serializeRequest()
  + deployAsync()
  + waitForDeploymentCompletion()
}

class TExecPlanFragmentParams {
  - fragment : TPlanFragment
  - desc_tbl : TDescriptorTable
  - params : TPlanFragmentExecParams
  - coord : TNetworkAddress
  - query_options : TQueryOptions
  - is_pipeline : boolean
  - pipeline_dop : i32
}

class TPlanFragmentExecParams {
  - query_id : TUniqueId
  - fragment_instance_id : TUniqueId
  - per_node_scan_ranges : Map
  - destinations : List~TPlanFragmentDestination~
  - per_exch_num_senders : Map
}

class TPlanFragmentDestination {
  - fragment_instance_id : TUniqueId
  - brpc_server : TNetworkAddress
}

class BackendServiceClient {
  + execPlanFragmentAsync()
  + fetchDataAsync()
}

class PExecPlanFragmentRequest {
  - attachment_protocol : string
}

class PExecPlanFragmentResult {
  - status : StatusPB
}

class ResultReceiver {
  - finstId : PUniqueId
  - address : TNetworkAddress
  - backendId : Long
  + getNext()
}

class PFetchDataRequest {
  - finst_id : PUniqueId
}

class PFetchDataResult {
  - packet_seq : i64
  - eos : bool
  - query_statistics : PQueryStatistics
}

class FragmentInstance {
  - instanceId : TUniqueId
  - worker : ComputeNode
  - node2ScanRanges : Map
}

DefaultCoordinator --> ExecutionSchedule : scheduler
DefaultCoordinator --> Deployer : deliverExecFragments
DefaultCoordinator --> ResultReceiver : receiver
ExecutionSchedule <|-- AllAtOnceExecutionSchedule
ExecutionSchedule <|-- PhasedExecutionSchedule
ExecutionSchedule --> Deployer : schedule
Deployer --> DeployState : createFragmentExecStates
Deployer --> TFragmentInstanceFactory : create
Deployer o-- FragmentInstanceExecState : deployFragments
TFragmentInstanceFactory ..> FragmentInstance : create
TFragmentInstanceFactory ..> TExecPlanFragmentParams : build
FragmentInstanceExecState --> TExecPlanFragmentParams : requestToDeploy
FragmentInstanceExecState --> BackendServiceClient : deployAsync
TExecPlanFragmentParams *-- TPlanFragmentExecParams : params
TPlanFragmentExecParams o-- TPlanFragmentDestination : destinations
BackendServiceClient ..> PExecPlanFragmentRequest : exec_plan_fragment
BackendServiceClient ..> PExecPlanFragmentResult : reply
ResultReceiver --> BackendServiceClient : fetchDataAsync
ResultReceiver ..> PFetchDataRequest
BackendServiceClient ..> PFetchDataResult : fetch_data reply

@enduml
```

**Deploy procedure.**

1. **`deliverExecFragments`** builds a **`Deployer`**, then the execution schedule (**`AllAtOnceExecutionSchedule`** or phased) groups concurrent fragments.
2. **`createFragmentExecStates`** — for each instance, **`TFragmentInstanceFactory.create`** builds a **`TExecPlanFragmentParams`** and wraps it in a **`FragmentInstanceExecState`**.
3. Optional concurrent **`serializeRequest`** (Thrift → bytes).
4. **`deployAsync`** — brpc **`exec_plan_fragment`** to that worker’s **`brpc_port`**.
5. **`waitForDeploymentCompletion`** — each RPC returns **`PExecPlanFragmentResult`** (`StatusPB`); failure cancels remaining instances.

**Wire format (FE → BE deploy).** The RPC is brpc protobuf; the plan payload is Thrift.

| Layer | Type | Role |
|-------|------|------|
| Transport | brpc to worker **`brpc_port`** | **`PInternalService.exec_plan_fragment`** |
| RPC envelope | **`PExecPlanFragmentRequest`** | `attachment_protocol` (`binary` / `compact` / `json`); body is attachment bytes |
| Attachment | Thrift **`TExecPlanFragmentParams`** | One fragment instance’s full exec request |
| Reply | **`PExecPlanFragmentResult`** | **`StatusPB`** (ok or error); not query rows |

**`TExecPlanFragmentParams`** is the unit of deploy. Shared plan shape vs per-instance binding:

| Field | Content |
|-------|---------|
| **`fragment`** (`TPlanFragment`) | **`plan`** (operator tree), **`output_sink`** (`TDataStreamSink` / `TResultSink` / …), **`partition`** |
| **`desc_tbl`** | Slot / tuple descriptors |
| **`params`** (`TPlanFragmentExecParams`) | **`query_id`**, **`fragment_instance_id`**, **`per_node_scan_ranges`** (this worker’s tablets), **`destinations`**, **`per_exch_num_senders`** |
| **`coord`** | FE address for later **`reportExecStatus`** |
| **`query_globals` / `query_options`** | Timezone, timeouts, mem limits, pipeline flags |
| **`is_pipeline` / `pipeline_dop` / `workgroup`** | Pipeline engine and resource group |

**`params.destinations`** is the Exchange fan-out for this instance: each **`TPlanFragmentDestination`** has the peer **`fragment_instance_id`** and **`brpc_server`**. The sink’s **`output_partition`** (HASH / BROADCAST / UNPARTITIONED) decides how chunks are keyed onto that list. After deploy, producers **`transmit_chunk`** directly to those addresses—the FE is off the intermediate data path.

```java
// --- deliverExecFragments: Deployer + schedule ---
void deliverExecFragments(ScheduleOption option) throws Exception {
    Deployer deployer = new Deployer(connectContext, jobSpec, executionDAG,
            coordinatorPreprocessor.getCoordAddress(), this::handleErrorExecution, option.doDeploy);
    scheduler.prepareSchedule(this, deployer, executionDAG);
    scheduler.schedule(option);  // createFragmentExecStates → deployFragments
}

// --- build one TExecPlanFragmentParams per FragmentInstance ---
TExecPlanFragmentParams create(FragmentInstance instance, TDescriptorTable descTable, ...) {
    TExecPlanFragmentParams result = new TExecPlanFragmentParams();
    toThriftFromCommonParams(result, instance.getExecFragment(), descTable, ...);
    toThriftForUniqueParams(result, instance, ...);
    return result;
}

void toThriftFromCommonParams(TExecPlanFragmentParams result, ExecutionFragment execFragment, ...) {
    result.setProtocol_version(InternalServiceVersion.V1);
    result.setFragment(execFragment.getPlanFragment().toThrift());  // plan + output_sink
    result.setDesc_tbl(descTable);
    result.setCoord(coordAddress);
    result.setQuery_globals(jobSpec.getQueryGlobals());
    result.setQuery_options(jobSpec.getQueryOptions());
    result.setIs_pipeline(true);

    result.setParams(new TPlanFragmentExecParams());
    result.params.setQuery_id(jobSpec.getQueryId());
    result.params.setDestinations(execFragment.getDestinations());
    result.params.setPer_exch_num_senders(execFragment.getNumSendersPerExchange());
    result.params.setNum_senders(execFragment.getInstances().size());
}

void toThriftForUniqueParams(TExecPlanFragmentParams result, FragmentInstance instance, ...) {
    result.setBackend_num(instance.getIndexInJob());
    result.setPipeline_dop(instance.getPipelineDop());
    result.params.setFragment_instance_id(instance.getInstanceId());
    result.params.setPer_node_scan_ranges(instance.getNode2ScanRanges());  // this worker's tablets
    result.params.setSender_id(instance.getIndexInFragment());
}

// --- brpc deploy ---
void Deployer.deployFragments(DeployState deployState) throws Exception {
    for (List<FragmentInstanceExecState> executions : threeStageExecutionsToDeploy) {
        executions.forEach(FragmentInstanceExecState::deployAsync);
        waitForDeploymentCompletion(executions);  // PExecPlanFragmentResult.status
    }
}

void FragmentInstanceExecState.deployAsync() {
    TNetworkAddress brpcAddress = worker.getBrpcAddress();
    deployFuture = BackendServiceClient.getInstance()
            .execPlanFragmentAsync(brpcAddress, requestToDeploy /* or serializedRequest */,
                    jobSpec.getPlanProtocol());
}
```

On the worker, **`exec_plan_fragment`** deserializes the Thrift attachment into **`TExecPlanFragmentParams`**, builds the pipeline from **`fragment.plan`** / **`output_sink`**, opens scan ranges from **`per_node_scan_ranges`**, and registers Exchange receivers for **`destinations`**.

**Collect results (FE ← root worker).** After deploy, the session thread only talks to the root instance. **`ResultReceiver`** (built in **`prepareResultSink`**, §3.6) issues brpc **`fetch_data`**; **`StmtExecutor`** loops until EOS and writes MySQL packets.

| Layer | Type | Role |
|-------|------|------|
| Transport | brpc | **`PInternalService.fetch_data`** |
| Request | **`PFetchDataRequest`** | root **`fragment_instance_id`** |
| Reply | **`PFetchDataResult`** | serialized **`TResultBatch`** or EOS |

```java
do {
    batch = coord.getNext();           // ResultReceiver → fetchDataAsync(root worker)
    responseRowBatch(..., batch, channel);
} while (!batch.isEos());

PFetchDataRequest request = new PFetchDataRequest(finstId);
Future<PFetchDataResult> future = BackendServiceClient.getInstance().fetchDataAsync(address, request);
// deserialize TResultBatch from the serialized payload
```

### 3.8 Query examples


#### 3.8.1 Simple query

Partition **`p2024`** has two tablets (**`BUCKETS 2`**): tablet **100** (replicas on BE 10001 / 10002) and tablet **101** (replicas on BE 10002 / 10003).

```sql
CREATE TABLE sales (
    dt     DATE,
    id     BIGINT,
    amount DECIMAL(12, 2)
)
DUPLICATE KEY(dt, id)
PARTITION BY RANGE(dt) (
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01'))
)
DISTRIBUTED BY HASH(id) BUCKETS 2;

SELECT id, amount
FROM sales
WHERE dt = '2024-06-01';
```

**PlanFragment shape** (after fragmentize / finalize)

```
PlanFragment F00
  fragmentId: F00
  dataPartition: UNPARTITIONED
  outputPartition: UNPARTITIONED
  planRoot: ExchangeNode(id=1)              -- GATHER
  destNode: null
  sink: ResultSink
  children: [ F01 ]                         -- TreeNode: producer fragments
  outputExprs: [ id, amount ]

PlanFragment F01
  fragmentId: F01
  dataPartition: RANDOM
  outputPartition: UNPARTITIONED            -- STREAM DATA SINK / EXCHANGE 01
  planRoot: OlapScanNode(id=0, table=sales)
    predicates: dt = '2024-06-01'
  destNode: ExchangeNode(id=1) on F00
  sink: DataStreamSink(exchNodeId=1, UNPARTITIONED)
  children: []
```

![Simple query PlanFragment tree](images/starrocks-mpp-ex-simple-planfragment.svg)

**ExecutionFragment shape** (3 BEs: 10001, 10002, 10003)

```
ExecutionFragment
  fragmentIndex: 0
  planFragment: F00
  destinations: []
  numSendersPerExchange: { 1 -> 2 }
  instances:
    FragmentInstance
      indexInJob: 0
      indexInFragment: 0
      worker: ComputeNode(id=10003)
      node2ScanRanges: {}

ExecutionFragment
  fragmentIndex: 1
  planFragment: F01
  scanRangeAssignment:
    10001 -> { 0 -> [ tablet 100 ] }
    10002 -> { 0 -> [ tablet 101 ] }
  destinations:
    - fragment_instance_id: (0, F00#0)
      brpc_server: 10.0.0.3:8060
  instances:
    FragmentInstance
      indexInJob: 1
      indexInFragment: 0
      worker: ComputeNode(id=10001)
      node2ScanRanges: { 0 -> [ tablet 100 ] }
    FragmentInstance
      indexInJob: 2
      indexInFragment: 1
      worker: ComputeNode(id=10002)
      node2ScanRanges: { 0 -> [ tablet 101 ] }
```

![Simple query ExecutionFragment: storage + compute per BE](images/starrocks-mpp-ex-simple-execution.svg)

#### 3.8.2 Complete join and aggregate

Tables are not colocated on the join key; CBO uses **`HASH_PARTITIONED`** on **`cust_id` / `id`**, local then merge aggregate on **`region`**, then GATHER.

```sql
CREATE TABLE orders (
    dt      DATE,
    cust_id BIGINT,
    amount  DECIMAL(12, 2)
)
DUPLICATE KEY(dt, cust_id)
PARTITION BY RANGE(dt) (
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01'))
)
DISTRIBUTED BY HASH(cust_id) BUCKETS 8;

CREATE TABLE customers (
    id     BIGINT,
    region VARCHAR(32)
)
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

SELECT c.region, SUM(o.amount)
FROM orders o
JOIN customers c ON o.cust_id = c.id
WHERE o.dt BETWEEN '2024-01-01' AND '2024-06-30'
GROUP BY c.region;
```

**PlanFragment shape** (after fragmentize / finalize)

```
PlanFragment F00
  fragmentId: F00
  dataPartition: UNPARTITIONED
  outputPartition: UNPARTITIONED
  planRoot: ExchangeNode(id=9)              -- GATHER
  destNode: null
  sink: ResultSink
  children: [ F01 ]
  outputExprs: [ region, sum ]

PlanFragment F01
  fragmentId: F01
  dataPartition: HASH_PARTITIONED(region)
  outputPartition: UNPARTITIONED
  planRoot: AggregationNode(id=8, merge finalize)
    child: ExchangeNode(id=7)               -- HASH region
  destNode: ExchangeNode(id=9) on F00
  sink: DataStreamSink(exchNodeId=9, UNPARTITIONED)
  children: [ F02 ]

PlanFragment F02
  fragmentId: F02
  dataPartition: HASH_PARTITIONED(cust_id)
  outputPartition: HASH_PARTITIONED(region)
  planRoot: AggregationNode(id=6, update serialize STREAMING)
    child: ProjectNode(id=5)
      child: HashJoinNode(id=4)
        left:  ExchangeNode(id=2)           -- HASH o.cust_id
        right: ExchangeNode(id=3)           -- HASH c.id
  destNode: ExchangeNode(id=7) on F01
  sink: DataStreamSink(exchNodeId=7, HASH_PARTITIONED(region))
  children: [ F03, F04 ]

PlanFragment F03
  fragmentId: F03
  dataPartition: RANDOM
  outputPartition: HASH_PARTITIONED(cust_id)
  planRoot: OlapScanNode(id=1, table=orders)
    predicates: dt BETWEEN ...
  destNode: ExchangeNode(id=2) on F02
  sink: DataStreamSink(exchNodeId=2, HASH_PARTITIONED(cust_id))
  children: []

PlanFragment F04
  fragmentId: F04
  dataPartition: RANDOM
  outputPartition: HASH_PARTITIONED(id)
  planRoot: OlapScanNode(id=0, table=customers)
  destNode: ExchangeNode(id=3) on F02
  sink: DataStreamSink(exchNodeId=3, HASH_PARTITIONED(id))
  children: []
```

![Complete query PlanFragment tree](images/starrocks-mpp-ex-complete-planfragment.svg)

**ExecutionFragment shape** (3 BEs; reduced instance counts)

```
ExecutionFragment
  fragmentIndex: 0
  planFragment: F00
  destinations: []
  numSendersPerExchange: { 9 -> 2 }
  instances:
    FragmentInstance { indexInJob: 0, indexInFragment: 0, worker: 10001 }

ExecutionFragment
  fragmentIndex: 1
  planFragment: F01
  destinations:
    - { fragment_instance_id: F00#0, brpc_server: 10.0.0.1:8060 }
  numSendersPerExchange: { 7 -> 2 }
  instances:
    FragmentInstance { indexInJob: 1, indexInFragment: 0, worker: 10001 }
    FragmentInstance { indexInJob: 2, indexInFragment: 1, worker: 10002 }

ExecutionFragment
  fragmentIndex: 2
  planFragment: F02
  destinations:
    - { fragment_instance_id: F01#0, brpc_server: 10.0.0.1:8060 }
    - { fragment_instance_id: F01#1, brpc_server: 10.0.0.2:8060 }
  numSendersPerExchange: { 2 -> 2, 3 -> 2 }
  instances:
    FragmentInstance { indexInJob: 3, indexInFragment: 0, worker: 10001 }
    FragmentInstance { indexInJob: 4, indexInFragment: 1, worker: 10002 }

ExecutionFragment
  fragmentIndex: 3
  planFragment: F03
  scanRangeAssignment:
    10001 -> { 1 -> [ tablet 201, 202 ] }
    10003 -> { 1 -> [ tablet 203, 204 ] }
  destinations:
    - { fragment_instance_id: F02#0, brpc_server: 10.0.0.1:8060 }
    - { fragment_instance_id: F02#1, brpc_server: 10.0.0.2:8060 }
  instances:
    FragmentInstance
      indexInJob: 5
      indexInFragment: 0
      worker: 10001
      node2ScanRanges: { 1 -> [ tablet 201, 202 ] }
    FragmentInstance
      indexInJob: 6
      indexInFragment: 1
      worker: 10003
      node2ScanRanges: { 1 -> [ tablet 203, 204 ] }

ExecutionFragment
  fragmentIndex: 4
  planFragment: F04
  scanRangeAssignment:
    10002 -> { 0 -> [ tablet 301, 302 ] }
    10003 -> { 0 -> [ tablet 303, 304 ] }
  destinations:
    - { fragment_instance_id: F02#0, brpc_server: 10.0.0.1:8060 }
    - { fragment_instance_id: F02#1, brpc_server: 10.0.0.2:8060 }
  instances:
    FragmentInstance
      indexInJob: 7
      indexInFragment: 0
      worker: 10002
      node2ScanRanges: { 0 -> [ tablet 301, 302 ] }
    FragmentInstance
      indexInJob: 8
      indexInFragment: 1
      worker: 10003
      node2ScanRanges: { 0 -> [ tablet 303, 304 ] }
```

![Complete query ExecutionFragment: storage + compute per BE](images/starrocks-mpp-ex-complete-execution.svg)

CBO may use **broadcast** or **colocate / local bucket shuffle** instead of both-side join shuffle; scan **`ExecutionFragment`** instances remain, while join-side **`destinations`** change.


## 4. Load transaction

A StarRocks **transaction** is not a client SQL `BEGIN`/`COMMIT`. **`DmlStmt.txnId`** is a **load transaction**: one INSERT, UPDATE, DELETE, MERGE, or stream load. The id is **globally unique** (`TransactionIdGenerator`) so FE and BEs can name one in-flight write; it is **not** the visibility watermark. Readers see data by **tablet / partition version**. On commit, FE assigns each touched partition a new **`PartitionCommitInfo.version`** (usually **`partition.getNextVersion()`**, i.e. visible + 1)—independent of the txn id. **Publish** then tells BEs: install the unpublished rowsets tagged with that **`txnId`** as version **V**. After publish, scans use **V**; the txn id is only the staging key. **`StatementPlanner`** calls **`beginTransaction()`** for DML; **`GlobalTransactionMgr`** creates a **`TransactionState`** (label; source usually **`INSERT_STREAMING`**). BE writers attach rowsets to that id. **Abort** drops unpublished deltas. **`SELECT`**, **`EXPLAIN`** (except **`EXPLAIN ANALYZE`**), **`INSERT INTO FILES`**, and old non-PK delete skip begin. Non-zero **`session.getTxnId()`** reuses the id (grouped inserts).

```plantuml
@startuml

class GlobalTransactionMgr {
  - dbIdToDatabaseTransactionMgrs : Map<Long, DatabaseTransactionMgr>
  - idGenerator : TransactionIdGenerator
  - explicitTxnStateMap : Map<Long, ExplicitTxnState>
}

class DatabaseTransactionMgr {
  - dbId : long
  - idToRunningTransactionState : Map<Long, TransactionState>
  - idToFinalStatusTransactionState : Map<Long, TransactionState>
  - labelToTxnIds : Map<String, Set<Long>>
}

class TransactionIdGenerator {
  - nextId : long
}

class TransactionState {
  - transactionId : long
  - dbId : long
  - tableIdList : List<Long>
  - label : String
  - transactionStatus : TransactionStatus
  - sourceType : LoadJobSourceType
  - txnCoordinator : TxnCoordinator
  - idToTableCommitInfos : Map<Long, TableCommitInfo>
  - tabletCommitInfos : Set<TabletCommitInfo>
  - timeoutMs : long
}

enum TransactionStatus {
  PREPARE
  PREPARED
  COMMITTED
  VISIBLE
  ABORTED
}

enum LoadJobSourceType {
  INSERT_STREAMING
  BACKEND_STREAMING
  FRONTEND_STREAMING
  ROUTINE_LOAD_TASK
  BATCH_LOAD_JOB
  ...
}

class TxnCoordinator {
  - sourceType : TxnSourceType
  - ip : String
  - backendId : long
}

enum TxnSourceType {
  FE
  BE
}

class TableCommitInfo {
  - tableId : long
  - idToPartitionCommitInfo : Map<Long, PartitionCommitInfo>
}

class PartitionCommitInfo {
  - physicalPartitionId : long
  - version : long
}

class TabletCommitInfo {
  - tabletId : long
  - backendId : long
}

abstract class DmlStmt {
  - txnId : long
}

GlobalTransactionMgr *-- "1" TransactionIdGenerator : idGenerator
GlobalTransactionMgr *-- "N" DatabaseTransactionMgr : dbIdToDatabaseTransactionMgrs
DatabaseTransactionMgr o-- "N" TransactionState : idToRunningTransactionState
TransactionState *-- "1" TransactionStatus : transactionStatus
TransactionState *-- "1" LoadJobSourceType : sourceType
TransactionState *-- "1" TxnCoordinator : txnCoordinator
TxnCoordinator *-- "1" TxnSourceType : sourceType
TransactionState *-- "N" TableCommitInfo : idToTableCommitInfos
TableCommitInfo *-- "N" PartitionCommitInfo : idToPartitionCommitInfo
TransactionState o-- "N" TabletCommitInfo : tabletCommitInfos
DmlStmt ..> TransactionState : txnId

@enduml
```

**Running-txn limit.** **`max_running_txn_num_per_db`** (default **1000**) caps non-final load txns per catalog database. **`runningTxnNums`** counts **`PREPARE` / `PREPARED` / `COMMITTED`**. Begin increments; visible or abort decrements. Checked only in **`checkRunningTxnExceedLimit`** at begin. Counts in-flight loads, not tables. **`ROUTINE_LOAD_TASK`** and **`LAKE_COMPACTION`** are excluded (routine load: **`max_routine_load_task_num_per_be`**). Over limit → **`RunningTxnExceedException`**. Raise the FE config for more concurrency; splitting databases isolates counters, not join cost.

**Steps** — status **`PREPARE` → `COMMITTED` → `VISIBLE`** (or **`ABORTED`**).

**1. Begin** — open txn; set **`DmlStmt.txnId`**. Skip if **`session.getTxnId() != 0`**.

```java
// StatementPlanner.beginTransaction
if (session.getTxnId() != 0) {
    stmt.setTxnId(session.getTxnId());
    return;
}
txnId = transactionMgr.beginTransaction(
        dbId, Lists.newArrayList(targetTable.getId()), label,
        new TransactionState.TxnCoordinator(FE, localHost),
        TransactionState.LoadJobSourceType.INSERT_STREAMING,
        session.getExecTimeout(), session.getCurrentComputeResource());
stmt.setTxnId(txnId);
```

**2. Id, label, limit** — allocate global id; under **`DatabaseTransactionMgr`** write lock: label check, **`checkRunningTxnExceedLimit`**, upsert **`PREPARE`**.

```java
// DatabaseTransactionMgr.beginTransaction
long tid = globalStateMgr.getGlobalTransactionMgr()
        .getTransactionIDGenerator().getNextTransactionId();
TransactionState transactionState = new TransactionState(
        dbId, tableIdList, tid, label, requestId, sourceType,
        coordinator, callbackId, timeoutSecond * 1000);
writeLock();
try {
    // label → LabelAlreadyUsedException / DuplicatedRequestException
    checkRunningTxnExceedLimit(sourceType);
    persistTxnStateInTxnLevelLock(transactionState, wal -> {
        unprotectUpsertTransactionState(transactionState);
    });
} finally {
    writeUnlock();
}
return tid;
```

```java
// DatabaseTransactionMgr.checkRunningTxnExceedLimit
switch (sourceType) {
    case ROUTINE_LOAD_TASK:
    case LAKE_COMPACTION:
        break;
    default:
        if (runningTxnNums >= Config.max_running_txn_num_per_db) {
            throw new RunningTxnExceedException(
                    "current running txns on db " + dbId + " is " + runningTxnNums
                    + ", larger than limit " + Config.max_running_txn_num_per_db);
        }
}
```

**3. Write** — deploy load fragments; BE rowsets under **`txnId`**.

**4. Commit and publish** — **`TabletCommitInfo`** → **`COMMITTED`** → publish **`version`** → **`VISIBLE`**.

```java
// GlobalTransactionMgr
VisibleStateWaiter waiter = retryCommitOnRateLimitExceeded(
        db, transactionId, tabletCommitInfos, tabletFailInfos,
        txnCommitAttachment, timeoutMillis);
return awaitVisibleAfterCommitUntil(transactionId, waiter, dueTime);
```

**5. Abort** — on failure: drop unpublished deltas; free the running-txn slot.

```java
transactionMgr.abortTransaction(db.getId(), txnId, errMsg);
```

## 5. References

1. K. Kang, “StarRocks Query Optimizer,” CMU Database Group Seminar, 31 March 2025. [Notes](https://kangkaisen.com/post/cmu-starrocks-query-optimizer).
2. G. Graefe, “The Cascades Framework for Query Optimization,” *IEEE Data Engineering Bulletin*, vol. 18, no. 3, pp. 19–29, 1995. [PDF](https://15721.courses.cs.cmu.edu/spring2016/papers/graefe-ieee1995.pdf).
3. Y. Xu, “Efficiency in the Columbia Database Query Optimizer,” M.S. thesis, Portland State University, 1998. [PDF](https://15721.courses.cs.cmu.edu/spring2019/papers/22-optimizer1/xu-columbia-thesis1998.pdf).
